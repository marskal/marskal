import AppIntents
import MarskalKit
import SwiftUI
import WidgetKit

@main
struct MarskalWidgets: WidgetBundle {
    var body: some Widget {
        TasksWidget()
        AgendaWidget()
    }
}

struct WidgetIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [MarskalKitIntents.self] }
}

/// A list of tasks from the local database, each with a button that marks
/// it Done without opening the app (ADR 0029).
struct TasksWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "tasks", intent: TasksWidgetIntent.self, provider: TasksProvider()) { entry in
            TasksWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tasks")
        .description("Your Inbox, open tasks, or flagged tasks. Check a task off right here.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// Which tasks a widget shows.
enum TaskList: String, AppEnum {
    case inbox
    case open
    case flagged

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "List"
    static let caseDisplayRepresentations: [TaskList: DisplayRepresentation] = [
        .inbox: "Inbox",
        .open: "Open Tasks",
        .flagged: "Flagged",
    ]

    var filter: TaskFilter {
        switch self {
        case .inbox: .inbox
        case .open: .open(unavailable: false)
        case .flagged: .flagged(unavailable: false)
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .inbox: "Inbox"
        case .open: "Open Tasks"
        case .flagged: "Flagged"
        }
    }
}

struct TasksWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Tasks"
    static let description = IntentDescription("Choose the tasks to show.")

    @Parameter(title: "List", default: .open)
    var list: TaskList
}

struct TaskRow: Identifiable, Equatable {
    var id: UUID
    var title: String
    var flagged: Bool
}

struct TasksEntry: TimelineEntry {
    enum Content: Equatable {
        case tasks([TaskRow], total: Int)
        case signedOut
        case unreadable
    }

    var date: Date
    var list: TaskList
    var content: Content
}

struct TasksProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> TasksEntry {
        TasksEntry(date: .now, list: .open, content: .tasks(Self.sample, total: Self.sample.count))
    }

    func snapshot(for configuration: TasksWidgetIntent, in context: Context) async -> TasksEntry {
        if context.isPreview {
            return TasksEntry(date: .now, list: configuration.list, content: .tasks(Self.sample, total: Self.sample.count))
        }
        return entry(for: configuration.list)
    }

    // A deferred task can come due, so read again within the half hour.
    // The app and the check-off button reload the widget after changes.
    func timeline(for configuration: TasksWidgetIntent, in _: Context) async -> Timeline<TasksEntry> {
        Timeline(entries: [entry(for: configuration.list)], policy: .after(.now.addingTimeInterval(30 * 60)))
    }

    private func entry(for list: TaskList) -> TasksEntry {
        let content: TasksEntry.Content
        do {
            if let store = try AppGroup.openStore() {
                defer { store.close() }
                let tasks = try store.tasks(filter: list.filter)
                content = .tasks(
                    tasks.prefix(Self.most).map { TaskRow(id: $0.id, title: $0.title, flagged: $0.flagged) },
                    total: tasks.count)
            } else {
                content = .signedOut
            }
        } catch {
            content = .unreadable
        }
        return TasksEntry(date: .now, list: list, content: content)
    }

    // As many as the large widget shows.
    static let most = 8

    static let sample = [
        TaskRow(id: UUID(), title: String(localized: "Buy milk"), flagged: false),
        TaskRow(id: UUID(), title: String(localized: "Call the dentist"), flagged: true),
        TaskRow(id: UUID(), title: String(localized: "Water the plants"), flagged: false),
    ]
}

struct TasksWidgetView: View {
    let entry: TasksEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            switch entry.content {
            case .tasks(let rows, _) where rows.isEmpty:
                Spacer()
                Text("Nothing to do")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            case .tasks(let rows, _):
                ForEach(rows.prefix(shown)) { row in
                    TaskLine(row: row)
                }
                Spacer(minLength: 0)
            case .signedOut:
                Spacer()
                Text("Sign in in the Marskal app")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            case .unreadable:
                Spacer()
                Text("Open Marskal to see your tasks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack {
            Text(entry.list.title)
                .font(.headline)
                .foregroundStyle(.tint)
            Spacer()
            if case .tasks(_, let total) = entry.content, total > 0 {
                Text(total, format: .number)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var shown: Int {
        switch family {
        case .systemSmall: 3
        case .systemMedium: 4
        default: TasksProvider.most
        }
    }
}

private struct TaskLine: View {
    let row: TaskRow

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: CompleteTaskIntent(taskID: row.id)) {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Mark “\(row.title)” Done"))

            Text(row.title)
                .font(.subheadline)
                .lineLimit(1)

            if row.flagged {
                Spacer(minLength: 0)
                Image(systemName: "flag.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(Text("Flagged"))
            }
        }
    }
}

#Preview(as: .systemMedium) {
    TasksWidget()
} timeline: {
    TasksEntry(date: .now, list: .open, content: .tasks(TasksProvider.sample, total: 12))
    TasksEntry(date: .now, list: .inbox, content: .tasks([], total: 0))
}
