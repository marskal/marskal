import Foundation
@_exported import MarskalCore

/// Where the local database lives: one SQLite file per server, in the App
/// Group the app and the widget share (ADR 0029).
public enum Database {
    public static let appGroup = "group.app.marskal"

    public static func url(server: URL) -> URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? URL.applicationSupportDirectory
        let directory = base.appending(path: "Library/Application Support/Marskal", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "\(slug(server)).sqlite")
    }

    public static func open(server: URL) throws -> Store {
        try Store.open(path: url(server: server).path(percentEncoded: false))
    }

    /// Deletes the database and its WAL files, as after signing out.
    public static func remove(server: URL) {
        let path = url(server: server).path(percentEncoded: false)
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
    }

    /// `http://marskal.localhost:8275` becomes `marskal.localhost-8275`.
    static func slug(_ server: URL) -> String {
        var name = server.host() ?? "server"
        if let port = server.port { name += "-\(port)" }
        if !server.path().isEmpty, server.path() != "/" { name += server.path() }
        return String(name.lowercased().map { $0.isLetter || $0.isNumber || $0 == "." ? $0 : "-" })
    }
}
