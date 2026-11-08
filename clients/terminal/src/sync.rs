//! Push the outbox, then pull until the server has nothing more (ADR 0019).

use marskal_sync::Store;
use serde::Serialize;

use crate::api::{Api, ApiError, SyncApi};
use crate::error::{CliError, Result};
use marskal_shell_common::TokenStore;

const PUSH_BATCH: usize = 1000;

#[derive(Clone, Copy, Debug, Default, Serialize)]
pub struct SyncReport {
    pub pushed: usize,
    pub rejected: usize,
    pub pulls: usize,
    pub cursor: i64,
}

pub fn sync(store: &mut Store, api: &Api, tokens: &TokenStore) -> Result<SyncReport> {
    let mut access = tokens.access_token(api, None)?;
    let mut report = SyncReport::default();

    loop {
        let batch = store.pending(PUSH_BATCH)?;
        if batch.is_empty() {
            break;
        }

        let results = with_auth(api, tokens, &mut access, |token| api.push(token, &batch))?;
        let summary = store.record_push(&results)?;
        report.pushed += summary.accepted;
        report.rejected += summary.rejected;

        // The server stopped part way; the rest go next time.
        if results.len() < batch.len() {
            break;
        }
    }

    loop {
        let cursor = store.pull_cursor()?;
        let response = match with_auth(api, tokens, &mut access, |token| api.pull(token, cursor)) {
            Err(CliError { code: "gone", .. }) => {
                store.reset_cursor()?;
                continue;
            }
            other => other?,
        };

        if let Some(local) = store.status()?.user_id
            && local != response.user.id
        {
            return Err(CliError::new(
                "other_account",
                1,
                "This device's local data belongs to another account. Run `marskal logout --forget` first.",
            ));
        }

        store.apply_pull(&response)?;
        report.pulls += 1;
        report.cursor = response.cursor;

        if !response.more {
            break;
        }
    }

    store.mark_synced()?;
    Ok(report)
}

// One retry with a refreshed token after a 401.
fn with_auth<T>(
    api: &Api,
    tokens: &TokenStore,
    access: &mut String,
    call: impl Fn(&str) -> std::result::Result<T, ApiError>,
) -> Result<T> {
    match call(access) {
        Err(ApiError::Unauthorized) => {
            *access = tokens.access_token(api, Some(access))?;
            call(access).map_err(api_error)
        }
        other => other.map_err(api_error),
    }
}

fn api_error(error: ApiError) -> CliError {
    match error {
        ApiError::Unauthorized => CliError::not_signed_in(),
        ApiError::Forbidden => CliError::new("forbidden", 4, error.to_string()),
        ApiError::Gone => CliError::new("gone", 1, error.to_string()),
        other => CliError::network(other.to_string()),
    }
}
