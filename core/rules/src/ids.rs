//! Ids every client must mint alike (ADR 0005, ADR 0011).

use uuid::Uuid;

/// The namespace of link ids, fixed by ADR 0005. Changing it would rename
/// every link row and duplicate links across devices.
pub const LINK_NAMESPACE: Uuid = uuid::uuid!("a5c0ffee-0005-5000-8000-000000000005");

/// The id people see and type: the last eight hex digits. A UUIDv7 starts
/// with its timestamp, so its start is shared by rows made together; its
/// end is random.
pub fn short(id: &Uuid) -> String {
    let simple = id.simple().to_string();
    simple[simple.len() - 8..].to_string()
}

/// What a link row links: a task or a project.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LinkKind {
    Task,
    Project,
}

impl LinkKind {
    fn as_str(self) -> &'static str {
        match self {
            LinkKind::Task => "task",
            LinkKind::Project => "project",
        }
    }
}

/// The id of the link between an owner and a tag: v5 of the pair, so two
/// devices tagging the same task offline name the same row (ADR 0005).
pub fn link_id(kind: LinkKind, owner_id: Uuid, tag_id: Uuid) -> Uuid {
    let name = format!("{}|{}|{}", kind.as_str(), owner_id, tag_id);
    Uuid::new_v5(&LINK_NAMESPACE, name.as_bytes())
}
