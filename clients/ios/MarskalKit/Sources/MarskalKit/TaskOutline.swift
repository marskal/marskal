import Foundation
import MarskalCore

/// Tasks in outline order, as the Inbox and a project list them (ADR 0009):
/// the rows a collapsed task leaves showing, which have subtasks, and which
/// can be indented or outdented.
public struct TaskOutline: Sendable {
    public struct Row: Sendable, Identifiable {
        public let task: TaskItem
        public let hasSubtasks: Bool
        public let collapsed: Bool
        /// A sibling is listed above it, for it to go under.
        public let canIndent: Bool
        /// Some row in the list has subtasks, so every row keeps room for
        /// the button that hides them, and siblings line up.
        public let besideSubtasks: Bool
        /// It is a subtask, to move out of its parent.
        public var canOutdent: Bool { task.parentId != nil }
        public var id: UUID { task.id }
    }

    public let rows: [Row]

    /// `tasks` in outline order, each subtask right after its parent's
    /// earlier subtasks. `collapsed` may name tasks not in the list.
    public init(tasks: [TaskItem], collapsed: Set<UUID>) {
        var rows: [Row] = []
        let besideSubtasks = tasks.contains { $0.parentId != nil }
        // Parents with a subtask listed so far; nil is the top level.
        var parents: Set<UUID?> = []
        // Rows deeper than this are under a collapsed task.
        var hidingBelow: UInt32?

        for (i, task) in tasks.enumerated() {
            let canIndent = !parents.insert(task.parentId).inserted
            if let depth = hidingBelow {
                if task.depth > depth { continue }
                hidingBelow = nil
            }

            let next = tasks.index(after: i)
            let hasSubtasks = next < tasks.endIndex && tasks[next].parentId == task.id
            let isCollapsed = hasSubtasks && collapsed.contains(task.id)
            if isCollapsed { hidingBelow = task.depth }

            rows.append(
                Row(
                    task: task, hasSubtasks: hasSubtasks, collapsed: isCollapsed, canIndent: canIndent,
                    besideSubtasks: besideSubtasks))
        }

        self.rows = rows
    }
}
