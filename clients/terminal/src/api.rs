//! HTTP to the server. Sign-in is `marskal-shell-common`'s (ADR 0021); the
//! sync API calls (ADR 0019) are here. The sync library does no HTTP
//! (ADR 0018).

use marskal_shell_common::json_or_error;
use marskal_sync::{Command, PullResponse, PushResult};
use serde::Deserialize;
use serde_json::json;

pub use marskal_shell_common::{Api, ApiError};

/// This program's OAuth client (ADR 0021). Every copy of `marskal` signs in as it.
pub const CLIENT_ID: &str = "marskal-terminal";

pub fn connect(server: &str) -> Api {
    Api::new(
        server,
        CLIENT_ID,
        concat!("marskal/", env!("CARGO_PKG_VERSION")),
    )
}

#[derive(Deserialize)]
struct Results {
    results: Vec<PushResult>,
}

/// The sync API, on top of the shared client.
pub trait SyncApi {
    fn pull(&self, access_token: &str, cursor: Option<i64>) -> Result<PullResponse, ApiError>;
    fn push(&self, access_token: &str, commands: &[Command]) -> Result<Vec<PushResult>, ApiError>;
}

impl SyncApi for Api {
    fn pull(&self, access_token: &str, cursor: Option<i64>) -> Result<PullResponse, ApiError> {
        let mut request = self
            .agent()
            .get(self.url("/api/v1/sync/pull"))
            .header("authorization", &format!("Bearer {access_token}"));

        if let Some(cursor) = cursor {
            request = request.query("cursor", cursor.to_string());
        }

        json_or_error(request.call())
    }

    fn push(&self, access_token: &str, commands: &[Command]) -> Result<Vec<PushResult>, ApiError> {
        let response = self
            .agent()
            .post(self.url("/api/v1/sync/push"))
            .header("authorization", &format!("Bearer {access_token}"))
            .send_json(json!({ "commands": commands }));

        json_or_error::<Results>(response).map(|r| r.results)
    }
}
