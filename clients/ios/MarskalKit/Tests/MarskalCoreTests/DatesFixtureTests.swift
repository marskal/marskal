import Foundation
import MarskalCore
import Testing

// sync/fixtures/dates.json, the vectors the server and sync/core run,
// through the bindings: the engine's own zone data, not the device's.
struct DatesFixtureTests {
    struct Vector: Decodable {
        let date: String
        let time: String?
        let at: String
        let field: String
        let zone: String
        let why: String
    }

    static let vectors: [Vector] = {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "../../../../../sync/fixtures/dates.json")
            .standardized
        struct File: Decodable { let from_local: [Vector] }
        return try! JSONDecoder().decode(File.self, from: Data(contentsOf: url)).from_local
    }()

    @Test(arguments: vectors)
    func aDayIsTheVectorsInstant(_ vector: Vector) throws {
        let day = vector.date.split(separator: "-").map { Int($0)! }
        let time = vector.time.map { text in
            let parts = text.split(separator: ":").map { Int8($0)! }
            return LocalTime(hour: parts[0], minute: parts[1])
        }
        let field: DateField = switch vector.field {
        case "defer": .defer
        case "planned": .planned
        default: .due
        }

        let at = try localInstant(
            date: LocalDate(year: Int16(day[0]), month: Int8(day[1]), day: Int8(day[2])),
            time: time, field: field, zone: vector.zone)
        #expect(at == (try Date(vector.at, strategy: .iso8601)), "\(vector.why)")
    }

    @Test func anUnknownZoneThrows() {
        #expect(throws: StoreError.self) {
            try localInstant(date: LocalDate(year: 2026, month: 1, day: 1), time: nil, field: .due, zone: "Mars/Olympus")
        }
    }
}

extension DatesFixtureTests.Vector: CustomTestStringConvertible {
    var testDescription: String { why }
}
