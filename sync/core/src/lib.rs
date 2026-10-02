//! The Marskal client sync engine (ADR 0018).
//!
//! One SQLite file holds a cache of the user's rows and an outbox of field
//! patches not yet pushed. A [`Store`] applies a command locally and queues
//! it, merges a pull response field by field, and reads tasks with the
//! derived state the server would compute (ADR 0005, 0006, 0009).
//!
//! The library does no HTTP, keeps no secrets, and schedules nothing. A
//! shell sends [`Store::pending`] to `POST /api/v1/sync/push`, hands the
//! results to [`Store::record_push`], then pulls with [`Store::pull_cursor`]
//! and [`Store::apply_pull`] until the response has no more (ADR 0019).

mod clock;
pub mod dates;
mod entity;
mod error;
pub mod ids;
mod local;
mod model;
mod ops;
mod pull;
mod push;
pub mod rank;
mod schema;
mod store;
mod value;
mod world;

pub use clock::{Clock, SystemClock};
pub use entity::Entity;
pub use error::{Error, Result};
pub use model::{Folder, Link, Project, ProjectState, Rejection, Tag, TagState, Task, TaskState};
pub use ops::{Location, NewProject, NewTask, TaskPatch};
pub use pull::{Gone, PullResponse, PullUser};
pub use push::{Command, Op, PushResult, PushStatus, PushSummary};
pub use store::{Status, Store};
pub use world::{TaskFilter, TaskView, World};
