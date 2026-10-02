//! HTTP to the server: OAuth (ADR 0019) and the sync API. The shell owns
//! this; the sync library does no HTTP (ADR 0018).

use std::time::Duration;

use marskal_sync::{Command, PullResponse, PushResult};
use serde::Deserialize;
use serde_json::{Value, json};
use ureq::Agent;

pub const CLIENT_ID: &str = "marskal";

pub struct Api {
    server: String,
    agent: Agent,
}

/// What the server or the network said.
#[derive(Debug)]
pub enum ApiError {
    /// `401`: the access token expired or was revoked.
    Unauthorized,
    /// `403`: the grant lacks a scope.
    Forbidden,
    /// `410`: the cursor is older than the feed.
    Gone,
    /// An OAuth error code, such as `authorization_pending`.
    OAuth(String),
    Http(u16, String),
    Network(String),
}

impl std::fmt::Display for ApiError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ApiError::Unauthorized => f.write_str("the server did not accept the sign-in"),
            ApiError::Forbidden => {
                f.write_str("this device is not allowed to do that (read-only?)")
            }
            ApiError::Gone => f.write_str("the server no longer has changes that old"),
            ApiError::OAuth(code) => write!(f, "the server said {code}"),
            ApiError::Http(status, body) => write!(f, "the server answered {status}: {body}"),
            ApiError::Network(message) => f.write_str(message),
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct DeviceCode {
    pub device_code: String,
    pub user_code: String,
    pub verification_uri: String,
    pub verification_uri_complete: Option<String>,
    pub expires_in: u64,
    pub interval: u64,
}

#[derive(Debug, Deserialize)]
pub struct TokenResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub expires_in: i64,
    pub scope: String,
}

#[derive(Deserialize)]
struct Results {
    results: Vec<PushResult>,
}

impl Api {
    pub fn new(server: &str) -> Api {
        let agent: Agent = Agent::config_builder()
            .timeout_global(Some(Duration::from_secs(30)))
            .http_status_as_error(false)
            .user_agent(concat!("marskal/", env!("CARGO_PKG_VERSION")))
            .build()
            .into();

        Api {
            server: server.to_string(),
            agent,
        }
    }

    fn url(&self, path: &str) -> String {
        format!("{}{path}", self.server)
    }

    pub fn device_code(&self, scope: &str, device_name: &str) -> Result<DeviceCode, ApiError> {
        let response = self
            .agent
            .post(self.url("/oauth/device_authorization"))
            .send_form([
                ("client_id", CLIENT_ID),
                ("scope", scope),
                ("device_name", device_name),
            ]);
        json_or_error(response)
    }

    pub fn poll_token(&self, device_code: &str) -> Result<TokenResponse, ApiError> {
        let response = self.agent.post(self.url("/oauth/token")).send_form([
            ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"),
            ("client_id", CLIENT_ID),
            ("device_code", device_code),
        ]);
        json_or_error(response)
    }

    pub fn refresh(&self, refresh_token: &str) -> Result<TokenResponse, ApiError> {
        let response = self.agent.post(self.url("/oauth/token")).send_form([
            ("grant_type", "refresh_token"),
            ("client_id", CLIENT_ID),
            ("refresh_token", refresh_token),
        ]);
        json_or_error(response)
    }

    pub fn revoke(&self, token: &str) -> Result<(), ApiError> {
        let response = self
            .agent
            .post(self.url("/oauth/revoke"))
            .send_form([("client_id", CLIENT_ID), ("token", token)]);
        json_or_error::<Value>(response).map(|_| ())
    }

    pub fn pull(&self, access_token: &str, cursor: Option<i64>) -> Result<PullResponse, ApiError> {
        let mut request = self
            .agent
            .get(self.url("/api/v1/sync/pull"))
            .header("authorization", &format!("Bearer {access_token}"));

        if let Some(cursor) = cursor {
            request = request.query("cursor", cursor.to_string());
        }

        json_or_error(request.call())
    }

    pub fn push(
        &self,
        access_token: &str,
        commands: &[Command],
    ) -> Result<Vec<PushResult>, ApiError> {
        let response = self
            .agent
            .post(self.url("/api/v1/sync/push"))
            .header("authorization", &format!("Bearer {access_token}"))
            .send_json(json!({ "commands": commands }));

        json_or_error::<Results>(response).map(|r| r.results)
    }
}

fn json_or_error<T: serde::de::DeserializeOwned>(
    response: Result<ureq::http::Response<ureq::Body>, ureq::Error>,
) -> Result<T, ApiError> {
    let mut response = response.map_err(|e| ApiError::Network(e.to_string()))?;
    let status = response.status().as_u16();

    if (200..300).contains(&status) {
        return response
            .body_mut()
            .read_json()
            .map_err(|e| ApiError::Network(format!("unreadable answer from the server: {e}")));
    }

    let body = response.body_mut().read_to_string().unwrap_or_default();

    match status {
        401 if !body.contains("invalid_client") => Err(ApiError::Unauthorized),
        403 => Err(ApiError::Forbidden),
        410 => Err(ApiError::Gone),
        _ => match serde_json::from_str::<Value>(&body)
            .ok()
            .and_then(|v| v["error"].as_str().map(str::to_string))
        {
            Some(code) => Err(ApiError::OAuth(code)),
            None => Err(ApiError::Http(status, body)),
        },
    }
}
