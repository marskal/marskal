/// What can go wrong in the engine.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Sqlite(#[from] rusqlite::Error),

    #[error(transparent)]
    Json(#[from] serde_json::Error),

    /// No live row has this id, or no id starts with this prefix.
    #[error("no {entity} matches {id}")]
    NotFound { entity: &'static str, id: String },

    /// More than one id starts with this prefix.
    #[error("{id} matches more than one {entity}")]
    Ambiguous { entity: &'static str, id: String },

    /// The command would break a rule the server also checks.
    #[error("{0}")]
    Invalid(String),
}

pub type Result<T> = std::result::Result<T, Error>;
