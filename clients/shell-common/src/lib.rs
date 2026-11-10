//! What Marskal's Rust shells share (ADR 0018): where files go, signing in
//! with the device grant (ADR 0021), and keeping the tokens. The local
//! replica is `core/replica` (ADR 0039); this crate is the part around it
//! that every shell would otherwise copy. Each shell keeps its own client
//! id, keychain names, messages, and the sync calls it makes.

pub mod api;
pub mod grant;
pub mod paths;
pub mod tokens;

pub use api::{Api, ApiError, DeviceCode, TokenResponse, json_or_error};
pub use grant::{GrantError, await_grant};
pub use tokens::{AuthError, Namespace, TokenStore, Tokens};
