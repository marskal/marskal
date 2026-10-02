//! Fractional sibling order (ADR 0014), the same as the server's
//! `Marskal.Rank`.
//!
//! A rank is a string over `0-9A-Za-z`, compared byte by byte. Read it as
//! the digits after a point in base 62. [`between`] gives a rank strictly
//! between two neighbors, never ending in `0`, so there is always room for
//! another. Both sides run `sync/fixtures/rank.json`.

const DIGITS: &[u8; 62] = b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
const BASE: u32 = 62;

/// The first rank in an empty list.
pub fn first() -> String {
    between(None, None).expect("an empty list has room")
}

/// A rank after `before` and before `later`; `None` is the start or the
/// end of the list. `None` when the two are not in order or not ranks.
pub fn between(before: Option<&str>, later: Option<&str>) -> Option<String> {
    let a = decode(before.unwrap_or(""))?;
    let b = match later {
        Some(later) => Some(decode(later)?),
        None => None,
    };

    if b.as_ref().is_some_and(|b| a >= *b) {
        return None;
    }

    Some(encode(&midpoint(&a, b.as_deref())))
}

/// `count` ranks in order, spread evenly, each as short as the list allows.
pub fn spread(count: u64) -> Vec<String> {
    if count == 0 {
        return Vec::new();
    }

    let mut width = 1u32;
    while u128::from(BASE).pow(width) < 2 * (u128::from(count) + 1) {
        width += 1;
    }

    let step = u128::from(BASE).pow(width) / (u128::from(count) + 1);

    (1..=u128::from(count))
        .map(|i| {
            let mut digits = to_digits(i * step, width);
            while digits.last() == Some(&0) {
                digits.pop();
            }
            encode(&digits)
        })
        .collect()
}

/// A well-formed rank: `0-9A-Za-z`, not empty, not ending in `0`.
pub fn is_valid(rank: &str) -> bool {
    !rank.is_empty() && !rank.ends_with('0') && decode(rank).is_some()
}

// A missing digit in `a` counts as 0. `b` of `None` is past every rank.
fn midpoint(a: &[u8], b: Option<&[u8]>) -> Vec<u8> {
    if let Some(b) = b {
        // A shared leading digit is kept: "VA", "VC" -> "V" + midpoint("A", "C").
        if let (Some(&x), Some(&y)) = (a.first(), b.first())
            && x == y
        {
            return prepend(x, midpoint(&a[1..], Some(&b[1..])));
        }

        if a.is_empty() && b.first() == Some(&0) {
            return prepend(0, midpoint(&[], Some(&b[1..])));
        }
    }

    let low = u32::from(a.first().copied().unwrap_or(0));
    let high = match b {
        Some(b) if !b.is_empty() => u32::from(b[0]),
        _ => BASE,
    };

    if high - low > 1 {
        // Room for a digit between: "V", "l" -> "d".
        vec![(low + high).div_ceil(2) as u8]
    } else if matches!(b, Some(b) if b.len() >= 2) {
        // b's first digit alone is below b: "V", "W1" -> "W".
        vec![high as u8]
    } else {
        // Adjacent: keep a's digit and go halfway from the rest of a to the end.
        prepend(low as u8, midpoint(a.get(1..).unwrap_or(&[]), None))
    }
}

fn prepend(digit: u8, mut rest: Vec<u8>) -> Vec<u8> {
    rest.insert(0, digit);
    rest
}

fn to_digits(mut n: u128, width: u32) -> Vec<u8> {
    let mut digits = vec![0u8; width as usize];
    for slot in digits.iter_mut().rev() {
        *slot = (n % u128::from(BASE)) as u8;
        n /= u128::from(BASE);
    }
    digits
}

fn decode(rank: &str) -> Option<Vec<u8>> {
    rank.bytes()
        .map(|byte| DIGITS.iter().position(|&d| d == byte).map(|i| i as u8))
        .collect()
}

fn encode(digits: &[u8]) -> String {
    digits.iter().map(|&d| DIGITS[d as usize] as char).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn three_siblings_then_one_between_the_first_two() {
        let a = first();
        let b = between(Some(&a), None).unwrap();
        let c = between(Some(&b), None).unwrap();
        assert_eq!((a.as_str(), b.as_str(), c.as_str()), ("V", "l", "t"));
        assert_eq!(between(Some(&a), Some(&b)).unwrap(), "d");
    }

    #[test]
    fn out_of_order_or_malformed_is_none() {
        assert_eq!(between(Some("l"), Some("V")), None);
        assert_eq!(between(Some("V"), Some("V")), None);
        assert_eq!(between(Some("a-b"), None), None);
    }
}
