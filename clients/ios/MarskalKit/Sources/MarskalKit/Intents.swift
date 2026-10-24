import AppIntents
import Foundation
import WidgetKit

/// The App Intents in this package, for the app and the widget to include
/// (ADR 0029).
public struct MarskalKitIntents: AppIntentsPackage {}

/// Adds a task to the Inbox, from Shortcuts, Siri, or Spotlight. It runs in
/// the app's process without opening the app, and syncs at once so the
/// task reaches the server; offline, it waits in the outbox.
public struct AddToInboxIntent: AppIntent {
    public static let title = LocalizedStringResource("Add to Inbox")
    public static let description = IntentDescription(LocalizedStringResource("Adds a task to your Marskal Inbox."))

    @Parameter(
        title: LocalizedStringResource("Title"),
        requestValueDialog: IntentDialog(LocalizedStringResource("What do you want to add?"))
    )
    public var taskTitle: String

    public init() {}

    public init(title: String) {
        self.taskTitle = title
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$taskTitle) to the Inbox")
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let title = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw $taskTitle.needsValueError(IntentDialog(LocalizedStringResource("What do you want to add?")))
        }

        try await AppGroup.change { store in
            _ = try store.addTask(new: NewTask(title: title))
        }
        // A format, not interpolation: the catalog extraction reads source and
        // cannot tell an interpolated value's type.
        let added = String(format: String(localized: "Added “%@” to the Inbox."), title)
        return .result(dialog: IntentDialog(stringLiteral: added))
    }
}

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
        // WidgetKit reloads the widget whose button this was; the task may
        // be on the others too.
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Why an intent could not do what it was asked, in words for Siri and
/// Shortcuts.
public enum IntentProblem: Error, CustomLocalizedStringResourceConvertible {
    case signedOut
    case invalid(String)
    case database

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .signedOut: LocalizedStringResource("Sign in to Marskal in the app first.")
        // The engine's reason, in English, as the server would give it.
        case .invalid(let reason): LocalizedStringResource(stringLiteral: reason)
        case .database: LocalizedStringResource("Marskal could not read its data. Open the app and try again.")
        }
    }
}

extension Notification.Name {
    /// Posted in the app's process after an intent changed the database, so
    /// an open app shows the change.
    public static let marskalStoreChanged = Notification.Name("app.marskal.storeChanged")
}

extension AppGroup {
    /// Applies a change from an intent in the app's process: opens the
    /// database, changes it, syncs if the server answers, and closes it.
    static func change(_ apply: (Store) throws -> Void) async throws {
        let store: Store
        do {
            guard let opened = try openStore() else { throw IntentProblem.signedOut }
            store = opened
        } catch let problem as IntentProblem {
            throw problem
        } catch {
            throw IntentProblem.database
        }
        defer { store.close() }

        do {
            try apply(store)
        } catch StoreError.Invalid(let message), StoreError.NotFound(let message) {
            throw IntentProblem.invalid(message)
        } catch {
            throw IntentProblem.database
        }

        if let server {
            _ = try? await Session(server: server, tokens: KeychainTokenStore()).sync(store)
        }
        WidgetCenter.shared.reloadAllTimelines()
        await MainActor.run {
            NotificationCenter.default.post(name: .marskalStoreChanged, object: nil)
        }
    }
}
