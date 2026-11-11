//! What a user does, as commands: the shared logic of every shell. Each
//! operation applies its patch here and queues it for the server in one
//! transaction (ADR 0014).

use jiff::Timestamp;
use rusqlite::{Connection, OptionalExtension};
use serde_json::{Map, Value, json};
use uuid::Uuid;

use crate::clock::stamp;
use crate::entity::Entity;
use crate::error::{Error, Result};
use crate::local;
use crate::model::TaskState;
use crate::push::{Command, Op, enqueue};
use crate::store::Store;
use marskal_rules::ids::{LinkKind, link_id};
use marskal_rules::url;

/// Where a task lives: the inbox, no project, or a project (ADR 0017).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Location {
    Inbox,
    NoProject,
    Project(Uuid),
}

impl Location {
    fn fields(self) -> Map<String, Value> {
        let (inbox, project_id) = match self {
            Location::Inbox => (true, None),
            Location::NoProject => (false, None),
            Location::Project(id) => (false, Some(id.to_string())),
        };
        object(json!({ "inbox": inbox, "project_id": project_id }))
    }
}

/// A task to capture. Without a location or a parent it goes to the inbox.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct NewTask {
    pub title: String,
    pub notes: Option<String>,
    /// Absolute, as [`crate::url::valid`] checks it. Blank means none.
    pub url: Option<String>,
    /// ADR 0025.
    pub flagged: bool,
    pub location: Option<Location>,
    /// A subtask lives where its parent does, whatever `location` says.
    pub parent_id: Option<Uuid>,
    pub defer_until: Option<Timestamp>,
    pub deferred_indefinitely: bool,
    pub planned_at: Option<Timestamp>,
    pub due_at: Option<Timestamp>,
}

/// Fields to change on a task. `None` leaves a field alone; `Some(None)`
/// clears it.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct TaskPatch {
    pub title: Option<String>,
    pub notes: Option<Option<String>>,
    /// `Some("")` or `Some(None)` clears it.
    pub url: Option<Option<String>>,
    pub flagged: Option<bool>,
    pub planned_at: Option<Option<Timestamp>>,
    pub due_at: Option<Option<Timestamp>>,
    /// Defer until an instant, or `Some(None)` to stop deferring.
    pub defer_until: Option<Option<Timestamp>>,
    /// Defer with no end. Takes the place of an until instant.
    pub defer_indefinitely: bool,
}

/// A project to create.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct NewProject {
    pub title: String,
    pub notes: Option<String>,
    pub url: Option<String>,
    pub flagged: bool,
    pub folder_id: Option<Uuid>,
}

impl Store {
    /// Applies a command here and queues it for the server.
    pub fn submit(&mut self, command: Command) -> Result<()> {
        self.write(|tx, now| {
            local::apply(tx, &command, now)?;
            enqueue(tx, &command, &stamp(now))
        })
    }

    /// Captures a task. Returns its id.
    pub fn add_task(&mut self, new: NewTask) -> Result<Uuid> {
        let title = title(&new.title)?;
        let url = new.url.as_deref().map(clean_url).transpose()?.flatten();
        let id = new_id();

        self.write(|tx, now| {
            let mut fields = object(json!({ "title": title }));

            let (inbox, project_id) = match new.parent_id {
                Some(parent) => local::location_of(tx, &parent.to_string())?,
                None => {
                    let location = new.location.unwrap_or(Location::Inbox);
                    let fields = location.fields();
                    (
                        fields["inbox"].as_bool().unwrap_or(true),
                        fields["project_id"].as_str().map(str::to_string),
                    )
                }
            };

            fields.insert("inbox".into(), inbox.into());
            fields.insert("project_id".into(), project_id.clone().into());

            if let Some(parent) = new.parent_id {
                fields.insert("parent_id".into(), parent.to_string().into());
            }

            let parent = new.parent_id.map(|p| p.to_string());
            let rank =
                local::default_rank(tx, parent.as_deref(), inbox, project_id.as_deref(), None)?;
            fields.insert("rank".into(), rank.into());

            if let Some(notes) = &new.notes {
                fields.insert("notes".into(), notes.clone().into());
            }
            if let Some(url) = &url {
                fields.insert("url".into(), url.clone().into());
            }
            if new.flagged {
                fields.insert("flagged".into(), true.into());
            }
            put_time(&mut fields, "planned_at", new.planned_at);
            put_time(&mut fields, "due_at", new.due_at);
            if new.deferred_indefinitely {
                put_defer(&mut fields, None, true);
            } else if new.defer_until.is_some() {
                put_defer(&mut fields, new.defer_until, false);
            }

            run(tx, now, Entity::Task, id, Op::Insert, fields)
        })?;

        Ok(id)
    }

    /// Changes a task's title, notes, URL, flag, or dates.
    pub fn edit_task(&mut self, id: Uuid, patch: TaskPatch) -> Result<()> {
        let mut fields = Map::new();

        if let Some(new_title) = &patch.title {
            fields.insert("title".into(), title(new_title)?.into());
        }
        if let Some(notes) = &patch.notes {
            fields.insert("notes".into(), notes.clone().into());
        }
        if let Some(new_url) = &patch.url {
            let new_url = new_url.as_deref().map(clean_url).transpose()?.flatten();
            fields.insert("url".into(), new_url.into());
        }
        if let Some(flagged) = patch.flagged {
            fields.insert("flagged".into(), flagged.into());
        }
        if let Some(planned) = patch.planned_at {
            fields.insert("planned_at".into(), planned.map(stamp).into());
        }
        if let Some(due) = patch.due_at {
            fields.insert("due_at".into(), due.map(stamp).into());
        }
        if patch.defer_indefinitely {
            put_defer(&mut fields, None, true);
        } else if let Some(until) = patch.defer_until {
            put_defer(&mut fields, until, false);
        }

        if fields.is_empty() {
            return Ok(());
        }

        self.write(|tx, now| run(tx, now, Entity::Task, id, Op::Patch, fields))
    }

    /// Marks a task Done, Dropped, or To-Do again.
    pub fn set_task_state(&mut self, id: Uuid, state: TaskState) -> Result<()> {
        self.write(|tx, now| {
            let fields = object(json!({ "state": state.as_str() }));
            run(tx, now, Entity::Task, id, Op::Patch, fields)
        })
    }

    /// Moves a task to the inbox, no project, or a project. It leaves its
    /// parent, and its subtasks come along.
    pub fn move_task(&mut self, id: Uuid, location: Location) -> Result<()> {
        self.write(|tx, now| run(tx, now, Entity::Task, id, Op::Patch, location.fields()))
    }

    /// Makes a task the last subtask of `parent_id`, or a top-level task in
    /// its location for `None`.
    pub fn set_parent(&mut self, id: Uuid, parent_id: Option<Uuid>) -> Result<()> {
        self.write(|tx, now| {
            let (inbox, project_id) = match parent_id {
                Some(parent) => local::location_of(tx, &parent.to_string())?,
                None => local::location_of(tx, &id.to_string())?,
            };
            let parent = parent_id.map(|p| p.to_string());
            let rank = local::default_rank(
                tx,
                parent.as_deref(),
                inbox,
                project_id.as_deref(),
                Some(&id.to_string()),
            )?;
            let fields = object(json!({ "parent_id": parent, "rank": rank }));
            run(tx, now, Entity::Task, id, Op::Patch, fields)
        })
    }

    /// Deletes a task and its subtasks. Done and Dropped are how work
    /// normally ends; this is for mistakes (ADR 0014).
    pub fn delete_task(&mut self, id: Uuid) -> Result<()> {
        self.write(|tx, now| {
            let fields = object(json!({ "discarded_at": stamp(now) }));
            run(tx, now, Entity::Task, id, Op::Patch, fields)
        })
    }

    /// Creates a project. Returns its id.
    pub fn add_project(&mut self, new: NewProject) -> Result<Uuid> {
        let title = title(&new.title)?;
        let url = new.url.as_deref().map(clean_url).transpose()?.flatten();
        let id = new_id();

        self.write(|tx, now| {
            let fields = object(json!({
                "title": title,
                "notes": new.notes,
                "url": url,
                "flagged": new.flagged,
                "project_folder_id": new.folder_id.map(|f| f.to_string()),
            }));
            run(tx, now, Entity::Project, id, Op::Insert, fields)
        })?;

        Ok(id)
    }

    /// Marks a project Done, Dropped, or To-Do again.
    pub fn set_project_state(&mut self, id: Uuid, state: TaskState) -> Result<()> {
        self.write(|tx, now| {
            let fields = object(json!({ "state": state.as_str() }));
            run(tx, now, Entity::Project, id, Op::Patch, fields)
        })
    }

    /// Flags a project, which flags its tasks, or clears its flag (ADR 0025).
    pub fn set_project_flagged(&mut self, id: Uuid, flagged: bool) -> Result<()> {
        self.write(|tx, now| {
            let fields = object(json!({ "flagged": flagged }));
            run(tx, now, Entity::Project, id, Op::Patch, fields)
        })
    }

    /// Creates a tag under `parent_id`, or at the top. Returns its id.
    pub fn add_tag(&mut self, name: &str, parent_id: Option<Uuid>) -> Result<Uuid> {
        let name = name.trim();
        if name.is_empty() {
            return Err(Error::Invalid("a tag needs a name".into()));
        }

        let id = new_id();
        self.write(|tx, now| {
            let fields = object(json!({
                "name": name,
                "parent_id": parent_id.map(|p| p.to_string()),
            }));
            run(tx, now, Entity::Tag, id, Op::Insert, fields)
        })?;

        Ok(id)
    }

    /// Tags a task. Tagging again after an untag revives the same link row.
    pub fn tag_task(&mut self, task_id: Uuid, tag_id: Uuid) -> Result<()> {
        self.link(Entity::TaskTag, LinkKind::Task, task_id, tag_id, true)
    }

    pub fn untag_task(&mut self, task_id: Uuid, tag_id: Uuid) -> Result<()> {
        self.link(Entity::TaskTag, LinkKind::Task, task_id, tag_id, false)
    }

    pub fn tag_project(&mut self, project_id: Uuid, tag_id: Uuid) -> Result<()> {
        self.link(
            Entity::ProjectTag,
            LinkKind::Project,
            project_id,
            tag_id,
            true,
        )
    }

    pub fn untag_project(&mut self, project_id: Uuid, tag_id: Uuid) -> Result<()> {
        self.link(
            Entity::ProjectTag,
            LinkKind::Project,
            project_id,
            tag_id,
            false,
        )
    }

    fn link(
        &mut self,
        entity: Entity,
        kind: LinkKind,
        owner: Uuid,
        tag: Uuid,
        on: bool,
    ) -> Result<()> {
        let id = link_id(kind, owner, tag);

        self.write(|tx, now| {
            let discarded: Option<Option<String>> = tx
                .query_row(
                    &format!("SELECT discarded_at FROM {} WHERE id = ?1", entity.table()),
                    [id.to_string()],
                    |row| row.get(0),
                )
                .optional()?;

            match (discarded, on) {
                (None, true) => {
                    let owner_field = if kind == LinkKind::Task {
                        "task_id"
                    } else {
                        "project_id"
                    };
                    let fields = object(
                        json!({ owner_field: owner.to_string(), "tag_id": tag.to_string() }),
                    );
                    run(tx, now, entity, id, Op::Insert, fields)
                }
                (Some(Some(_)), true) => run(
                    tx,
                    now,
                    entity,
                    id,
                    Op::Patch,
                    object(json!({ "discarded_at": null })),
                ),
                (Some(None), false) => run(
                    tx,
                    now,
                    entity,
                    id,
                    Op::Patch,
                    object(json!({ "discarded_at": stamp(now) })),
                ),
                // Already as asked.
                _ => Ok(()),
            }
        })
    }
}

fn run(
    conn: &Connection,
    now: Timestamp,
    entity: Entity,
    entity_id: Uuid,
    op: Op,
    fields: Map<String, Value>,
) -> Result<()> {
    let command = Command {
        id: new_id(),
        entity,
        entity_id,
        op,
        fields,
        at: Some(now.to_string()),
    };

    local::apply(conn, &command, now)?;
    enqueue(conn, &command, &stamp(now))
}

fn title(title: &str) -> Result<String> {
    let title = title.trim();
    if title.is_empty() {
        Err(Error::Invalid("a title cannot be blank".into()))
    } else {
        Ok(title.to_string())
    }
}

// Defer has one shape: an instant, or indefinite. A change patches both
// fields, so two offline edits merge into one shape (ADR 0006).
fn put_defer(fields: &mut Map<String, Value>, until: Option<Timestamp>, indefinite: bool) {
    fields.insert("defer_until".into(), until.map(stamp).into());
    fields.insert("deferred_indefinitely".into(), indefinite.into());
}

fn put_time(fields: &mut Map<String, Value>, name: &str, at: Option<Timestamp>) {
    if let Some(at) = at {
        fields.insert(name.into(), stamp(at).into());
    }
}

fn object(value: Value) -> Map<String, Value> {
    match value {
        Value::Object(map) => map,
        _ => Map::new(),
    }
}

/// A new domain key: UUIDv7, minted before insert (ADR 0011).
fn new_id() -> Uuid {
    Uuid::now_v7()
}

/// Trims a URL; blank clears it (ADR 0022).
fn clean_url(text: &str) -> Result<Option<String>> {
    match text.trim() {
        "" => Ok(None),
        text if url::valid(text) => Ok(Some(text.to_string())),
        _ => Err(Error::Invalid(
            "a URL must be absolute, such as https://marskal.example, and not a script".into(),
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clean_url_trims_and_clears() {
        assert_eq!(
            clean_url("  https://a.example ").unwrap().as_deref(),
            Some("https://a.example")
        );
        assert_eq!(clean_url("   ").unwrap(), None);
        assert!(clean_url("javascript:x").is_err());
    }
}
