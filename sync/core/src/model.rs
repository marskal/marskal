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
    pub state: TaskState,
    pub inbox: bool,
    pub project_id: Option<Uuid>,
    pub parent_id: Option<Uuid>,
    pub rank: Option<String>,
    pub defer_until: Option<String>,
    pub deferred_indefinitely: bool,
    pub planned_at: Option<String>,
    pub due_at: Option<String>,
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
    pub state: ProjectState,
    pub project_folder_id: Option<Uuid>,
    pub defer_until: Option<String>,
    pub deferred_indefinitely: bool,
    pub planned_at: Option<String>,
    pub due_at: Option<String>,
    pub resolved_at: Option<String>,
    pub discarded_at: Option<String>,
    pub inserted_at: Option<String>,
    pub updated_at: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Folder {
    pub id: Uuid,
    pub name: String,
    pub parent_id: Option<Uuid>,
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
