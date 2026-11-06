import Foundation
import MarskalKit
import Testing

// The sidebar's and the tag page's rules (ADR 0005), as the web app's
// Marskal.Tags has them. Which tasks a tag matches is tested in Rust.
struct TagOutlineTests {
    let path = FileManager.default.temporaryDirectory
        .appending(path: "marskal-\(UUID().uuidString).sqlite").path()

    func tag(_ name: String, rank: String?, in parent: UUID? = nil, state: TagState = .active) -> TagItem {
        TagItem(id: UUID(), name: name, parentId: parent, path: [name], state: state, rank: rank)
    }

    @Test func childrenGoByRankAndLeaveOutDroppedOnes() {
        let work = tag("Work", rank: "b")
        let old = tag("Old", rank: "A", state: .dropped)
        let inOld = tag("Inside old", rank: "A", in: old.id)
        let outline = TagOutline(tags: [
            work, old, inOld,
            tag("Home", rank: "a"),
            tag("Later", rank: "B", state: .onHold),
            tag("New", rank: nil),
            tag("Client", rank: "V", in: work.id),
        ])

        #expect(outline.children(of: nil).map(\.name) == ["Later", "Home", "Work", "New"])
        #expect(outline.children(of: work.id).map(\.name) == ["Client"])
        // A dropped tag's page still lists what is inside it.
        #expect(outline.children(of: old.id).map(\.name) == ["Inside old"])
        #expect(outline.isDropped(inOld.id))
        #expect(!outline.isDropped(work.id))
    }

    @Test func aTagsPageIsItsOwnTasksThenAGroupPerTagInside() throws {
        let store = try Store.open(path: path)
        defer { store.close() }

        let work = try store.addTag(name: "Work", parentId: nil)
        let client = try store.addTag(name: "Client", parentId: work)
        let call = try store.addTag(name: "Calls", parentId: client)
        let empty = try store.addTag(name: "Empty", parentId: work)
        let gone = try store.addTag(name: "Gone", parentId: work)

        let invoice = try store.addTask(new: NewTask(title: "Invoice"))
        try store.tagTask(taskId: invoice, tagId: call)
        let report = try store.addTask(new: NewTask(title: "Report"))
        try store.tagTask(taskId: report, tagId: client)
        try store.tagTask(taskId: report, tagId: call)
        let old = try store.addTask(new: NewTask(title: "Old"))
        try store.tagTask(taskId: old, tagId: gone)
        let later = try store.addTask(new: NewTask(title: "Later", deferred: .indefinitely))
        try store.tagTask(taskId: later, tagId: client)

        var tags = try store.tags()
        tags = tags.map { $0.id == gone ? TagItem(id: $0.id, name: $0.name, parentId: $0.parentId, path: $0.path, state: .dropped, rank: $0.rank) : $0 }
        let outline = TagOutline(tags: tags)
        let groups = outline.groups(for: work, tasks: try store.tasks(filter: .tag(id: work)))

        #expect(groups.map(\.path) == [[], ["Client"], ["Client", "Calls"]])
        #expect(groups[0].tasks.isEmpty)
        #expect(groups[1].tasks.map(\.title) == ["Report"])
        #expect(Set(groups[2].tasks.map(\.title)) == ["Invoice", "Report"])
        #expect(!groups.contains { $0.tag.id == empty })
    }

    @Test func untaggedIsTasksWithNoTagsNewestFirst() throws {
        let store = try Store.open(path: path)
        defer { store.close() }

        let home = try store.addTag(name: "Home", parentId: nil)
        let first = try store.addTask(new: NewTask(title: "First"))
        let tagged = try store.addTask(new: NewTask(title: "Tagged"))
        try store.tagTask(taskId: tagged, tagId: home)
        _ = try store.addTask(new: NewTask(title: "Paused", deferred: .indefinitely))
        let second = try store.addTask(new: NewTask(title: "Second", location: .noProject))

        let tasks = try store.tasks(filter: .inbox) + store.tasks(filter: .open(unavailable: false))
        #expect(TagOutline.untagged(tasks).map(\.id) == [second, first])
    }
}
