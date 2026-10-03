//! Signing in with the device grant, and keeping the tokens (ADR 0019,
//! ADR 0020).
//!
//! Tokens live in the OS keychain. Where there is none, in a file only the
//! user can read, under `$XDG_STATE_HOME`. The command line and an open
//! terminal UI share one grant, so a refresh, which spends the refresh
//! token, runs under a lock file: two processes refreshing at once would
//! look like a stolen token and sign the device out.

use std::fs::File;
use std::io::Write;
use std::path::PathBuf;
use std::time::Duration;

use jiff::Timestamp;
use serde::{Deserialize, Serialize};

use crate::api::{Api, ApiError, TokenResponse};
use crate::error::{CliError, Result};
use crate::paths;

const KEYCHAIN_SERVICE: &str = "marskal";

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Tokens {
    pub access_token: String,
    /// Unix seconds.
    pub access_expires_at: i64,
    pub refresh_token: String,
    pub scope: String,
}

impl Tokens {
    fn from_response(response: TokenResponse) -> Tokens {
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

/// Where one server's tokens are kept.
pub struct TokenStore {
    server: String,
}

impl TokenStore {
    pub fn new(server: &str) -> TokenStore {
        TokenStore {
            server: server.to_string(),
        }
    }

    // MARSKAL_NO_KEYCHAIN=1 keeps tokens in the file, as on a machine with
    // no keychain.
    fn keychain(&self) -> Option<keyring::Entry> {
        if std::env::var_os("MARSKAL_NO_KEYCHAIN").is_some_and(|v| v != "0" && !v.is_empty()) {
            return None;
        }
        keyring::Entry::store_status().as_ref().ok()?;
        keyring::Entry::new(KEYCHAIN_SERVICE, &self.server).ok()
    }

    fn file(&self) -> PathBuf {
        paths::state_dir()
            .join("tokens")
            .join(format!("{}.json", paths::server_slug(&self.server)))
    }

    pub fn load(&self) -> Result<Option<Tokens>> {
        let text = match self.keychain() {
            Some(entry) => match entry.get_password() {
                Ok(text) => Some(text),
                Err(keyring::Error::NoEntry) => None,
                Err(e) => return Err(CliError::new("keychain", 1, e.to_string())),
            },
            None => match std::fs::read_to_string(self.file()) {
                Ok(text) => Some(text),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
                Err(e) => return Err(e.into()),
            },
        };

        Ok(text.and_then(|text| serde_json::from_str(&text).ok()))
    }

    pub fn save(&self, tokens: &Tokens) -> Result<()> {
        let text = serde_json::to_string(tokens).expect("tokens serialize");

        match self.keychain() {
            Some(entry) => entry
                .set_password(&text)
                .map_err(|e| CliError::new("keychain", 1, e.to_string())),
            None => write_private(&self.file(), &text),
        }
    }

    pub fn delete(&self) -> Result<()> {
        match self.keychain() {
            Some(entry) => match entry.delete_credential() {
                Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
                Err(e) => Err(CliError::new("keychain", 1, e.to_string())),
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
    pub fn access_token(&self, api: &Api, rejected: Option<&str>) -> Result<String> {
        let usable =
            |tokens: &Tokens| tokens.fresh() && Some(tokens.access_token.as_str()) != rejected;

        let tokens = self.load()?.ok_or_else(CliError::not_signed_in)?;
        if usable(&tokens) {
            return Ok(tokens.access_token);
        }

        let _lock = self.lock()?;

        // Another process may have refreshed while this one waited.
        let tokens = self.load()?.ok_or_else(CliError::not_signed_in)?;
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
                Err(CliError::new(
                    "signed_out",
                    4,
                    "This device was signed out. Run `marskal login`.",
                ))
            }
            Err(e) => Err(CliError::network(e.to_string())),
        }
    }

    fn lock(&self) -> Result<File> {
        let path = paths::state_dir().join(format!("{}.lock", paths::server_slug(&self.server)));
        std::fs::create_dir_all(paths::state_dir())?;
        let file = File::options()
            .create(true)
            .truncate(false)
            .write(true)
            .open(path)?;
        file.lock()?;
        Ok(file)
    }
}

/// The device grant: show a code, let the user approve it in the browser,
/// and poll until they do.
pub fn login(api: &Api, store: &TokenStore, scope: &str, open_browser: bool) -> Result<Tokens> {
    let device = api
        .device_code(scope)
        .map_err(|e| CliError::network(format!("Could not start signing in: {e}")))?;

    let link = device
        .verification_uri_complete
        .clone()
        .unwrap_or_else(|| device.verification_uri.clone());

    eprintln!("To sign in, open {}", device.verification_uri);
    eprintln!("and enter the code {}", device.user_code);
    eprintln!("You will name this device there.");
    if open_browser {
        open(&link);
    }

    let deadline = Timestamp::now().as_second() + device.expires_in as i64;
    let mut interval = device.interval.max(1);

    loop {
        std::thread::sleep(Duration::from_secs(interval));

        match api.poll_token(&device.device_code) {
            Ok(response) => {
                let tokens = Tokens::from_response(response);
                store.save(&tokens)?;
                return Ok(tokens);
            }
            Err(ApiError::OAuth(code)) => match code.as_str() {
                "authorization_pending" => {}
                "slow_down" => interval += 5,
                "access_denied" => {
                    return Err(CliError::new("access_denied", 4, "Sign-in was denied."));
                }
                "expired_token" => {
                    return Err(CliError::new(
                        "expired",
                        4,
                        "The code expired. Run `marskal login` again.",
                    ));
                }
                other => {
                    return Err(CliError::new(
                        "login_failed",
                        4,
                        format!("Sign-in failed: {other}"),
                    ));
                }
            },
            Err(e) => return Err(CliError::network(format!("Sign-in failed: {e}"))),
        }

        if Timestamp::now().as_second() > deadline {
            return Err(CliError::new(
                "expired",
                4,
                "The code expired. Run `marskal login` again.",
            ));
        }
    }
}

pub fn open(url: &str) {
    let opener = if cfg!(target_os = "macos") {
        "open"
    } else {
        "xdg-open"
    };
    let _ = std::process::Command::new(opener)
        .arg(url)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn();
}

fn write_private(path: &PathBuf, text: &str) -> Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }

    let mut options = File::options();
    options.create(true).truncate(true).write(true);
    #[cfg(unix)]
    std::os::unix::fs::OpenOptionsExt::mode(&mut options, 0o600);

    let mut file = options.open(path)?;
    file.write_all(text.as_bytes())?;
    Ok(())
}
