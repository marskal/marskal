use serde::{Deserialize, Serialize};

/// The synced entity types, named as the sync API names them (ADR 0019).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Entity {
    ProjectFolder,
    Project,
    Tag,
    Task,
    TaskTag,
    ProjectTag,
}

/// How a column is stored locally.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Kind {
    Text,
    Bool,
}

/// A synced field. The names are the server's.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Column {
    pub name: &'static str,
    pub kind: Kind,
}

const fn text(name: &'static str) -> Column {
    Column {
        name,
        kind: Kind::Text,
    }
}

const fn boolean(name: &'static str) -> Column {
    Column {
        name,
        kind: Kind::Bool,
    }
}

const TASK: &[Column] = &[
    text("id"),
    text("title"),
    text("notes"),
    text("state"),
    boolean("inbox"),
    text("project_id"),
    text("parent_id"),
    text("rank"),
    text("defer_until"),
    boolean("deferred_indefinitely"),
    text("planned_at"),
    text("due_at"),
    text("resolved_at"),
    text("discarded_at"),
    text("inserted_at"),
    text("updated_at"),
];

const PROJECT: &[Column] = &[
    text("id"),
    text("title"),
    text("notes"),
    text("state"),
    text("project_folder_id"),
    text("defer_until"),
    boolean("deferred_indefinitely"),
    text("planned_at"),
    text("due_at"),
    text("resolved_at"),
    text("discarded_at"),
    text("inserted_at"),
    text("updated_at"),
];

const PROJECT_FOLDER: &[Column] = &[
    text("id"),
    text("name"),
    text("parent_id"),
    text("state"),
    text("discarded_at"),
    text("inserted_at"),
    text("updated_at"),
];

const TAG: &[Column] = &[
    text("id"),
    text("name"),
    text("parent_id"),
    text("state"),
    text("rank"),
    text("merged_into_id"),
    text("discarded_at"),
    text("inserted_at"),
    text("updated_at"),
];

const TASK_TAG: &[Column] = &[
    text("id"),
    text("task_id"),
    text("tag_id"),
    text("discarded_at"),
    text("inserted_at"),
    text("updated_at"),
];

const PROJECT_TAG: &[Column] = &[
    text("id"),
    text("project_id"),
    text("tag_id"),
    text("discarded_at"),
    text("inserted_at"),
    text("updated_at"),
];

impl Entity {
    /// Every type, in the order rows are applied: containers first, so a
    /// row usually arrives after the row it refers to.
    pub const ALL: [Entity; 6] = [
        Entity::ProjectFolder,
        Entity::Project,
        Entity::Tag,
        Entity::Task,
        Entity::TaskTag,
        Entity::ProjectTag,
    ];

    /// The name on the wire.
    pub fn as_str(self) -> &'static str {
        match self {
            Entity::ProjectFolder => "project_folder",
            Entity::Project => "project",
            Entity::Tag => "tag",
            Entity::Task => "task",
            Entity::TaskTag => "task_tag",
            Entity::ProjectTag => "project_tag",
        }
    }

    pub(crate) fn parse(name: &str) -> Option<Entity> {
        Entity::ALL
            .into_iter()
            .find(|entity| entity.as_str() == name)
    }

    pub(crate) fn table(self) -> &'static str {
        match self {
            Entity::ProjectFolder => "project_folders",
            Entity::Project => "projects",
            Entity::Tag => "tags",
            Entity::Task => "tasks",
            Entity::TaskTag => "task_tags",
            Entity::ProjectTag => "project_tags",
        }
    }

    pub(crate) fn columns(self) -> &'static [Column] {
        match self {
            Entity::ProjectFolder => PROJECT_FOLDER,
            Entity::Project => PROJECT,
            Entity::Tag => TAG,
            Entity::Task => TASK,
            Entity::TaskTag => TASK_TAG,
            Entity::ProjectTag => PROJECT_TAG,
        }
    }

    pub(crate) fn column(self, name: &str) -> Option<Column> {
        self.columns()
            .iter()
            .copied()
            .find(|column| column.name == name)
    }

    /// Link rows: whether the link exists is their only content, so their
    /// `discarded_at` is an ordinary field (ADR 0014).
    pub(crate) fn is_link(self) -> bool {
        matches!(self, Entity::TaskTag | Entity::ProjectTag)
    }
}

impl std::fmt::Display for Entity {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}
