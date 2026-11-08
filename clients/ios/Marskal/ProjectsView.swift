import MarskalKit
import SwiftUI

/// Folders and projects, as the web app's sidebar has them (ADR 0009). A
/// folder opens its subfolders and projects; a project opens its tasks.
struct ProjectsView: View {
    static let folderSymbol = "folder"
    static let projectSymbol = "list.bullet.rectangle"

    var body: some View {
        NavigationStack {
            FolderView(folderId: nil)
                .navigationDestination(for: ProjectRoute.self) { route in
                    switch route {
                    case .folder(let id): FolderView(folderId: id)
                    case .project(let id): ProjectView(projectId: id)
                    }
                }
        }
    }
}

enum ProjectRoute: Hashable {
    case folder(UUID)
    case project(UUID)
}

/// A folder's subfolders and projects in their order, or the top of the
/// outline for `nil`.
private struct FolderView: View {
    let folderId: UUID?
    @Environment(AppModel.self) private var model

    var body: some View {
        let items = model.outline.children(of: folderId)
        List {
            Section {
                ForEach(items) { item in
                    switch item {
                    case .folder(let folder):
                        NavigationLink(value: ProjectRoute.folder(folder.id)) {
                            // A folder's name is the user's own text, not translated.
                            Label(folder.name, systemImage: ProjectsView.folderSymbol)
                        }
                    case .project(let project):
                        NavigationLink(value: ProjectRoute.project(project.id)) {
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
            if items.isEmpty && !model.syncing {
                if folderId == nil {
                    ContentUnavailableView(
                        "No projects",
                        systemImage: ProjectsView.folderSymbol,
                        description: Text("Projects you haven’t finished show up here."))
                } else {
                    ContentUnavailableView("Nothing in this folder", systemImage: ProjectsView.folderSymbol)
                }
            }
        }
        .refreshable { await model.refresh() }
        .navigationTitle(title)
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

/// A project's open tasks as an outline. Check a task off with its circle
/// or a swipe.
private struct ProjectView: View {
    let projectId: UUID
    @Environment(AppModel.self) private var model
    @State private var moving: TaskItem?

    var body: some View {
        let project = model.projectsById[projectId]
        let tasks = model.tasks(inProject: projectId)
        List {
            Section {
                ForEach(tasks) { task in
                    TaskRow(task: task, showsProject: false) { model.setState(task, .done) }
                        .taskActions(task, moving: $moving)
                }
            } footer: {
                SyncStatus()
            }
        }
        .animation(.default, value: tasks.map(\.id))
        .overlay {
            if project == nil {
                ContentUnavailableView("This project was deleted", systemImage: ProjectsView.projectSymbol)
            } else if tasks.isEmpty && !model.syncing {
                ContentUnavailableView("No open tasks", systemImage: "checkmark.circle")
            }
        }
        .refreshable { await model.refresh() }
        // A project's title is the user's own text, not translated.
        .navigationTitle(Text(verbatim: project?.title ?? ""))
        .sheet(item: $moving) { task in
            MoveSheet(task: task)
        }
    }
}
