import MarskalKit
import SwiftUI

/// Today's agenda: what is due or planned today, and earlier days' still to
/// do, as one list by time (ADR 0006). Check a task off with its circle or
/// a swipe.
struct AgendaView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.agenda) { item in
                        NavigationLink(value: TaskRoute(id: item.task.id)) {
                            TaskRow(task: item.task, indented: false, showsDates: false) {
                                model.setState(item.task, .done)
                            } detail: {
                                AgendaTime(item: item)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button("Done", systemImage: "checkmark") { model.setState(item.task, .done) }
                                .tint(.green)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Drop", systemImage: "xmark") { model.setState(item.task, .dropped) }
                                .tint(.gray)
                        }
                        .contextMenu {
                            Button("Done", systemImage: "checkmark") { model.setState(item.task, .done) }
                            Button("Drop", systemImage: "xmark") { model.setState(item.task, .dropped) }
                        }
                    }
                } footer: {
                    SyncStatus()
                }
            }
            .animation(.default, value: model.agenda.map(\.id))
            .overlay {
                if model.agenda.isEmpty && !model.syncing {
                    ContentUnavailableView(
                        "Nothing planned or due today",
                        systemImage: "calendar",
                        description: Text("Tasks planned or due today show up here."))
                }
            }
            .refreshable { await model.refresh() }
            .navigationTitle("Today")
            .taskDestination()
        }
    }
}

/// The time a task is on the agenda for: a time today, or the day it was
/// for when that has passed. Due in red once it is overdue.
struct AgendaTime: View {
    let item: AgendaItem

    var body: some View {
        Group {
            if item.due {
                Text("Due \(when)")
            } else {
                when
            }
        }
        .font(.subheadline)
        .monospacedDigit()
        .foregroundStyle(item.task.overdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
    }

    private var when: Text {
        if Calendar.current.isDateInToday(item.at) {
            Text(item.at, format: .dateTime.hour().minute())
        } else {
            Text(item.at, format: .dateTime.day().month(.abbreviated))
        }
    }
}
