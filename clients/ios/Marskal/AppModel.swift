import Foundation
import MarskalKit
import Observation
import UIKit

/// The app's state: which server it is signed in to, the local database
/// while the app is in the foreground, and what the lists show.
@Observable @MainActor
final class AppModel {
    private(set) var session: Session?
    private(set) var inbox: [TaskItem] = []
    private(set) var open: [TaskItem] = []
    private(set) var preferences: Preferences?
    private(set) var lastSyncedAt: Date?
    private(set) var pending: UInt64 = 0
    private(set) var syncing = false
    private(set) var signingIn = false
    var problem: Problem?

    private var store: Store?
    private var syncTask: Task<Void, Never>?
    private let tokens: TokenStore
    private let defaults: UserDefaults

    static let serverKey = "server"
    static let refreshTask = "app.marskal.ios.sync"

    init(tokens: TokenStore = KeychainTokenStore(), defaults: UserDefaults = .standard) {
        self.tokens = tokens
        self.defaults = defaults
        if let saved = defaults.url(forKey: Self.serverKey) {
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
            defaults.set(server, forKey: Self.serverKey)
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
        syncTask?.cancel()
        await syncTask?.value
        store?.close()
        store = nil
        await session.signOut()
        Database.remove(server: session.server)
        defaults.removeObject(forKey: Self.serverKey)
        self.session = nil
        inbox = []
        open = []
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

    /// Starts a sync, or joins the one under way.
    func sync() {
        guard syncTask == nil, let session, let store else { return }
        syncing = true
        syncTask = Task {
            defer {
                syncing = false
                syncTask = nil
            }
            do {
                _ = try await session.sync(store)
            } catch let error as ServerError {
                if error == .notSignedIn {
                    signedOutOnServer()
                    problem = .signedOut
                } else {
                    problem = Problem(error)
                }
            } catch StoreError.OtherAccount {
                problem = .otherAccount
            } catch StoreError.Closed {
                // The app went to the background.
            } catch {
                problem = .database
            }
            reload()
        }
    }

    /// Waits for a sync to finish, for pull to refresh.
    func refresh() async {
        sync()
        await syncTask?.value
    }

    /// Reads the lists again, if anything changed since the last read.
    func reload() {
        guard let store else { return }
        do {
            inbox = try store.tasks(filter: .inbox)
            open = try store.tasks(filter: .open(unavailable: false))
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
        }
    }
}
