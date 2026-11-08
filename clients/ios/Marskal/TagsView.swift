import MarskalKit
import SwiftUI

/// Tags, as the web app's sidebar has them (ADR 0005), and Untagged. A tag
/// opens its page: its tasks, grouped by the tags inside it.
struct TagsView: View {
    static let tagSymbol = "tag"
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            let tags = model.tagOutline.children(of: nil)
            List {
                Section {
                    NavigationLink(value: TagRoute.untagged) {
                        Label("Untagged", systemImage: "tag.slash")
                    }
                }
                Section {
                    ForEach(tags) { TagLink(tag: $0) }
                }
            }
            .refreshable { await model.refresh() }
            .navigationTitle("Tags")
            .toolbar {
                ToolbarItem(placement: .status) {
                    SyncStatus()
                }
            }
            .navigationDestination(for: TagRoute.self) { route in
                switch route {
                case .tag(let id): TagView(tagId: id)
                case .untagged: UntaggedView()
                }
            }
            .taskDestination()
        }
    }
}

enum TagRoute: Hashable {
    case tag(UUID)
    case untagged
}

private struct TagLink: View {
    let tag: TagItem

    var body: some View {
        NavigationLink(value: TagRoute.tag(tag.id)) {
            HStack {
                // A tag's name is the user's own text, not translated.
                Label(tag.name, systemImage: TagsView.tagSymbol)
                Spacer(minLength: 0)
                if tag.state == .onHold {
                    Text("On Hold")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A tag's page: the tasks carrying it, then a section for each tag inside
/// it that tasks carry, then the tags inside it to open.
private struct TagView: View {
    let tagId: UUID
    @Environment(AppModel.self) private var model
    @State private var moving: TaskItem?

    var body: some View {
        let outline = model.tagOutline
        let tag = outline.tag(tagId)
        let groups = outline.groups(for: tagId, tasks: model.tasks(withTag: tagId))
        let inside = outline.children(of: tagId)
        let empty = groups.allSatisfy(\.tasks.isEmpty)

        List {
            if let note = note(tag) {
                Section {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(groups) { group in
                if group.path.isEmpty {
                    if !group.tasks.isEmpty {
                        Section { rows(group.tasks) }
                    } else if !empty {
                        Section {
                            Text("No tasks carry this tag itself.")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        rows(group.tasks)
                    } header: {
                        Text(verbatim: group.path.joined(separator: " › "))
                    }
                }
            }
            if !inside.isEmpty {
                Section("Tags Inside") {
                    ForEach(inside) { TagLink(tag: $0) }
                }
            }
        }
        .animation(.default, value: groups.flatMap { $0.tasks.map(\.id) })
        .overlay {
            if tag == nil {
                ContentUnavailableView("This tag was deleted", systemImage: TagsView.tagSymbol)
            } else if empty && inside.isEmpty && !model.syncing {
                ContentUnavailableView("No open tasks", systemImage: "checkmark.circle")
            }
        }
        .refreshable { await model.refresh() }
        .navigationTitle(Text(verbatim: tag?.name ?? ""))
        .showDeferredToggle()
        .toolbar {
            ToolbarItem(placement: .status) {
                SyncStatus()
            }
        }
        .sheet(item: $moving) { task in
            MoveSheet(task: task)
        }
    }

    private func rows(_ tasks: [TaskItem]) -> some View {
        ForEach(tasks) { task in
            NavigationLink(value: TaskRoute(id: task.id)) {
                TaskRow(task: task, indented: false) { model.setState(task, .done) }
            }
            .taskActions(task, moving: $moving)
        }
    }

    private func note(_ tag: TagItem?) -> LocalizedStringKey? {
        guard let tag else { return nil }
        if tag.state == .onHold { return "On hold. Tasks with this tag are unavailable." }
        if tag.state == .dropped { return "Dropped. This tag and the tags inside it are hidden from lists." }
        if model.tagOutline.isDropped(tag.id) { return "Inside a dropped tag, so it is hidden from lists." }
        return nil
    }
}

/// To-do tasks with no tags of their own or from their project.
private struct UntaggedView: View {
    @Environment(AppModel.self) private var model
    @State private var moving: TaskItem?

    var body: some View {
        let tasks = model.untagged
        List(tasks) { task in
            NavigationLink(value: TaskRoute(id: task.id)) {
                TaskRow(task: task, indented: false) { model.setState(task, .done) }
            }
            .taskActions(task, moving: $moving)
        }
        .animation(.default, value: tasks.map(\.id))
        .overlay {
            if tasks.isEmpty && !model.syncing {
                ContentUnavailableView(
                    "No untagged tasks",
                    systemImage: "tag.slash",
                    description: Text("To-do tasks with no tags of their own or from their project show up here."))
            }
        }
        .refreshable { await model.refresh() }
        .navigationTitle("Untagged")
        .showDeferredToggle()
        .toolbar {
            ToolbarItem(placement: .status) {
                SyncStatus()
            }
        }
        .sheet(item: $moving) { task in
            MoveSheet(task: task)
        }
    }
}
