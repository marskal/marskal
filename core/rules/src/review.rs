//! Project review intervals (ADR 0026), as the server's
//! `Marskal.ReviewInterval` has them.
//!
//! An interval is an ISO 8601 duration with date parts only, such as `P1W`
//! or `P1M15D`, letters in either case. It is kept as Postgres keeps it:
//! weeks become days and twelve months a year, so `P2W` is `P14D`. No time
//! part, no negative part, and not zero, because a review is due on a day.

use jiff::Span;
use jiff::civil::Date;
use jiff::fmt::temporal::SpanParser;

/// Reads an interval and normalizes it to years, months, and days, or
/// `None` when it is not one a project may have.
pub fn parse(text: &str) -> Option<Span> {
    let text = text.trim().to_ascii_uppercase();
    let span = SpanParser::new().parse_span(text.as_bytes()).ok()?;
    normalize(span)
}

/// The interval as the server sends it: `P1Y2M`, `P14D`. `None` for a
/// span that is not a valid interval.
pub fn format(interval: Span) -> Option<String> {
    let span = normalize(interval)?;
    let mut text = String::from("P");
    for (value, unit) in [
        (i64::from(span.get_years()), 'Y'),
        (i64::from(span.get_months()), 'M'),
        (i64::from(span.get_days()), 'D'),
    ] {
        if value != 0 {
            text.push_str(&format!("{value}{unit}"));
        }
    }
    Some(text)
}

/// Reads an interval and writes it back as the server would store it.
pub fn normalize_text(text: &str) -> Option<String> {
    format(parse(text)?)
}

/// The day `interval` after `from`. Years and months are added first, then
/// days, and a step past a short month's end lands on its last day, as
/// Postgres adds an interval to a date: Jan 31 + `P1M` is Feb 28, and
/// Jan 31 + `P1M1D` is Mar 1. `None` for an invalid interval or a day out
/// of range.
pub fn next_review_on(from: Date, interval: Span) -> Option<Date> {
    let span = normalize(interval)?;
    let months = Span::new()
        .try_years(span.get_years())
        .ok()?
        .try_months(span.get_months())
        .ok()?;
    let days = Span::new().try_days(span.get_days()).ok()?;
    from.checked_add(months).ok()?.checked_add(days).ok()
}

// Date parts only, none negative, not zero; then as Postgres keeps them.
fn normalize(span: Span) -> Option<Span> {
    let time = [
        span.get_hours() as i64,
        span.get_minutes(),
        span.get_seconds(),
        span.get_milliseconds(),
        span.get_microseconds(),
        span.get_nanoseconds(),
    ];
    if span.is_negative() || span.is_zero() || time.iter().any(|&part| part != 0) {
        return None;
    }

    let months = 12 * i64::from(span.get_years()) + i64::from(span.get_months());
    let days = 7 * i64::from(span.get_weeks()) + i64::from(span.get_days());

    Span::new()
        .try_years(months / 12)
        .ok()?
        .try_months(months % 12)
        .ok()?
        .try_days(days)
        .ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use jiff::civil::date;

    fn next(from: Date, text: &str) -> Date {
        next_review_on(from, parse(text).unwrap()).unwrap()
    }

    #[test]
    fn reads_date_parts_as_postgres_keeps_them() {
        for (text, kept) in [
            ("P1W", "P7D"),
            ("p2w", "P14D"),
            (" P2W3D ", "P17D"),
            ("P1M", "P1M"),
            ("P1m15d", "P1M15D"),
            ("P14M", "P1Y2M"),
            ("P1Y", "P1Y"),
            ("P12M", "P1Y"),
            ("P1DT0H", "P1D"),
        ] {
            assert_eq!(normalize_text(text).as_deref(), Some(kept), "{text}");
        }
    }

    #[test]
    fn refuses_time_parts_negatives_zero_and_other_text() {
        for text in [
            "",
            "P",
            "P0D",
            "PT0S",
            "P1DT1H",
            "PT24H",
            "-P1D",
            "P-1D",
            "1 week",
            "P1.5D",
            "1W",
            "every week",
        ] {
            assert!(parse(text).is_none(), "{text}");
        }
    }

    #[test]
    fn adds_months_first_then_days_clamping_to_a_short_month() {
        let jan31 = date(2026, 1, 31);
        assert_eq!(next(jan31, "P1M"), date(2026, 2, 28));
        assert_eq!(next(jan31, "P1M1D"), date(2026, 3, 1));
        assert_eq!(next(date(2028, 1, 31), "P1M"), date(2028, 2, 29));
        assert_eq!(next(date(2028, 2, 29), "P1Y"), date(2029, 2, 28));
        assert_eq!(next(date(2026, 10, 2), "P1W"), date(2026, 10, 9));
        assert_eq!(next(date(2026, 12, 25), "P2W"), date(2027, 1, 8));
        assert_eq!(next(date(2026, 8, 31), "P1Y6M"), date(2028, 2, 29));
    }

    #[test]
    fn weeks_in_a_span_count_as_days() {
        let span = Span::new().weeks(2).days(1);
        assert_eq!(format(span).as_deref(), Some("P15D"));
        assert_eq!(
            next_review_on(date(2026, 10, 1), span),
            Some(date(2026, 10, 16))
        );
        assert_eq!(
            next_review_on(date(2026, 10, 1), Span::new().hours(1)),
            None
        );
    }
}
