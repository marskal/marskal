import MarskalKit
import SwiftUI

/// Opens a task's detail from a row in any list.
struct TaskRoute: Hashable {
    let id: UUID
}

extension View {
    /// Shows a task's detail for a `TaskRoute` pushed in this stack.
    func taskDestination() -> some View {
        navigationDestination(for: TaskRoute.self) { TaskDetailView(taskId: $0.id) }
    }
}

/// One task: its title, notes, URL, flag, and dates to edit, where it is,
/// and Done, Drop, Reopen, and Delete. A text field saves when it loses focus,
/// so typing is one change rather than one per key.
struct TaskDetailView: View {
    let taskId: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var title = ""
    @State private var url = ""
    @State private var moving: TaskItem?
    @State private var editingDate: DateField?
    @State private var confirmingDelete = false
    @FocusState private var focus: Field?

    private enum Field { case title, url }

    var body: some View {
        let task = model.task(taskId)
        Group {
            if let task {
                form(task)
            } else {
                ContentUnavailableView("This task was deleted", systemImage: "checkmark.circle")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load(task) }
        // A sync or another view changed it: show that, but not over what
        // is being typed.
        .onChange(of: task) { _, new in load(new) }
        .onChange(of: focus) { old, _ in
            if let old { save(old) }
        }
        // Before the app closes the database in the background.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveAll() }
        }
        .onDisappear { saveAll() }
        .sheet(item: $moving) { task in
            MoveSheet(task: task)
        }
        .sheet(item: $editingDate) { field in
            if let task { DateSheet(task: task, field: field) }
        }
    }

    private func form(_ task: TaskItem) -> some View {
        Form {
            Section {
                // A title is one line; it wraps when long. Return ends it.
                TextField("Title", text: $title, axis: .vertical)
                    .font(.title3)
                    .focused($focus, equals: .title)
                    .submitLabel(.done)
                    .onChange(of: title) { _, new in
                        if new.contains(where: \.isNewline) {
                            title = new.filter { !$0.isNewline }
                            focus = nil
                        }
                    }
                NavigationLink {
                    NotesEditor(taskId: taskId)
                } label: {
                    notesPreview(task)
                }
            }

            Section {
                HStack {
                    TextField("URL", text: $url)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focus, equals: .url)
                    if let link {
                        Button("Open Link", systemImage: "arrow.up.right.square") { openURL(link) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                }
                Toggle(isOn: flagged(task)) {
                    Label("Flagged", systemImage: "flag")
                }
            } footer: {
                if !urlIsAcceptable {
                    Text("A URL must be absolute, such as https://marskal.example.")
                        .foregroundStyle(.red)
                } else if task.flagged && !task.ownFlagged {
                    Text("Its project is flagged, so it is too.")
                }
            }

            TaskDatesSection(task: task) { editingDate = $0 }

            Section {
                Button { moving = task } label: {
                    LabeledContent("Place") {
                        place(task)
                    }
                }
                .foregroundStyle(.primary)
            }

            Section {
                if task.state == .toDo {
                    Button("Mark Done", systemImage: "checkmark.circle") { model.setState(task, .done) }
                    Button("Drop", systemImage: "xmark.circle") { model.setState(task, .dropped) }
                } else {
                    LabeledContent {
                        if let at = task.resolvedAt {
                            Text(at, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                        }
                    } label: {
                        Text(task.state == .done ? "Done" : "Dropped")
                    }
                    Button("Reopen", systemImage: "arrow.uturn.backward.circle") { model.setState(task, .toDo) }
                }
            } footer: {
                if task.state == .toDo && task.resolved {
                    Text("A task or project above it is resolved, so this task is too.")
                }
            }

            Section {
                Button("Delete Task", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            }
        }
        .confirmationDialog("Delete this task?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.delete(task)
                dismiss()
            }
        } message: {
            Text("Its subtasks are deleted with it. To finish a task, mark it Done or Drop it.")
        }
    }

    /// The first lines of the notes: a captured email can run long. The
    /// whole of them opens on a page of its own.
    @ViewBuilder
    private func notesPreview(_ task: TaskItem) -> some View {
        let notes = task.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if notes.isEmpty {
            Text("Notes")
                .foregroundStyle(.tertiary)
        } else {
            Text(verbatim: notes)
                .lineLimit(6)
        }
    }

    // A project's title is the user's own text, not translated.
    private func place(_ task: TaskItem) -> Text {
        if task.inbox { return Text("Inbox") }
        if let project = task.project { return Text(verbatim: project) }
        return Text("No Project")
    }

    private func flagged(_ task: TaskItem) -> Binding<Bool> {
        Binding(
            get: { task.ownFlagged },
            set: { model.edit(task, [.flagged(flagged: $0)]) })
    }

    private var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var urlIsAcceptable: Bool {
        trimmedURL.isEmpty || urlIsValid(url: trimmedURL)
    }

    /// The URL in the field, when it is one to open.
    private var link: URL? {
        guard !trimmedURL.isEmpty, urlIsValid(url: trimmedURL) else { return nil }
        return URL(string: trimmedURL)
    }

    // MARK: Saving

    private func load(_ task: TaskItem?) {
        guard let task else { return }
        if focus != .title { title = task.title }
        if focus != .url { url = task.url ?? "" }
    }

    private func saveAll() {
        save(.title)
        save(.url)
    }

    private func save(_ field: Field) {
        guard let task = model.task(taskId) else { return }
        switch field {
        case .title:
            // Unchanged: nothing to save, even if trimming would change it.
            guard title != task.title else { return }
            let new = title.trimmingCharacters(in: .whitespacesAndNewlines)
            // A task always has a title: a blank one puts the old one back.
            if new.isEmpty {
                title = task.title
            } else if new != task.title {
                model.edit(task, [.title(title: new)])
            }
        case .url:
            guard url != (task.url ?? "") else { return }
            // A bad URL stays in the field, with the footer saying why.
            guard urlIsAcceptable else { return }
            let new = trimmedURL.isEmpty ? nil : trimmedURL
            if new != task.url { model.edit(task, [.url(url: new)]) }
        }
    }
}

/// A task's notes on a page of their own, to read in full and edit. Saves
/// when editing ends or the page closes, and only when they changed.
private struct NotesEditor: View {
    let taskId: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var notes = ""
    @State private var loaded = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: $notes)
            .focused($focused)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if focused {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", role: .confirm) { focused = false }
                    }
                }
            }
            .onAppear {
                loaded = model.task(taskId)?.notes ?? ""
                notes = loaded
                // Empty notes are there to be written; long ones to be read first.
                if loaded.isEmpty { focused = true }
            }
            .onChange(of: focused) { _, now in
                if !now { save() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { save() }
            }
            .onDisappear { save() }
    }

    private func save() {
        guard notes != loaded, let task = model.task(taskId) else { return }
        let new = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        if new != task.notes { model.edit(task, [.notes(notes: new)]) }
        loaded = notes
    }
}
