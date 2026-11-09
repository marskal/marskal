import Foundation
import MarskalKit
import Testing

// The web's location picker: Marskal.GoTo.projects/1 and the inspector's
// locations, ranked by the engine's path_search::rank.
struct LocationsTests {
    let now = Date(timeIntervalSince1970: 1_793_000_000)
    let none = Dates(deferUntil: nil, deferredIndefinitely: false, plannedAt: nil, dueAt: nil)

    func folder(_ name: String, rank: String?, in parent: UUID? = nil, active: Bool = true) -> FolderItem {
        FolderItem(id: UUID(), name: name, parentId: parent, rank: rank, active: active)
    }

    func project(
        _ title: String, rank: String?, in folder: UUID? = nil, state: TaskState = .toDo, dates: Dates? = nil
    ) -> ProjectItem {
        ProjectItem(
            id: UUID(), title: title, notes: nil, url: nil, flagged: false, state: state,
            folderId: folder, rank: rank, dates: dates ?? none, seriesId: nil, insertedAt: nil)
    }

    func locations(_ folders: [FolderItem], _ projects: [ProjectItem], current: Location? = nil) -> Locations {
        Locations(folders: folders, projects: projects, inbox: "Inbox", noProject: "No project", current: current, now: now)
    }

    func paths(_ targets: [Locations.Target]) -> [String] {
        targets.map { $0.path.joined(separator: " › ") }
    }

    @Test func viewsThenProjectsInSidebarOrderWithTheirFolders() {
        let work = folder("Work", rank: "V")
        let clients = folder("Clients", rank: "a", in: work.id)
        let all = locations(
            [work, clients],
            [
                project("Errands", rank: "B"),
                project("Website", rank: "V", in: work.id),
                project("Acme", rank: "V", in: clients.id),
            ])

        #expect(paths(all.targets) == ["Inbox", "No project", "Errands", "Work › Website", "Work › Clients › Acme"])
        #expect(all.targets.allSatisfy { !$0.hidden })
    }

    @Test func deferredAndDroppedFolderProjectsAreHiddenAndLast() {
        let old = folder("Old", rank: "B", active: false)
        let later = Dates(deferUntil: now.addingTimeInterval(86_400), deferredIndefinitely: false, plannedAt: nil, dueAt: nil)
        let all = locations(
            [old],
            [
                project("Website", rank: "A", in: old.id),
                project("Someday", rank: "C", dates: later),
                project("Home", rank: "D"),
            ])

        #expect(all.targets.filter(\.hidden).map(\.path.last) == ["Website", "Someday"])
        #expect(paths(all.search("")) == ["Inbox", "No project", "Home", "Old › Website", "Someday"])
    }

    @Test func resolvedProjectsAreLeftOutButTheCurrentOne() {
        let done = project("Done", rank: "A", state: .done)
        let dropped = project("Dropped", rank: "B", state: .dropped)

        #expect(paths(locations([], [done, dropped]).targets) == ["Inbox", "No project"])
        let kept = locations([], [done, dropped], current: .project(id: done.id))
        #expect(paths(kept.targets) == ["Inbox", "No project", "Done"])
        #expect(kept.targets.last?.hidden == true)
    }

    @Test func typingMatchesNamesAndFolderPaths() {
        let work = folder("Work", rank: "V")
        let old = folder("Old", rank: "a", active: false)
        let all = locations(
            [work, old],
            [
                project("Website", rank: "V", in: old.id),
                project("Website", rank: "V", in: work.id),
                project("Inbox zero", rank: "B"),
            ])

        #expect(paths(all.search("web")) == ["Work › Website", "Old › Website"])
        #expect(paths(all.search("old/web")) == ["Old › Website"])
        #expect(paths(all.search("in")) == ["Inbox", "Inbox zero"])
        #expect(paths(all.search("nothing")) == [])
    }
}
