//! Matches a typed query against a path of names, such as a tag's path or a
//! project's folders and title (ADR 0005, ADR 0033), as the server's
//! `Marskal.PathSearch` does. `sync/fixtures/path_search.json` holds the
//! vectors both run.
//!
//! The query is split on `/ : › > \`, and so is every segment of the path,
//! so one rule covers both readings of `som/may`: the literal name
//! `Someday/maybe` and the path `Someday › Maybach`. Each piece must be a
//! case-insensitive prefix of a part, or of a word in it, in order. The last
//! piece must land in the last segment, the record's own name, so a query
//! finds the record, not everything under the ancestor it names. Pieces may
//! skip ancestors: `per/wi` finds `Person › Family › Wife`.
//!
//! Text is compared as given, after lowercasing: names are stored in NFC,
//! and a shell normalizes what the user types to NFC before it searches.

const SEPARATORS: [char; 5] = ['/', ':', '›', '>', '\\'];

/// The query's pieces, normalized; empty for a blank query.
pub fn pieces(query: &str) -> Vec<String> {
    split(query)
}

/// The whole query, normalized, to compare with a name for an exact match.
pub fn whole(query: &str) -> String {
    query.to_lowercase().trim().to_string()
}

/// Whether a name equals the query, ignoring case.
pub fn is_exact(name: &str, whole: &str) -> bool {
    name.to_lowercase() == whole
}

/// The number of path segments skipped between the first match and the
/// last segment, or `None` when the path does not match. No pieces match
/// nothing.
pub fn matches(path: &[String], pieces: &[String]) -> Option<usize> {
    if pieces.is_empty() || path.is_empty() {
        return None;
    }

    let own = path.len() - 1;
    let parts: Vec<(String, usize)> = path
        .iter()
        .enumerate()
        .flat_map(|(index, segment)| split(segment).into_iter().map(move |part| (part, index)))
        .collect();

    let (first, last) = place(pieces, &parts)?;
    if last != own {
        return None;
    }
    let span = own - first + 1;
    Some(span - pieces.len().min(span))
}

// Matches pieces to parts in order, greedily from the right, which finds a
// match whenever one exists and puts the last piece as late as possible.
// Returns (segment of the first piece, segment of the last piece).
fn place(pieces: &[String], parts: &[(String, usize)]) -> Option<(usize, usize)> {
    let mut remaining = parts.iter().rev();
    let mut first = None;
    let mut last = None;

    for piece in pieces.iter().rev() {
        let (_, index) = remaining
            .by_ref()
            .find(|(part, _)| is_prefix(part, piece))?;
        first = Some(*index);
        last = last.or(Some(*index));
    }

    Some((first?, last?))
}

fn is_prefix(part: &str, piece: &str) -> bool {
    part.starts_with(piece) || part.split_whitespace().any(|word| word.starts_with(piece))
}

fn split(text: &str) -> Vec<String> {
    text.to_lowercase()
        .split(SEPARATORS)
        .map(str::trim)
        .filter(|piece| !piece.is_empty())
        .map(str::to_string)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn path(names: &[&str]) -> Vec<String> {
        names.iter().map(|n| n.to_string()).collect()
    }

    #[test]
    fn a_blank_query_matches_nothing() {
        assert_eq!(pieces(" / "), Vec::<String>::new());
        assert_eq!(matches(&path(&["Person"]), &pieces(" / ")), None);
    }

    #[test]
    fn counts_the_ancestors_skipped() {
        let wife = path(&["Person", "Family", "Wife"]);
        assert_eq!(matches(&wife, &pieces("per/wi")), Some(1));
        assert_eq!(matches(&wife, &pieces("wi")), Some(0));
        assert_eq!(matches(&wife, &pieces("per/fam/wi")), Some(0));
    }
}
