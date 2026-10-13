//! The local SQLite schema and its migrations (ADR 0018).
//!
//! Synced tables mirror the server's rows, with the same field names, and
//! no foreign keys: a pulled row may refer to one that has not arrived yet
//! (ADR 0019). Timestamps are the server's UTC strings, which sort in time
//! order. Ranks compare byte by byte, as SQLite's default collation does.

use rusqlite::Connection;

use crate::error::Result;

const MIGRATIONS: &[&str] = &[
    r#"
CREATE TABLE meta (
  key TEXT PRIMARY KEY,
  value TEXT
);

CREATE TABLE project_folders (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  parent_id TEXT,
  state TEXT NOT NULL DEFAULT 'active',
  discarded_at TEXT,
  inserted_at TEXT,
  updated_at TEXT
);

CREATE TABLE projects (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  notes TEXT,
  state TEXT NOT NULL DEFAULT 'to_do',
  project_folder_id TEXT,
  defer_until TEXT,
  deferred_indefinitely INTEGER NOT NULL DEFAULT 0,
  planned_at TEXT,
  due_at TEXT,
  resolved_at TEXT,
  discarded_at TEXT,
  inserted_at TEXT,
  updated_at TEXT
);

CREATE TABLE tags (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  parent_id TEXT,
  state TEXT NOT NULL DEFAULT 'active',
  rank TEXT,
  merged_into_id TEXT,
  discarded_at TEXT,
  inserted_at TEXT,
  updated_at TEXT
);

CREATE TABLE tasks (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  notes TEXT,
  state TEXT NOT NULL DEFAULT 'to_do',
  inbox INTEGER NOT NULL DEFAULT 1,
  project_id TEXT,
  parent_id TEXT,
  rank TEXT,
  defer_until TEXT,
  deferred_indefinitely INTEGER NOT NULL DEFAULT 0,
  planned_at TEXT,
  due_at TEXT,
  resolved_at TEXT,
  discarded_at TEXT,
  inserted_at TEXT,
  updated_at TEXT
);

CREATE INDEX tasks_parent_id ON tasks (parent_id);
CREATE INDEX tasks_project_id ON tasks (project_id);

CREATE TABLE task_tags (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  discarded_at TEXT,
  inserted_at TEXT,
  updated_at TEXT
);

CREATE TABLE project_tags (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  discarded_at TEXT,
  inserted_at TEXT,
  updated_at TEXT
);

-- Field patches not yet accepted by the server, in the order they were made.
CREATE TABLE outbox (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  command_id TEXT NOT NULL UNIQUE,
  entity TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  op TEXT NOT NULL,
  fields TEXT NOT NULL,
  at TEXT,
  created_at TEXT NOT NULL
);

CREATE INDEX outbox_entity ON outbox (entity, entity_id);

-- Commands the server refused, kept so the user can be told once.
CREATE TABLE rejections (
  command_id TEXT PRIMARY KEY,
  entity TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  op TEXT NOT NULL,
  fields TEXT NOT NULL,
  reason TEXT NOT NULL,
  errors TEXT,
  rejected_at TEXT NOT NULL,
  seen INTEGER NOT NULL DEFAULT 0
);
"#,
    r#"
-- ADR 0007. weekdays and month_days are JSON arrays.
CREATE TABLE recurrence_series (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  mode TEXT NOT NULL,
  anchor TEXT NOT NULL,
  interval INTEGER NOT NULL,
  frequency TEXT NOT NULL,
  weekdays TEXT NOT NULL DEFAULT '[]',
  month_days TEXT NOT NULL DEFAULT '[]',
  month_ordinal INTEGER,
  month_day_kind TEXT,
  ends_at TEXT,
  end_count INTEGER,
  stopped_at TEXT,
  discarded_at TEXT,
  inserted_at TEXT,
  updated_at TEXT
);

ALTER TABLE tasks ADD COLUMN series_id TEXT;
ALTER TABLE tasks ADD COLUMN occurrence_for TEXT;
ALTER TABLE projects ADD COLUMN series_id TEXT;
ALTER TABLE projects ADD COLUMN occurrence_for TEXT;

CREATE INDEX tasks_series_id ON tasks (series_id);
"#,
    // ADR 0022. Rows pulled before this have no URL, so the next pull is a
    // snapshot.
    r#"
ALTER TABLE projects ADD COLUMN url TEXT;
ALTER TABLE tasks ADD COLUMN url TEXT;
INSERT OR REPLACE INTO meta (key, value) VALUES ('needs_snapshot', '1');
"#,
    // ADR 0007, ADR 0023. Series pulled before this were all made with
    // weeks starting on Monday. The preferences row came before any change
    // a cursor covers, so the next pull is a snapshot.
    r#"
ALTER TABLE recurrence_series ADD COLUMN week_start INTEGER NOT NULL DEFAULT 1;

CREATE TABLE user_preferences (
  id TEXT PRIMARY KEY,
  timezone TEXT NOT NULL,
  week_start INTEGER NOT NULL DEFAULT 1,
  inserted_at TEXT,
  updated_at TEXT
);

INSERT OR REPLACE INTO meta (key, value) VALUES ('needs_snapshot', '1');
"#,
    // ADR 0007 (2026-10-09). A monthly or yearly rule's days are one list
    // of rows. Series pulled before this have none, so the next pull is a
    // snapshot.
    r#"
ALTER TABLE recurrence_series DROP COLUMN month_days;
ALTER TABLE recurrence_series DROP COLUMN month_ordinal;
ALTER TABLE recurrence_series DROP COLUMN month_day_kind;
ALTER TABLE recurrence_series ADD COLUMN on_days TEXT NOT NULL DEFAULT '[]';
INSERT OR REPLACE INTO meta (key, value) VALUES ('needs_snapshot', '1');
"#,
    // ADR 0025. Rows pulled before this have no flag, so the next pull is a
    // snapshot.
    r#"
ALTER TABLE projects ADD COLUMN flagged INTEGER NOT NULL DEFAULT 0;
ALTER TABLE tasks ADD COLUMN flagged INTEGER NOT NULL DEFAULT 0;
INSERT OR REPLACE INTO meta (key, value) VALUES ('needs_snapshot', '1');
"#,
    // ADR 0027. A preferences row pulled before this has no locale, so the
    // next pull is a snapshot.
    r#"
ALTER TABLE user_preferences ADD COLUMN locale TEXT NOT NULL DEFAULT 'en-150';
INSERT OR REPLACE INTO meta (key, value) VALUES ('needs_snapshot', '1');
"#,
];

/// Brings the database to the latest schema. `user_version` counts the
/// migrations applied.
pub(crate) fn migrate(conn: &mut Connection) -> Result<()> {
    let applied: i64 = conn.query_row("PRAGMA user_version", [], |row| row.get(0))?;

    for (index, sql) in MIGRATIONS.iter().enumerate().skip(applied as usize) {
        let tx = conn.transaction()?;
        tx.execute_batch(sql)?;
        tx.pragma_update(None, "user_version", (index + 1) as i64)?;
        tx.commit()?;
    }

    Ok(())
}
