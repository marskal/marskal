import Foundation
import MarskalKit
import Testing

// The sidebar's rules (ADR 0009), as the web app's Marskal.ProjectNav has them.
struct ProjectOutlineTests {
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

    func names(_ items: [ProjectOutline.Item]) -> [String] {
        items.map {
            switch $0 {
            case .folder(let folder): folder.name
            case .project(let project): project.title
            }
        }
    }

    @Test func foldersAndProjectsAreOneListByRank() {
        let home = folder("Home", rank: "V")
        let outline = ProjectOutline(
            folders: [home, folder("Work", rank: "a")],
            projects: [
                project("Garden", rank: "B"),
                project("Taxes", rank: "b"),
                project("Paint", rank: nil),
                project("Kitchen", rank: "V", in: home.id),
            ],
            now: now)

        // Byte order: uppercase before lowercase. No rank yet goes last.
        #expect(names(outline.children(of: nil)) == ["Garden", "Home", "Work", "Taxes", "Paint"])
        #expect(names(outline.children(of: home.id)) == ["Kitchen"])
    }

    @Test func resolvedAndDeferredProjectsAreLeftOut() {
        let later = Dates(deferUntil: now.addingTimeInterval(60), deferredIndefinitely: false, plannedAt: nil, dueAt: nil)
        let past = Dates(deferUntil: now.addingTimeInterval(-60), deferredIndefinitely: false, plannedAt: nil, dueAt: nil)
        let paused = Dates(deferUntil: nil, deferredIndefinitely: true, plannedAt: nil, dueAt: nil)
        let outline = ProjectOutline(
            folders: [],
            projects: [
                project("Open", rank: "A"),
                project("Done", rank: "B", state: .done),
                project("Dropped", rank: "C", state: .dropped),
                project("Later", rank: "D", dates: later),
                project("Paused", rank: "E", dates: paused),
                project("Back", rank: "F", dates: past),
            ],
            now: now)

        #expect(names(outline.children(of: nil)) == ["Open", "Back"])
    }

    @Test func aDroppedFolderHidesWhatIsInIt() {
        let old = folder("Old", rank: "A", active: false)
        let inner = folder("Inner", rank: "A", in: old.id)
        let outline = ProjectOutline(
            folders: [old, inner],
            projects: [project("Archive", rank: "B", in: old.id), project("Deep", rank: "A", in: inner.id)],
            now: now)

        #expect(outline.isEmpty)
        #expect(outline.children(of: old.id).isEmpty)
        #expect(outline.folder(old.id) == nil)
    }
}
