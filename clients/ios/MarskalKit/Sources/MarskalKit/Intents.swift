import AppIntents
import Foundation

/// The App Intents in this package, for the app and the widget to include
/// (ADR 0029).
public struct MarskalKitIntents: AppIntentsPackage {}

/// Marks a task Done in the local database. The change waits in the
/// outbox; the app sends it the next time it syncs (ADR 0018).
///
/// The widget's check-off button runs it in the widget's process.
public struct CompleteTaskIntent: AppIntent {
    public static let title = LocalizedStringResource("Mark Task Done")
    public static let isDiscoverable = false

    @Parameter(title: LocalizedStringResource("Task"))
    public var taskID: String

    public init() {}

    public init(taskID: UUID) {
        self.taskID = taskID.uuidString.lowercased()
    }

    public func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID), let store = try AppGroup.openStore() else {
            return .result()
        }
        defer { store.close() }
        try store.setTaskState(id: id, state: .done)
        return .result()
    }
}
