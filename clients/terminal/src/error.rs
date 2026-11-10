//! Errors, with the exit code and the stable code `--json` reports.

use serde::Serialize;

#[derive(Debug)]
pub struct CliError {
    pub code: &'static str,
    pub message: String,
    pub exit: i32,
}

pub type Result<T> = std::result::Result<T, CliError>;

impl CliError {
    pub fn new(code: &'static str, exit: i32, message: impl Into<String>) -> CliError {
        CliError {
            code,
            message: message.into(),
            exit,
        }
    }

    pub fn usage(message: impl Into<String>) -> CliError {
        CliError::new("usage", 2, message)
    }

    pub fn not_signed_in() -> CliError {
        CliError::new("not_signed_in", 4, "Not signed in. Run `marskal login`.")
    }

    pub fn network(message: impl Into<String>) -> CliError {
        CliError::new("network", 5, message)
    }
}

/// The JSON shape of an error.
#[derive(Serialize)]
pub struct ErrorBody<'a> {
    pub code: &'a str,
    pub message: &'a str,
}

impl std::fmt::Display for CliError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

impl From<marskal_replica::Error> for CliError {
    fn from(error: marskal_replica::Error) -> CliError {
        use marskal_replica::Error::*;
        match error {
            NotFound { .. } => CliError::new("not_found", 3, error.to_string()),
            Ambiguous { .. } => CliError::new("ambiguous", 3, error.to_string()),
            Invalid(message) => CliError::new("invalid", 1, message),
            other => CliError::new("local_database", 1, other.to_string()),
        }
    }
}

impl From<std::io::Error> for CliError {
    fn from(error: std::io::Error) -> CliError {
        CliError::new("io", 1, error.to_string())
    }
}
