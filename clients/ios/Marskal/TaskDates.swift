import MarskalKit
import SwiftUI

/// A task's Defer, Planned, and Due (ADR 0006). Each opens a sheet to pick
/// it. A date the task goes by but does not have, from a task above it or
/// its project, shows in gray.
struct TaskDatesSection: View {
    let task: TaskItem
    let edit: (DateField) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            row(.defer)
            row(.planned)
            row(.due)
        } footer: {
            if [DateField.defer, .planned, .due].contains(where: { inherited($0) }) {
                Text("Dates in gray come from a task above it or its project.")
            }
        }
    }

    private func row(_ field: DateField) -> some View {
        Button { edit(field) } label: {
            LabeledContent {
                value(field)
            } label: {
                Label(field.title, systemImage: field.symbol)
            }
        }
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func value(_ field: DateField) -> some View {
        let own = DateValue(task.dates, field)
        let effective = DateValue(task.effective, field)
        if let own {
            text(own, field)
                .foregroundStyle(field == .due && task.overdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
        } else if let effective {
            text(effective, field)
                .foregroundStyle(field == .due && task.overdue ? AnyShapeStyle(.red.opacity(0.6)) : AnyShapeStyle(.tertiary))
        } else {
            Text("None")
                .foregroundStyle(.tertiary)
        }
    }

    private func text(_ value: DateValue, _ field: DateField) -> Text {
        switch value {
        case .indefinitely: Text("Indefinitely")
        case .at(let at): Text(verbatim: model.clock.label(at, for: field))
        }
    }

    private func inherited(_ field: DateField) -> Bool {
        DateValue(task.dates, field) == nil && DateValue(task.effective, field) != nil
    }
}

/// One of a task's dates: an instant, or Defer with no end.
enum DateValue: Equatable {
    case at(Date)
    case indefinitely

    init?(_ dates: Dates, _ field: DateField) {
        switch field {
        case .defer:
            if dates.deferredIndefinitely {
                self = .indefinitely
            } else if let at = dates.deferUntil {
                self = .at(at)
            } else {
                return nil
            }
        case .planned:
            guard let at = dates.plannedAt else { return nil }
            self = .at(at)
        case .due:
            guard let at = dates.dueAt else { return nil }
            self = .at(at)
        }
    }

    /// The edit that gives `field` this value, or clears it for `nil`.
    static func change(_ field: DateField, to value: DateValue?) -> TaskChange {
        switch (field, value) {
        case (.defer, .indefinitely): .deferred(deferred: .indefinitely)
        case (.defer, .at(let at)): .deferred(deferred: .until(at: at))
        case (.defer, nil): .deferred(deferred: nil)
        case (.planned, .at(let at)): .planned(at: at)
        case (.due, .at(let at)): .due(at: at)
        case (.planned, _): .planned(at: nil)
        case (.due, _): .due(at: nil)
        }
    }
}

extension DateField: @retroactive Identifiable {
    public var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .defer: "Defer"
        case .planned: "Planned"
        case .due: "Due"
        }
    }

    var symbol: String {
        switch self {
        case .defer: "moon.zzz"
        case .planned: "calendar"
        case .due: "alarm"
        }
    }
}

/// Picks one date: a day on the calendar, starting on the user's week
/// start, and a time if it needs one; without one it takes the field's
/// default. Today, Tomorrow, and Next Week set the day and save at once.
/// Defer can also be indefinite.
struct DateSheet: View {
    let task: TaskItem
    let field: DateField
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var day = Date.now
    @State private var timed = false
    @State private var time = Date.now
    @State private var indefinitely = false

    private var clock: UserClock { model.clock }
    private var stored: DateValue? { DateValue(task.dates, field) }

    var body: some View {
        NavigationStack {
            Form {
                if field == .defer {
                    Section {
                        Toggle("Indefinitely", isOn: $indefinitely)
                    } footer: {
                        Text("Hidden until you clear Defer.")
                    }
                }

                if !indefinitely {
                    Section {
                        HStack {
                            Button("Today") { save(on: clock.today()) }
                            Button("Tomorrow") { save(on: clock.tomorrow()) }
                            Button("Next Week") { save(on: clock.nextWeek()) }
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                        DatePicker("Day", selection: $day, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                    }

                    Section {
                        Toggle("Time", isOn: $timed)
                        if timed {
                            DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        }
                    } footer: {
                        if !timed {
                            Text("Without a time, it is at \(clock.defaultTimeLabel(for: field)).")
                        }
                    }
                }

                if stored != nil {
                    Section {
                        Button("Clear", role: .destructive) { save(nil) }
                    }
                }
            }
            .environment(\.calendar, clock.calendar)
            .environment(\.timeZone, clock.zone)
            .navigationTitle(field.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) {
                        save(indefinitely ? .indefinitely : .at(instant(on: day)))
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        switch stored {
        case .at(let at):
            day = at
            timed = clock.hasTime(at, for: field)
            time = at
        case .indefinitely:
            indefinitely = true
            day = clock.today()
            time = clock.instant(on: day, at: nil, for: field)
        case nil:
            // A new Defer is for a later day; Planned and Due often today.
            day = field == .defer ? clock.tomorrow() : clock.today()
            time = clock.instant(on: day, at: nil, for: field)
        }
    }

    private func instant(on day: Date) -> Date {
        clock.instant(on: day, at: timed ? clock.time(of: time) : nil, for: field)
    }

    private func save(on day: Date) {
        save(.at(instant(on: day)))
    }

    private func save(_ value: DateValue?) {
        if value != stored {
            model.edit(task, [DateValue.change(field, to: value)])
        }
        dismiss()
    }
}
