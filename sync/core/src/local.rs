//! Applying a command to the local rows, as the server will (ADR 0014).
//!
//! The server stays the authority. The effects here are what a user should
//! see before the next sync: a moved task's subtasks moving with it, a
//! deleted project's tasks going. Rows written as a side effect are not
//! dirty, so the next pull overwrites them with the server's result.

use std::collections::HashSet;

use jiff::Timestamp;
use rusqlite::{Connection, OptionalExtension, params, params_from_iter};
use serde_json::{Map, Value};

use crate::clock::stamp;
use crate::entity::Entity;
use crate::error::{Error, Result};
use crate::push::{Command, Op};
use crate::rank;
use crate::value::to_sql;

pub(crate) fn apply(conn: &Connection, command: &Command, now: Timestamp) -> Result<()> {
    for field in command.fields.keys() {
        if command.entity.column(field).is_none() {
            return Err(Error::Invalid(format!(
                "{} has no field {field}",
                command.entity
            )));
        }
    }

    let id = command.entity_id.to_string();
    let now_stamp = stamp(now);
    let at = command.at.clone().unwrap_or_else(|| now_stamp.clone());

    match command.op {
        Op::Insert => insert(conn, command.entity, &id, &command.fields, &now_stamp, &at),
        Op::Patch => patch(conn, command.entity, &id, &command.fields, &now_stamp, &at),
    }
}

fn insert(
    conn: &Connection,
    entity: Entity,
    id: &str,
    fields: &Map<String, Value>,
    now: &str,
    at: &str,
) -> Result<()> {
    let mut row = fields.clone();
    row.insert("id".into(), id.into());
    row.insert("inserted_at".into(), now.into());
    row.insert("updated_at".into(), now.into());

    match entity {
        Entity::Task => {
            if !row.contains_key("inbox") {
                let in_project = !row.get("project_id").unwrap_or(&Value::Null).is_null();
                row.insert("inbox".into(), (!in_project).into());
            }
            if let Some(parent) = text(&row, "parent_id") {
                let (inbox, project_id) = location_of(conn, &parent)?;
                row.insert("inbox".into(), inbox.into());
                row.insert("project_id".into(), project_id.into());
            }
            resolve(&mut row, None, at);
        }
        Entity::Project => resolve(&mut row, None, at),
        Entity::Tag => {
            let last: Option<String> = conn.query_row(
                "SELECT max(rank) FROM tags WHERE parent_id IS ?1 AND discarded_at IS NULL",
                [text(&row, "parent_id")],
                |r| r.get(0),
            )?;
            row.insert("rank".into(), rank::between(last.as_deref(), None).into());
        }
        _ => {}
    }

    let names: Vec<&String> = row.keys().collect();
    let sql = format!(
        "INSERT INTO {} ({}) VALUES ({})",
        entity.table(),
        names
            .iter()
            .map(|n| n.as_str())
            .collect::<Vec<_>>()
            .join(", "),
        vec!["?"; names.len()].join(", ")
    );

    conn.execute(&sql, params_from_iter(row.values().map(to_sql)))?;
    Ok(())
}

fn patch(
    conn: &Connection,
    entity: Entity,
    id: &str,
    fields: &Map<String, Value>,
    now: &str,
    at: &str,
) -> Result<()> {
    let current = live(conn, entity, id)?;

    if !entity.is_link() && current.is_none() {
        return Err(Error::NotFound {
            entity: entity.as_str(),
            id: id.to_string(),
        });
    }

    // Discard wins over the rest of the patch (ADR 0014).
    if !entity.is_link() && !fields.get("discarded_at").unwrap_or(&Value::Null).is_null() {
        return discard(conn, entity, id, now);
    }

    // No revive: a null discarded_at only means something on a link.
    let mut row = fields.clone();
    if !entity.is_link() {
        row.remove("discarded_at");
    }

    match entity {
        Entity::Task => {
            let current = current.expect("checked above");
            resolve(&mut row, Some(&current), at);
            place_task(conn, id, &current, &mut row)?;
        }
        Entity::Project => resolve(&mut row, current.as_ref(), at),
        _ => {}
    }

    update(conn, entity, id, &row, now)?;

    if entity == Entity::Task && (row.contains_key("inbox") || row.contains_key("project_id")) {
        let (inbox, project_id) = location_of(conn, id)?;
        relocate_children(
            conn,
            id,
            inbox,
            project_id.as_deref(),
            now,
            &mut HashSet::new(),
        )?;
    }

    Ok(())
}

// A new parent brings its location. A move to another location without one
// leaves the parent and goes where a new task would.
fn place_task(
    conn: &Connection,
    id: &str,
    current: &Map<String, Value>,
    row: &mut Map<String, Value>,
) -> Result<()> {
    if let Some(parent) = row.get("parent_id").map(|v| v.as_str().map(str::to_string)) {
        if let Some(parent) = parent {
            if within(conn, &parent, id)? {
                return Err(Error::Invalid(
                    "a task cannot go under its own subtask".into(),
                ));
            }
            let (inbox, project_id) = location_of(conn, &parent)?;
            row.insert("inbox".into(), inbox.into());
            row.insert("project_id".into(), project_id.into());
        }
        return Ok(());
    }

    let moved = |field: &str| {
        row.get(field)
            .is_some_and(|v| Some(v) != current.get(field))
    };

    if moved("inbox") || moved("project_id") {
        let inbox = row
            .get("inbox")
            .or(current.get("inbox"))
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let project_id = row
            .get("project_id")
            .or(current.get("project_id"))
            .and_then(Value::as_str)
            .map(str::to_string);

        row.insert("parent_id".into(), Value::Null);
        row.insert(
            "rank".into(),
            default_rank(conn, None, inbox, project_id.as_deref(), Some(id))?.into(),
        );
    }

    Ok(())
}

/// The rank a new task gets: the top of the inbox, which lists newest
/// first, and the bottom anywhere else.
pub(crate) fn default_rank(
    conn: &Connection,
    parent_id: Option<&str>,
    inbox: bool,
    project_id: Option<&str>,
    except: Option<&str>,
) -> Result<String> {
    let top = parent_id.is_none() && inbox;
    let sql = format!(
        "SELECT {}(rank) FROM tasks
         WHERE parent_id IS ?1 AND inbox = ?2 AND project_id IS ?3
           AND discarded_at IS NULL AND id IS NOT ?4",
        if top { "min" } else { "max" }
    );

    let neighbor: Option<String> =
        conn.query_row(&sql, params![parent_id, inbox, project_id, except], |r| {
            r.get(0)
        })?;

    let rank = if top {
        rank::between(None, neighbor.as_deref())
    } else {
        rank::between(neighbor.as_deref(), None)
    };

    rank.ok_or_else(|| Error::Invalid("sibling ranks are out of order".into()))
}

// The first resolve sets resolved_at; a later one keeps it (ADR 0014).
fn resolve(row: &mut Map<String, Value>, current: Option<&Map<String, Value>>, at: &str) {
    let resolving = matches!(
        row.get("state").and_then(Value::as_str),
        Some("done" | "dropped")
    );
    let already = current
        .and_then(|c| c.get("resolved_at"))
        .is_some_and(|v| !v.is_null());

    if resolving && !already {
        row.insert("resolved_at".into(), at.into());
    }
}

fn discard(conn: &Connection, entity: Entity, id: &str, now: &str) -> Result<()> {
    match entity {
        Entity::Task => {
            for child in ids(
                conn,
                "SELECT id FROM tasks WHERE parent_id = ?1 AND discarded_at IS NULL",
                id,
            )? {
                discard(conn, Entity::Task, &child, now)?;
            }
        }
        Entity::Project => {
            for task in ids(
                conn,
                "SELECT id FROM tasks WHERE project_id = ?1 AND discarded_at IS NULL",
                id,
            )? {
                mark_discarded(conn, Entity::Task, &task, now)?;
            }
        }
        Entity::ProjectFolder => {
            for child in ids(
                conn,
                "SELECT id FROM project_folders WHERE parent_id = ?1 AND discarded_at IS NULL",
                id,
            )? {
                discard(conn, Entity::ProjectFolder, &child, now)?;
            }
            conn.execute(
                "UPDATE projects SET project_folder_id = NULL, updated_at = ?2 WHERE project_folder_id = ?1",
                params![id, now],
            )?;
        }
        Entity::Tag => {
            for child in ids(
                conn,
                "SELECT id FROM tags WHERE parent_id = ?1 AND discarded_at IS NULL",
                id,
            )? {
                discard(conn, Entity::Tag, &child, now)?;
            }
            for table in ["task_tags", "project_tags"] {
                conn.execute(
                    &format!("UPDATE {table} SET discarded_at = ?2 WHERE tag_id = ?1 AND discarded_at IS NULL"),
                    params![id, now],
                )?;
            }
        }
        Entity::TaskTag | Entity::ProjectTag => {}
    }

    mark_discarded(conn, entity, id, now)
}

fn mark_discarded(conn: &Connection, entity: Entity, id: &str, now: &str) -> Result<()> {
    conn.execute(
        &format!(
            "UPDATE {} SET discarded_at = ?2, updated_at = ?2 WHERE id = ?1",
            entity.table()
        ),
        params![id, now],
    )?;
    Ok(())
}

fn relocate_children(
    conn: &Connection,
    id: &str,
    inbox: bool,
    project_id: Option<&str>,
    now: &str,
    seen: &mut HashSet<String>,
) -> Result<()> {
    for child in ids(
        conn,
        "SELECT id FROM tasks WHERE parent_id = ?1 AND discarded_at IS NULL",
        id,
    )? {
        if seen.insert(child.clone()) {
            conn.execute(
                "UPDATE tasks SET inbox = ?2, project_id = ?3, updated_at = ?4 WHERE id = ?1",
                params![child, inbox, project_id, now],
            )?;
            relocate_children(conn, &child, inbox, project_id, now, seen)?;
        }
    }
    Ok(())
}

fn update(
    conn: &Connection,
    entity: Entity,
    id: &str,
    row: &Map<String, Value>,
    now: &str,
) -> Result<()> {
    if row.is_empty() {
        return Ok(());
    }

    let mut row = row.clone();
    row.insert("updated_at".into(), now.into());

    let sets: Vec<String> = row
        .keys()
        .enumerate()
        .map(|(i, name)| format!("{name} = ?{}", i + 1))
        .collect();

    let sql = format!(
        "UPDATE {} SET {} WHERE id = ?{}",
        entity.table(),
        sets.join(", "),
        row.len() + 1
    );
    let values = row
        .values()
        .map(to_sql)
        .chain(std::iter::once(to_sql(&Value::from(id))));
    conn.execute(&sql, params_from_iter(values))?;
    Ok(())
}

// The row, if it is there and not discarded.
fn live(conn: &Connection, entity: Entity, id: &str) -> Result<Option<Map<String, Value>>> {
    let columns = entity.columns();
    let names: Vec<&str> = columns.iter().map(|c| c.name).collect();
    let sql = format!(
        "SELECT {} FROM {} WHERE id = ?1 AND (discarded_at IS NULL OR ?2)",
        names.join(", "),
        entity.table()
    );

    Ok(conn
        .query_row(&sql, params![id, entity.is_link()], |row| {
            let mut map = Map::new();
            for (i, column) in columns.iter().enumerate() {
                map.insert(
                    column.name.to_string(),
                    crate::value::from_sql(*column, row.get_ref(i)?),
                );
            }
            Ok(map)
        })
        .optional()?)
}

pub(crate) fn location_of(conn: &Connection, task_id: &str) -> Result<(bool, Option<String>)> {
    conn.query_row(
        "SELECT inbox, project_id FROM tasks WHERE id = ?1 AND discarded_at IS NULL",
        [task_id],
        |row| Ok((row.get(0)?, row.get(1)?)),
    )
    .optional()?
    .ok_or_else(|| Error::NotFound {
        entity: "task",
        id: task_id.to_string(),
    })
}

// Whether `task` is `ancestor` or somewhere below it.
fn within(conn: &Connection, task: &str, ancestor: &str) -> Result<bool> {
    let mut next = Some(task.to_string());
    let mut seen = HashSet::new();

    while let Some(id) = next {
        if id == ancestor {
            return Ok(true);
        }
        if !seen.insert(id.clone()) {
            return Ok(false);
        }
        next = conn
            .query_row("SELECT parent_id FROM tasks WHERE id = ?1", [&id], |r| {
                r.get(0)
            })
            .optional()?
            .flatten();
    }

    Ok(false)
}

fn ids(conn: &Connection, sql: &str, id: &str) -> Result<Vec<String>> {
    let mut statement = conn.prepare_cached(sql)?;
    let rows = statement.query_map([id], |row| row.get(0))?;
    Ok(rows.collect::<std::result::Result<_, _>>()?)
}

fn text(row: &Map<String, Value>, field: &str) -> Option<String> {
    row.get(field).and_then(Value::as_str).map(str::to_string)
}
