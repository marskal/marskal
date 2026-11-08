//! Keeping a shell's tokens (ADR 0019, ADR 0021).
//!
//! Tokens live in the OS keychain. Where there is none, in a file only the
//! user can read, under `$XDG_STATE_HOME`. Processes of one shell share a
//! grant, so a refresh, which spends the refresh token, runs under a lock
//! file: two processes refreshing at once would look like a stolen token and
//! sign the device out. Each shell has its own `Namespace`, so one shell's
//! grant never replaces another's.

use std::fs::File;
use std::io::Write;
use std::path::{Path, PathBuf};

use jiff::Timestamp;
use serde::{Deserialize, Serialize};

use crate::api::{Api, ApiError, TokenResponse};
use crate::paths;

/// Where one shell keeps its tokens. Changing a value signs that shell's
/// users out, so the names stay as they shipped.
#[derive(Clone, Copy, Debug)]
pub struct Namespace {
    /// The keychain service; the account is the server URL.
    pub keychain_service: &'static str,
    /// The directory under the state directory for the token files.
    pub token_dir: &'static str,
    /// Put before the server slug in the lock file's name.
    pub lock_prefix: &'static str,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Tokens {
    pub access_token: String,
    /// Unix seconds.
    pub access_expires_at: i64,
    pub refresh_token: String,
    pub scope: String,
}

impl Tokens {
    pub fn from_response(response: TokenResponse) -> Tokens {
        Tokens {
            access_expires_at: Timestamp::now().as_second() + response.expires_in,
            access_token: response.access_token,
            refresh_token: response.refresh_token,
            scope: response.scope,
        }
    }

    // A minute's margin, so a token does not expire on the way.
    fn fresh(&self) -> bool {
        self.access_expires_at - 60 > Timestamp::now().as_second()
    }
}

#[derive(Debug)]
pub enum AuthError {
    /// No tokens for this server.
    NotSignedIn,
    /// The refresh token was refused: the device was signed out on the
    /// server. The stored tokens are gone.
    SignedOut,
    Keychain(String),
    Io(std::io::Error),
    /// The refresh did not reach the server, or it answered oddly.
    Network(String),
}

impl std::fmt::Display for AuthError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AuthError::NotSignedIn => f.write_str("Sign in first."),
            AuthError::SignedOut => f.write_str("This device was signed out. Sign in again."),
            AuthError::Keychain(message) => write!(f, "keychain: {message}"),
            AuthError::Io(error) => error.fmt(f),
            AuthError::Network(message) => write!(f, "Could not refresh the sign-in: {message}"),
        }
    }
}

impl std::error::Error for AuthError {}

impl From<std::io::Error> for AuthError {
    fn from(error: std::io::Error) -> AuthError {
        AuthError::Io(error)
    }
}

/// Where one server's tokens are kept, for one shell.
pub struct TokenStore {
    server: String,
    namespace: Namespace,
}

impl TokenStore {
    pub fn new(server: &str, namespace: Namespace) -> TokenStore {
        TokenStore {
            server: server.to_string(),
            namespace,
        }
    }

    // MARSKAL_NO_KEYCHAIN=1 keeps tokens in the file, as on a machine with
    // no keychain.
    fn keychain(&self) -> Option<keyring::Entry> {
        if std::env::var_os("MARSKAL_NO_KEYCHAIN").is_some_and(|v| v != "0" && !v.is_empty()) {
            return None;
        }
        keyring::Entry::store_status().as_ref().ok()?;
        keyring::Entry::new(self.namespace.keychain_service, &self.server).ok()
    }

    fn file(&self) -> PathBuf {
        paths::state_dir()
            .join(self.namespace.token_dir)
            .join(format!("{}.json", paths::server_slug(&self.server)))
    }

    pub fn load(&self) -> Result<Option<Tokens>, AuthError> {
        let text = match self.keychain() {
            Some(entry) => match entry.get_password() {
                Ok(text) => Some(text),
                Err(keyring::Error::NoEntry) => None,
                Err(e) => return Err(AuthError::Keychain(e.to_string())),
            },
            None => match std::fs::read_to_string(self.file()) {
                Ok(text) => Some(text),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
                Err(e) => return Err(e.into()),
            },
        };

        Ok(text.and_then(|text| serde_json::from_str(&text).ok()))
    }

    pub fn signed_in(&self) -> bool {
        self.load().ok().flatten().is_some()
    }

    pub fn save(&self, tokens: &Tokens) -> Result<(), AuthError> {
        let text = serde_json::to_string(tokens).expect("tokens serialize");

        match self.keychain() {
            Some(entry) => entry
                .set_password(&text)
                .map_err(|e| AuthError::Keychain(e.to_string())),
            None => Ok(write_private(&self.file(), &text)?),
        }
    }

    pub fn delete(&self) -> Result<(), AuthError> {
        match self.keychain() {
            Some(entry) => match entry.delete_credential() {
                Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
                Err(e) => Err(AuthError::Keychain(e.to_string())),
            },
            None => match std::fs::remove_file(self.file()) {
                Ok(()) => Ok(()),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
                Err(e) => Err(e.into()),
            },
        }
    }

    /// A live access token, refreshing if needed. `rejected` is a token the
    /// server just refused, so it is not handed back.
    pub fn access_token(&self, api: &Api, rejected: Option<&str>) -> Result<String, AuthError> {
        let usable =
            |tokens: &Tokens| tokens.fresh() && Some(tokens.access_token.as_str()) != rejected;

        let tokens = self.load()?.ok_or(AuthError::NotSignedIn)?;
        if usable(&tokens) {
            return Ok(tokens.access_token);
        }

        let _lock = self.lock()?;

        // Another process may have refreshed while this one waited.
        let tokens = self.load()?.ok_or(AuthError::NotSignedIn)?;
        if usable(&tokens) {
            return Ok(tokens.access_token);
        }

        match api.refresh(&tokens.refresh_token) {
            Ok(response) => {
                let tokens = Tokens::from_response(response);
                self.save(&tokens)?;
                Ok(tokens.access_token)
            }
            Err(ApiError::OAuth(code)) if code == "invalid_grant" => {
                self.delete()?;
                Err(AuthError::SignedOut)
            }
            Err(e) => Err(AuthError::Network(e.to_string())),
        }
    }

    /// Revokes the grant on the server, as far as it can be reached, and
    /// forgets the tokens here.
    pub fn sign_out(&self, api: &Api) -> Result<(), AuthError> {
        if let Some(tokens) = self.load()? {
            let _ = api.revoke(&tokens.refresh_token);
        }
        self.delete()
    }

    fn lock(&self) -> Result<File, AuthError> {
        let dir = paths::state_dir();
        let path = dir.join(format!(
            "{}{}.lock",
            self.namespace.lock_prefix,
            paths::server_slug(&self.server)
        ));
        std::fs::create_dir_all(&dir)?;
        let file = File::options()
            .create(true)
            .truncate(false)
            .write(true)
            .open(path)?;
        file.lock()?;
        Ok(file)
    }
}

/// Writes `text` to a file only the user can read. `mode` applies only when
/// the file is created, so an older file is tightened too.
fn write_private(path: &Path, text: &str) -> std::io::Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }

    let mut options = File::options();
    options.create(true).truncate(true).write(true);
    #[cfg(unix)]
    std::os::unix::fs::OpenOptionsExt::mode(&mut options, 0o600);

    let mut file = options.open(path)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        file.set_permissions(std::fs::Permissions::from_mode(0o600))?;
    }
    file.write_all(text.as_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(unix)]
    #[test]
    fn the_token_file_is_private_even_when_it_existed() {
        use std::os::unix::fs::PermissionsExt;

        let dir = std::env::temp_dir().join(format!("marskal-shell-common-{}", std::process::id()));
        let path = dir.join("tokens.json");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(&path, "old").unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o644)).unwrap();

        write_private(&path, "new").unwrap();

        let mode = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600);
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "new");
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
