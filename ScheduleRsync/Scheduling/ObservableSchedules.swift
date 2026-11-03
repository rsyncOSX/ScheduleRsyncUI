//
//  ObservableSchedules.swift
//  Calendar
//
//  Created by Thomas Evensen on 27/03/2025.
//

import AppKit
import Foundation
import Observation
import OSLog
import SwiftUI

@Observable @MainActor
final class ObservableSchedules {
    let globaltimer = GlobalTimer.shared

    @ObservationIgnored var lastdateinnextmonth: Date?
    private(set) var scheduleDefinitions = [SchedulesConfigurations]()
    private(set) var lastTriggeredURL: URL?
    private(set) var lastExecutedScheduleText: String?
    private(set) var isUpdatingScheduleFile = false

    /// Drain due work before rebuilding, so a delayed maintenance task cannot erase it.
    func maintainSchedulingHorizon() {
        guard globaltimer.canRun else { return }
        globaltimer.processDueSchedules()
        ensureSchedulingHorizon(through: .now)
        recomputeschedules()
    }

    /// Browsing never expands the bounded current-and-next-month execution plan.
    func ensureSchedulingHorizon(through date: Date, calendar: Calendar = .current) {
        let requested = computelastdateinnextmonth() ?? date
        guard requested != lastdateinnextmonth else { return }
        lastdateinnextmonth = requested
        recomputeschedules()
    }

    private func computefuturedates(_ definition: SchedulesConfigurations) {
        guard let schedule = definition.schedule,
              let dateRun = definition.dateRun?.validate_en_date_from_string() else { return }
        let profile = definition.profile
        let definitionID = definition.id
        if lastdateinnextmonth == nil {
            lastdateinnextmonth = computelastdateinnextmonth()
        }

        switch schedule {
        case ScheduleType.daily.rawValue:
            computeDailySchedule(profile: profile, dateRun: dateRun, definitionID: definitionID)
        case ScheduleType.weekly.rawValue:
            computeWeeklySchedule(profile: profile, dateRun: dateRun, definitionID: definitionID)
        case ScheduleType.repeating.rawValue:
            computeIntervalSchedule(definition)
        case ScheduleType.once.rawValue:
            computeOnceSchedule(profile: profile, dateRun: dateRun, definitionID: definitionID)
        default:
            return
        }
    }

    private func computeIntervalSchedule(_ definition: SchedulesConfigurations) {
        guard let minutes = definition.repeatIntervalMinutes,
              let start = definition.repeatStartTimestamp.map(Date.init(timeIntervalSince1970:))
              ?? definition.dateRun?.validate_en_date_from_string() else { return }
        for time in RepeatSchedule.occurrences(start: start, everyMinutes: minutes,
                                               after: .now, through: schedulingHorizon) {
            var occurrence = definition
            occurrence.dateRun = time.en_string_from_date()
            // Keep the actual instant, including both occurrences of an hour when clocks go back.
            addtaskandcallback(occurrence, at: time)
        }
    }

    private func computeOnceSchedule(profile: String?, dateRun: Date, definitionID: UUID) {
        guard dateRun <= schedulingHorizon else { return }
        appendScheduleOccurrence(id: definitionID,
                                 profile: profile,
                                 dateRun: dateRun.en_string_from_date(),
                                 schedule: ScheduleType.once.rawValue)
    }

    private func computeDailySchedule(profile: String?, dateRun: Date, definitionID: UUID) {
        var dateComponents = DateComponents()
        dateComponents.day = 1
        computeRepeatingSchedule(
            definitionID: definitionID,
            profile: profile,
            dateRun: dateRun,
            dateComponents: dateComponents,
            scheduleType: ScheduleType.daily.rawValue
        )
    }

    private func computeWeeklySchedule(profile: String?, dateRun: Date, definitionID: UUID) {
        var dateComponents = DateComponents()
        dateComponents.day = 7
        computeRepeatingSchedule(
            definitionID: definitionID,
            profile: profile,
            dateRun: dateRun,
            dateComponents: dateComponents,
            scheduleType: ScheduleType.weekly.rawValue
        )
    }

    private func computeRepeatingSchedule(definitionID: UUID, profile: String?, dateRun: Date,
                                          dateComponents: DateComponents, scheduleType: String) {
        let timeInterval: TimeInterval = schedulingHorizon.timeIntervalSince(dateRun)
        guard timeInterval > 0 else { return }

        let index = calculateScheduleIndex(timeInterval: timeInterval, dayInterval: dateComponents.day ?? 0)
        appendInitialScheduleIfNeeded(
            definitionID: definitionID,
            profile: profile,
            dateRun: dateRun,
            lastDayOfMonth: schedulingHorizon,
            scheduleType: scheduleType
        )

        addFutureSchedules(
            definitionID: definitionID,
            profile: profile,
            startDate: dateRun,
            dateComponents: dateComponents,
            scheduleType: scheduleType,
            count: index,
            lastDayOfMonth: schedulingHorizon
        )
    }

    private func calculateScheduleIndex(timeInterval: TimeInterval, dayInterval: Int) -> Int {
        switch dayInterval {
        case 1:
            return Int(timeInterval / (60 * 60 * 24))
        case 7:
            return Int(timeInterval / (60 * 60 * 24 * 7))
        default:
            Logger.process.warning("ObservableSchedules: unhandled dayInterval \(dayInterval), returning 0")
            return 0
        }
    }

    private func appendInitialScheduleIfNeeded(definitionID: UUID, profile: String?, dateRun: Date,
                                               lastDayOfMonth: Date, scheduleType: String) {
        if dateRun >= Date.now, dateRun <= lastDayOfMonth {
            appendScheduleOccurrence(id: definitionID,
                                     profile: profile,
                                     dateRun: dateRun.en_string_from_date(),
                                     schedule: scheduleType)
        }
    }

    private func addFutureSchedules(definitionID: UUID, profile: String?, startDate: Date, dateComponents: DateComponents,
                                    scheduleType: String, count: Int, lastDayOfMonth: Date) {
        var computedDateRun: Date = startDate
        for _ in 0 ..< count {
            if let futureDate = Calendar.current.date(byAdding: dateComponents, to: computedDateRun) {
                computedDateRun = futureDate
                if futureDate <= lastDayOfMonth {
                    appendScheduleOccurrence(id: definitionID,
                                             profile: profile,
                                             dateRun: futureDate.en_string_from_date(),
                                             schedule: scheduleType)
                }
            } else {
                Logger.process.warning("ObservableSchedules: Failed to calculate future dates")
            }
        }
    }

    func computelastdateinnextmonth() -> Date? {
        let calendar = Calendar.current
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: Date()),
              let interval = calendar.dateInterval(of: .month, for: nextMonth),
              let lastSecondOfNextMonth = calendar.date(byAdding: .second, value: -1, to: interval.end)
        else { return nil }
        return lastSecondOfNextMonth
    }

    func appendSchedule(profile: String?, dateRun: String, schedule: String,
                        repeatIntervalMinutes: Int? = nil, repeatStartDate: Date? = nil) -> Bool {
        guard let type = ScheduleType(rawValue: schedule),
              let plannedDate = validPlannedScheduleDate(dateRun),
              canAddSchedule(dateRun: dateRun, schedule: type,
                             repeatIntervalMinutes: repeatIntervalMinutes) else { return false }
        if type == .repeating, !RepeatSchedule.isValid(minutes: repeatIntervalMinutes) {
            return false
        }
        let anchor = repeatStartDate ?? plannedDate
        guard anchor.timeIntervalSince1970.isFinite else { return false }
        let normalizedAnchor = Date(timeIntervalSince1970: floor(anchor.timeIntervalSince1970 / 60) * 60)
        if type == .repeating, normalizedAnchor <= .now || normalizedAnchor > schedulingHorizon {
            return false
        }
        let scheduleDefinition = SchedulesConfigurations(profile: profile,
                                                         dateAdded: Date.now.en_string_from_date(),
                                                         dateRun: plannedDate.en_string_from_date(),
                                                         schedule: schedule,
                                                         repeatIntervalMinutes: type == .repeating ? repeatIntervalMinutes : nil,
                                                         repeatStartTimestamp: type == .repeating ? normalizedAnchor.timeIntervalSince1970 : nil)
        guard scheduleDefinitions.contains(where: { sameScheduleDefinition($0, scheduleDefinition) }) == false else { return false }
        scheduleDefinitions.append(scheduleDefinition)
        recomputeschedules()
        return true
    }

    func appendScheduleOccurrence(id: UUID, profile: String?, dateRun: String, schedule: String) {
        guard let parsedDate = dateRun.validate_en_date_from_string(), parsedDate >= Date.now else { return }
        let futureschedule = SchedulesConfigurations(id: id,
                                                     profile: profile,
                                                     dateAdded: Date.now.en_string_from_date(),
                                                     dateRun: parsedDate.en_string_from_date(),
                                                     schedule: schedule)
        addtaskandcallback(futureschedule)
    }

    func scheduleDataForPersistence() -> [SchedulesConfigurations] {
        scheduleDefinitions.filter { definition in
            guard let schedule = definition.schedule,
                  let dateRun = definition.dateRun?.validate_en_date_from_string()
            else { return false }
            if schedule == ScheduleType.once.rawValue {
                return dateRun > Date.now || globaltimer.allSchedules.contains { $0.scheduledata?.id == definition.id && $0.time > .now }
            }
            if schedule == ScheduleType.repeating.rawValue {
                return RepeatSchedule.isValid(minutes: definition.repeatIntervalMinutes)
                    && (definition.repeatStartTimestamp?.isFinite ?? true)
            }
            return ScheduleType(rawValue: schedule) != nil
        }
    }

    /// Recompute the calendardata to only show active schedules in row.
    func recomputeschedules() {
        guard !isUpdatingScheduleFile else { return }
        scheduleDefinitions = scheduleDataForPersistence()

        guard scheduleDefinitions.isEmpty == false else {
            globaltimer.skippedSchedules = []
            globaltimer.invalidateAllSchedulesAndTimer()
            globaltimer.firstscheduledate = nil
            return
        }

        globaltimer.planningHorizon = schedulingHorizon
        let pending = globaltimer.allSchedules.filter { $0.requestedTime <= .now && $0.time > .now }
        globaltimer.skippedSchedules = []
        globaltimer.replaceSchedules {
            globaltimer.allSchedules.append(contentsOf: pending.filter { item in
                scheduleDefinitions.contains { $0.id == item.scheduledata?.id }
            })
            for definition in scheduleDefinitions {
                computefuturedates(definition)
            }
        }
    }

    private func addtaskandcallback(_ schedule: SchedulesConfigurations, at actualTime: Date? = nil) {
        let callback: () -> Void = { [weak self] in
            guard let self else { return }
            if let url = ScheduleURL.make(profile: schedule.profile ?? "Default") {
                lastTriggeredURL = url
                lastExecutedScheduleText = "\(schedule.profile ?? "Default") · \(Date.now.formatted(date: .abbreviated, time: .shortened)) · Test trigger delivered; RsyncUI launch disabled."
                // Testing period: display the URL without launching RsyncUI.
                // if NSWorkspace.shared.open(url) == false {
                //     StorageStatus.shared.message = "Could not open RsyncUI. Install RsyncUI and try again."
                // }
            }
            globaltimer.refreshTimerAfterScheduleMutation()
        }
        if let schedultime = actualTime ?? schedule.dateRun?.validate_en_date_from_string() {
            globaltimer.addSchedule(time: schedultime,
                                    callback: callback,
                                    scheduledata: schedule)
        }
    }

    /// Apply Scheduledata read from file, used by SidebarMainView
    func appendschdeuldatafromfile(_ schedules: [SchedulesConfigurations]) {
        scheduleDefinitions = uniquedScheduleDefinitions(schedules).filter { definition in
            guard let schedule = definition.schedule,
                  let dateRun = definition.dateRun?.validate_en_date_from_string()
            else { return false }
            if schedule == ScheduleType.once.rawValue {
                return dateRun > Date.now || globaltimer.allSchedules.contains { $0.scheduledata?.id == definition.id && $0.time > .now }
            }
            if schedule == ScheduleType.repeating.rawValue {
                return RepeatSchedule.isValid(minutes: definition.repeatIntervalMinutes)
                    && (definition.repeatStartTimestamp?.isFinite ?? true)
            }
            return ScheduleType(rawValue: schedule) != nil
        }
        recomputeschedules()
    }

    /// The button and save path share the same validation rules.
    func canAddSchedule(dateRun: String, schedule: ScheduleType = .once,
                        repeatIntervalMinutes: Int? = nil, now: Date = .now) -> Bool {
        scheduleValidationWarning(dateRun: dateRun, schedule: schedule,
                                  repeatIntervalMinutes: repeatIntervalMinutes, now: now) == nil
    }

    func verifynextschedule(plannednextschedule: String) -> Bool {
        canAddSchedule(dateRun: plannednextschedule)
    }

    /// Validate input only; the planner resolves spacing conflicts automatically.
    func scheduleValidationWarning(dateRun: String, schedule: ScheduleType,
                                   repeatIntervalMinutes: Int? = nil, now: Date = .now) -> String? {
        guard let start = dateRun.validate_en_date_from_string(), start > now,
              start <= schedulingHorizon else {
            return "Choose a future time within the current or next month."
        }
        if schedule == .repeating, !RepeatSchedule.isValid(minutes: repeatIntervalMinutes) {
            return "Enter a whole number of minutes, at least 30."
        }
        return nil
    }

    func validPlannedScheduleDate(_ plannednextschedule: String) -> Date? {
        guard let plannedDate = plannednextschedule.validate_en_date_from_string(),
              plannedDate > Date.now,
              plannedDate <= schedulingHorizon
        else { return nil }
        return plannedDate
    }

    func definitions(for occurrences: Set<ScheduledItem.ID>) -> [SchedulesConfigurations] {
        let selected = (globaltimer.displayedSchedules + globaltimer.notExecutedSchedulesafterWakeUp)
            .filter { occurrences.contains($0.id) }
        var result: [SchedulesConfigurations] = []
        for item in selected {
            guard let data = item.scheduledata, !result.contains(where: { $0.id == data.id }) else { continue }
            result.append(scheduleDefinitions.first(where: { $0.id == data.id }) ?? data)
        }
        return result
    }

    /// Remove persisted definitions first, then rebuild the tracker from the updated file.
    func deleteSeries(_ definitions: [SchedulesConfigurations], from fileURL: URL? = nil) async throws {
        guard !definitions.isEmpty, !isUpdatingScheduleFile else { return }
        let target: URL
        if let fileURL {
            target = fileURL
        } else {
            guard let path = Homepath().fullpathmacserial else { throw CocoaError(.fileNoSuchFile) }
            target = URL(filePath: path).appending(path: SharedConstants().caldenarfilejson)
        }
        isUpdatingScheduleFile = true
        globaltimer.pauseTimer()
        do {
            let reloaded = try await WriteSchedule.deleteSeries(definitions, from: target)
            let deletedIDs = Set(definitions.map(\.id))
            globaltimer.notExecutedSchedulesafterWakeUp.removeAll { item in
                item.scheduledata.map { deletedIDs.contains($0.id) } ?? false
            }
            globaltimer.thereisnotexecutedschedulesafterwakeup = !globaltimer.notExecutedSchedulesafterWakeUp.isEmpty
            globaltimer.scheduledprofile = ""
            lastTriggeredURL = nil
            isUpdatingScheduleFile = false
            appendschdeuldatafromfile(reloaded)
        } catch {
            isUpdatingScheduleFile = false
            globaltimer.refreshTimerAfterScheduleMutation()
            throw error
        }
    }

    /// Delete by IndexSet
    func delete(_ uuids: Set<UUID>) {
        let definitionsToRemove = globaltimer.allSchedules.compactMap { schedule -> SchedulesConfigurations? in
            uuids.contains(schedule.id) ? schedule.scheduledata : nil
        }
        globaltimer.allSchedules.removeAll { occurrence in
            definitionsToRemove.contains { $0.id == occurrence.scheduledata?.id }
        }
        scheduleDefinitions.removeAll { definition in
            definitionsToRemove.contains(where: { $0.id == definition.id })
        }
        recomputeschedules()
    }

    private var schedulingHorizon: Date {
        if lastdateinnextmonth == nil {
            lastdateinnextmonth = computelastdateinnextmonth()
        }
        return lastdateinnextmonth ?? Date.now.endOfCurrentMonth
    }

    private func uniquedScheduleDefinitions(_ schedules: [SchedulesConfigurations]) -> [SchedulesConfigurations] {
        var result = [SchedulesConfigurations]()
        for schedule in schedules where result.contains(where: { sameScheduleDefinition($0, schedule) }) == false {
            result.append(schedule)
        }
        return result
    }

    private func sameScheduleDefinition(_ lhs: SchedulesConfigurations, _ rhs: SchedulesConfigurations) -> Bool {
        lhs.matchesDefinition(rhs)
    }
}
