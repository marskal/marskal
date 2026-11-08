//! Waiting for the user to approve a device code (RFC 8628). The shell shows
//! the code and opens the browser; this polls until the server answers.

use std::time::Duration;

use jiff::Timestamp;

use crate::api::{Api, ApiError, DeviceCode, TokenResponse};

#[derive(Debug)]
pub enum GrantError {
    /// The user refused on the approval page.
    Denied,
    /// The code ran out before it was approved.
    Expired,
    /// The shell asked to stop.
    Stopped,
    /// Another OAuth error code.
    Failed(String),
    Network(String),
}

impl std::fmt::Display for GrantError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            GrantError::Denied => f.write_str("Sign-in was denied."),
            GrantError::Expired => f.write_str("The code expired."),
            GrantError::Stopped => f.write_str("Sign-in was stopped."),
            GrantError::Failed(code) => write!(f, "Sign-in failed: {code}"),
            GrantError::Network(message) => write!(f, "Sign-in failed: {message}"),
        }
    }
}

impl std::error::Error for GrantError {}

/// Polls at the server's interval until the code is approved, refused, or
/// expired. `stop` is checked before each poll.
pub fn await_grant(
    api: &Api,
    device: &DeviceCode,
    stop: impl Fn() -> bool,
) -> Result<TokenResponse, GrantError> {
    let deadline = Timestamp::now().as_second() + device.expires_in as i64;
    let mut interval = device.interval.max(1);

    loop {
        std::thread::sleep(Duration::from_secs(interval));
        if stop() {
            return Err(GrantError::Stopped);
        }

        match api.poll_token(&device.device_code) {
            Ok(response) => return Ok(response),
            Err(ApiError::OAuth(code)) => match code.as_str() {
                "authorization_pending" => {}
                "slow_down" => interval += 5,
                "access_denied" => return Err(GrantError::Denied),
                "expired_token" => return Err(GrantError::Expired),
                _ => return Err(GrantError::Failed(code)),
            },
            Err(error) => return Err(GrantError::Network(error.to_string())),
        }

        if Timestamp::now().as_second() > deadline {
            return Err(GrantError::Expired);
        }
    }
}
