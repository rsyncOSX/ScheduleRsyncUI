//
//  CalendarMonthView.swift
//  Calendar
//
//  Created by Thomas Evensen on 25/03/2025.
//

import SwiftUI

struct CalendarMonthView: View {
    private enum FocusedTable: Hashable {
        case schedules
        case notExecutedSchedules
    }

    @Environment(\.calendar) private var calendar

    @Bindable var schedules: ObservableSchedules

    @State private var date = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? Date.now
    @State private var plannedDate = Date.now.addingTimeInterval(300)

    @State private var selecteduuids: Set<SchedulesConfigurations.ID> = []
    @State private var selecteduuidsnotexecuted: Set<SchedulesConfigurations.ID> = []
    @State private var pendingDeletion: [SchedulesConfigurations]?
    @FocusState private var focusedTable: FocusedTable?

    let globaltimer = GlobalTimer.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ScrollView {
                CalendarMonthGridView(date: date, plannedDate: $plannedDate,
                                      occurrences: globaltimer.allSchedules,
                                      firstScheduledText: firstScheduledText,
                                      lastExecutedScheduleText: schedules.lastExecutedScheduleText,
                                      sleepDelayNotice: globaltimer.lastSleepDelayNotice)
            }
            .frame(minWidth: 280, idealWidth: 300, maxWidth: 320)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                ScrollView {
                    AddSchedule(schedules: schedules, plannedDate: $plannedDate)
                }
                .frame(maxHeight: 280)
                .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text("Upcoming schedules").font(.headline)
                    Spacer()
                    Button(role: .destructive, action: requestSeriesDeletion) {
                        Label("Delete series", systemImage: "trash")
                    }
                    .disabled(selecteduuids.isEmpty && selecteduuidsnotexecuted.isEmpty)
                    .help("Delete every run belonging to the selected schedule series")
                    Text(globaltimer.allSchedules.count == 1 ? "1 run" : "\(globaltimer.allSchedules.count) runs")
                        .foregroundStyle(.secondary)
                }

                VStack {
                    TableofSchedules(selecteduuids: $selecteduuids)
                        .overlay {
                            if globaltimer.displayedSchedules.isEmpty {
                                ContentUnavailableView("No upcoming schedules", systemImage: "calendar",
                                                       description: Text("Choose a day, profile, and time above to add a schedule."))
                            }
                        }
                        .focused($focusedTable, equals: .schedules)
                        .onDeleteCommand(perform: requestSeriesDeletion)

                    selectedRunDetails

                    if GlobalTimer.shared.notExecutedSchedulesafterWakeUp.count > 0 {
                        AdaptiveProminentButton(
                            systemImage: "",
                            text: "Move to Schedules ↑",
                            helpText: "Move to Schedules"
                        ) {
                            GlobalTimer.shared.moveToSchedules(itemIDs: Array(selecteduuidsnotexecuted))
                            selecteduuidsnotexecuted.removeAll()
                        }
                        .disabled(selecteduuidsnotexecuted.isEmpty)
                        .padding()

                        TableofNotExeSchedules(selecteduuids: $selecteduuidsnotexecuted)
                            .focused($focusedTable, equals: .notExecutedSchedules)
                            .onDeleteCommand(perform: requestSeriesDeletion)
                    }
                }
            }
        }
        .defaultFocus($focusedTable, .schedules)
        .onAppear { schedules.ensureSchedulingHorizon(through: date) }
        .onChange(of: selecteduuids) {
            if selecteduuids.isEmpty == false {
                focusedTable = .schedules
                selecteduuidsnotexecuted.removeAll()
            }
        }
        .onChange(of: selecteduuidsnotexecuted) {
            if selecteduuidsnotexecuted.isEmpty == false {
                focusedTable = .notExecutedSchedules
                selecteduuids.removeAll()
            }
        }
        .onChange(of: date) { schedules.ensureSchedulingHorizon(through: date) }
        .onChange(of: plannedDate) {
            date = CalendarMonthLayout.monthStart(containing: plannedDate, calendar: calendar)
            schedules.ensureSchedulingHorizon(through: plannedDate)
        }
        .onChange(of: globaltimer.firstscheduledate) {
            if globaltimer.allSchedules.isEmpty {
                globaltimer.invalidateAllSchedulesAndTimer()
            }
        }
        .padding()
        .disabled(schedules.isUpdatingScheduleFile)
        .confirmationDialog(pendingDeletion?.count == 1 ? "Delete schedule series?" :
            "Delete \(pendingDeletion?.count ?? 0) schedule series?", item: $pendingDeletion) { definitions in
                Button("Delete series", role: .destructive) {
                    Task {
                        do {
                            try await schedules.deleteSeries(definitions)
                            selecteduuids.removeAll()
                            selecteduuidsnotexecuted.removeAll()
                        } catch {
                            StorageStatus.shared.message = "Could not delete the schedule series: \(error.localizedDescription)"
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("All runs belonging to the selected series will be deleted, including repeats.")
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Divider()
                DisclosureGroup("Last scheduled URL") {
                    Text(schedules.lastTriggeredURL?.absoluteString ?? "Waiting for a schedule to fire…")
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.callout)
            }
            .padding([.horizontal, .bottom])
        }
        .toolbar { calendartoolbarcontent }
    }

    @ViewBuilder
    private var selectedRunDetails: some View {
        let selectedIDs = selecteduuids.union(selecteduuidsnotexecuted)
        let runs = globaltimer.displayedSchedules + globaltimer.notExecutedSchedulesafterWakeUp
        if let run = runs.first(where: { selectedIDs.contains($0.id) }) {
            DisclosureGroup(selectedIDs.count > 1 ? "Run details (first of \(selectedIDs.count) selected)" : "Run details") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profile: \(run.scheduledata?.profile ?? "Default") · \(run.scheduledata?.scheduleDescription ?? "")")
                    Text("Run: \(run.time.formatted(date: .complete, time: .shortened))")
                    Text("Status: \(run.skipReason ?? (run.isAdjusted ? "Adjusted" : "Scheduled"))")
                    Text("Requested: \(run.requestedTime.formatted(date: .abbreviated, time: .shortened))")
                    Text("Added: \(run.scheduledata?.dateAdded ?? "Unknown")")
                    Text("\(run.time > .now ? "Time remaining" : "Overdue by"): \(abs(run.time.timeIntervalSinceNow).latest())")
                }
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func requestSeriesDeletion() {
        let definitions = schedules.definitions(for: selecteduuids.union(selecteduuidsnotexecuted))
        guard !definitions.isEmpty, !schedules.isUpdatingScheduleFile else { return }
        pendingDeletion = definitions
    }

    @ToolbarContentBuilder
    private var calendartoolbarcontent: some ToolbarContent {
        ToolbarItemGroup {
            Button("Previous month", systemImage: "chevron.left") {
                date = CalendarMonthLayout.month(byAdding: -1, to: date, calendar: calendar)
            }
            .labelStyle(.iconOnly)
            .help("Previous month")
            Button("Today") {
                date = CalendarMonthLayout.monthStart(containing: .now, calendar: calendar)
                plannedDate = Date.now.addingTimeInterval(300)
            }
            Button("Next month", systemImage: "chevron.right") {
                date = CalendarMonthLayout.month(byAdding: 1, to: date, calendar: calendar)
            }
            .labelStyle(.iconOnly)
            .help("Next month")
        }
    }

    private var firstScheduledText: String? {
        guard let next = globaltimer.allSchedules.first else { return nil }
        return "\(next.scheduledata?.profile ?? "Default") · \(next.time.formatted(date: .abbreviated, time: .shortened))"
    }
}
