import Foundation

/// What the app and the widget share through the App Group (ADR 0029): the
/// database, and the settings that say which server it belongs to.
public enum AppGroup {
    public static let id = "group.app.marskal"

    /// The App Group's settings. The standard ones are the app's alone.
    public static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }

    static let serverKey = "server"

    /// The server the app is signed in to, if any.
    public static var server: URL? {
        get { defaults.url(forKey: serverKey) }
        set { defaults.set(newValue, forKey: serverKey) }
    }

    /// The database of the server the app is signed in to, or `nil` when
    /// signed out. Open it for one read or command and close it after, so
    /// no lock outlives the work (ADR 0029).
    public static func openStore() throws -> Store? {
        guard let server else { return nil }
        return try Database.open(server: server)
    }
}
