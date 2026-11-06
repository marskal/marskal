import MarskalKit
import SwiftUI

/// The Inbox and the open tasks, read from the local database. Capture
/// with the add button; check a task off with its circle or a swipe.
struct TasksView: View {
    @Environment(AppModel.self) private var model
    @State private var capturing = false
    @State private var moving: TaskItem?
    @State private var confirmingSignOut = false

    var body: some View {
        NavigationStack {
            List {
                if !model.inbox.isEmpty {
                    Section("Inbox") {
                        ForEach(model.inbox, id: \.id) { row($0) }
                    }
                }
                if !model.open.isEmpty {
                    Section("Open Tasks") {
                        ForEach(model.open, id: \.id) { row($0) }
                    }
                }
            }
            .animation(.default, value: model.inbox.map(\.id) + model.open.map(\.id))
            .overlay {
                if model.inbox.isEmpty && model.open.isEmpty && !model.syncing {
                    ContentUnavailableView("Nothing to do", systemImage: "checkmark.circle")
                }
            }
            .refreshable { await model.refresh() }
            .navigationTitle(Text(verbatim: "Marskal"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            confirmingSignOut = true
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                }
                ToolbarItem(placement: .status) {
                    SyncStatus()
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Add to Inbox", systemImage: "plus") { capturing = true }
                }
            }
            .sheet(isPresented: $capturing) {
                CaptureSheet()
            }
            .sheet(item: $moving) { task in
                MoveSheet(task: task)
            }
            .confirmationDialog("Sign out?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task { await model.signOut() }
                }
            } message: {
                if model.pending > 0 {
                    Text("\(model.pending) changes on this device have not reached the server, and will be lost.")
                } else {
                    Text("The tasks on this device are removed. They stay on the server.")
                }
            }
        }
    }

    private func row(_ task: TaskItem) -> some View {
        TaskRow(task: task) { model.setState(task, .done) }
            .taskActions(task, moving: $moving)
    }
}

extension TaskItem: @retroactive Identifiable {}

extension View {
    /// Done on a leading swipe; Drop and Move on a trailing one and in the
    /// context menu. Move sets `moving`, for the view to show a MoveSheet.
    func taskActions(_ task: TaskItem, moving: Binding<TaskItem?>) -> some View {
        modifier(TaskActions(task: task, moving: moving))
    }
}

private struct TaskActions: ViewModifier {
    let task: TaskItem
    @Binding var moving: TaskItem?
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading) {
                Button("Done", systemImage: "checkmark") { model.setState(task, .done) }
                    .tint(.green)
            }
            .swipeActions(edge: .trailing) {
                Button("Drop", systemImage: "xmark") { model.setState(task, .dropped) }
                    .tint(.gray)
                Button("Move", systemImage: "folder") { moving = task }
                    .tint(.indigo)
            }
            .contextMenu {
                Button("Done", systemImage: "checkmark") { model.setState(task, .done) }
                Button("Drop", systemImage: "xmark") { model.setState(task, .dropped) }
                Button("Move…", systemImage: "folder") { moving = task }
            }
    }
}

/// A task in a list: a circle that marks it Done, its title, project, and
/// flag, and whatever the list shows after them.
struct TaskRow<Detail: View>: View {
    let task: TaskItem
    /// By its depth in the outline.
    var indented = true
    /// Its project under the title; off where the list is that project.
    var showsProject = true
    let complete: () -> Void
    @ViewBuilder var detail: Detail

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(action: complete) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Mark “\(task.title)” Done"))

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                if showsProject, let project = task.project {
                    Text(project)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if task.flagged {
                Image(systemName: "flag.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(Text("Flagged"))
            }

            detail
        }
        .padding(.leading, indented ? CGFloat(task.depth) * 16 : 0)
    }
}

extension TaskRow where Detail == EmptyView {
    init(task: TaskItem, showsProject: Bool = true, complete: @escaping () -> Void) {
        self.init(task: task, showsProject: showsProject, complete: complete) { EmptyView() }
    }
}

/// Quick capture: return adds the title to the Inbox and clears the
/// field for the next; Add adds it and closes.
private struct CaptureSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var added = 0
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                // One line: return adds the task and keeps the field for
                // the next. The Add button adds and closes.
                TextField("Title", text: $title)
                    .focused($focused)
                    .submitLabel(.next)
                    .onSubmit {
                        add()
                        focused = true
                    }

                if added > 0 {
                    Text("\(added) tasks added to the Inbox")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add to Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", role: .confirm) {
                        add()
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private var trimmed: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add() {
        guard !trimmed.isEmpty else { return }
        model.capture(trimmed)
        title = ""
        added += 1
    }
}

/// Where a task can go: the Inbox, No project, or an open project
/// (ADR 0017).
struct MoveSheet: View {
    let task: TaskItem
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    choice("Inbox", systemImage: "tray", .inbox)
                    choice("No Project", systemImage: "circle.dashed", .noProject)
                }
                if !model.projects.isEmpty {
                    Section("Projects") {
                        ForEach(model.projects, id: \.id) { project in
                            choice(project.title, systemImage: ProjectsView.projectSymbol, .project(id: project.id))
                        }
                    }
                }
            }
            .navigationTitle("Move To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
    }

    private var current: Location {
        if task.inbox { return .inbox }
        if let id = task.projectId { return .project(id: id) }
        return .noProject
    }

    private func choice(_ title: LocalizedStringKey, systemImage: String, _ location: Location) -> some View {
        label(Label(title, systemImage: systemImage), location)
    }

    // A project's title is the user's own text, not translated.
    private func choice(_ title: String, systemImage: String, _ location: Location) -> some View {
        label(Label(title, systemImage: systemImage), location)
    }

    private func label(_ label: Label<Text, Image>, _ location: Location) -> some View {
        Button {
            if location != current { model.move(task, to: location) }
            dismiss()
        } label: {
            HStack {
                label
                Spacer()
                if location == current {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityLabel(Text("Current"))
                }
            }
        }
        .foregroundStyle(.primary)
    }
}

struct SyncStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.syncing {
                Text("Syncing…")
            } else if model.offline {
                if model.pending > 0 {
                    Text("Offline, \(model.pending) changes waiting")
                } else {
                    Text("Offline")
                }
            } else if let at = model.lastSyncedAt {
                Text("Synced \(at, format: .relative(presentation: .named))")
            } else {
                Text("Not synced yet")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
