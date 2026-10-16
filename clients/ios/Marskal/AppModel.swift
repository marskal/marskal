import Foundation
import MarskalKit
import Observation
import UIKit
import WidgetKit

/// The app's state: which server it is signed in to, the local database
/// while the app is in the foreground, and what the lists show.
@Observable @MainActor
final class AppModel {
    private(set) var session: Session?
    private(set) var inbox: [TaskItem] = []
    private(set) var open: [TaskItem] = []
    private(set) var preferences: Preferences?
    private(set) var lastSyncedAt: Date?
    private(set) var projects: [ProjectItem] = []
    private(set) var pending: UInt64 = 0
    private(set) var syncing = false
    /// The last sync could not reach the server. Changes wait in the outbox.
    private(set) var offline = false
    private(set) var signingIn = false
    var problem: Problem?

    private var store: Store?
    private var syncTask: Task<Void, Never>?
    private var soonTask: Task<Void, Never>?
    private var syncAgain = false
    private let tokens: TokenStore
    static let refreshTask = "app.marskal.ios.sync"

    init(tokens: TokenStore = KeychainTokenStore()) {
        self.tokens = tokens
        // An intent in this process, such as Add to Inbox from Siri,
        // changed the database.
        NotificationCenter.default.addObserver(forName: .marskalStoreChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        if let saved = AppGroup.server {
            let session = Session(server: saved, tokens: tokens)
            if session.isSignedIn { self.session = session }
        }
    }

    /// The locale dates and text go by: the user's preference, once a sync
    /// has brought it, or the device's (ADR 0027).
    var locale: Locale {
        preferences.map { Locale(identifier: $0.locale) } ?? .current
    }

    // MARK: Sign-in

    /// Signs in through the system's web sheet. `authenticate` shows the
    /// URL and returns the callback URL.
    func signIn(address: String, authenticate: (URL) async throws -> URL) async {
        guard let server = ServerAddress.parse(address) else {
            problem = .badAddress
            return
        }

        signingIn = true
        defer { signingIn = false }

        do {
            let signIn = try await SignIn.start(server: server)
            let callback = try await authenticate(signIn.url)
            let new = try await signIn.finish(callback: callback)

            let session = Session(server: server, tokens: tokens)
            await session.signedIn(new, endpoints: signIn.endpoints)
            AppGroup.server = server
            self.session = session
            activate()
        } catch let error as ServerError {
            problem = Problem(error)
        } catch {
            // The user closed the sheet.
        }
    }

    /// Signs out and deletes the local database, with any changes the
    /// server has not taken yet.
    func signOut() async {
        guard let session else { return }
        soonTask?.cancel()
        soonTask = nil
        await syncTask?.value
        store?.close()
        store = nil
        await session.signOut()
        Database.remove(server: session.server)
        AppGroup.server = nil
        WidgetCenter.shared.reloadAllTimelines()
        self.session = nil
        inbox = []
        open = []
        projects = []
        offline = false
        preferences = nil
        lastSyncedAt = nil
        pending = 0
    }

    // The grant was revoked or expired. The database stays, with any
    // changes not yet sent: signing in again to this server sends them.
    private func signedOutOnServer() {
        store?.close()
        store = nil
        session = nil
    }

    // MARK: Foreground and background

    /// Opens the database and syncs, as the app comes to the foreground.
    func activate() {
        guard let session else { return }
        if store == nil {
            do {
                store = try Database.open(server: session.server)
            } catch {
                problem = .database
                return
            }
        }
        reload()
        sync()
    }

    /// Finishes a sync under way, then closes the database, so the
    /// suspended app holds no lock on the shared file (ADR 0029).
    func deactivate() async {
        let application = UIApplication.shared
        let id = application.beginBackgroundTask(withName: "Close the database")
        // Send what is waiting now rather than when the app comes back.
        soonTask?.cancel()
        soonTask = nil
        if pending > 0 { sync() }
        await syncTask?.value
        store?.close()
        store = nil
        application.endBackgroundTask(id)
    }

    /// A sync from a background refresh task. Opens and closes its own
    /// connection.
    func backgroundSync() async {
        guard let session, store == nil, let store = try? Database.open(server: session.server) else { return }
        _ = try? await session.sync(store)
        store.close()
    }

    // MARK: Sync and reads

    /// Starts a sync. One under way runs again when it finishes, to send
    /// what changed meanwhile. An unreachable server is reported only when
    /// the user asked for the sync; otherwise the app shows it is offline.
    func sync(asked: Bool = false) {
        guard let session, let store else { return }
        guard syncTask == nil else {
            syncAgain = true
            return
        }
        syncing = true
        syncTask = Task {
            do {
                _ = try await session.sync(store)
                offline = false
            } catch let error as ServerError {
                switch error {
                case .notSignedIn:
                    signedOutOnServer()
                    problem = .signedOut
                case .network:
                    offline = true
                    if asked { problem = Problem(error) }
                default:
                    problem = Problem(error)
                }
            } catch StoreError.OtherAccount {
                problem = .otherAccount
            } catch StoreError.Closed {
                // The app went to the background.
            } catch {
                problem = .database
            }
            syncing = false
            syncTask = nil
            reload()
            WidgetCenter.shared.reloadAllTimelines()

            if syncAgain {
                syncAgain = false
                sync()
            }
        }
    }

    /// Syncs a moment after a change, so a burst of changes goes in one push.
    private func syncSoon() {
        soonTask?.cancel()
        soonTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            soonTask = nil
            sync()
        }
    }

    /// Waits for a sync to finish, for pull to refresh.
    func refresh() async {
        sync(asked: true)
        await syncTask?.value
    }

    // MARK: Changes

    /// Captures a task in the Inbox.
    func capture(_ title: String) {
        change { _ = try $0.addTask(new: NewTask(title: title)) }
    }

    /// Marks a task Done, Dropped, or To-Do again.
    func setState(_ task: TaskItem, _ state: TaskState) {
        change { try $0.setTaskState(id: task.id, state: state) }
    }

    /// Moves a task to the Inbox, No project, or a project.
    func move(_ task: TaskItem, to location: Location) {
        change { try $0.moveTask(id: task.id, location: location) }
    }

    // Applies a change here, where it shows at once, and sends it soon.
    private func change(_ apply: (Store) throws -> Void) {
        guard let store else { return }
        do {
            try apply(store)
        } catch StoreError.Invalid(let message), StoreError.NotFound(let message) {
            problem = .invalid(message)
        } catch {
            problem = .database
        }
        reload()
        WidgetCenter.shared.reloadAllTimelines()
        syncSoon()
    }

    /// Reads the lists again.
    func reload() {
        guard let store else { return }
        do {
            inbox = try store.tasks(filter: .inbox)
            open = try store.tasks(filter: .open(unavailable: false))
            projects = try store.projects().filter { $0.state == .toDo }
            preferences = try store.preferences()
            let status = try store.status()
            lastSyncedAt = status.lastSyncedAt
            pending = status.pending
        } catch StoreError.Closed {
        } catch {
            problem = .database
        }
    }
}

/// Something to tell the user.
enum Problem: Identifiable, Equatable {
    case badAddress
    case unreachable
    case signInFailed(String)
    case signedOut
    case otherAccount
    case database
    case server(Int)
    case invalid(String)

    var id: String { "\(self)" }

    init(_ error: ServerError) {
        switch error {
        case .network: self = .unreachable
        case .badAddress: self = .badAddress
        case .oauth(let code): self = .signInFailed(code)
        case .notSignedIn: self = .signedOut
        case .forbidden: self = .server(403)
        case .gone: self = .server(410)
        case .status(let status): self = .server(status)
        }
    }

    var title: String {
        switch self {
        case .badAddress: String(localized: "That is not a server address")
        case .unreachable: String(localized: "The server could not be reached")
        case .signInFailed: String(localized: "Sign-in did not finish")
        case .signedOut: String(localized: "You were signed out")
        case .otherAccount: String(localized: "This data belongs to another account")
        case .database: String(localized: "The local data could not be read")
        case .server: String(localized: "The server could not sync")
        case .invalid: String(localized: "That change could not be made")
        }
    }

    var message: String {
        switch self {
        case .badAddress:
            String(localized: "Type the address you open Marskal at in a browser, such as marskal.example.")
        case .unreachable:
            String(localized: "Check the address and your connection. Your changes are kept and sent later.")
        case .signInFailed(let code):
            String(localized: "The server answered “\(code)”. Try signing in again.")
        case .signedOut:
            String(localized: "This device was signed out on the server. Sign in again to keep syncing.")
        case .otherAccount:
            String(localized: "Sign out to remove it from this device, then sign in again.")
        case .database:
            String(localized: "Try closing and opening the app again.")
        case .server(let status):
            String(localized: "The server answered with status \(status). Your changes are kept and sent later.")
        case .invalid(let reason):
            // The engine's reason, in English, as the server would give it.
            reason
        }
    }
}
