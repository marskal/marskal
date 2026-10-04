//! The optional URL on a task or project (ADR 0022), checked as the server
//! checks it, so a bad one fails here instead of being rejected later.

use crate::error::{Error, Result};

/// The most characters a URL may have.
pub const MAX: usize = 2048;

const REFUSED: &[&str] = &["javascript", "data", "vbscript"];

/// Whether `url` is absolute, has no whitespace, fits, and does not use a
/// scheme that runs in the page that shows it.
pub fn valid(url: &str) -> bool {
    let Some((scheme, rest)) = url.split_once(':') else {
        return false;
    };
    let mut chars = scheme.chars();
    let scheme_ok = chars.next().is_some_and(|c| c.is_ascii_alphabetic())
        && chars.all(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '.' | '-'));

    scheme_ok
        && !rest.is_empty()
        && !url.chars().any(char::is_whitespace)
        && url.chars().count() <= MAX
        && !REFUSED.contains(&scheme.to_ascii_lowercase().as_str())
}

/// Trims `url`; blank clears it.
pub(crate) fn clean(url: &str) -> Result<Option<String>> {
    match url.trim() {
        "" => Ok(None),
        url if valid(url) => Ok(Some(url.to_string())),
        _ => Err(Error::Invalid(
            "a URL must be absolute, such as https://example.com, and not a script".into(),
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_any_absolute_url_but_scripts() {
        for url in [
            "https://a.example",
            "file:///Users/me/plan.md",
            "mailto:me@example.com",
            "obsidian://open?vault=x",
        ] {
            assert!(valid(url), "{url}");
        }
        for url in [
            "www.example.com",
            "/tmp/x",
            "https:",
            "https://a.example/a b",
            "javascript:alert(1)",
            "JavaScript:alert(1)",
            "data:text/html,x",
            "vbscript:x",
            "1http://x",
        ] {
            assert!(!valid(url), "{url}");
        }
        assert!(!valid(&format!("https://a.example/{}", "a".repeat(MAX))));
    }

    #[test]
    fn clean_trims_and_clears() {
        assert_eq!(
            clean("  https://a.example ").unwrap().as_deref(),
            Some("https://a.example")
        );
        assert_eq!(clean("   ").unwrap(), None);
        assert!(clean("javascript:x").is_err());
    }
}
