//! `$XDG_CONFIG_HOME/marskal/config.toml`.

use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::error::{CliError, Result};
use crate::paths;

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Config {
    /// The server's base URL, such as `https://tasks.example.com`.
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

    pub fn save(&self) -> Result<()> {
        std::fs::create_dir_all(paths::config_dir())?;
        let text = toml::to_string(self).expect("the config serializes");
        std::fs::write(path(), text)?;
        Ok(())
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
