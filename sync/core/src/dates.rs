//! Defer, Planned, and Due as people type them (ADR 0006), the same rules
//! as the server's `Marskal.Dates`: a day with no time takes the field's
//! default time on the wall clock of a zone. A time a DST change skips
//! moves forward; a repeated one takes the first.

use jiff::civil::{Date, Time, Weekday};
use jiff::tz::{AmbiguousOffset, TimeZone};
use jiff::{Timestamp, ToSpan};

/// Which date a value is for, since each has its own default time.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DateField {
    Defer,
    Planned,
    Due,
}

impl DateField {
    /// The wall-clock time a day gets when no time is given.
    pub fn default_time(self) -> Time {
        match self {
            DateField::Defer => Time::constant(0, 0, 0, 0),
            DateField::Planned => Time::constant(9, 0, 0, 0),
            DateField::Due => Time::constant(17, 0, 0, 0),
        }
    }
}

/// The instant for `date` at `time` (or the field's default) in `zone`.
pub fn from_local(date: Date, time: Option<Time>, field: DateField, zone: &TimeZone) -> Timestamp {
    let datetime = date.to_datetime(time.unwrap_or(field.default_time()));

    let at = match zone.to_ambiguous_timestamp(datetime).offset() {
        AmbiguousOffset::Unambiguous { offset } => offset.to_timestamp(datetime).ok(),
        // The first instant after the gap is the transition itself.
        AmbiguousOffset::Gap { before, .. } => before
            .to_timestamp(datetime)
            .ok()
            .and_then(|guess| zone.preceding(guess).next())
            .map(|transition| transition.timestamp()),
        AmbiguousOffset::Fold { before, .. } => before.to_timestamp(datetime).ok(),
    };

    at.unwrap_or_else(|| {
        datetime
            .to_zoned(TimeZone::UTC)
            .expect("UTC has no gaps")
            .timestamp()
    })
}

/// A day as typed: `today`, `tomorrow`, `yesterday`, a weekday (`fri`,
/// `friday`: the next one after today), `+3d` / `+2w`, or `2026-10-05`.
pub fn parse_day(text: &str, today: Date) -> Option<Date> {
    let text = text.trim().to_lowercase();

    match text.as_str() {
        "today" | "tod" => return Some(today),
        "tomorrow" | "tom" => return today.checked_add(1.day()).ok(),
        "yesterday" => return today.checked_sub(1.day()).ok(),
        _ => {}
    }

    if let Some(weekday) = weekday(&text) {
        let ahead = (weekday.to_monday_zero_offset() - today.weekday().to_monday_zero_offset() + 6)
            .rem_euclid(7)
            + 1;
        return today.checked_add(i64::from(ahead).days()).ok();
    }

    if let Some(offset) = text.strip_prefix('+') {
        let (number, unit) = offset.split_at(offset.find(|c: char| !c.is_ascii_digit())?);
        let n: i64 = number.parse().ok()?;
        return match unit {
            "d" => today.checked_add(n.days()).ok(),
            "w" => today.checked_add((n * 7).days()).ok(),
            _ => None,
        };
    }

    text.parse().ok()
}

/// An instant as typed: a day as [`parse_day`] reads it, optionally
/// followed by a time (`fri 14:00`), or an RFC 3339 timestamp. The day is
/// read in `zone`.
pub fn parse(text: &str, field: DateField, zone: &TimeZone, now: Timestamp) -> Option<Timestamp> {
    let text = text.trim();

    if let Ok(at) = text.parse::<Timestamp>() {
        return Some(at);
    }

    let today = now.to_zoned(zone.clone()).date();
    let (day, time) = match text.rsplit_once([' ', 'T']) {
        Some((day, time)) if time.contains(':') => (day, Some(time.parse::<Time>().ok()?)),
        _ => (text, None),
    };

    Some(from_local(parse_day(day, today)?, time, field, zone))
}

fn weekday(text: &str) -> Option<Weekday> {
    let days = [
        ("mon", Weekday::Monday),
        ("tue", Weekday::Tuesday),
        ("wed", Weekday::Wednesday),
        ("thu", Weekday::Thursday),
        ("fri", Weekday::Friday),
        ("sat", Weekday::Saturday),
        ("sun", Weekday::Sunday),
    ];

    days.into_iter()
        .find(|(short, day)| text == *short || text == format!("{day:?}").to_lowercase())
        .map(|(_, day)| day)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn copenhagen() -> TimeZone {
        TimeZone::get("Europe/Copenhagen").unwrap()
    }

    #[test]
    fn a_day_takes_the_default_time_in_the_zone() {
        let due = from_local(
            jiff::civil::date(2026, 9, 30),
            None,
            DateField::Due,
            &copenhagen(),
        );
        assert_eq!(due.to_string(), "2026-09-30T15:00:00Z");

        let defer = from_local(
            jiff::civil::date(2026, 9, 30),
            None,
            DateField::Defer,
            &copenhagen(),
        );
        assert_eq!(defer.to_string(), "2026-09-29T22:00:00Z");
    }

    #[test]
    fn a_skipped_time_moves_forward_and_a_repeated_one_takes_the_first() {
        let zone = copenhagen();
        let skipped = from_local(
            jiff::civil::date(2026, 3, 29),
            Some(Time::constant(2, 30, 0, 0)),
            DateField::Due,
            &zone,
        );
        assert_eq!(skipped.to_string(), "2026-03-29T01:00:00Z");

        let repeated = from_local(
            jiff::civil::date(2026, 10, 25),
            Some(Time::constant(2, 30, 0, 0)),
            DateField::Due,
            &zone,
        );
        assert_eq!(repeated.to_string(), "2026-10-25T00:30:00Z");
    }

    #[test]
    fn days_as_typed() {
        let friday = jiff::civil::date(2026, 10, 2);
        assert_eq!(parse_day("today", friday), Some(friday));
        assert_eq!(
            parse_day("tomorrow", friday),
            Some(jiff::civil::date(2026, 10, 3))
        );
        assert_eq!(
            parse_day("mon", friday),
            Some(jiff::civil::date(2026, 10, 5))
        );
        assert_eq!(
            parse_day("friday", friday),
            Some(jiff::civil::date(2026, 10, 9))
        );
        assert_eq!(
            parse_day("+2w", friday),
            Some(jiff::civil::date(2026, 10, 16))
        );
        assert_eq!(
            parse_day("2026-12-24", friday),
            Some(jiff::civil::date(2026, 12, 24))
        );
        assert_eq!(parse_day("someday", friday), None);
    }

    #[test]
    fn an_instant_with_a_time() {
        let now: Timestamp = "2026-10-02T08:00:00Z".parse().unwrap();
        let at = parse("tomorrow 14:30", DateField::Planned, &copenhagen(), now).unwrap();
        assert_eq!(at.to_string(), "2026-10-03T12:30:00Z");
    }
}
