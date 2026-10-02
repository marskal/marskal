use std::path::Path;

use jiff::Timestamp;
use rusqlite::{Connection, OptionalExtension, TransactionBehavior, params};
use serde::Serialize;

use crate::clock::{Clock, SystemClock, stamp};
use crate::error::Result;
use crate::model::Rejection;
use crate::schema;
use crate::world::World;

/// The local database: one SQLite file per server and account (ADR 0020).
///
/// Several processes may open the same file, such as the command line and
/// a terminal UI. It runs in WAL mode, and every write takes the write lock
/// for the length of one command.
pub struct Store {
    pub(crate) conn: Connection,
    clock: Box<dyn Clock>,
}

/// What a shell shows about sync.
#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
pub struct Status {
    pub user_id: Option<String>,
    pub timezone: Option<String>,
    pub cursor: Option<i64>,
    pub needs_snapshot: bool,
    pub pending: usize,
    pub unseen_rejections: usize,
    pub last_synced_at: Option<String>,
}

impl Store {
    /// Opens or creates the database at `path` and migrates it.
    pub fn open(path: impl AsRef<Path>) -> Result<Store> {
        let conn = Connection::open(path)?;
        conn.pragma_update(None, "journal_mode", "WAL")?;
        conn.pragma_update(None, "synchronous", "NORMAL")?;
        Store::setup(conn)
    }

    /// A database in memory, for tests.
    pub fn open_in_memory() -> Result<Store> {
        Store::setup(Connection::open_in_memory()?)
    }

    fn setup(mut conn: Connection) -> Result<Store> {
        conn.busy_timeout(std::time::Duration::from_secs(10))?;
        schema::migrate(&mut conn)?;
        Ok(Store {
            conn,
            clock: Box::new(SystemClock),
        })
    }

    /// Reads the time from `clock` from now on.
    pub fn with_clock(mut self, clock: impl Clock + 'static) -> Store {
        self.clock = Box::new(clock);
        self
    }

    pub(crate) fn now(&self) -> Timestamp {
        self.clock.now()
    }

    /// Changes when another connection commits a write, so a terminal UI
    /// can redraw after the command line changes something.
    pub fn data_version(&self) -> Result<i64> {
        Ok(self
            .conn
            .query_row("PRAGMA data_version", [], |row| row.get(0))?)
    }

    /// Every live row, with what the server would derive from them.
    pub fn world(&self) -> Result<World> {
        World::load(&self.conn, self.now())
    }

    pub fn status(&self) -> Result<Status> {
        Ok(Status {
            user_id: meta(&self.conn, "user_id")?,
            timezone: meta(&self.conn, "timezone")?,
            cursor: meta(&self.conn, "cursor")?.and_then(|c| c.parse().ok()),
            needs_snapshot: meta(&self.conn, "needs_snapshot")?.as_deref() == Some("1"),
            pending: self.pending_count()?,
            unseen_rejections: self.conn.query_row(
                "SELECT count(*) FROM rejections WHERE seen = 0",
                [],
                |row| row.get::<_, i64>(0),
            )? as usize,
            last_synced_at: meta(&self.conn, "last_synced_at")?,
        })
    }

    /// The user's timezone from the last pull, for recurrence and the web
    /// agenda. A device's own "today" uses the device zone (ADR 0014).
    pub fn timezone(&self) -> Result<Option<String>> {
        meta(&self.conn, "timezone")
    }

    /// Records a finished push and pull.
    pub fn mark_synced(&mut self) -> Result<()> {
        let now = stamp(self.now());
        set_meta(&self.conn, "last_synced_at", Some(&now))
    }

    /// The last finished sync, if any.
    pub fn last_synced_at(&self) -> Result<Option<Timestamp>> {
        Ok(meta(&self.conn, "last_synced_at")?.and_then(|at| at.parse().ok()))
    }

    /// Commands the server refused, newest first. With `unseen`, only those
    /// not yet shown.
    pub fn rejections(&self, unseen: bool) -> Result<Vec<Rejection>> {
        let sql = format!(
            "SELECT command_id, entity, entity_id, op, fields, reason, errors, rejected_at
             FROM rejections {} ORDER BY rejected_at DESC, command_id",
            if unseen { "WHERE seen = 0" } else { "" }
        );

        let mut statement = self.conn.prepare(&sql)?;
        let rows = statement.query_map([], |row| {
            Ok(Rejection {
                command_id: row.get(0)?,
                entity: row.get(1)?,
                entity_id: row.get(2)?,
                op: row.get(3)?,
                fields: parse_json(row.get::<_, String>(4)?),
                reason: row.get(5)?,
                errors: row.get::<_, Option<String>>(6)?.map(parse_json),
                rejected_at: row.get(7)?,
            })
        })?;

        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    /// Marks every rejection as shown.
    pub fn mark_rejections_seen(&mut self) -> Result<()> {
        self.conn
            .execute("UPDATE rejections SET seen = 1 WHERE seen = 0", [])?;
        Ok(())
    }

    /// Runs `f` in a transaction that holds the write lock from the start,
    /// so another process cannot write in between.
    pub(crate) fn write<T>(
        &mut self,
        f: impl FnOnce(&rusqlite::Transaction<'_>, Timestamp) -> Result<T>,
    ) -> Result<T> {
        let now = self.now();
        let tx = self
            .conn
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let value = f(&tx, now)?;
        tx.commit()?;
        Ok(value)
    }
}

pub(crate) fn meta(conn: &Connection, key: &str) -> Result<Option<String>> {
    Ok(conn
        .query_row("SELECT value FROM meta WHERE key = ?1", [key], |row| {
            row.get(0)
        })
        .optional()?
        .flatten())
}

pub(crate) fn set_meta(conn: &Connection, key: &str, value: Option<&str>) -> Result<()> {
    conn.execute(
        "INSERT INTO meta (key, value) VALUES (?1, ?2)
         ON CONFLICT (key) DO UPDATE SET value = excluded.value",
        params![key, value],
    )?;
    Ok(())
}

fn parse_json(text: String) -> serde_json::Value {
    serde_json::from_str(&text).unwrap_or(serde_json::Value::String(text))
}
