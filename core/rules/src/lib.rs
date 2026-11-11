//! The rules Marskal's server and clients share (ADR 0039).
//!
//! Functions of plain values: text, instants, ids, and time zones. No
//! database, no I/O, and no clock of its own. The server implements each
//! one in Elixir too, and both run the vectors in `core/fixtures`.

pub mod dates;
pub mod ids;
pub mod rank;
pub mod url;
