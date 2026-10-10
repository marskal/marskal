//! `$XDG_STATE_HOME/marskal/state.toml`: what `marskal` records about
//! itself, as opposed to the user's settings in `crate::config`.

use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::error::{CliError, Result};
use crate::paths;

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct State {
    /// The server last signed in to. The config file's server wins over it.
    pub server: Option<String>,
}

fn path() -> PathBuf {
    paths::state_dir().join("state.toml")
}

impl State {
    pub fn load() -> Result<State> {
        match std::fs::read_to_string(path()) {
            Ok(text) => toml::from_str(&text)
                .map_err(|e| CliError::usage(format!("{}: {e}", path().display()))),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(State::default()),
            Err(e) => Err(e.into()),
        }
    }

    pub fn save(&self) -> Result<()> {
        std::fs::create_dir_all(paths::state_dir())?;
        let text = toml::to_string(self).expect("the state serializes");
        std::fs::write(path(), text)?;
        Ok(())
    }
}
