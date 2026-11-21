import Foundation
import MarskalKit
import Testing

struct TaskOutlineTests {
    let none = Dates(deferUntil: nil, deferredIndefinitely: false, plannedAt: nil, dueAt: nil)

    func task(_ title: String, under parent: TaskItem? = nil) -> TaskItem {
        TaskItem(
            id: UUID(), title: title, notes: nil, url: nil, state: .toDo, inbox: false, projectId: nil,
            project: nil, parentId: parent?.id, depth: parent.map { $0.depth + 1 } ?? 0, ownFlagged: false,
            flagged: false, dates: none, effective: none, tags: [], deferred: false, overdue: false,
            available: true, resolved: false, seriesId: nil, resolvedAt: nil, insertedAt: nil)
    }

    @Test func aRowKnowsItsSubtasksAndWhereItCanGo() {
        let pack = task("Pack")
        let socks = task("Socks", under: pack)
        let shirts = task("Shirts", under: pack)
        let leave = task("Leave")
        let outline = TaskOutline(tasks: [pack, socks, shirts, leave], collapsed: [])

        #expect(outline.rows.map(\.task.title) == ["Pack", "Socks", "Shirts", "Leave"])
        #expect(outline.rows.map(\.hasSubtasks) == [true, false, false, false])
        // The first of its siblings has nothing above it to go under.
        #expect(outline.rows.map(\.canIndent) == [false, false, true, true])
        #expect(outline.rows.map(\.canOutdent) == [false, true, true, false])
        #expect(outline.rows.map(\.besideSubtasks) == [true, true, true, true])
        let flat = TaskOutline(tasks: [pack, leave], collapsed: [])
        #expect(flat.rows.map(\.besideSubtasks) == [false, false])
    }

    @Test func aCollapsedTaskHidesItsSubtree() {
        let pack = task("Pack")
        let socks = task("Socks", under: pack)
        let wool = task("Wool", under: socks)
        let shirts = task("Shirts", under: pack)
        let leave = task("Leave")
        let tasks = [pack, socks, wool, shirts, leave]

        let outline = TaskOutline(tasks: tasks, collapsed: [socks.id])
        #expect(outline.rows.map(\.task.title) == ["Pack", "Socks", "Shirts", "Leave"])
        #expect(outline.rows.map(\.collapsed) == [false, true, false, false])

        let top = TaskOutline(tasks: tasks, collapsed: [pack.id, socks.id])
        #expect(top.rows.map(\.task.title) == ["Pack", "Leave"])
        // Leave has Pack above it still.
        #expect(top.rows.last?.canIndent == true)
    }

    @Test func aTaskWithoutSubtasksDoesNotCollapse() {
        let pack = task("Pack")
        let outline = TaskOutline(tasks: [pack], collapsed: [pack.id])
        #expect(outline.rows.map(\.collapsed) == [false])
    }
}
