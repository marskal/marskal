//! `$XDG_CONFIG_HOME/marskal/config.toml`: the user's settings. `marskal`
//! reads it and never writes it (ADR 0020), so it may be a read-only file
//! managed elsewhere, such as by Home Manager. What `marskal` records
//! itself goes to the state directory (`crate::state`).

use std::path::PathBuf;

use serde::Deserialize;

use crate::error::{CliError, Result};
use crate::paths;
use crate::state::State;

#[derive(Clone, Debug, Default, PartialEq, Eq, Deserialize)]
pub struct Config {
    /// The server's base URL, such as `https://tasks.marskal.example`.
    pub server: Option<String>,
}

fn path() -> PathBuf {
    paths::config_dir().join("config.toml")
}

impl Config {
    pub fn load() -> Result<Config> {
        match std::fs::read_to_string(path()) {
            Ok(text) => toml::from_str(&text)
                .map_err(|e| CliError::usage(format!("{}: {e}", path().display()))),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Config::default()),
            Err(e) => Err(e.into()),
        }
    }

    /// The configured server, normalized.
    pub fn server(&self) -> Result<Option<String>> {
        self.server.as_deref().map(normalize_server).transpose()
    }
}

/// The server when none is given on the command line: the config file's,
/// else the one last signed in to.
pub fn default_server() -> Result<Option<String>> {
    match Config::load()?.server()? {
        Some(server) => Ok(Some(server)),
        None => Ok(State::load()?.server),
    }
}

/// A server URL without a trailing slash.
pub fn normalize_server(server: &str) -> Result<String> {
    let server = server.trim().trim_end_matches('/');
    if server.starts_with("https://") || server.starts_with("http://") {
        Ok(server.to_string())
    } else {
        Err(CliError::usage(format!(
            "{server} is not a URL; give it with https://"
        )))
    }
}
