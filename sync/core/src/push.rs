//! The outbox and the push side of ADR 0019.

use std::collections::HashSet;

use rusqlite::{Connection, params};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use uuid::Uuid;

use crate::clock::stamp;
use crate::entity::Entity;
use crate::error::{Error, Result};
use crate::store::{Store, set_meta};

/// A field patch, as the server takes it on push.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Command {
    pub id: Uuid,
    pub entity: Entity,
    pub entity_id: Uuid,
    pub op: Op,
    pub fields: Map<String, Value>,
    /// When the user acted, by this device's clock. The server takes it
    /// for `resolved_at`, inside a skew window (ADR 0014).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub at: Option<String>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Op {
    Insert,
    Patch,
}

impl Op {
    fn as_str(self) -> &'static str {
        match self {
            Op::Insert => "insert",
            Op::Patch => "patch",
        }
    }
}

/// The server's answer to one command.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct PushResult {
    pub id: Option<Uuid>,
    pub status: PushStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub errors: Option<Value>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PushStatus {
    Applied,
    Noop,
    Replayed,
    Rejected,
}

/// What a push did to the outbox.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize)]
pub struct PushSummary {
    pub accepted: usize,
    pub rejected: usize,
}

impl Store {
    /// The oldest `limit` commands not yet accepted, in the order they were
    /// made. Send them as `{"commands": [...]}`.
    pub fn pending(&self, limit: usize) -> Result<Vec<Command>> {
        let mut statement = self.conn.prepare(
            "SELECT command_id, entity, entity_id, op, fields, at
             FROM outbox ORDER BY seq LIMIT ?1",
        )?;

        let rows = statement.query_map([limit as i64], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
                row.get::<_, String>(4)?,
                row.get::<_, Option<String>>(5)?,
            ))
        })?;

        rows.map(|row| {
            let (id, entity, entity_id, op, fields, at) = row?;
            Ok(Command {
                id: parse_uuid(&id)?,
                entity: Entity::parse(&entity)
                    .ok_or_else(|| Error::Invalid(format!("unknown entity {entity}")))?,
                entity_id: parse_uuid(&entity_id)?,
                op: if op == "insert" {
                    Op::Insert
                } else {
                    Op::Patch
                },
                fields: serde_json::from_str(&fields)?,
                at,
            })
        })
        .collect()
    }

    pub fn pending_count(&self) -> Result<usize> {
        let count: i64 = self
            .conn
            .query_row("SELECT count(*) FROM outbox", [], |row| row.get(0))?;
        Ok(count as usize)
    }

    /// Takes the push results out of the outbox. Accepted commands go. A
    /// rejected one goes too, into the rejections, and the next pull is a
    /// snapshot: an incremental pull only carries rows the server changed,
    /// so it would not undo the refused edit here (ADR 0019).
    pub fn record_push(&mut self, results: &[PushResult]) -> Result<PushSummary> {
        self.write(|tx, now| {
            let mut summary = PushSummary::default();

            for result in results {
                let Some(id) = result.id else { continue };
                let id = id.to_string();

                if result.status == PushStatus::Rejected {
                    let moved = tx.execute(
                        "INSERT OR REPLACE INTO rejections
                           (command_id, entity, entity_id, op, fields, reason, errors, rejected_at)
                         SELECT command_id, entity, entity_id, op, fields, ?2, ?3, ?4
                         FROM outbox WHERE command_id = ?1",
                        params![
                            id,
                            result.reason.as_deref().unwrap_or("rejected"),
                            result.errors.as_ref().map(Value::to_string),
                            stamp(now)
                        ],
                    )?;

                    if moved > 0 {
                        summary.rejected += 1;
                        set_meta(tx, "needs_snapshot", Some("1"))?;
                    }
                } else {
                    summary.accepted += 1;
                }

                tx.execute("DELETE FROM outbox WHERE command_id = ?1", [&id])?;
            }

            Ok(summary)
        })
    }
}

/// Queues a command applied locally.
pub(crate) fn enqueue(conn: &Connection, command: &Command, now: &str) -> Result<()> {
    conn.execute(
        "INSERT INTO outbox (command_id, entity, entity_id, op, fields, at, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        params![
            command.id.to_string(),
            command.entity.as_str(),
            command.entity_id.to_string(),
            command.op.as_str(),
            Value::Object(command.fields.clone()).to_string(),
            command.at,
            now
        ],
    )?;
    Ok(())
}

/// Which local fields of a row still wait for the server. A pull keeps
/// those and takes the server's value for the rest (ADR 0014).
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum Pending {
    /// The row was made here and the server has not taken it yet.
    Insert,
    Fields(HashSet<String>),
}

impl Pending {
    pub(crate) fn holds(&self, field: &str) -> bool {
        match self {
            Pending::Insert => true,
            Pending::Fields(fields) => fields.contains(field),
        }
    }
}

pub(crate) fn pending_fields(conn: &Connection, entity: Entity, id: &str) -> Result<Pending> {
    let mut statement =
        conn.prepare_cached("SELECT op, fields FROM outbox WHERE entity = ?1 AND entity_id = ?2")?;
    let mut rows = statement.query(params![entity.as_str(), id])?;
    let mut fields = HashSet::new();

    while let Some(row) = rows.next()? {
        if row.get::<_, String>(0)? == "insert" {
            return Ok(Pending::Insert);
        }
        let patch: Map<String, Value> = serde_json::from_str(&row.get::<_, String>(1)?)?;
        fields.extend(patch.into_iter().map(|(field, _)| field));
    }

    Ok(Pending::Fields(fields))
}

fn parse_uuid(text: &str) -> Result<Uuid> {
    Uuid::parse_str(text).map_err(|_| Error::Invalid(format!("bad id {text}")))
}
