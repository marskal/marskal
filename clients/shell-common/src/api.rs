//! HTTP to the server: OAuth through Ory Hydra (ADR 0021). A shell adds its
//! own calls to the sync API (ADR 0019) with `agent`, `url`, and
//! `json_or_error`. The sync library does no HTTP (ADR 0018).

use std::sync::OnceLock;
use std::time::Duration;

use serde::Deserialize;
use serde_json::Value;
use ureq::Agent;

pub struct Api {
    server: String,
    client_id: &'static str,
    agent: Agent,
    endpoints: OnceLock<Endpoints>,
}

/// Where the OAuth endpoints are, from the server's metadata (RFC 8414).
/// Only the server's URL is configured; Hydra may sit behind it or beside it.
#[derive(Clone, Debug, Deserialize)]
struct Endpoints {
    device_authorization_endpoint: String,
    token_endpoint: String,
    revocation_endpoint: String,
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
            ApiError::Forbidden => f.write_str("this device is not allowed to do that"),
            ApiError::Gone => f.write_str("the server no longer has changes that old"),
            ApiError::OAuth(code) => write!(f, "the server said {code}"),
            ApiError::Http(status, body) => write!(f, "the server answered {status}: {body}"),
            ApiError::Network(message) => f.write_str(message),
        }
    }
}

impl std::error::Error for ApiError {}

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

impl Api {
    /// `client_id` is the shell's OAuth client (ADR 0021); `user_agent` names
    /// the shell and its version.
    pub fn new(server: &str, client_id: &'static str, user_agent: &str) -> Api {
        let agent: Agent = Agent::config_builder()
            .timeout_global(Some(Duration::from_secs(30)))
            .http_status_as_error(false)
            .user_agent(user_agent)
            .build()
            .into();

        Api {
            server: server.to_string(),
            client_id,
            agent,
            endpoints: OnceLock::new(),
        }
    }

    pub fn agent(&self) -> &Agent {
        &self.agent
    }

    /// `path` on the server, such as `/api/v1/sync/push`.
    pub fn url(&self, path: &str) -> String {
        format!("{}{path}", self.server)
    }

    fn endpoints(&self) -> Result<&Endpoints, ApiError> {
        if let Some(endpoints) = self.endpoints.get() {
            return Ok(endpoints);
        }
        let response = self
            .agent
            .get(self.url("/.well-known/oauth-authorization-server"))
            .call();
        let endpoints: Endpoints = json_or_error(response)?;
        Ok(self.endpoints.get_or_init(|| endpoints))
    }

    pub fn device_code(&self, scope: &str) -> Result<DeviceCode, ApiError> {
        let response = self
            .agent
            .post(&self.endpoints()?.device_authorization_endpoint)
            .send_form([("client_id", self.client_id), ("scope", scope)]);
        json_or_error(response)
    }

    pub fn poll_token(&self, device_code: &str) -> Result<TokenResponse, ApiError> {
        let response = self
            .agent
            .post(&self.endpoints()?.token_endpoint)
            .send_form([
                ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"),
                ("client_id", self.client_id),
                ("device_code", device_code),
            ]);
        json_or_error(response)
    }

    pub fn refresh(&self, refresh_token: &str) -> Result<TokenResponse, ApiError> {
        let response = self
            .agent
            .post(&self.endpoints()?.token_endpoint)
            .send_form([
                ("grant_type", "refresh_token"),
                ("client_id", self.client_id),
                ("refresh_token", refresh_token),
            ]);
        json_or_error(response)
    }

    /// Revokes a token and its chain (RFC 7009). The answer has no body.
    pub fn revoke(&self, token: &str) -> Result<(), ApiError> {
        let response = self
            .agent
            .post(&self.endpoints()?.revocation_endpoint)
            .send_form([("client_id", self.client_id), ("token", token)])
            .map_err(|e| ApiError::Network(e.to_string()))?;

        match response.status().as_u16() {
            200..=299 => Ok(()),
            status => Err(ApiError::Http(status, String::new())),
        }
    }
}

/// A 2xx answer read as JSON, or the error it stands for.
pub fn json_or_error<T: serde::de::DeserializeOwned>(
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
