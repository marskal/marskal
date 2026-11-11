import MarskalKit
import SwiftUI

/// Folders and projects, as the web app's sidebar has them (ADR 0009). A
/// folder opens its subfolders and projects; a project opens its tasks.
struct ProjectsView: View {
    static let folderSymbol = "folder"
    static let projectSymbol = "list.bullet.rectangle"
    static let inboxSymbol = "tray"
    static let noProjectSymbol = "circle.dashed"

    var body: some View {
        NavigationStack {
            FolderView(folderId: nil)
                .navigationDestination(for: ProjectRoute.self) { route in
                    switch route {
                    case .folder(let id): FolderView(folderId: id)
                    case .tasks(let location): LocationView(location: location)
                    }
                }
                .taskDestination()
        }
    }
}

enum ProjectRoute: Hashable {
    case folder(UUID)
    /// The Inbox, No project, or a project.
    case tasks(Location)
}

/// A folder's subfolders and projects in their order, or the top of the
/// outline for `nil`, below the Inbox and No project (ADR 0017).
private struct FolderView: View {
    let folderId: UUID?
    @Environment(AppModel.self) private var model

    var body: some View {
        let items = model.outline.children(of: folderId)
        List {
            if folderId == nil {
                Section {
                    NavigationLink(value: ProjectRoute.tasks(.inbox)) {
                        Label("Inbox", systemImage: ProjectsView.inboxSymbol)
                    }
                    NavigationLink(value: ProjectRoute.tasks(.noProject)) {
                        Label("No Project", systemImage: ProjectsView.noProjectSymbol)
                    }
                }
            }
            Section {
                ForEach(items) { item in
                    switch item {
                    case .folder(let folder):
                        NavigationLink(value: ProjectRoute.folder(folder.id)) {
                            // A folder's name is the user's own text, not translated.
                            Label(folder.name, systemImage: ProjectsView.folderSymbol)
                        }
                    case .project(let project):
                        NavigationLink(value: ProjectRoute.tasks(.project(id: project.id))) {
                            ProjectRow(project: project)
                        }
                    }
                }
            } footer: {
                SyncStatus()
            }
        }
        .animation(.default, value: items.map(\.id))
        .overlay {
            // At the top, the Inbox and No project are always there.
            if folderId != nil && items.isEmpty && !model.syncing {
                ContentUnavailableView("Nothing in this folder", systemImage: ProjectsView.folderSymbol)
            }
        }
        .refreshable { await model.refresh() }
        .navigationTitle(title)
        .showDeferredToggle()
    }

    private var title: Text {
        if let folderId {
            Text(verbatim: model.outline.folder(folderId)?.name ?? "")
        } else {
            Text("Projects")
        }
    }
}

private struct ProjectRow: View {
    let project: ProjectItem

    var body: some View {
        HStack {
            Label(project.title, systemImage: ProjectsView.projectSymbol)
            Spacer(minLength: 0)
            if project.flagged {
                Image(systemName: "flag.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(Text("Flagged"))
            }
        }
    }
}

/// The open tasks in the Inbox, in No project, or in a project, as an
/// outline. Check a task off with its circle or a swipe; add one here, or
/// under a task from its menu.
private struct LocationView: View {
    let location: Location
    @Environment(AppModel.self) private var model
    @State private var moving: TaskItem?
    @State private var capturing = false
    @State private var addingSubtask: TaskItem?

    var body: some View {
        let tasks = model.tasks(at: location)
        List {
            Section {
                ForEach(tasks) { task in
                    NavigationLink(value: TaskRoute(id: task.id)) {
                        TaskRow(task: task, showsProject: false) { model.setState(task, .done) }
                    }
                    .taskActions(task, moving: $moving, addingSubtask: $addingSubtask)
                }
            } footer: {
                SyncStatus()
            }
        }
        .animation(.default, value: tasks.map(\.id))
        .overlay {
            if deleted {
                ContentUnavailableView("This project was deleted", systemImage: ProjectsView.projectSymbol)
            } else if tasks.isEmpty && !model.syncing {
                if model.hidesDeferred(at: location) {
                    DeferredHidden()
                } else {
                    empty
                }
            }
        }
        .refreshable { await model.refresh() }
        .navigationTitle(title)
        .showDeferredToggle()
        .toolbar {
            if !deleted {
                ToolbarItem(placement: .primaryAction) {
                    Button(addLabel, systemImage: "plus") { capturing = true }
                }
            }
        }
        .sheet(item: $moving) { task in
            MoveSheet(task: task)
        }
        .sheet(isPresented: $capturing) {
            CaptureSheet(place: location)
        }
        .sheet(item: $addingSubtask) { task in
            CaptureSheet(under: task)
        }
    }

    private var addLabel: LocalizedStringKey {
        location == .inbox ? "Add to Inbox" : "Add Task"
    }

    private var deleted: Bool {
        if case .project(let id) = location { return model.projectsById[id] == nil }
        return false
    }

    private var title: Text {
        switch location {
        case .inbox: Text("Inbox")
        case .noProject: Text("No Project")
        // A project's title is the user's own text, not translated.
        case .project(let id): Text(verbatim: model.projectsById[id]?.title ?? "")
        }
    }

    @ViewBuilder
    private var empty: some View {
        switch location {
        case .inbox:
            ContentUnavailableView("The Inbox is empty", systemImage: ProjectsView.inboxSymbol)
        case .noProject:
            ContentUnavailableView(
                "No tasks outside projects",
                systemImage: ProjectsView.noProjectSymbol,
                description: Text("Tasks you move out of the Inbox without a project show up here."))
        case .project:
            ContentUnavailableView("No open tasks", systemImage: "checkmark.circle")
        }
    }
}
