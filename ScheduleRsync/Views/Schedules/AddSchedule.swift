import SwiftUI

struct AddSchedule: View {
    @Bindable var schedules: ObservableSchedules
    @Binding var plannedDate: Date
    @State private var selectedProfile = "Default"
    @State private var recurrence = ScheduleType.repeating
    @State private var repeatMinutes = "60"
    @State private var rulesExpanded = false
    @State private var profiles: [String] = []
    @AppStorage(SchedulePlanner.gapKey) private var gapMinutes = 15

    @AppStorage(SchedulePlanner.QuietPeriod.enabledKey) private var quietPeriodEnabled = true
    @AppStorage(SchedulePlanner.QuietPeriod.startKey) private var quietStartMinutes = 23 * 60
    @AppStorage(SchedulePlanner.QuietPeriod.endKey) private var quietEndMinutes = 7 * 60

    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: minutes.wrappedValue / 60,
                                  minute: minutes.wrappedValue % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    private var plannedRun: String {
        plannedDate.en_string_from_date()
    }

    private var canAdd: Bool {
        schedules.canAddSchedule(dateRun: plannedRun, schedule: recurrence,
                                 repeatIntervalMinutes: Int(repeatMinutes))
    }

    private var validationWarning: String? {
        schedules.scheduleValidationWarning(dateRun: plannedRun, schedule: recurrence,
                                            repeatIntervalMinutes: Int(repeatMinutes))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        Picker("Profile", selection: $selectedProfile) {
                            Text("Default").tag("Default")
                            ForEach(profiles, id: \.self) { Text($0).tag($0) }
                        }
                        Picker("Schedule", selection: $recurrence) {
                            ForEach(ScheduleType.allCases) { Text($0.description).tag($0) }
                        }
                    }

                    HStack(spacing: 8) {
                        DatePicker("Run", selection: $plannedDate, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .accessibilityLabel("Run date and time")
                        if recurrence == .repeating {
                            Text("Every")
                            TextField("60", text: $repeatMinutes)
                                .modifier(AdaptiveRoundedTextFieldStyle())
                                .frame(width: 50)
                                .accessibilityLabel("Repeat interval in minutes")
                                .help("Minimum 30 minutes. 90 minutes = 1 hour 30 minutes.")
                            Text("min")
                        }
                        Spacer(minLength: 0)
                        AdaptiveProminentButton(systemImage: "plus", text: "Add",
                                                helpText: "Add schedule", action: add)
                            .disabled(!canAdd)
                    }
                    DisclosureGroup(isExpanded: $rulesExpanded) {
                        VStack(alignment: .leading, spacing: 8) {
                            Stepper("Minimum between tasks: \(gapMinutes) minutes", value: $gapMinutes, in: 1 ... 1440)
                            HStack {
                                Toggle("Quiet period", isOn: $quietPeriodEnabled)
                                DatePicker("From", selection: timeBinding($quietStartMinutes), displayedComponents: .hourAndMinute)
                                    .disabled(!quietPeriodEnabled)
                                DatePicker("To", selection: timeBinding($quietEndMinutes), displayedComponents: .hourAndMinute)
                                    .disabled(!quietPeriodEnabled)
                            }
                            Text("Starts in quiet hours move to their end, or are skipped if the next occurrence is reached. Equal times mean no quiet period. The gap spaces starts, not completions.")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Repeat intervals must be at least 30 minutes. 90 minutes = 1 hour 30 minutes.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.top, 6)
                    } label: {
                        Text("\(gapMinutes)-minute gap · \(quietPeriodSummary)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let validationWarning {
                        Text(validationWarning).font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(6)
            } label: {
                Label("New schedule", systemImage: "calendar.badge.plus")
            }
        }
        .onChange(of: gapMinutes) { replan() }
        .onChange(of: quietPeriodEnabled) { replan() }
        .onChange(of: quietStartMinutes) { replan() }
        .onChange(of: quietEndMinutes) { replan() }
        .onAppear { profiles = Homepath().profiles().filter { $0 != "Default" } }
    }

    private var quietPeriodSummary: String {
        guard quietPeriodEnabled, quietStartMinutes != quietEndMinutes else { return "No quiet hours" }
        func time(_ minutes: Int) -> String {
            String(format: "%02d:%02d", minutes / 60, minutes % 60)
        }
        return "Quiet hours \(time(quietStartMinutes))–\(time(quietEndMinutes))"
    }

    private func replan() {
        schedules.recomputeschedules()
    }

    private func add() {
        guard canAdd,
              schedules.appendSchedule(profile: selectedProfile == "Default" ? nil : selectedProfile,
                                       dateRun: plannedRun, schedule: recurrence.rawValue,
                                       repeatIntervalMinutes: recurrence == .repeating ? Int(repeatMinutes) : nil,
                                       repeatStartDate: recurrence == .repeating ? plannedDate : nil) else { return }
        Task { await WriteSchedule.write(schedules.scheduleDataForPersistence()) }
    }
}
