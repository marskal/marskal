//! UniFFI bindings over `marskal-sync` for the iOS app (ADR 0029).
//!
//! `sync/core` keeps its borrowed, typed Rust API for the terminal client.
//! This crate puts a [`Store`] behind a mutex, copies every read into an
//! owned record, and passes the sync API's bodies through as JSON text: the
//! shell does the HTTP, and the engine parses what the server sent.
//!
//! Timestamps cross as Unix milliseconds and ids as strings; `uniffi.toml`
//! makes them `Date` and `UUID` in Swift.

use std::sync::{Mutex, MutexGuard};

use jiff::Timestamp;
use marskal_sync as core;
use uuid::Uuid;

uniffi::setup_scaffolding!();

uniffi::custom_type!(Timestamp, i64, {
    remote,
    lower: |at| at.as_millisecond(),
    try_lift: |ms| Ok(Timestamp::from_millisecond(ms)?),
});

uniffi::custom_type!(Uuid, String, {
    remote,
    lower: |id| id.to_string(),
    try_lift: |text| Ok(Uuid::parse_str(&text)?),
});

/// What can go wrong, as the shell tells them apart.
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum StoreError {
    /// No live row has this id.
    #[error("{message}")]
    NotFound { message: String },
    /// The command would break a rule the server also checks.
    #[error("{message}")]
    Invalid { message: String },
    /// The server sent data for another account than the one stored here.
    #[error("this device's local data belongs to another account")]
    OtherAccount,
    /// The store was closed, as when the app leaves the foreground.
    #[error("the store is closed")]
    Closed,
    /// SQLite, or a body that is not what the sync API sends.
    #[error("{message}")]
    Storage { message: String },
}

impl From<core::Error> for StoreError {
    fn from(error: core::Error) -> StoreError {
        let message = error.to_string();
        match error {
            core::Error::NotFound { .. } | core::Error::Ambiguous { .. } => {
                StoreError::NotFound { message }
            }
            core::Error::Invalid(_) => StoreError::Invalid { message },
            core::Error::Sqlite(_) | core::Error::Json(_) => StoreError::Storage { message },
        }
    }
}

impl From<serde_json::Error> for StoreError {
    fn from(error: serde_json::Error) -> StoreError {
        StoreError::Storage {
            message: error.to_string(),
        }
    }
}

type Result<T> = std::result::Result<T, StoreError>;

/// To-Do, Done, or Dropped, for tasks and projects alike (ADR 0008).
#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum TaskState {
    ToDo,
    Done,
    Dropped,
}

impl From<core::TaskState> for TaskState {
    fn from(state: core::TaskState) -> TaskState {
        match state {
            core::TaskState::ToDo => TaskState::ToDo,
            core::TaskState::Done => TaskState::Done,
            core::TaskState::Dropped => TaskState::Dropped,
        }
    }
}

impl From<TaskState> for core::TaskState {
    fn from(state: TaskState) -> core::TaskState {
        match state {
            TaskState::ToDo => core::TaskState::ToDo,
            TaskState::Done => core::TaskState::Done,
            TaskState::Dropped => core::TaskState::Dropped,
        }
    }
}

/// Active, On Hold, or Dropped (ADR 0005).
#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum TagState {
    Active,
    OnHold,
    Dropped,
}

/// The view a login opens (ADR 0023).
#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum HomeView {
    Inbox,
    OpenTasks,
    Agenda,
    Flagged,
}

/// Where a task lives (ADR 0017).
#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum Location {
    Inbox,
    NoProject,
    Project { id: Uuid },
}

impl From<Location> for core::Location {
    fn from(location: Location) -> core::Location {
        match location {
            Location::Inbox => core::Location::Inbox,
            Location::NoProject => core::Location::NoProject,
            Location::Project { id } => core::Location::Project(id),
        }
    }
}

/// Which tasks to list. See `marskal_sync::TaskFilter`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum TaskFilter {
    Open { unavailable: bool },
    Inbox,
    Project { id: Uuid },
    Tag { id: Uuid },
    Flagged { unavailable: bool },
    All,
}

impl From<TaskFilter> for core::TaskFilter {
    fn from(filter: TaskFilter) -> core::TaskFilter {
        match filter {
            TaskFilter::Open { unavailable } => core::TaskFilter::Open { unavailable },
            TaskFilter::Inbox => core::TaskFilter::Inbox,
            TaskFilter::Project { id } => core::TaskFilter::Project(id),
            TaskFilter::Tag { id } => core::TaskFilter::Tag(id),
            TaskFilter::Flagged { unavailable } => core::TaskFilter::Flagged { unavailable },
            TaskFilter::All => core::TaskFilter::All,
        }
    }
}

/// Defer, Planned, and Due (ADR 0006).
#[derive(Clone, Debug, Default, PartialEq, Eq, uniffi::Record)]
pub struct Dates {
    pub defer_until: Option<Timestamp>,
    pub deferred_indefinitely: bool,
    pub planned_at: Option<Timestamp>,
    pub due_at: Option<Timestamp>,
}

/// A tag on a task, with the names from the root down.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct TagPath {
    pub id: Uuid,
    pub path: Vec<String>,
}

/// A task as a list shows it: its own fields, and what is derived from the
/// tasks above it, its project, and its tags.
#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct TaskItem {
    pub id: Uuid,
    pub title: String,
    pub notes: Option<String>,
    pub url: Option<String>,
    pub state: TaskState,
    pub inbox: bool,
    pub project_id: Option<Uuid>,
    /// The project's title, if the task is in one.
    pub project: Option<String>,
    pub parent_id: Option<Uuid>,
    /// Depth in the outline: 0 for a top-level task.
    pub depth: u32,
    /// Its own flag. `flagged` also counts the project's (ADR 0025).
    pub own_flagged: bool,
    pub flagged: bool,
    /// Its own dates, as an edit form shows them.
    pub dates: Dates,
    /// The dates it goes by, its own or inherited.
    pub effective: Dates,
    /// Own tags, then the project's.
    pub tags: Vec<TagPath>,
    pub deferred: bool,
    pub overdue: bool,
    pub available: bool,
    /// Done or Dropped, by its own state or one above it.
    pub resolved: bool,
    pub series_id: Option<Uuid>,
    pub resolved_at: Option<Timestamp>,
    pub inserted_at: Option<Timestamp>,
}

#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct ProjectItem {
    pub id: Uuid,
    pub title: String,
    pub notes: Option<String>,
    pub url: Option<String>,
    pub flagged: bool,
    pub state: TaskState,
    pub folder_id: Option<Uuid>,
    pub dates: Dates,
    pub series_id: Option<Uuid>,
    pub inserted_at: Option<Timestamp>,
}

#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct FolderItem {
    pub id: Uuid,
    pub name: String,
    pub parent_id: Option<Uuid>,
    /// False for a dropped folder.
    pub active: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct TagItem {
    pub id: Uuid,
    pub name: String,
    pub parent_id: Option<Uuid>,
    pub path: Vec<String>,
    pub state: TagState,
    pub rank: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct Preferences {
    pub timezone: String,
    /// The ISO day weeks start on, 1 for Monday.
    pub week_start: u8,
    /// The CLDR locale dates are formatted in, such as `en-DK` (ADR 0027).
    pub locale: String,
    pub home_view: HomeView,
}

/// What a shell shows about sync.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct SyncStatus {
    pub user_id: Option<String>,
    pub pending: u64,
    pub unseen_rejections: u64,
    pub last_synced_at: Option<Timestamp>,
}

/// A command the server refused (ADR 0019).
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct Rejection {
    pub command_id: String,
    pub entity: String,
    pub entity_id: String,
    pub op: String,
    pub reason: String,
    pub rejected_at: Option<Timestamp>,
}

/// A task to capture. Without a location or a parent it goes to the inbox.
#[derive(Clone, Debug, Default, PartialEq, uniffi::Record)]
pub struct NewTask {
    pub title: String,
    #[uniffi(default = None)]
    pub notes: Option<String>,
    #[uniffi(default = None)]
    pub url: Option<String>,
    #[uniffi(default = false)]
    pub flagged: bool,
    #[uniffi(default = None)]
    pub location: Option<Location>,
    #[uniffi(default = None)]
    pub parent_id: Option<Uuid>,
    #[uniffi(default = None)]
    pub deferred: Option<Defer>,
    #[uniffi(default = None)]
    pub planned_at: Option<Timestamp>,
    #[uniffi(default = None)]
    pub due_at: Option<Timestamp>,
}

/// Deferred until an instant, or with no end (ADR 0006).
#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum Defer {
    Until { at: Timestamp },
    Indefinitely,
}

/// One field of a task to change, or clear with `None`.
#[derive(Clone, Debug, PartialEq, uniffi::Enum)]
pub enum TaskChange {
    Title {
        title: String,
    },
    Notes {
        notes: Option<String>,
    },
    /// Blank clears it too.
    Url {
        url: Option<String>,
    },
    Flagged {
        flagged: bool,
    },
    Planned {
        at: Option<Timestamp>,
    },
    Due {
        at: Option<Timestamp>,
    },
    Deferred {
        deferred: Option<Defer>,
    },
}

#[derive(Clone, Debug, Default, PartialEq, uniffi::Record)]
pub struct NewProject {
    pub title: String,
    #[uniffi(default = None)]
    pub notes: Option<String>,
    #[uniffi(default = None)]
    pub url: Option<String>,
    #[uniffi(default = false)]
    pub flagged: bool,
    #[uniffi(default = None)]
    pub folder_id: Option<Uuid>,
}

/// The body for `POST /api/v1/sync/push`, and how many commands it holds.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct PushBatch {
    pub body: String,
    pub count: u64,
}

/// What one push did to the outbox.
#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Record)]
pub struct PushSummary {
    /// Results the server sent. Fewer than the batch means it stopped part
    /// way, and the rest go next time.
    pub answered: u64,
    pub accepted: u64,
    pub rejected: u64,
}

/// What one pull brought.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct PullSummary {
    pub cursor: i64,
    /// Pull again: the server has more after this cursor.
    pub more: bool,
}

/// The local database (ADR 0029): one SQLite file in the App Group, opened
/// by the app and by the widget. Close it before the app is suspended, so
/// it holds no lock; every call after that fails with `Closed`.
#[derive(uniffi::Object)]
pub struct Store {
    inner: Mutex<Option<core::Store>>,
}

#[uniffi::export]
impl Store {
    /// Opens or creates the database at `path` and migrates it.
    #[uniffi::constructor]
    pub fn open(path: String) -> Result<Store> {
        Ok(Store {
            inner: Mutex::new(Some(core::Store::open(path)?)),
        })
    }

    /// Closes the database. Calls after this fail with `Closed`.
    pub fn close(&self) {
        self.lock().take();
    }

    /// Changes when another process commits a write, such as the widget.
    pub fn data_version(&self) -> Result<i64> {
        self.with(|store| Ok(store.data_version()?))
    }

    pub fn status(&self) -> Result<SyncStatus> {
        self.with(|store| {
            let status = store.status()?;
            Ok(SyncStatus {
                user_id: status.user_id,
                pending: status.pending as u64,
                unseen_rejections: status.unseen_rejections as u64,
                last_synced_at: timestamp(&status.last_synced_at),
            })
        })
    }

    /// The user's preferences, once a pull has brought them (ADR 0023).
    pub fn preferences(&self) -> Result<Option<Preferences>> {
        self.with(|store| Ok(store.preferences()?.map(preferences)))
    }

    pub fn tasks(&self, filter: TaskFilter) -> Result<Vec<TaskItem>> {
        self.with(|store| {
            let world = store.world()?;
            Ok(world.tasks(filter.into()).into_iter().map(task).collect())
        })
    }

    /// A live task, or `None`.
    pub fn task(&self, id: Uuid) -> Result<Option<TaskItem>> {
        self.with(|store| {
            let world = store.world()?;
            Ok(world.task(id).map(|t| task(world.view(t))))
        })
    }

    /// Every live project, resolved ones too, by title.
    pub fn projects(&self) -> Result<Vec<ProjectItem>> {
        self.with(|store| {
            let mut projects: Vec<ProjectItem> =
                store.world()?.projects.into_iter().map(project).collect();
            projects.sort_by_cached_key(|p| (p.title.to_lowercase(), p.id));
            Ok(projects)
        })
    }

    /// Every live folder, by name.
    pub fn folders(&self) -> Result<Vec<FolderItem>> {
        self.with(|store| {
            let mut folders: Vec<FolderItem> = store
                .world()?
                .folders
                .into_iter()
                .map(|f| FolderItem {
                    id: f.id,
                    name: f.name,
                    parent_id: f.parent_id,
                    active: f.state == core::FolderState::Active,
                })
                .collect();
            folders.sort_by_cached_key(|f| (f.name.to_lowercase(), f.id));
            Ok(folders)
        })
    }

    /// Every live tag, by path.
    pub fn tags(&self) -> Result<Vec<TagItem>> {
        self.with(|store| {
            let world = store.world()?;
            let mut tags: Vec<TagItem> = world
                .tags
                .iter()
                .map(|t| TagItem {
                    id: t.id,
                    name: t.name.clone(),
                    parent_id: t.parent_id,
                    path: world.tag_path(t.id),
                    state: tag_state(t.state),
                    rank: t.rank.clone(),
                })
                .collect();
            tags.sort_by_cached_key(|t| {
                (
                    t.path.iter().map(|p| p.to_lowercase()).collect::<Vec<_>>(),
                    t.id,
                )
            });
            Ok(tags)
        })
    }

    /// Captures a task. Returns its id.
    pub fn add_task(&self, new: NewTask) -> Result<Uuid> {
        self.with(|store| {
            Ok(store.add_task(core::NewTask {
                title: new.title,
                notes: new.notes,
                url: new.url,
                flagged: new.flagged,
                location: new.location.map(Into::into),
                parent_id: new.parent_id,
                defer_until: match new.deferred {
                    Some(Defer::Until { at }) => Some(at),
                    _ => None,
                },
                deferred_indefinitely: new.deferred == Some(Defer::Indefinitely),
                planned_at: new.planned_at,
                due_at: new.due_at,
            })?)
        })
    }

    /// Changes fields of a task, as one command.
    pub fn edit_task(&self, id: Uuid, changes: Vec<TaskChange>) -> Result<()> {
        let mut patch = core::TaskPatch::default();
        for change in changes {
            match change {
                TaskChange::Title { title } => patch.title = Some(title),
                TaskChange::Notes { notes } => patch.notes = Some(notes),
                TaskChange::Url { url } => patch.url = Some(url),
                TaskChange::Flagged { flagged } => patch.flagged = Some(flagged),
                TaskChange::Planned { at } => patch.planned_at = Some(at),
                TaskChange::Due { at } => patch.due_at = Some(at),
                TaskChange::Deferred { deferred } => match deferred {
                    Some(Defer::Indefinitely) => patch.defer_indefinitely = true,
                    Some(Defer::Until { at }) => patch.defer_until = Some(Some(at)),
                    None => patch.defer_until = Some(None),
                },
            }
        }
        self.with(|store| Ok(store.edit_task(id, patch)?))
    }

    /// Marks a task Done, Dropped, or To-Do again.
    pub fn set_task_state(&self, id: Uuid, state: TaskState) -> Result<()> {
        self.with(|store| Ok(store.set_task_state(id, state.into())?))
    }

    /// Moves a task, with its subtasks, out of its parent.
    pub fn move_task(&self, id: Uuid, location: Location) -> Result<()> {
        self.with(|store| Ok(store.move_task(id, location.into())?))
    }

    /// Makes a task the last subtask of `parent_id`, or top-level for `None`.
    pub fn set_parent(&self, id: Uuid, parent_id: Option<Uuid>) -> Result<()> {
        self.with(|store| Ok(store.set_parent(id, parent_id)?))
    }

    /// Deletes a task and its subtasks.
    pub fn delete_task(&self, id: Uuid) -> Result<()> {
        self.with(|store| Ok(store.delete_task(id)?))
    }

    /// Creates a project. Returns its id.
    pub fn add_project(&self, new: NewProject) -> Result<Uuid> {
        self.with(|store| {
            Ok(store.add_project(core::NewProject {
                title: new.title,
                notes: new.notes,
                url: new.url,
                flagged: new.flagged,
                folder_id: new.folder_id,
            })?)
        })
    }

    pub fn set_project_state(&self, id: Uuid, state: TaskState) -> Result<()> {
        self.with(|store| Ok(store.set_project_state(id, state.into())?))
    }

    pub fn set_project_flagged(&self, id: Uuid, flagged: bool) -> Result<()> {
        self.with(|store| Ok(store.set_project_flagged(id, flagged)?))
    }

    /// Creates a tag under `parent_id`, or at the top. Returns its id.
    pub fn add_tag(&self, name: String, parent_id: Option<Uuid>) -> Result<Uuid> {
        self.with(|store| Ok(store.add_tag(&name, parent_id)?))
    }

    pub fn tag_task(&self, task_id: Uuid, tag_id: Uuid) -> Result<()> {
        self.with(|store| Ok(store.tag_task(task_id, tag_id)?))
    }

    pub fn untag_task(&self, task_id: Uuid, tag_id: Uuid) -> Result<()> {
        self.with(|store| Ok(store.untag_task(task_id, tag_id)?))
    }

    pub fn tag_project(&self, project_id: Uuid, tag_id: Uuid) -> Result<()> {
        self.with(|store| Ok(store.tag_project(project_id, tag_id)?))
    }

    pub fn untag_project(&self, project_id: Uuid, tag_id: Uuid) -> Result<()> {
        self.with(|store| Ok(store.untag_project(project_id, tag_id)?))
    }

    /// The oldest `limit` commands not yet accepted, as a push body, or
    /// `None` when the outbox is empty.
    pub fn push_batch(&self, limit: u64) -> Result<Option<PushBatch>> {
        self.with(|store| {
            let commands = store.pending(limit as usize)?;
            if commands.is_empty() {
                return Ok(None);
            }
            Ok(Some(PushBatch {
                count: commands.len() as u64,
                body: serde_json::json!({ "commands": commands }).to_string(),
            }))
        })
    }

    /// Takes a push response's results out of the outbox.
    pub fn record_push(&self, response: String) -> Result<PushSummary> {
        #[derive(serde::Deserialize)]
        struct Body {
            results: Vec<core::PushResult>,
        }
        let body: Body = serde_json::from_str(&response)?;

        self.with(|store| {
            let summary = store.record_push(&body.results)?;
            Ok(PushSummary {
                answered: body.results.len() as u64,
                accepted: summary.accepted as u64,
                rejected: summary.rejected as u64,
            })
        })
    }

    /// The cursor for the next pull, or `None` to ask for a snapshot.
    pub fn pull_cursor(&self) -> Result<Option<i64>> {
        self.with(|store| Ok(store.pull_cursor()?))
    }

    /// Asks for a snapshot on the next pull, as after `410 Gone`.
    pub fn reset_cursor(&self) -> Result<()> {
        self.with(|store| Ok(store.reset_cursor()?))
    }

    /// Merges a pull response. Fails with `OtherAccount`, changing
    /// nothing, when the local data belongs to another user.
    pub fn apply_pull(&self, response: String) -> Result<PullSummary> {
        let response: core::PullResponse = serde_json::from_str(&response)?;

        self.with(|store| {
            if let Some(local) = store.status()?.user_id
                && local != response.user.id
            {
                return Err(StoreError::OtherAccount);
            }

            store.apply_pull(&response)?;
            Ok(PullSummary {
                cursor: response.cursor,
                more: response.more,
            })
        })
    }

    /// Records a finished push and pull.
    pub fn mark_synced(&self) -> Result<()> {
        self.with(|store| Ok(store.mark_synced()?))
    }

    /// Commands the server refused, newest first.
    pub fn rejections(&self, unseen: bool) -> Result<Vec<Rejection>> {
        self.with(|store| {
            Ok(store
                .rejections(unseen)?
                .into_iter()
                .map(|r| Rejection {
                    rejected_at: timestamp(&Some(r.rejected_at)),
                    command_id: r.command_id,
                    entity: r.entity,
                    entity_id: r.entity_id,
                    op: r.op,
                    reason: r.reason,
                })
                .collect())
        })
    }

    pub fn mark_rejections_seen(&self) -> Result<()> {
        self.with(|store| Ok(store.mark_rejections_seen()?))
    }
}

impl Store {
    fn lock(&self) -> MutexGuard<'_, Option<core::Store>> {
        // A panic inside a call leaves the store as SQLite left it, which
        // rolled back any open transaction.
        self.inner
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn with<T>(&self, f: impl FnOnce(&mut core::Store) -> Result<T>) -> Result<T> {
        match self.lock().as_mut() {
            Some(store) => f(store),
            None => Err(StoreError::Closed),
        }
    }
}

/// Whether a URL may go on a task or project (ADR 0022).
#[uniffi::export]
pub fn url_is_valid(url: String) -> bool {
    core::url::valid(&url)
}

fn timestamp(text: &Option<String>) -> Option<Timestamp> {
    text.as_deref().and_then(|t| t.parse().ok())
}

fn dates(
    defer_until: &Option<String>,
    deferred_indefinitely: bool,
    planned_at: &Option<String>,
    due_at: &Option<String>,
) -> Dates {
    Dates {
        defer_until: timestamp(defer_until),
        deferred_indefinitely,
        planned_at: timestamp(planned_at),
        due_at: timestamp(due_at),
    }
}

fn task(view: core::TaskView) -> TaskItem {
    let t = view.task;
    TaskItem {
        dates: dates(
            &t.defer_until,
            t.deferred_indefinitely,
            &t.planned_at,
            &t.due_at,
        ),
        effective: dates(
            &view.effective.defer_until,
            view.effective.deferred_indefinitely,
            &view.effective.planned_at,
            &view.effective.due_at,
        ),
        resolved_at: timestamp(&t.resolved_at),
        inserted_at: timestamp(&t.inserted_at),
        id: t.id,
        title: t.title,
        notes: t.notes,
        url: t.url,
        state: t.state.into(),
        inbox: t.inbox,
        project_id: t.project_id,
        project: view.project,
        parent_id: t.parent_id,
        depth: view.depth as u32,
        own_flagged: t.flagged,
        flagged: view.flagged,
        tags: view
            .tags
            .into_iter()
            .map(|tag| TagPath {
                id: tag.id,
                path: tag.path,
            })
            .collect(),
        deferred: view.deferred,
        overdue: view.overdue,
        available: view.available,
        resolved: view.resolved,
        series_id: t.series_id,
    }
}

fn project(p: core::Project) -> ProjectItem {
    ProjectItem {
        dates: dates(
            &p.defer_until,
            p.deferred_indefinitely,
            &p.planned_at,
            &p.due_at,
        ),
        inserted_at: timestamp(&p.inserted_at),
        id: p.id,
        title: p.title,
        notes: p.notes,
        url: p.url,
        flagged: p.flagged,
        state: p.state.into(),
        folder_id: p.project_folder_id,
        series_id: p.series_id,
    }
}

fn tag_state(state: core::TagState) -> TagState {
    match state {
        core::TagState::Active => TagState::Active,
        core::TagState::OnHold => TagState::OnHold,
        core::TagState::Dropped => TagState::Dropped,
    }
}

fn preferences(p: core::UserPreferences) -> Preferences {
    Preferences {
        timezone: p.timezone,
        week_start: p.week_start,
        locale: p.locale,
        home_view: match p.home_view {
            core::HomeView::Inbox => HomeView::Inbox,
            core::HomeView::OpenTasks => HomeView::OpenTasks,
            core::HomeView::Agenda => HomeView::Agenda,
            core::HomeView::Flagged => HomeView::Flagged,
        },
    }
}
