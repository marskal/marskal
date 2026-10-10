//! Where `marskal` keeps its files: the XDG Base Directory spec on every
//! platform, macOS included (ADR 0020). An unset or relative variable
//! falls back to the spec's default.

use std::path::PathBuf;

fn base(variable: &str, default: &str) -> PathBuf {
    match std::env::var_os(variable).map(PathBuf::from) {
        Some(path) if path.is_absolute() => path,
        _ => std::env::home_dir()
            .unwrap_or_else(|| PathBuf::from("/"))
            .join(default),
    }
}

/// `$XDG_CONFIG_HOME/marskal`: settings only, never a secret.
pub fn config_dir() -> PathBuf {
    base("XDG_CONFIG_HOME", ".config").join("marskal")
}

/// `$XDG_DATA_HOME/marskal`: the local databases. Data, not cache: the
/// outbox holds edits the server has not seen.
pub fn data_dir() -> PathBuf {
    base("XDG_DATA_HOME", ".local/share").join("marskal")
}

/// Create `data_dir()`, readable by the user alone: the databases hold
/// every task. The parents it creates get the umask, as usual. A directory
/// that already exists keeps its mode.
pub fn create_data_dir() -> std::io::Result<PathBuf> {
    let dir = data_dir();
    if let Some(parent) = dir.parent() {
        std::fs::create_dir_all(parent)?;
    }

    let mut builder = std::fs::DirBuilder::new();
    #[cfg(unix)]
    std::os::unix::fs::DirBuilderExt::mode(&mut builder, 0o700);
    match builder.create(&dir) {
        Err(e) if e.kind() != std::io::ErrorKind::AlreadyExists => Err(e),
        _ => Ok(dir),
    }
}

/// `$XDG_STATE_HOME/marskal`: what `marskal` records (`state.toml`), the
/// token file where there is no keychain, and the refresh lock.
pub fn state_dir() -> PathBuf {
    base("XDG_STATE_HOME", ".local/state").join("marskal")
}

/// A file name for a server: its host and port, safe for any filesystem.
pub fn server_slug(server: &str) -> String {
    let host = server
        .split("://")
        .nth(1)
        .unwrap_or(server)
        .trim_end_matches('/');

    host.chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '.' || c == '-' {
                c
            } else {
                '_'
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slugs_keep_host_and_port() {
        assert_eq!(
            server_slug("https://tasks.example.com/"),
            "tasks.example.com"
        );
        assert_eq!(
            server_slug("http://marskal.localhost:8275"),
            "marskal.localhost_8275"
        );
    }
}
