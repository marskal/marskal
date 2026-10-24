import Foundation

/// Today's agenda on this device's clock (ADR 0006, 0014): what is due or
/// planned today, and earlier days' still to do, by the time each is on it
/// for, earliest first.
public enum Agenda {
    /// When today ends on `calendar`, which is when the agenda changes.
    public static func endOfDay(after now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(24 * 60 * 60)
    }

    public static func today(_ store: Store, now: Date = .now, calendar: Calendar = .current) throws -> [AgendaItem] {
        try store.agenda(until: endOfDay(after: now, calendar: calendar))
    }
}

extension AgendaItem: Identifiable {
    public var id: UUID { task.id }
}
