//! What `marskal` prints. With `--json`, one JSON object on stdout in a
//! shape that only changes with its `version` (ADR 0020). Without it,
//! lines for people, which may change. Sync notes go to stderr either way.

use jiff::Timestamp;
use jiff::tz::TimeZone;
use marskal_sync::{Rejection, Status, Task, TaskState, TaskView, World};
use serde::Serialize;
use serde_json::{Value, json};
use uuid::Uuid;

use crate::error::{CliError, ErrorBody};
use crate::sync::SyncReport;

/// The version of the `--json` shape.
pub const JSON_VERSION: u32 = 1;

pub struct Output {
    json: bool,
}

impl Output {
    pub fn new(json: bool) -> Output {
        Output { json }
    }

    fn emit(&self, mut value: Value, unsynced: Option<&str>) {
        if let Value::Object(map) = &mut value {
            map.insert("version".into(), JSON_VERSION.into());
            map.insert("synced".into(), unsynced.is_none().into());
            if let Some(reason) = unsynced {
                map.insert("sync_error".into(), reason.into());
            }
        }
        println!("{value}");
    }

    fn note_unsynced(&self, unsynced: Option<&str>) {
        if let Some(reason) = unsynced {
            eprintln!("(not synced: {reason})");
        }
    }

    pub fn error(&self, error: &CliError) {
        if self.json {
            let body = ErrorBody {
                code: error.code,
                message: &error.message,
            };
            println!("{}", json!({ "version": JSON_VERSION, "error": body }));
        } else {
            eprintln!("marskal: {error}");
        }
    }

    pub fn tasks(&self, views: &[TaskView], unsynced: Option<&str>) {
        if self.json {
            return self.emit(json!({ "tasks": views }), unsynced);
        }

        if views.is_empty() {
            println!("Nothing here.");
        }
        for view in views {
            println!("{}", line(view));
        }
        self.note_unsynced(unsynced);
    }

    pub fn task(&self, world: &World, task: &Task, verb: &str, unsynced: Option<&str>) {
        let view = world.view(task);

        if self.json {
            return self.emit(json!({ "task": view }), unsynced);
        }

        if !verb.is_empty() {
            print!("{verb}: ");
        }
        println!(
            "{}",
            line(&TaskView {
                depth: 0,
                ..view.clone()
            })
        );

        if verb.is_empty() {
            println!("  id       {}", task.id);
            let place = if task.inbox {
                "Inbox".to_string()
            } else {
                view.project.clone().unwrap_or_else(|| "No project".into())
            };
            println!("  place    {place}");
            if let Some(parent) = task.parent_id.and_then(|id| world.task(id)) {
                println!("  under    {}", parent.title);
            }
            for (label, at) in [
                ("planned", &view.effective.planned_at),
                ("due", &view.effective.due_at),
                ("deferred", &view.effective.defer_until),
            ] {
                if let Some(at) = at {
                    println!("  {label:<8} {}", day(at));
                }
            }
            if view.effective.deferred_indefinitely {
                println!("  deferred indefinitely");
            }
            if let Some(url) = task.url.as_deref() {
                println!("  url      {url}");
            }
            if let Some(notes) = task.notes.as_deref().filter(|n| !n.is_empty()) {
                println!();
                for note in notes.lines() {
                    println!("  {note}");
                }
            }
        }
        self.note_unsynced(unsynced);
    }

    pub fn opened(&self, url: &str, unsynced: Option<&str>) {
        if self.json {
            return self.emit(json!({ "action": "opened", "url": url }), unsynced);
        }
        println!("Opened {url}");
        self.note_unsynced(unsynced);
    }

    pub fn ids(&self, verb: &str, ids: &[Uuid], unsynced: Option<&str>) {
        if self.json {
            return self.emit(
                json!({ "action": verb.to_lowercase(), "ids": ids }),
                unsynced,
            );
        }
        for id in ids {
            println!("{verb}: {}", short(id));
        }
        self.note_unsynced(unsynced);
    }

    pub fn projects(&self, world: &World, unsynced: Option<&str>) {
        let mut projects: Vec<_> = world.projects.iter().collect();
        projects.sort_by_key(|p| (p.state.is_resolved(), p.title.to_lowercase()));

        if self.json {
            let rows: Vec<Value> = projects
                .iter()
                .map(|p| {
                    let folder = p
                        .project_folder_id
                        .and_then(|id| world.folders.iter().find(|f| f.id == id))
                        .map(|f| f.name.clone());
                    with(p, json!({ "folder": folder }))
                })
                .collect();
            return self.emit(json!({ "projects": rows }), unsynced);
        }

        for project in projects {
            println!(
                "{}  {} {}",
                short(&project.id),
                state_box(project.state),
                project.title
            );
        }
        self.note_unsynced(unsynced);
    }

    pub fn tags(&self, world: &World, unsynced: Option<&str>) {
        let mut tags: Vec<(Vec<String>, &marskal_sync::Tag)> = world
            .tags
            .iter()
            .map(|t| (world.tag_path(t.id), t))
            .collect();
        tags.sort_by(|a, b| a.0.cmp(&b.0));

        if self.json {
            let rows: Vec<Value> = tags
                .iter()
                .map(|(path, t)| with(t, json!({ "path": path })))
                .collect();
            return self.emit(json!({ "tags": rows }), unsynced);
        }

        for (path, tag) in tags {
            let state = match tag.state {
                marskal_sync::TagState::Active => "",
                marskal_sync::TagState::OnHold => "  (on hold)",
                marskal_sync::TagState::Dropped => "  (dropped)",
            };
            println!("{}  {}{state}", short(&tag.id), path.join(" › "));
        }
        self.note_unsynced(unsynced);
    }

    pub fn status(&self, server: Option<&str>, scope: Option<&str>, status: &Status) {
        if self.json {
            let value = with(
                status,
                json!({ "server": server, "signed_in": scope.is_some(), "scope": scope }),
            );
            println!("{}", with(&value, json!({ "version": JSON_VERSION })));
            return;
        }

        println!("server       {}", server.unwrap_or("(none)"));
        println!(
            "signed in    {}",
            match scope {
                Some(scope) if scope.contains("sync:write") => "yes",
                Some(_) => "yes, read-only",
                None => "no",
            }
        );
        println!(
            "last sync    {}",
            status
                .last_synced_at
                .as_deref()
                .map(day)
                .unwrap_or_else(|| "never".into())
        );
        println!("unsent       {}", status.pending);
        if status.unseen_rejections > 0 {
            println!(
                "refused      {} (see `marskal rejections`)",
                status.unseen_rejections
            );
        }
    }

    pub fn login(&self, server: &str, scope: &str, unsynced: Option<&str>) {
        if self.json {
            return self.emit(json!({ "server": server, "scope": scope }), unsynced);
        }
        let read_only = if scope.contains("sync:write") {
            ""
        } else {
            ", read-only"
        };
        println!("Signed in to {server}{read_only}.");
        self.note_unsynced(unsynced);
    }

    pub fn logout(&self, forgot: bool, unsent: usize) {
        if self.json {
            println!(
                "{}",
                json!({ "version": JSON_VERSION, "forgot": forgot, "unsent": unsent })
            );
            return;
        }
        println!("Signed out.");
        if unsent > 0 && forgot {
            println!("{unsent} edits that were not sent are gone with the local data.");
        } else if unsent > 0 {
            println!("{unsent} edits are not sent yet; they go when you sign in again.");
        }
    }

    pub fn synced(&self, report: &SyncReport, rejections: &[Rejection]) {
        if self.json {
            let value = with(report, json!({ "rejections": rejections }));
            return self.emit(value, None);
        }
        println!("Synced. Sent {} edits.", report.pushed);
        self.rejections_lines(rejections);
    }

    pub fn rejections(&self, rejections: &[Rejection]) {
        if self.json {
            return self.emit(json!({ "rejections": rejections }), None);
        }
        if rejections.is_empty() {
            println!("The server has refused nothing.");
        }
        self.rejections_lines(rejections);
    }

    fn rejections_lines(&self, rejections: &[Rejection]) {
        for r in rejections {
            let errors = r
                .errors
                .as_ref()
                .map(|e| format!(" {e}"))
                .unwrap_or_default();
            println!(
                "Refused: {} {} {}: {}{errors}",
                r.op,
                r.entity,
                Uuid::parse_str(&r.entity_id)
                    .map(|id| short(&id))
                    .unwrap_or_else(|_| r.entity_id.clone()),
                r.reason
            );
        }
    }
}

fn line(view: &TaskView) -> String {
    let mut text = format!(
        "{}  {} {}{}",
        short(&view.task.id),
        state_box(view.task.state),
        "  ".repeat(view.depth),
        view.task.title
    );

    if let Some(project) = &view.project {
        text.push_str(&format!("  · {project}"));
    }
    for tag in &view.tags {
        text.push_str(&format!("  #{}", tag.path.join("›")));
    }
    if let Some(due) = &view.effective.due_at {
        text.push_str(&format!("  due {}", day(due)));
        if view.overdue {
            text.push('!');
        }
    } else if let Some(planned) = &view.effective.planned_at {
        text.push_str(&format!("  planned {}", day(planned)));
    }
    if view.deferred {
        text.push_str("  (deferred)");
    }
    if !view.available {
        text.push_str("  (unavailable)");
    }
    text
}

fn state_box(state: TaskState) -> &'static str {
    match state {
        TaskState::ToDo => "[ ]",
        TaskState::Done => "[x]",
        TaskState::Dropped => "[-]",
    }
}

pub fn short(id: &Uuid) -> String {
    marskal_sync::ids::short(id)
}

// A day on this device's wall clock, short.
fn day(at: &str) -> String {
    let Ok(at) = at.parse::<Timestamp>() else {
        return at.to_string();
    };
    let zone = TimeZone::system();
    let local = at.to_zoned(zone.clone());
    let today = Timestamp::now().to_zoned(zone).date();

    let date = match (local.date() - today).get_days() {
        0 => "today".to_string(),
        1 => "tomorrow".to_string(),
        -1 => "yesterday".to_string(),
        2..=6 => local.strftime("%a").to_string(),
        _ if local.year() == today.year() => local.strftime("%-d %b").to_string(),
        _ => local.strftime("%-d %b %Y").to_string(),
    };

    let time = local.strftime("%H:%M").to_string();
    if matches!(time.as_str(), "00:00" | "09:00" | "17:00") {
        date
    } else {
        format!("{date} {time}")
    }
}

// A serializable row with extra fields merged in.
fn with(row: &impl Serialize, extra: Value) -> Value {
    let mut value = serde_json::to_value(row).unwrap_or(Value::Null);
    if let (Value::Object(map), Value::Object(extra)) = (&mut value, extra) {
        map.extend(extra);
    }
    value
}
