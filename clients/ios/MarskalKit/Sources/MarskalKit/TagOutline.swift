import Foundation

/// Tags as the web app's sidebar and tag pages show them (ADR 0005): each
/// tag's children in rank order. A dropped tag hides the tags inside it;
/// On Hold applies to that tag only.
public struct TagOutline: Sendable {
    /// One section of a tag's page: the tasks carrying `tag` itself.
    /// `path` runs from just below the page's tag down to `tag`, empty for
    /// the page's own tag.
    public struct Group: Sendable, Identifiable {
        public let tag: TagItem
        public let path: [String]
        public let tasks: [TaskItem]
        public var id: UUID { tag.id }
    }

    private let tags: [UUID: TagItem]
    private let children: [UUID?: [TagItem]]

    public init(tags: [TagItem]) {
        let byId = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        var children: [UUID?: [TagItem]] = [:]
        // A tag whose parent is gone is not hoisted to the top.
        for tag in tags where tag.parentId == nil || byId[tag.parentId!] != nil {
            children[tag.parentId, default: []].append(tag)
        }
        self.tags = byId
        self.children = children.mapValues {
            $0.sorted { rankPrecedes($0.rank, $0.id, $1.rank, $1.id) }
        }
    }

    public func tag(_ id: UUID) -> TagItem? { tags[id] }

    /// Dropped by itself or by a tag above it.
    public func isDropped(_ id: UUID) -> Bool {
        var current = tags[id]
        while let tag = current {
            if tag.state == .dropped { return true }
            current = tag.parentId.flatMap { tags[$0] }
        }
        return false
    }

    /// The tags inside a tag, or the top-level tags for `nil`, in order.
    /// Dropped ones are left out, unless the tag is dropped itself: its
    /// page shows what is inside it.
    public func children(of parent: UUID?) -> [TagItem] {
        let all = children[parent] ?? []
        if let parent, isDropped(parent) { return all }
        return all.filter { $0.state != .dropped }
    }

    /// A tag's page: its own tasks first, always, then a group for each tag
    /// inside it that tasks carry, depth first. `tasks` are those carrying
    /// the tag or one inside it, in the order to show them; a task with two
    /// of these tags shows in both groups. Deferred tasks are left out.
    public func groups(for id: UUID, tasks: [TaskItem]) -> [Group] {
        guard let root = tags[id] else { return [] }
        let shown = tasks.filter { !$0.deferred }
        var groups: [Group] = []

        func walk(_ tag: TagItem, _ path: [String]) {
            let carrying = shown.filter { task in task.tags.contains { $0.id == tag.id } }
            if tag.id == root.id || !carrying.isEmpty {
                groups.append(Group(tag: tag, path: path, tasks: carrying))
            }
            for child in children(of: tag.id) {
                walk(child, path + [child.name])
            }
        }

        walk(root, [])
        return groups
    }

    /// To-do tasks with no tags of their own or from their project, the
    /// Inbox's included, newest first; deferred ones left out.
    public static func untagged(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks
            .filter { $0.tags.isEmpty && !$0.deferred && !$0.resolved }
            .sorted { ($0.insertedAt ?? .distantPast, $0.id.uuidString) > ($1.insertedAt ?? .distantPast, $1.id.uuidString) }
    }
}

extension TagItem: Identifiable {}
