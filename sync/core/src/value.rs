//! Moving JSON field values in and out of SQLite.

use rusqlite::types::{ToSqlOutput, Value as Sql, ValueRef};
use serde_json::Value;

use crate::entity::{Column, Kind};

/// A JSON value as the column stores it.
pub(crate) fn to_sql(value: &Value) -> ToSqlOutput<'static> {
    ToSqlOutput::Owned(match value {
        Value::Null => Sql::Null,
        Value::Bool(b) => Sql::Integer(i64::from(*b)),
        Value::Number(n) => match n.as_i64() {
            Some(i) => Sql::Integer(i),
            None => Sql::Real(n.as_f64().unwrap_or_default()),
        },
        Value::String(s) => Sql::Text(s.clone()),
        other => Sql::Text(other.to_string()),
    })
}

/// A stored value as JSON, by the column's kind.
pub(crate) fn from_sql(column: Column, value: ValueRef<'_>) -> Value {
    match (value, column.kind) {
        (ValueRef::Null, _) => Value::Null,
        (ValueRef::Integer(i), Kind::Bool) => Value::Bool(i != 0),
        (ValueRef::Integer(i), _) => Value::from(i),
        (ValueRef::Real(f), _) => Value::from(f),
        (ValueRef::Text(t), Kind::Json) => serde_json::from_slice(t).unwrap_or(Value::Null),
        (ValueRef::Text(t), _) => Value::String(String::from_utf8_lossy(t).into_owned()),
        (ValueRef::Blob(_), _) => Value::Null,
    }
}
