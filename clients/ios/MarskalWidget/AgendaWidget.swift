import AppIntents
import MarskalKit
import SwiftUI
import WidgetKit

/// Today's agenda from the local database, by time, each task with a
/// button that marks it Done without opening the app.
struct AgendaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "agenda", provider: AgendaProvider()) { entry in
            AgendaWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Agenda")
        .description("What is planned or due today, by time. Check a task off right here.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct AgendaLine: Identifiable, Equatable {
    var id: UUID
    var title: String
    var flagged: Bool
    var at: Date
    var due: Bool
}

struct AgendaEntry: TimelineEntry {
    enum Content: Equatable {
        case agenda([AgendaLine], total: Int)
        case signedOut
        case unreadable
    }

    var date: Date
    var content: Content
}

struct AgendaProvider: TimelineProvider {
    func placeholder(in _: Context) -> AgendaEntry {
        AgendaEntry(date: .now, content: .agenda(Self.sample, total: Self.sample.count))
    }

    func getSnapshot(in context: Context, completion: @escaping (AgendaEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry())
    }

    // Read again at midnight, when the day's agenda changes, and within
    // the half hour, for a deferred task that comes back. The app and the
    // check-off button reload the widget after changes.
    func getTimeline(in _: Context, completion: @escaping (Timeline<AgendaEntry>) -> Void) {
        let next = min(.now.addingTimeInterval(30 * 60), Agenda.endOfDay())
        completion(Timeline(entries: [entry()], policy: .after(next)))
    }

    private func entry() -> AgendaEntry {
        let content: AgendaEntry.Content
        do {
            if let store = try AppGroup.openStore() {
                defer { store.close() }
                let items = try Agenda.today(store)
                content = .agenda(
                    items.prefix(Self.most).map {
                        AgendaLine(id: $0.task.id, title: $0.task.title, flagged: $0.task.flagged, at: $0.at, due: $0.due)
                    },
                    total: items.count)
            } else {
                content = .signedOut
            }
        } catch {
            content = .unreadable
        }
        return AgendaEntry(date: .now, content: content)
    }

    // As many as the large widget shows.
    static let most = 8

    static var sample: [AgendaLine] {
        let today = Calendar.current.startOfDay(for: .now)
        return [
            AgendaLine(id: UUID(), title: String(localized: "Call the dentist"), flagged: true,
                       at: today.addingTimeInterval(9 * 3600), due: false),
            AgendaLine(id: UUID(), title: String(localized: "Water the plants"), flagged: false,
                       at: today.addingTimeInterval(12 * 3600), due: false),
            AgendaLine(id: UUID(), title: String(localized: "Buy milk"), flagged: false,
                       at: today.addingTimeInterval(17 * 3600), due: true),
        ]
    }
}

struct AgendaWidgetView: View {
    let entry: AgendaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            switch entry.content {
            case .agenda(let lines, _) where lines.isEmpty:
                Spacer()
                Text("Nothing planned or due today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            case .agenda(let lines, _):
                ForEach(lines.prefix(shown)) { line in
                    AgendaLineView(line: line, now: entry.date, timed: family != .systemSmall)
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
            Text("Today")
                .font(.headline)
                .foregroundStyle(.tint)
            Spacer()
            if case .agenda(_, let total) = entry.content, total > 0 {
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
        default: AgendaProvider.most
        }
    }
}

private struct AgendaLineView: View {
    let line: AgendaLine
    let now: Date
    /// Room for the time after the title.
    let timed: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: CompleteTaskIntent(taskID: line.id)) {
                Image(systemName: "circle")
                    .foregroundStyle(overdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Mark “\(line.title)” Done"))

            Text(line.title)
                .font(.subheadline)
                .lineLimit(1)

            Spacer(minLength: 0)

            if line.flagged {
                Image(systemName: "flag.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(Text("Flagged"))
            }

            if timed {
                Group {
                    if line.due {
                        Text("Due \(when)")
                    } else {
                        when
                    }
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(overdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }
        }
    }

    private var overdue: Bool { line.due && line.at <= now }

    // A time today, or the day it was for when that has passed.
    private var when: Text {
        if Calendar.current.isDate(line.at, inSameDayAs: now) {
            Text(line.at, format: .dateTime.hour().minute())
        } else {
            Text(line.at, format: .dateTime.day().month(.abbreviated))
        }
    }
}

#Preview(as: .systemMedium) {
    AgendaWidget()
} timeline: {
    AgendaEntry(date: .now, content: .agenda(AgendaProvider.sample, total: 5))
    AgendaEntry(date: .now, content: .agenda([], total: 0))
}
