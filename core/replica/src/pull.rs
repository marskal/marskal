//! The pull merge of ADR 0014 and ADR 0019.

use std::collections::{BTreeMap, HashSet};

use rusqlite::{Connection, OptionalExtension, params_from_iter};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use crate::entity::Entity;
use crate::error::Result;
use crate::push::{Pending, pending_fields};
use crate::store::{Store, meta, set_meta};
use crate::value::to_sql;

/// `GET /api/v1/sync/pull`.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct PullResponse {
    pub cursor: i64,
    pub snapshot: bool,
    pub more: bool,
    pub user: PullUser,
    /// Rows by entity name. A type this library does not know is skipped.
    pub rows: BTreeMap<String, Vec<Map<String, Value>>>,
    #[serde(default)]
    pub gone: Vec<Gone>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PullUser {
    pub id: String,
    pub timezone: String,
}

/// A row the user can no longer see.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Gone {
    pub entity: String,
    pub id: String,
}

impl Store {
    /// The cursor for the next pull. `None` asks for a snapshot: on the
    /// first sync, after a rejected command, or after [`Store::reset_cursor`].
    pub fn pull_cursor(&self) -> Result<Option<i64>> {
        if meta(&self.conn, "needs_snapshot")?.as_deref() == Some("1") {
            return Ok(None);
        }
        Ok(meta(&self.conn, "cursor")?.and_then(|cursor| cursor.parse().ok()))
    }

    /// Asks for a snapshot on the next pull, as after `410 Gone`. The
    /// outbox is kept.
    pub fn reset_cursor(&mut self) -> Result<()> {
        set_meta(&self.conn, "needs_snapshot", Some("1"))
    }

    /// Merges a pull response. A field with a pending local edit keeps the
    /// local value; every other field takes the server's. Discard wins.
    /// A snapshot also drops local rows the server no longer has, except
    /// ones made here and not pushed yet.
    pub fn apply_pull(&mut self, response: &PullResponse) -> Result<()> {
        self.write(|tx, _now| {
            for entity in Entity::ALL {
                let rows = response
                    .rows
                    .get(entity.as_str())
                    .map(Vec::as_slice)
                    .unwrap_or_default();

                if response.snapshot {
                    drop_missing(tx, entity, rows)?;
                }

                for row in rows {
                    merge_row(tx, entity, row)?;
                }
            }

            for gone in &response.gone {
                if let Some(entity) = Entity::parse(&gone.entity) {
                    tx.execute(
                        &format!("DELETE FROM {} WHERE id = ?1", entity.table()),
                        [&gone.id],
                    )?;
                }
            }

            set_meta(tx, "cursor", Some(&response.cursor.to_string()))?;
            set_meta(tx, "user_id", Some(&response.user.id))?;
            set_meta(tx, "timezone", Some(&response.user.timezone))?;

            if response.snapshot {
                set_meta(tx, "needs_snapshot", None)?;
            }

            Ok(())
        })
    }
}

fn drop_missing(conn: &Connection, entity: Entity, rows: &[Map<String, Value>]) -> Result<()> {
    let keep: HashSet<&str> = rows
        .iter()
        .filter_map(|row| row.get("id").and_then(Value::as_str))
        .collect();

    let local: Vec<String> = conn
        .prepare(&format!("SELECT id FROM {}", entity.table()))?
        .query_map([], |row| row.get(0))?
        .collect::<std::result::Result<_, _>>()?;

    for id in local.iter().filter(|id| !keep.contains(id.as_str())) {
        if pending_fields(conn, entity, id)? != Pending::Insert {
            conn.execute(
                &format!("DELETE FROM {} WHERE id = ?1", entity.table()),
                [id],
            )?;
        }
    }

    Ok(())
}

fn merge_row(conn: &Connection, entity: Entity, row: &Map<String, Value>) -> Result<()> {
    let Some(id) = row.get("id").and_then(Value::as_str) else {
        return Ok(());
    };

    let exists = conn
        .query_row(
            &format!("SELECT 1 FROM {} WHERE id = ?1", entity.table()),
            [id],
            |_| Ok(()),
        )
        .optional()?
        .is_some();

    let known = entity
        .columns()
        .iter()
        .filter(|column| row.contains_key(column.name));

    if !exists {
        let names: Vec<&str> = known.map(|column| column.name).collect();
        let sql = format!(
            "INSERT INTO {} ({}) VALUES ({})",
            entity.table(),
            names.join(", "),
            vec!["?"; names.len()].join(", ")
        );
        conn.execute(
            &sql,
            params_from_iter(names.iter().map(|name| to_sql(&row[*name]))),
        )?;
        return Ok(());
    }

    let pending = pending_fields(conn, entity, id)?;
    let server_discarded = !row.get("discarded_at").unwrap_or(&Value::Null).is_null();

    let take: Vec<&str> = known
        .map(|column| column.name)
        .filter(|&name| name != "id")
        .filter(|&name| match name {
            // Discard wins over a pending edit, except on a link row, where
            // it is an ordinary field (ADR 0014).
            "discarded_at" if server_discarded && !entity.is_link() => true,
            // A pending resolve set resolved_at here; keep it with the state.
            "resolved_at" => !pending.holds("state") && !pending.holds(name),
            _ => !pending.holds(name),
        })
        .collect();

    if take.is_empty() {
        return Ok(());
    }

    let sets: Vec<String> = take
        .iter()
        .enumerate()
        .map(|(i, name)| format!("{name} = ?{}", i + 1))
        .collect();

    let sql = format!(
        "UPDATE {} SET {} WHERE id = ?{}",
        entity.table(),
        sets.join(", "),
        take.len() + 1
    );

    let values = take
        .iter()
        .map(|name| to_sql(&row[*name]))
        .chain(std::iter::once(to_sql(&Value::from(id))));

    conn.execute(&sql, params_from_iter(values))?;
    Ok(())
}
