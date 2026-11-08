import Foundation
import MarskalKit
import Testing

// Days on the user's clock, whatever the device's zone and week start.
struct UserClockTests {
    let copenhagen = TimeZone(identifier: "Europe/Copenhagen")!

    func clock(weekStart: UInt8 = 1) -> UserClock {
        UserClock(zone: copenhagen, weekStart: weekStart, locale: Locale(identifier: "en_DK"))
    }

    func at(_ text: String) -> Date {
        try! Date(text, strategy: .iso8601)
    }

    @Test func theWeekStartsOnThePreferencesDay() {
        #expect(clock(weekStart: 1).calendar.firstWeekday == 2)
        #expect(clock(weekStart: 7).calendar.firstWeekday == 1)
        #expect(clock(weekStart: 6).calendar.firstWeekday == 7)
    }

    @Test func nextWeekIsItsFirstDay() {
        // Wednesday 11 November 2026, 23:30 in Copenhagen.
        let now = at("2026-11-11T22:30:00Z")
        #expect(clock(weekStart: 1).nextWeek(now) == at("2026-11-15T23:00:00Z"))
        #expect(clock(weekStart: 7).nextWeek(now) == at("2026-11-14T23:00:00Z"))
    }

    @Test func todayIsTheUsersDayNotUTCs() {
        // Already 12 November in Copenhagen.
        let now = at("2026-11-11T23:30:00Z")
        #expect(clock().today(now) == at("2026-11-11T23:00:00Z"))
        #expect(clock().tomorrow(now) == at("2026-11-12T23:00:00Z"))
    }

    @Test func aPickedDayTakesTheFieldsDefaultTime() {
        // A picker's date: any instant on 12 November in Copenhagen.
        let picked = at("2026-11-11T23:30:00Z")
        #expect(clock().instant(on: picked, at: nil, for: .due) == at("2026-11-12T16:00:00Z"))
        #expect(clock().instant(on: picked, at: nil, for: .defer) == at("2026-11-11T23:00:00Z"))
        #expect(
            clock().instant(on: picked, at: LocalTime(hour: 14, minute: 30), for: .planned)
                == at("2026-11-12T13:30:00Z"))
    }

    @Test func aDefaultTimeIsNoTimeOfItsOwn() {
        let due = at("2026-11-12T16:00:00Z")
        #expect(!clock().hasTime(due, for: .due))
        #expect(clock().hasTime(due, for: .planned))
        #expect(clock().day(of: due) == LocalDate(year: 2026, month: 11, day: 12))
        #expect(clock().time(of: due) == LocalTime(hour: 17, minute: 0))
    }

    @Test func aLabelLeavesOutThisYearAndTheDefaultTime() {
        let now = at("2026-11-08T10:00:00Z")
        let due = at("2026-11-12T16:00:00Z")
        #expect(!clock().label(due, for: .due, now: now).contains("2026"))
        #expect(!clock().label(due, for: .due, now: now).contains("17"))
        #expect(clock().label(due, for: .planned, now: now).contains("17"))
        #expect(clock().label(at("2027-01-04T16:00:00Z"), for: .due, now: now).contains("2027"))
    }
}
