import MarskalKit
import SwiftUI

/// Captures tasks: a title, and if wanted a place, Defer, Planned, Due, and
/// tags. Return adds the task and clears the title for the next, which
/// keeps the rest; Add adds it and closes. A subtask goes where its parent
/// is (ADR 0009), so its place is not picked.
struct CaptureSheet: View {
    let parent: TaskItem?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var place: Location
    @State private var dates: [DateField: DateValue] = [:]
    @State private var tags: [TagItem] = []
    @State private var added = 0
    @State private var choosingPlace = false
    @State private var choosingTags = false
    @State private var editingDate: DateField?
    @FocusState private var focused: Bool

    /// A new task in the Inbox, No project, or a project.
    init(place: Location) {
        parent = nil
        _place = State(initialValue: place)
    }

    /// A new subtask, last under `parent`.
    init(under parent: TaskItem) {
        self.parent = parent
        _place = State(initialValue: parent.location)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // One line: return adds the task and keeps the field for
                    // the next. The Add button adds and closes.
                    TextField("Title", text: $title)
                        .focused($focused)
                        .submitLabel(.next)
                        .onSubmit {
                            add()
                            focused = true
                        }
                } footer: {
                    if added > 0 { addedText }
                }

                Section {
                    if let parent {
                        // A task's title is the user's own text.
                        LabeledContent("Under", value: parent.title)
                    } else {
                        Button { choosingPlace = true } label: {
                            LabeledContent("Place") {
                                PlaceName(location: place)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section {
                    ForEach([DateField.defer, .planned, .due]) { field in
                        Button { editingDate = field } label: {
                            LabeledContent {
                                dateText(field)
                            } label: {
                                Label(field.title, systemImage: field.symbol)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section {
                    ForEach(tags) { tag in
                        TagPath(tag: tag)
                    }
                    .onDelete { tags.remove(atOffsets: $0) }
                    Button("Add Tags", systemImage: "plus") { choosingTags = true }
                } header: {
                    Text("Tags")
                }
            }
            .navigationTitle(navigationTitle)
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
            .sheet(isPresented: $choosingPlace) {
                PlaceSheet(title: "Place", current: place) { place = $0 }
            }
            .sheet(item: $editingDate) { field in
                DateSheet(field: field, stored: dates[field]) { dates[field] = $0 }
            }
            .sheet(isPresented: $choosingTags) {
                TagPicker(chosen: $tags)
            }
        }
        .presentationDetents([.medium, .large])
    }

    // Not by place: the Place row says where, and it can change.
    private var navigationTitle: LocalizedStringKey {
        parent != nil ? "Add Subtask" : "Add Task"
    }

    private var addedText: Text {
        if parent != nil { return Text("\(added) subtasks added") }
        if place == .inbox { return Text("\(added) tasks added to the Inbox") }
        return Text("\(added) tasks added")
    }

    private func dateText(_ field: DateField) -> Text {
        switch dates[field] {
        case .indefinitely?: Text("Indefinitely").foregroundStyle(.secondary)
        case .at(let at)?: Text(verbatim: model.clock.label(at, for: field)).foregroundStyle(.secondary)
        case nil: Text("None").foregroundStyle(.tertiary)
        }
    }

    private var trimmed: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add() {
        guard !trimmed.isEmpty else { return }
        var new = NewTask(title: trimmed)
        if let parent {
            new.parentId = parent.id
        } else {
            new.location = place
        }
        switch dates[.defer] {
        case .indefinitely?: new.deferred = .indefinitely
        case .at(let at)?: new.deferred = .until(at: at)
        case nil: break
        }
        if case .at(let at)? = dates[.planned] { new.plannedAt = at }
        if case .at(let at)? = dates[.due] { new.dueAt = at }
        model.capture(new, tags: tags.map(\.id))
        title = ""
        added += 1
    }
}

/// The Inbox, No project, or a project's title.
struct PlaceName: View {
    let location: Location
    @Environment(AppModel.self) private var model

    var body: some View {
        switch location {
        case .inbox: Text("Inbox")
        case .noProject: Text("No Project")
        // A project's title is the user's own text, not translated.
        case .project(let id): Text(verbatim: model.projectsById[id]?.title ?? "")
        }
    }
}

/// A tag by its path, with a chevron between the names (ADR 0005).
struct TagPath: View {
    let tag: TagItem

    var body: some View {
        // A tag's names are the user's own text, not translated.
        Label(tag.path.joined(separator: " › "), systemImage: TagsView.tagSymbol)
    }
}

/// Picks tags: every tag as an outline, or those matching what is typed,
/// as the web's autocomplete matches them (ADR 0005). A tap adds or takes
/// off a tag. Dropped tags are not offered.
struct TagPicker: View {
    @Binding var chosen: [TagItem]
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            let found = model.searchTags(query)
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ForEach(outline, id: \.tag.id) { row in
                        choice(row.tag) {
                            Label(row.tag.name, systemImage: TagsView.tagSymbol)
                                .padding(.leading, CGFloat(row.depth) * 16)
                        }
                    }
                } else {
                    ForEach(found) { tag in
                        choice(tag) { TagPath(tag: tag) }
                    }
                }
            }
            .overlay {
                if model.tagOutline.children(of: nil).isEmpty {
                    ContentUnavailableView("No tags yet", systemImage: TagsView.tagSymbol)
                } else if !query.isEmpty && found.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                }
            }
        }
    }

    /// Live tags, each before the tags inside it.
    private var outline: [(tag: TagItem, depth: Int)] {
        let tags = model.tagOutline
        var rows: [(tag: TagItem, depth: Int)] = []
        func walk(_ parent: UUID?, _ depth: Int) {
            for tag in tags.children(of: parent) {
                rows.append((tag, depth))
                walk(tag.id, depth + 1)
            }
        }
        walk(nil, 0)
        return rows
    }

    private func choice(_ tag: TagItem, @ViewBuilder label: () -> some View) -> some View {
        let isChosen = chosen.contains { $0.id == tag.id }
        return Button {
            if isChosen {
                chosen.removeAll { $0.id == tag.id }
            } else {
                chosen.append(tag)
            }
        } label: {
            HStack {
                label()
                Spacer(minLength: 0)
                if tag.state == .onHold {
                    Text("On Hold")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if isChosen {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityLabel(Text("Chosen"))
                }
            }
        }
        .foregroundStyle(.primary)
    }
}
