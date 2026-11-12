//! Rows as a shell reads them. Field names and values are the sync API's
//! (ADR 0019); timestamps stay in its UTC string form.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use uuid::Uuid;

/// To-Do, Done, or Dropped, for tasks and projects alike (ADR 0008).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TaskState {
    ToDo,
    Done,
    Dropped,
}

pub type ProjectState = TaskState;

impl TaskState {
    pub fn as_str(self) -> &'static str {
        match self {
            TaskState::ToDo => "to_do",
            TaskState::Done => "done",
            TaskState::Dropped => "dropped",
        }
    }

    pub fn is_resolved(self) -> bool {
        self != TaskState::ToDo
    }
}

/// Active, On Hold, or Dropped (ADR 0005).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TagState {
    Active,
    OnHold,
    Dropped,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FolderState {
    Active,
    Dropped,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Task {
    pub id: Uuid,
    pub title: String,
    pub notes: Option<String>,
    pub url: Option<String>,
    pub flagged: bool,
    pub state: TaskState,
    pub inbox: bool,
    pub project_id: Option<Uuid>,
    pub parent_id: Option<Uuid>,
    pub rank: Option<String>,
    pub defer_until: Option<String>,
    pub deferred_indefinitely: bool,
    pub planned_at: Option<String>,
    pub due_at: Option<String>,
    pub series_id: Option<Uuid>,
    pub occurrence_for: Option<String>,
    pub resolved_at: Option<String>,
    pub discarded_at: Option<String>,
    pub inserted_at: Option<String>,
    pub updated_at: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Project {
    pub id: Uuid,
    pub title: String,
    pub notes: Option<String>,
    pub url: Option<String>,
    pub flagged: bool,
    pub state: ProjectState,
    pub project_folder_id: Option<Uuid>,
    pub rank: Option<String>,
    pub defer_until: Option<String>,
    pub deferred_indefinitely: bool,
    pub planned_at: Option<String>,
    pub due_at: Option<String>,
    pub series_id: Option<Uuid>,
    pub occurrence_for: Option<String>,
    /// How far apart reviews are, as ISO 8601 date parts (`P7D`, `P1M`);
    /// `None` is Never (ADR 0026). `marskal_rules::review::parse` reads it.
    pub review_interval: Option<String>,
    /// The day, `YYYY-MM-DD` on the user's clock, the project is next due
    /// for review. `None` exactly when the interval is.
    pub next_review_on: Option<String>,
    pub last_reviewed_at: Option<String>,
    pub resolved_at: Option<String>,
    pub discarded_at: Option<String>,
    pub inserted_at: Option<String>,
    pub updated_at: Option<String>,
}

/// What a series repeats (ADR 0007).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SeriesKind {
    Task,
    Project,
}

/// Regular: on the schedule, open or not. On completion: when the last
/// one is Done or Dropped.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Mode {
    Regular,
    OnCompletion,
}

/// The date field the rule advances.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Anchor {
    Defer,
    Planned,
    Due,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Frequency {
    Minutes,
    Hours,
    Days,
    Weeks,
    Months,
    Years,
}

/// The view a login opens.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HomeView {
    Inbox,
    OpenTasks,
    Agenda,
    Flagged,
}

/// Which keyboard map list navigation uses (ADR 0031).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Keymap {
    Standard,
    Vim,
}

/// The user's preferences, one row keyed by the user id (ADR 0023).
/// `week_start` is the ISO day weeks start on, 1 for Monday. `locale` is
/// the CLDR locale dates and times are formatted in, such as `en-DK`
/// (ADR 0027). `home_view` is the view a login opens. `keymap` chooses
/// the keyboard map (ADR 0031). `default_review_interval` is the review
/// interval new projects take, `None` for Never (ADR 0026).
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct UserPreferences {
    pub id: Uuid,
    pub timezone: String,
    pub week_start: u8,
    pub locale: String,
    pub home_view: HomeView,
    pub keymap: Keymap,
    pub default_review_interval: Option<String>,
    pub inserted_at: Option<String>,
    pub updated_at: Option<String>,
}

/// A recurrence rule and the identity its occurrences share (ADR 0007).
/// `weekdays` are ISO numbers, 1 for Monday. `on_days` are a monthly or
/// yearly rule's rows, `ordinal:kind` with the month first for a year:
/// `"14:day"`, `"-1:day"`, `"2:tuesday"`, `"-1:work_day"`, `"10:-1:monday"`.
/// Ordinals go to 31 for a day, 5 for a weekday, 23 for a work day, and 10
/// for a weekend day; -1 to -5 count from the end, -1 being the last.
/// `week_start` is the ISO day weeks start on, kept from when the series
/// was made.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Series {
    pub id: Uuid,
    pub kind: SeriesKind,
    pub mode: Mode,
    pub anchor: Anchor,
    pub interval: u32,
    pub frequency: Frequency,
    pub weekdays: Vec<u8>,
    pub on_days: Vec<String>,
    pub ends_at: Option<String>,
    pub end_count: Option<u32>,
    pub week_start: u8,
    pub stopped_at: Option<String>,
    pub discarded_at: Option<String>,
    pub inserted_at: Option<String>,
    pub updated_at: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Folder {
    pub id: Uuid,
    pub name: String,
    pub parent_id: Option<Uuid>,
    pub rank: Option<String>,
    pub state: FolderState,
    pub discarded_at: Option<String>,
    pub inserted_at: Option<String>,
    pub updated_at: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Tag {
    pub id: Uuid,
    pub name: String,
    pub parent_id: Option<Uuid>,
    pub state: TagState,
    pub rank: Option<String>,
    pub merged_into_id: Option<Uuid>,
    pub discarded_at: Option<String>,
    pub inserted_at: Option<String>,
    pub updated_at: Option<String>,
}

/// A task↔tag or project↔tag row. `owner_id` is the task or project.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Link {
    pub id: Uuid,
    pub owner_id: Uuid,
    pub tag_id: Uuid,
}

/// A command the server refused (ADR 0019).
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Rejection {
    pub command_id: String,
    pub entity: String,
    pub entity_id: String,
    pub op: String,
    pub fields: Value,
    pub reason: String,
    pub errors: Option<Value>,
    pub rejected_at: String,
}
