import Foundation

/// Where a task can go, as the web's location picker lists them (ADR 0017,
/// ADR 0033): the Inbox, No project, and every open project in sidebar
/// order, each with the folders it is in. A project the sidebar hides, for
/// being deferred or in a dropped folder, is marked hidden; the task's own
/// project is kept even when it is resolved.
public struct Locations: Sendable {
    public struct Target: Sendable, Identifiable {
        public let location: Location
        /// The folders and the project's title, or the view's name alone.
        public let path: [String]
        public let hidden: Bool
        public var id: Location { location }
    }

    public let targets: [Target]

    /// `inbox` and `noProject` are the views' names, in the user's language.
    public init(
        folders: [FolderItem], projects: [ProjectItem], inbox: String, noProject: String,
        current: Location? = nil, now: Date = .now
    ) {
        let kept: UUID? = if case .project(let id)? = current { id } else { nil }

        var children: [UUID?: [(rank: String?, id: UUID, item: Either)]] = [:]
        for folder in folders {
            children[folder.parentId, default: []].append((folder.rank, folder.id, .folder(folder)))
        }
        for project in projects {
            children[project.folderId, default: []].append((project.rank, project.id, .project(project)))
        }
        children = children.mapValues { $0.sorted { rankPrecedes($0.rank, $0.id, $1.rank, $1.id) } }

        var targets = [
            Target(location: .inbox, path: [inbox], hidden: false),
            Target(location: .noProject, path: [noProject], hidden: false),
        ]
        var seen: Set<UUID> = []
        func walk(_ parent: UUID?, _ ancestors: [String], _ dropped: Bool) {
            for child in children[parent] ?? [] where seen.insert(child.id).inserted {
                switch child.item {
                case .folder(let folder):
                    walk(folder.id, ancestors + [folder.name], dropped || !folder.active)
                case .project(let project):
                    guard project.state == .toDo || project.id == kept else { continue }
                    let shown = !dropped && project.state == .toDo && !project.dates.isDeferred(at: now)
                    targets.append(
                        Target(location: .project(id: project.id), path: ancestors + [project.title], hidden: !shown))
                }
            }
        }
        walk(nil, [], false)
        self.targets = targets
    }

    private enum Either {
        case folder(FolderItem)
        case project(ProjectItem)
    }

    /// Every location for a blank query, in sidebar order with hidden ones
    /// last; otherwise those matching it, best first, as the web ranks them.
    public func search(_ query: String, limit: Int = 50) -> [Target] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return targets.filter { !$0.hidden } + targets.filter(\.hidden)
        }
        let searchable = targets.map { target in
            SearchTarget(kind: target.location == .inbox || target.location == .noProject ? .view : .project,
                         path: target.path, hidden: target.hidden)
        }
        // The engine compares text as stored: in NFC.
        let query = query.precomposedStringWithCanonicalMapping
        return searchTargets(targets: searchable, query: query, limit: UInt32(limit)).map { targets[Int($0)] }
    }
}
