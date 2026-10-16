import Foundation
import MarskalCore
import Testing

// The engine through its Swift bindings: dates as Date, ids as UUID, and
// the errors as Swift errors. The engine's rules are tested in Rust.
struct StoreTests {
    let path = FileManager.default.temporaryDirectory
        .appending(path: "marskal-\(UUID().uuidString).sqlite").path()

    @Test func aCaptureReadsBackWithItsDates() throws {
        let store = try Store.open(path: path)
        defer { store.close() }

        let due = Date(timeIntervalSince1970: 1_793_000_000)
        let id = try store.addTask(new: NewTask(title: "Buy milk", dueAt: due))

        let inbox = try store.tasks(filter: .inbox)
        #expect(inbox.map(\.id) == [id])
        #expect(inbox.first?.dates.dueAt == due)
        #expect(try store.status().pending == 1)
    }

    @Test func aClosedStoreThrows() throws {
        let store = try Store.open(path: path)
        store.close()
        #expect(throws: StoreError.Closed.self) { try store.status() }
    }
}
