//! Signing in with the device grant (ADR 0019, ADR 0020). The token store
//! and the poll are `marskal-shell-common`'s; the messages are this
//! program's. The command line and an open terminal UI share one grant.

use marskal_shell_common::{AuthError, GrantError, Namespace, TokenStore, Tokens, await_grant};

use crate::api::Api;
use crate::error::{CliError, Result};

/// The names the terminal client's tokens shipped under.
const NAMESPACE: Namespace = Namespace {
    keychain_service: "marskal",
    token_dir: "tokens",
    lock_prefix: "",
};

pub fn store(server: &str) -> TokenStore {
    TokenStore::new(server, NAMESPACE)
}

impl From<AuthError> for CliError {
    fn from(error: AuthError) -> CliError {
        match error {
            AuthError::NotSignedIn => CliError::not_signed_in(),
            AuthError::SignedOut => CliError::new(
                "signed_out",
                4,
                "This device was signed out. Run `marskal login`.",
            ),
            AuthError::Keychain(message) => CliError::new("keychain", 1, message),
            AuthError::Io(error) => error.into(),
            AuthError::Network(message) => CliError::network(message),
        }
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

    let tokens = match await_grant(api, &device, || false) {
        Ok(response) => Tokens::from_response(response),
        Err(GrantError::Denied) => {
            return Err(CliError::new("access_denied", 4, "Sign-in was denied."));
        }
        Err(GrantError::Expired | GrantError::Stopped) => {
            return Err(CliError::new(
                "expired",
                4,
                "The code expired. Run `marskal login` again.",
            ));
        }
        Err(error @ GrantError::Failed(_)) => {
            return Err(CliError::new("login_failed", 4, error.to_string()));
        }
        Err(error @ GrantError::Network(_)) => return Err(CliError::network(error.to_string())),
    };
    store.save(&tokens)?;
    Ok(tokens)
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
