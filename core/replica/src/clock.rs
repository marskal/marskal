use jiff::Timestamp;

/// Where the engine reads the time, so tests can fix it.
pub trait Clock: Send + Sync {
    fn now(&self) -> Timestamp;
}

/// The system clock.
#[derive(Clone, Copy, Debug, Default)]
pub struct SystemClock;

impl Clock for SystemClock {
    fn now(&self) -> Timestamp {
        Timestamp::now()
    }
}

/// A timestamp as the server stores and sends it: UTC, whole seconds,
/// `2026-10-02T09:14:03Z`. Strings in this shape sort in time order.
pub(crate) fn stamp(at: Timestamp) -> String {
    Timestamp::from_second(at.as_second())
        .expect("a timestamp's own seconds are in range")
        .to_string()
}
