import Foundation

/// The user's wall clock (ADR 0006, 0023): their zone, the day their weeks
/// start on, and their locale. Dates are picked and shown on it rather than
/// on the device's settings, so a day is the same day as on the web.
public struct UserClock: Sendable {
    public let zone: TimeZone
    public let calendar: Calendar
    public let locale: Locale

    /// The user's preferences, or the device's settings before a sync has
    /// brought them.
    public init(preferences: Preferences?) {
        guard let preferences else {
            self.init(zone: .current, firstWeekday: Calendar.current.firstWeekday, locale: .current)
            return
        }
        self.init(
            zone: TimeZone(identifier: preferences.timezone) ?? .current,
            weekStart: preferences.weekStart,
            locale: Locale(identifier: preferences.locale))
    }

    /// `weekStart` is the ISO day, 1 for Monday, as the preference has it.
    public init(zone: TimeZone, weekStart: UInt8, locale: Locale) {
        // Foundation counts Sunday as 1.
        self.init(zone: zone, firstWeekday: Int(weekStart) % 7 + 1, locale: locale)
    }

    private init(zone: TimeZone, firstWeekday: Int, locale: Locale) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = locale
        calendar.firstWeekday = firstWeekday
        self.zone = zone
        self.calendar = calendar
        self.locale = locale
    }

    // MARK: Days and times

    /// The day `at` falls on.
    public func day(of at: Date) -> LocalDate {
        let parts = calendar.dateComponents([.year, .month, .day], from: at)
        return LocalDate(year: Int16(parts.year ?? 1970), month: Int8(parts.month ?? 1), day: Int8(parts.day ?? 1))
    }

    /// The time on the wall clock at `at`.
    public func time(of at: Date) -> LocalTime {
        let parts = calendar.dateComponents([.hour, .minute], from: at)
        return LocalTime(hour: Int8(parts.hour ?? 0), minute: Int8(parts.minute ?? 0))
    }

    /// Whether `at` has a time of its own rather than the one a day with no
    /// time gets for `field`.
    public func hasTime(_ at: Date, for field: DateField) -> Bool {
        time(of: at) != defaultTime(field: field)
    }

    /// The instant for the day `day` falls on, at `time` or the field's
    /// default time. The engine decides it, as it does for typed dates.
    public func instant(on day: Date, at time: LocalTime?, for field: DateField) -> Date {
        if let at = try? localInstant(date: self.day(of: day), time: time, field: field, zone: zone.identifier) {
            return at
        }
        // A zone the engine does not know: Foundation's reading of it.
        let time = time ?? defaultTime(field: field)
        return calendar.date(
            bySettingHour: Int(time.hour), minute: Int(time.minute), second: 0, of: day,
            matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward) ?? day
    }

    /// The start of today.
    public func today(_ now: Date = .now) -> Date {
        calendar.startOfDay(for: now)
    }

    /// The start of tomorrow.
    public func tomorrow(_ now: Date = .now) -> Date {
        calendar.date(byAdding: .day, value: 1, to: today(now)) ?? now
    }

    /// The first day of next week, by the user's week start.
    public func nextWeek(_ now: Date = .now) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: now)?.end ?? now
    }

    // MARK: Text

    /// A date as a row shows it: "Fri 13 Nov", with the year when it is
    /// not this year's, and the time when it is not the field's default.
    public func label(_ at: Date, for field: DateField, now: Date = .now) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: zone)
            .weekday(.abbreviated).day().month(.abbreviated)
        if !calendar.isDate(at, equalTo: now, toGranularity: .year) {
            style = style.year()
        }
        if hasTime(at, for: field) {
            style = style.hour().minute()
        }
        return at.formatted(style)
    }

    /// The time a day with no time gets for `field`, such as "17:00".
    public func defaultTimeLabel(for field: DateField) -> String {
        let at = instant(on: today(), at: nil, for: field)
        return at.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: zone).hour().minute())
    }
}
