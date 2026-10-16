import MarskalKit
import SwiftUI

/// The Inbox and the open tasks, read from the local database. Capture
/// and check-off come next.
struct TasksView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingSignOut = false

    var body: some View {
        NavigationStack {
            List {
                if !model.inbox.isEmpty {
                    Section("Inbox") {
                        ForEach(model.inbox, id: \.id) { TaskRow(task: $0) }
                    }
                }
                Section("Open Tasks") {
                    ForEach(model.open, id: \.id) { TaskRow(task: $0) }
                }
            }
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
}

private struct TaskRow: View {
    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(task.title)
            if let project = task.project {
                Text(project)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, CGFloat(task.depth) * 16)
    }
}

private struct SyncStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.syncing {
                Text("Syncing…")
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
