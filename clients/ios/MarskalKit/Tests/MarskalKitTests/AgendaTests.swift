import Foundation
import MarskalKit
import Testing

// Today is the device's day; the engine's agenda rules are tested in Rust.
struct AgendaTests {
    let path = FileManager.default.temporaryDirectory
        .appending(path: "marskal-\(UUID().uuidString).sqlite").path()

    var copenhagen: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Copenhagen")!
        return calendar
    }

    func at(_ text: String) -> Date {
        try! Date(text, strategy: .iso8601)
    }

    @Test func todayEndsAtTheDevicesMidnight() {
        #expect(Agenda.endOfDay(after: at("2026-10-24T21:30:00Z"), calendar: copenhagen) == at("2026-10-24T22:00:00Z"))
        // 25 October is 25 hours long there.
        #expect(Agenda.endOfDay(after: at("2026-10-24T22:30:00Z"), calendar: copenhagen) == at("2026-10-25T23:00:00Z"))
    }

    @Test func todayLeavesOutTomorrow() throws {
        let store = try Store.open(path: path)
        defer { store.close() }

        let today = try store.addTask(new: NewTask(title: "Today", plannedAt: at("2020-05-04T08:00:00Z")))
        _ = try store.addTask(new: NewTask(title: "Tomorrow", plannedAt: at("2020-05-04T22:00:00Z")))

        let agenda = try Agenda.today(store, now: at("2020-05-04T10:00:00Z"), calendar: copenhagen)
        #expect(agenda.map(\.id) == [today])
        #expect(agenda.first?.due == false)
    }
}
