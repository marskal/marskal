//! Reads over the local rows, with what the server derives at read time:
//! resolved-above (ADR 0009), effective dates (ADR 0006), and effective
//! tags and availability (ADR 0005). None of it is stored or synced.

use std::collections::{HashMap, HashSet};

use jiff::Timestamp;
use rusqlite::Connection;
use serde::Serialize;
use serde_json::{Map, Value};
use uuid::Uuid;

use crate::entity::Entity;
use crate::error::{Error, Result};
use crate::model::{Folder, Link, Project, Series, Tag, TagState, Task, TaskState};
use crate::value::from_sql;

/// Which tasks to list.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TaskFilter {
    /// The open stream: to-do, out of the inbox, not resolved above, newest
    /// first. Deferred and unavailable tasks only with `unavailable`.
    Open { unavailable: bool },
    /// Open tasks in the inbox, in outline order.
    Inbox,
    /// A project's open tasks, in outline order.
    Project(Uuid),
    /// Open tasks with the tag or one below it, newest first.
    Tag(Uuid),
    /// Every live task, resolved ones too, newest first.
    All,
}

/// A task with what a list shows about it.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct TaskView {
    #[serde(flatten)]
    pub task: Task,
    /// The project's title, if the task is in one.
    pub project: Option<String>,
    /// Depth in the outline: 0 for a top-level task.
    pub depth: usize,
    /// Own tags, then the project's (ADR 0005), each as its path.
    pub tags: Vec<TagRef>,
    /// The dates the task goes by, its own or inherited.
    pub effective: EffectiveDates,
    pub deferred: bool,
    pub overdue: bool,
    /// False when tag state makes the task unavailable.
    pub available: bool,
    /// Done or Dropped, by its own state or one above it.
    pub resolved: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct TagRef {
    pub id: Uuid,
    pub path: Vec<String>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize)]
pub struct EffectiveDates {
    pub defer_until: Option<String>,
    pub deferred_indefinitely: bool,
    pub planned_at: Option<String>,
    pub due_at: Option<String>,
}

/// Every live row, loaded once for a read.
pub struct World {
    pub tasks: Vec<Task>,
    pub projects: Vec<Project>,
    pub folders: Vec<Folder>,
    pub tags: Vec<Tag>,
    pub series: Vec<Series>,
    pub task_tags: Vec<Link>,
    pub project_tags: Vec<Link>,
    now: Timestamp,
    task_index: HashMap<Uuid, usize>,
    project_index: HashMap<Uuid, usize>,
    tag_index: HashMap<Uuid, usize>,
    series_index: HashMap<Uuid, usize>,
    children: HashMap<Uuid, Vec<usize>>,
}

impl World {
    pub(crate) fn load(conn: &Connection, now: Timestamp) -> Result<World> {
        let tasks: Vec<Task> = load(conn, Entity::Task)?;
        let projects: Vec<Project> = load(conn, Entity::Project)?;
        let folders: Vec<Folder> = load(conn, Entity::ProjectFolder)?;
        let tags: Vec<Tag> = load(conn, Entity::Tag)?;
        let series: Vec<Series> = load(conn, Entity::RecurrenceSeries)?;

        let task_index = index(&tasks, |t| t.id);
        let mut children: HashMap<Uuid, Vec<usize>> = HashMap::new();
        for (i, task) in tasks.iter().enumerate() {
            if let Some(parent) = task.parent_id {
                children.entry(parent).or_default().push(i);
            }
        }

        Ok(World {
            task_tags: links(conn, "task_tags", "task_id")?,
            project_tags: links(conn, "project_tags", "project_id")?,
            task_index,
            project_index: index(&projects, |p| p.id),
            tag_index: index(&tags, |t| t.id),
            series_index: index(&series, |s| s.id),
            children,
            tasks,
            projects,
            folders,
            tags,
            series,
            now,
        })
    }

    pub fn now(&self) -> Timestamp {
        self.now
    }

    pub fn task(&self, id: Uuid) -> Option<&Task> {
        self.task_index.get(&id).map(|&i| &self.tasks[i])
    }

    pub fn project(&self, id: Uuid) -> Option<&Project> {
        self.project_index.get(&id).map(|&i| &self.projects[i])
    }

    /// A live recurrence series.
    pub fn series(&self, id: Uuid) -> Option<&Series> {
        self.series_index.get(&id).map(|&i| &self.series[i])
    }

    pub fn tag(&self, id: Uuid) -> Option<&Tag> {
        self.tag_index.get(&id).map(|&i| &self.tags[i])
    }

    /// A live task by id, or a unique start or end of it (see `ids::short`).
    pub fn find_task(&self, key: &str) -> Result<&Task> {
        find(&self.tasks, key, "task", |t| t.id, |_| None)
    }

    /// A live project by id, a unique start or end of it, or its exact title (ignoring case).
    pub fn find_project(&self, key: &str) -> Result<&Project> {
        find(
            &self.projects,
            key,
            "project",
            |p| p.id,
            |p| Some(p.title.as_str()),
        )
    }

    /// A live tag by id, id prefix, or its path (`Home/Errands`, or a name
    /// unique among tags), ignoring case.
    pub fn find_tag(&self, key: &str) -> Result<&Tag> {
        if let Ok(tag) = find(&self.tags, key, "tag", |t| t.id, |_| None) {
            return Ok(tag);
        }

        let wanted: Vec<String> = key
            .split(['/', '›', '>', ':', '\\'])
            .map(|segment| segment.trim().to_lowercase())
            .filter(|segment| !segment.is_empty())
            .collect();

        let matches: Vec<&Tag> = self
            .tags
            .iter()
            .filter(|tag| {
                let path: Vec<String> = self
                    .tag_path(tag.id)
                    .iter()
                    .map(|s| s.to_lowercase())
                    .collect();
                path == wanted || (wanted.len() == 1 && path.last() == wanted.last())
            })
            .collect();

        one(matches, "tag", key)
    }

    /// A live folder by id, id prefix, or its exact name (ignoring case).
    pub fn find_folder(&self, key: &str) -> Result<&Folder> {
        find(
            &self.folders,
            key,
            "folder",
            |f| f.id,
            |f| Some(f.name.as_str()),
        )
    }

    /// The names from the root to this tag.
    pub fn tag_path(&self, id: Uuid) -> Vec<String> {
        let mut path = Vec::new();
        let mut next = self.tag(id);
        let mut seen = HashSet::new();

        while let Some(tag) = next {
            if !seen.insert(tag.id) {
                break;
            }
            path.push(tag.name.clone());
            next = tag.parent_id.and_then(|parent| self.tag(parent));
        }

        path.reverse();
        path
    }

    /// The tasks a filter selects, as views.
    pub fn tasks(&self, filter: TaskFilter) -> Vec<TaskView> {
        match filter {
            TaskFilter::Open { unavailable } => self.newest_first(|view| {
                !view.task.inbox
                    && !view.resolved
                    && (unavailable || (view.available && !view.deferred))
            }),
            TaskFilter::Inbox => self.outline(|task| task.inbox && task.parent_id.is_none()),
            TaskFilter::Project(id) => self.outline(|task| {
                task.project_id == Some(id) && !task.inbox && task.parent_id.is_none()
            }),
            TaskFilter::Tag(id) => {
                let subtree = self.tag_subtree(id);
                self.newest_first(|view| {
                    !view.resolved && view.tags.iter().any(|tag| subtree.contains(&tag.id))
                })
            }
            TaskFilter::All => self.newest_first(|_| true),
        }
    }

    /// One task as a view.
    pub fn view(&self, task: &Task) -> TaskView {
        let tags = self.effective_tags(task);
        let effective = self.effective_dates(task);
        let deferred = effective.deferred_indefinitely
            || effective
                .defer_until
                .as_deref()
                .and_then(parse)
                .is_some_and(|until| until > self.now);
        let overdue = task.state == TaskState::ToDo
            && effective
                .due_at
                .as_deref()
                .and_then(parse)
                .is_some_and(|due| due <= self.now);

        TaskView {
            project: task
                .project_id
                .and_then(|id| self.project(id))
                .map(|p| p.title.clone()),
            depth: self.depth(task),
            available: self.available(&tags),
            resolved: self.resolved(task),
            tags,
            effective,
            deferred,
            overdue,
            task: task.clone(),
        }
    }

    fn newest_first(&self, keep: impl Fn(&TaskView) -> bool) -> Vec<TaskView> {
        let mut views: Vec<TaskView> = self
            .tasks
            .iter()
            .map(|task| self.view(task))
            .filter(|view| keep(view))
            .collect();

        views.sort_by(|a, b| {
            b.task
                .inserted_at
                .cmp(&a.task.inserted_at)
                .then(b.task.id.cmp(&a.task.id))
        });
        views
    }

    // Open tasks under the roots `root` picks, depth first by rank.
    fn outline(&self, root: impl Fn(&Task) -> bool) -> Vec<TaskView> {
        let mut roots: Vec<&Task> = self.tasks.iter().filter(|task| root(task)).collect();
        sort_by_rank(&mut roots);

        let mut views = Vec::new();
        let mut seen = HashSet::new();
        for task in roots {
            self.walk(task, &mut views, &mut seen);
        }
        views
    }

    fn walk(&self, task: &Task, views: &mut Vec<TaskView>, seen: &mut HashSet<Uuid>) {
        if !seen.insert(task.id) || task.state.is_resolved() || self.resolved(task) {
            return;
        }

        views.push(self.view(task));

        let mut children: Vec<&Task> = self
            .children
            .get(&task.id)
            .map(|indices| indices.iter().map(|&i| &self.tasks[i]).collect())
            .unwrap_or_default();
        sort_by_rank(&mut children);

        for child in children {
            self.walk(child, views, seen);
        }
    }

    // The chain of parents, nearest first, stopping at a cycle.
    fn ancestors(&self, task: &Task) -> Vec<&Task> {
        let mut chain = Vec::new();
        let mut seen = HashSet::from([task.id]);
        let mut next = task.parent_id.and_then(|id| self.task(id));

        while let Some(parent) = next {
            if !seen.insert(parent.id) {
                break;
            }
            chain.push(parent);
            next = parent.parent_id.and_then(|id| self.task(id));
        }

        chain
    }

    fn depth(&self, task: &Task) -> usize {
        self.ancestors(task).len()
    }

    /// Done or Dropped by its own state, a task above it, or its project.
    pub fn resolved(&self, task: &Task) -> bool {
        task.state.is_resolved()
            || self.ancestors(task).iter().any(|t| t.state.is_resolved())
            || task
                .project_id
                .and_then(|id| self.project(id))
                .is_some_and(|p| p.state.is_resolved())
    }

    // Planned and Due come from the nearest task above that has one, then
    // the project. Defer is the strongest of all of them (ADR 0006).
    fn effective_dates(&self, task: &Task) -> EffectiveDates {
        let mut chain: Vec<&Task> = self.ancestors(task);
        chain.reverse();
        chain.push(task);

        let mut dates = task
            .project_id
            .and_then(|id| self.project(id))
            .map(|p| EffectiveDates {
                defer_until: p.defer_until.clone(),
                deferred_indefinitely: p.deferred_indefinitely,
                planned_at: p.planned_at.clone(),
                due_at: p.due_at.clone(),
            })
            .unwrap_or_default();

        for t in chain {
            dates.defer_until = later(dates.defer_until, t.defer_until.clone());
            dates.deferred_indefinitely |= t.deferred_indefinitely;
            dates.planned_at = t.planned_at.clone().or(dates.planned_at);
            dates.due_at = t.due_at.clone().or(dates.due_at);
        }

        dates
    }

    // Own tags, then the project's not already there, in tag order.
    fn effective_tags(&self, task: &Task) -> Vec<TagRef> {
        let own = self.task_tags.iter().filter(|l| l.owner_id == task.id);
        let inherited = self
            .project_tags
            .iter()
            .filter(|l| Some(l.owner_id) == task.project_id);

        let mut seen = HashSet::new();
        own.chain(inherited)
            .filter(|link| self.tag(link.tag_id).is_some() && seen.insert(link.tag_id))
            .map(|link| TagRef {
                id: link.tag_id,
                path: self.tag_path(link.tag_id),
            })
            .collect()
    }

    // A tag's state, with Dropped covering its subtree (ADR 0005).
    fn tag_state(&self, id: Uuid) -> Option<TagState> {
        let tag = self.tag(id)?;
        let mut above = tag.parent_id.and_then(|p| self.tag(p));
        let mut seen = HashSet::from([id]);

        while let Some(parent) = above {
            if parent.state == TagState::Dropped {
                return Some(TagState::Dropped);
            }
            if !seen.insert(parent.id) {
                break;
            }
            above = parent.parent_id.and_then(|p| self.tag(p));
        }

        Some(tag.state)
    }

    // None on hold, and not all dropped.
    fn available(&self, tags: &[TagRef]) -> bool {
        let states: Vec<TagState> = tags.iter().filter_map(|t| self.tag_state(t.id)).collect();
        !states.contains(&TagState::OnHold)
            && (states.is_empty() || states.iter().any(|s| *s != TagState::Dropped))
    }

    fn tag_subtree(&self, id: Uuid) -> HashSet<Uuid> {
        let mut ids = HashSet::from([id]);
        loop {
            let before = ids.len();
            for tag in &self.tags {
                if tag.parent_id.is_some_and(|p| ids.contains(&p)) {
                    ids.insert(tag.id);
                }
            }
            if ids.len() == before {
                return ids;
            }
        }
    }
}

fn sort_by_rank(tasks: &mut [&Task]) {
    tasks.sort_by(|a, b| a.rank.cmp(&b.rank).then(a.id.cmp(&b.id)));
}

fn later(a: Option<String>, b: Option<String>) -> Option<String> {
    match (a, b) {
        (Some(a), Some(b)) => Some(if parse(&b) > parse(&a) { b } else { a }),
        (a, b) => a.or(b),
    }
}

pub(crate) fn parse(at: &str) -> Option<Timestamp> {
    at.parse().ok()
}

fn index<T>(rows: &[T], id: impl Fn(&T) -> Uuid) -> HashMap<Uuid, usize> {
    rows.iter()
        .enumerate()
        .map(|(i, row)| (id(row), i))
        .collect()
}

fn find<'a, T>(
    rows: &'a [T],
    key: &str,
    entity: &'static str,
    id: impl Fn(&T) -> Uuid,
    name: impl Fn(&T) -> Option<&str>,
) -> Result<&'a T> {
    let key = key.trim();
    let lower = key.to_lowercase();

    if let Ok(uuid) = Uuid::parse_str(key) {
        return rows
            .iter()
            .find(|row| id(row) == uuid)
            .ok_or_else(|| not_found(entity, key));
    }

    // A UUIDv7 starts with its timestamp, so rows made in the same minute
    // share a prefix. The short id people see is the random end
    // (`ids::short`); either end matches.
    let hex: String = lower.chars().filter(|c| *c != '-').collect();
    let by_id: Vec<&T> = if hex.len() >= 4 && hex.chars().all(|c| c.is_ascii_hexdigit()) {
        rows.iter()
            .filter(|row| {
                let simple = id(row).simple().to_string();
                simple.ends_with(&hex) || simple.starts_with(&hex)
            })
            .collect()
    } else {
        Vec::new()
    };

    if !by_id.is_empty() {
        return one(by_id, entity, key);
    }

    let by_name: Vec<&T> = rows
        .iter()
        .filter(|row| name(row).is_some_and(|n| n.to_lowercase() == lower))
        .collect();

    one(by_name, entity, key)
}

fn one<'a, T>(matches: Vec<&'a T>, entity: &'static str, key: &str) -> Result<&'a T> {
    match matches.as_slice() {
        [only] => Ok(only),
        [] => Err(not_found(entity, key)),
        _ => Err(Error::Ambiguous {
            entity,
            id: key.to_string(),
        }),
    }
}

fn not_found(entity: &'static str, key: &str) -> Error {
    Error::NotFound {
        entity,
        id: key.to_string(),
    }
}

pub(crate) fn load<T: serde::de::DeserializeOwned>(
    conn: &Connection,
    entity: Entity,
) -> Result<Vec<T>> {
    let columns = entity.columns();
    let names: Vec<&str> = columns.iter().map(|c| c.name).collect();
    let sql = format!(
        "SELECT {} FROM {} WHERE discarded_at IS NULL",
        names.join(", "),
        entity.table()
    );

    let mut statement = conn.prepare(&sql)?;
    let mut rows = statement.query([])?;
    let mut out = Vec::new();

    while let Some(row) = rows.next()? {
        let mut map = Map::new();
        for (i, column) in columns.iter().enumerate() {
            map.insert(column.name.to_string(), from_sql(*column, row.get_ref(i)?));
        }
        out.push(serde_json::from_value(Value::Object(map))?);
    }

    Ok(out)
}

fn links(conn: &Connection, table: &str, owner: &str) -> Result<Vec<Link>> {
    let sql = format!("SELECT id, {owner}, tag_id FROM {table} WHERE discarded_at IS NULL");
    let mut statement = conn.prepare(&sql)?;
    let rows = statement.query_map([], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, String>(2)?,
        ))
    })?;

    let mut out = Vec::new();
    for row in rows {
        let (id, owner_id, tag_id) = row?;
        if let (Ok(id), Ok(owner_id), Ok(tag_id)) = (
            Uuid::parse_str(&id),
            Uuid::parse_str(&owner_id),
            Uuid::parse_str(&tag_id),
        ) {
            out.push(Link {
                id,
                owner_id,
                tag_id,
            });
        }
    }
    Ok(out)
}
