import Foundation

/// Folders and projects as the web app's sidebar shows them (ADR 0009):
/// a folder's subfolders and projects are one list by rank. Active folders
/// and To-Do projects that are not deferred; a project in a folder that is
/// left out is not hoisted to the top.
public struct ProjectOutline: Sendable {
    public enum Item: Sendable, Hashable, Identifiable {
        case folder(FolderItem)
        case project(ProjectItem)

        public var id: UUID {
            switch self {
            case .folder(let folder): folder.id
            case .project(let project): project.id
            }
        }

        fileprivate var rank: String? {
            switch self {
            case .folder(let folder): folder.rank
            case .project(let project): project.rank
            }
        }
    }

    private let children: [UUID?: [Item]]
    private let folders: [UUID: FolderItem]

    public init(folders: [FolderItem], projects: [ProjectItem], now: Date = .now) {
        let active = folders.filter(\.active)
        let shown = projects.filter { $0.state == .toDo && !$0.dates.isDeferred(at: now) }

        var children: [UUID?: [Item]] = [:]
        for folder in active { children[folder.parentId, default: []].append(.folder(folder)) }
        for project in shown { children[project.folderId, default: []].append(.project(project)) }
        self.children = children.mapValues { $0.sorted(by: Self.ranked) }
        self.folders = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
    }

    /// The folders and projects in a folder, or at the top for `nil`, in
    /// order. Empty for a folder that is not shown.
    public func children(of folder: UUID?) -> [Item] {
        if let folder, folders[folder] == nil { return [] }
        return children[folder] ?? []
    }

    public func folder(_ id: UUID) -> FolderItem? { folders[id] }

    public var isEmpty: Bool { children(of: nil).isEmpty }

    private static func ranked(_ a: Item, _ b: Item) -> Bool {
        rankPrecedes(a.rank, a.id, b.rank, b.id)
    }
}

/// Sibling order (ADR 0009, 0005): byte by byte, as the server compares
/// ranks; one the server has not given yet goes last. Ties by id.
func rankPrecedes(_ a: String?, _ aId: UUID, _ b: String?, _ bId: UUID) -> Bool {
    switch (a, b) {
    case let (x?, y?) where x != y: x.utf8.lexicographicallyPrecedes(y.utf8)
    case (_?, nil): true
    case (nil, _?): false
    default: aId.uuidString < bId.uuidString
    }
}

extension Dates {
    /// Deferred until a later time, or with no end (ADR 0006).
    public func isDeferred(at now: Date = .now) -> Bool {
        if deferredIndefinitely { return true }
        if let deferUntil { return deferUntil > now }
        return false
    }
}

extension FolderItem: Identifiable {}
extension ProjectItem: Identifiable {}
