//
//  ObservableSchedulesTests.swift
//  RsyncUITests
//

import Foundation
@testable import ScheduleRsync
import Testing

@MainActor
@Suite(.serialized)
struct ObservableSchedulesTests {
    @Test("Deleting earliest schedule reschedules to next earliest")
    func deletingEarliestScheduleReschedulesTimer() throws {
        let schedules = makeCleanSchedules()
        let first = try #require(Calendar.current.date(byAdding: .minute, value: 90, to: Date.now))
        let second = try #require(Calendar.current.date(byAdding: .minute, value: 150, to: Date.now))

        #expect(schedules.appendSchedule(profile: nil, dateRun: first.en_string_from_date(), schedule: ScheduleType.once.rawValue))
        #expect(schedules.appendSchedule(profile: "Work", dateRun: second.en_string_from_date(), schedule: ScheduleType.once.rawValue))

        let firstID = try #require(GlobalTimer.shared.allSchedules.first?.id)
        schedules.delete([firstID])

        #expect(GlobalTimer.shared.allSchedules.count == 1)
        #expect(GlobalTimer.shared.timerIsActive())
        #expect(GlobalTimer.shared.firstscheduledate?.profile == "Work")
        #expect(GlobalTimer.shared.firstscheduledate?.dateRun == second.en_string_from_date())
    }

    @Test("Deleting only schedule clears first schedule and timer")
    func deletingOnlyScheduleClearsTimer() throws {
        let schedules = makeCleanSchedules()
        let runDate = try #require(Calendar.current.date(byAdding: .minute, value: 90, to: Date.now))

        #expect(schedules.appendSchedule(profile: nil, dateRun: runDate.en_string_from_date(), schedule: ScheduleType.once.rawValue))

        let onlyID = try #require(GlobalTimer.shared.allSchedules.first?.id)
        schedules.delete([onlyID])

        #expect(GlobalTimer.shared.allSchedules.isEmpty)
        #expect(GlobalTimer.shared.firstscheduledate == nil)
        #expect(GlobalTimer.shared.timerIsActive() == false)
    }

    @Test("Daily and weekly schedule definitions do not duplicate when recomputed or reloaded")
    func repeatingSchedulesDoNotDuplicate() throws {
        let schedules = makeCleanSchedules()
        let daily = try #require(Calendar.current.date(byAdding: .day, value: 1, to: Date.now))
        let weekly = try #require(Calendar.current.date(byAdding: .day, value: 7, to: Date.now.addingTimeInterval(3600)))

        #expect(schedules.appendSchedule(profile: nil, dateRun: daily.en_string_from_date(), schedule: ScheduleType.daily.rawValue))
        #expect(schedules.appendSchedule(profile: "Work",
                                         dateRun: weekly.en_string_from_date(),
                                         schedule: ScheduleType.weekly.rawValue))

        let firstExpansionCount = GlobalTimer.shared.allSchedules.count
        let persistedDefinitions = schedules.scheduleDataForPersistence()

        schedules.recomputeschedules()
        #expect(GlobalTimer.shared.allSchedules.count == firstExpansionCount)
        #expect(schedules.scheduleDataForPersistence().count == 2)

        let reloadedSchedules = makeCleanSchedules()
        reloadedSchedules.appendschdeuldatafromfile(persistedDefinitions)

        #expect(GlobalTimer.shared.allSchedules.count == firstExpansionCount)
        #expect(reloadedSchedules.scheduleDataForPersistence().count == 2)
    }

    @Test("Date horizon uses full dates across December and January")
    func scheduleHorizonCrossesYearBoundary() throws {
        let schedules = makeCleanSchedules()
        let decemberRun = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 8, minute: 0)))
        let januaryHorizon = try #require(
            Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 31, hour: 23, minute: 59))
        )

        schedules.lastdateinnextmonth = januaryHorizon
        schedules.appendschdeuldatafromfile([
            SchedulesConfigurations(profile: nil,
                                    dateAdded: Date.now.en_string_from_date(),
                                    dateRun: decemberRun.en_string_from_date(),
                                    schedule: ScheduleType.daily.rawValue)
        ])

        #expect(GlobalTimer.shared.allSchedules.contains { item in
            item.scheduledata?.dateRun == "01 Jan 2027 08:00"
        })
    }

    @Test("Invalid and beyond-horizon schedule strings are rejected")
    func invalidAndBeyondHorizonSchedulesAreRejected() throws {
        let schedules = makeCleanSchedules()
        let beyondHorizon = try #require(
            Calendar.current.date(byAdding: .day, value: 1, to: schedules.computelastdateinnextmonth() ?? Date.now)
        )

        #expect(schedules.validPlannedScheduleDate("not a date") == nil)
        #expect(schedules.verifynextschedule(plannednextschedule: "not a date") == false)
        #expect(schedules.validPlannedScheduleDate(beyondHorizon.en_string_from_date()) == nil)
        #expect(schedules.appendSchedule(profile: nil,
                                         dateRun: beyondHorizon.en_string_from_date(),
                                         schedule: ScheduleType.once.rawValue) == false)
    }

    @Test("Validation follows edited planned run value")
    func validationUsesPlannedRunValue() throws {
        let schedules = makeCleanSchedules()
        let validRun = try #require(Calendar.current.date(byAdding: .minute, value: 90, to: Date.now))
        let invalidRun = try #require(Calendar.current.date(byAdding: .minute, value: -30, to: Date.now))

        #expect(schedules.validPlannedScheduleDate(validRun.en_string_from_date()) != nil)
        #expect(schedules.verifynextschedule(plannednextschedule: validRun.en_string_from_date()))
        #expect(schedules.validPlannedScheduleDate(invalidRun.en_string_from_date()) == nil)
        #expect(schedules.appendSchedule(profile: nil, dateRun: validRun.en_string_from_date(), schedule: ScheduleType.once.rawValue))
    }

    @Test("Browsing does not expand the two-month horizon")
    func browsingPreservesSchedules() throws {
        let schedules = makeCleanSchedules()
        let horizon = schedules.computelastdateinnextmonth()
        let distant = try #require(Calendar.current.date(byAdding: .month, value: 4, to: .now))
        schedules.ensureSchedulingHorizon(through: distant)
        #expect(schedules.lastdateinnextmonth == horizon)
        #expect(!schedules.appendSchedule(profile: "Work", dateRun: distant.en_string_from_date(), schedule: "once"))
        let definition = SchedulesConfigurations(profile: "Work", dateAdded: nil, dateRun: distant.en_string_from_date(), schedule: "daily")
        schedules.appendschdeuldatafromfile([definition])
        #expect(schedules.scheduleDataForPersistence().count == 1)
        #expect(GlobalTimer.shared.allSchedules.isEmpty)
    }

    @Test("Repeat definitions validate intervals, rebuild without duplicates, reload, and delete as a series")
    func repeatDefinitions() throws {
        defer { GlobalTimer.shared.invalidateAllSchedulesAndTimer() }
        let schedules = makeCleanSchedules()
        let start = Date.now.addingTimeInterval(3600).en_string_from_date()
        #expect(!schedules.appendSchedule(profile: nil, dateRun: start, schedule: "repeat"))
        #expect(!schedules.appendSchedule(profile: nil, dateRun: start, schedule: "repeat", repeatIntervalMinutes: 29))
        #expect(schedules.appendSchedule(profile: nil, dateRun: start, schedule: "repeat", repeatIntervalMinutes: 90))
        #expect(!schedules.appendSchedule(profile: nil, dateRun: start, schedule: "repeat", repeatIntervalMinutes: 90))
        #expect(schedules.appendSchedule(profile: "Work", dateRun: start.en_date_from_string().addingTimeInterval(1800).en_string_from_date(), schedule: "repeat", repeatIntervalMinutes: 180))
        let definitions = schedules.scheduleDataForPersistence()
        let count = GlobalTimer.shared.allSchedules.count
        #expect(count > 2)
        schedules.recomputeschedules()
        #expect(GlobalTimer.shared.allSchedules.count == count)
        let reloaded = makeCleanSchedules()
        reloaded.appendschdeuldatafromfile(definitions)
        #expect(reloaded.scheduleDataForPersistence().count == 2)
        #expect(GlobalTimer.shared.allSchedules.count == count)
        let series = GlobalTimer.shared.displayedSchedules.filter { $0.scheduledata?.repeatIntervalMinutes == 90 }
            .sorted { $0.requestedTime < $1.requestedTime }
        #expect(series.first?.requestedTime == start.en_date_from_string())
        #expect(zip(series, series.dropFirst()).allSatisfy { $1.requestedTime.timeIntervalSince($0.requestedTime) == 90 * 60 })
        let first = try #require(GlobalTimer.shared.allSchedules.first { $0.scheduledata?.repeatIntervalMinutes == 90 })
        reloaded.delete([first.id])
        #expect(reloaded.scheduleDataForPersistence().count == 1)
        #expect(GlobalTimer.shared.allSchedules.allSatisfy { $0.scheduledata?.repeatIntervalMinutes == 180 })
    }

    @Test("A loaded repeat schedule skips elapsed runs and ignores invalid saved intervals")
    func reloadRepeatFromPast() throws {
        defer { GlobalTimer.shared.invalidateAllSchedulesAndTimer() }
        let schedules = makeCleanSchedules()
        let start = Date.now.addingTimeInterval(-3 * 3600).en_string_from_date().en_date_from_string()
        let definition = SchedulesConfigurations(profile: nil, dateAdded: nil,
                                                 dateRun: start.en_string_from_date(), schedule: "repeat",
                                                 repeatIntervalMinutes: 90, repeatStartTimestamp: start.timeIntervalSince1970)
        let invalid = SchedulesConfigurations(profile: "Invalid", dateAdded: nil,
                                              dateRun: start.en_string_from_date(), schedule: "repeat", repeatIntervalMinutes: 29)
        schedules.appendschdeuldatafromfile([definition, invalid])
        #expect(schedules.scheduleDataForPersistence().count == 1)
        let first = try #require(GlobalTimer.shared.allSchedules.first)
        #expect(first.time > .now)
        #expect(first.time.timeIntervalSince(start).truncatingRemainder(dividingBy: 90 * 60) == 0)
        #expect(CalendarMonthLayout.groupedOccurrences(GlobalTimer.shared.allSchedules, calendar: .current)
            .values.contains { $0.count > 1 })
        GlobalTimer.shared.allSchedules.removeFirst()
        first.execute()
        #expect(schedules.lastTriggeredURL == ScheduleURL.make(profile: "Default"))
        #expect(schedules.lastExecutedScheduleText?.contains("Test trigger delivered") == true)
        #expect(GlobalTimer.shared.allSchedules.first?.time == first.time.addingTimeInterval(90 * 60))
    }

    @Test("Repeat timer queues preserve both instants when a local hour occurs twice")
    func repeatTimerAtFallBack() throws {
        defer { GlobalTimer.shared.invalidateAllSchedulesAndTimer() }
        let schedules = makeCleanSchedules()
        let start = try #require(ISO8601DateFormatter().date(from: "2027-10-30T22:30:00Z"))
        schedules.lastdateinnextmonth = start.addingTimeInterval(5 * 3600)
        schedules.appendschdeuldatafromfile([
            SchedulesConfigurations(profile: nil, dateAdded: nil, dateRun: start.en_string_from_date(),
                                    schedule: "repeat", repeatIntervalMinutes: 60,
                                    repeatStartTimestamp: start.timeIntervalSince1970)
        ])
        let times = GlobalTimer.shared.displayedSchedules.map(\.requestedTime).sorted()
        #expect(times == (0 ... 5).map { start.addingTimeInterval(Double($0) * 3600) })
        #expect(Set(times).count == 6)
    }

    @Test("Deleting one selected repeat occurrence removes the saved series and resets the tracker")
    func deleteSavedSeries() async throws {
        defer { GlobalTimer.shared.invalidateAllSchedulesAndTimer() }
        let url = try temporaryScheduleURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let schedules = makeCleanSchedules()
        let start = Date.now.addingTimeInterval(3600).en_string_from_date()
        #expect(schedules.appendSchedule(profile: nil, dateRun: start, schedule: "repeat", repeatIntervalMinutes: 90))
        try await SharedJSONStorageWriter.shared.write(schedules.scheduleDataForPersistence(), to: url)
        let first = try #require(GlobalTimer.shared.allSchedules.first)
        let second = try #require(GlobalTimer.shared.allSchedules.dropFirst().first)
        let definitions = schedules.definitions(for: [first.id, second.id])
        #expect(definitions.count == 1)
        first.execute()
        #expect(schedules.lastTriggeredURL != nil)
        GlobalTimer.shared.notExecutedSchedulesafterWakeUp = [first]
        GlobalTimer.shared.thereisnotexecutedschedulesafterwakeup = true
        GlobalTimer.shared.scheduledprofile = "Default"

        try await schedules.deleteSeries(definitions, from: url)

        let stored = try JSONDecoder().decode([DecodeSchedules].self, from: Data(contentsOf: url))
        #expect(stored.isEmpty)
        #expect(schedules.scheduleDataForPersistence().isEmpty)
        #expect(GlobalTimer.shared.allSchedules.isEmpty)
        #expect(GlobalTimer.shared.notExecutedSchedulesafterWakeUp.isEmpty)
        #expect(GlobalTimer.shared.firstscheduledate == nil)
        #expect(!GlobalTimer.shared.timerIsActive())
        #expect(GlobalTimer.shared.scheduledprofile.isEmpty)
        #expect(!GlobalTimer.shared.thereisnotexecutedschedulesafterwakeup)
        #expect(schedules.lastTriggeredURL == nil)
        #expect(!schedules.isUpdatingScheduleFile)
    }

    @Test("Series deletion rereads the file and preserves unrelated records and unknown fields")
    func deletePreservesOtherRecords() async throws {
        defer { GlobalTimer.shared.invalidateAllSchedulesAndTimer() }
        let url = try temporaryScheduleURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let schedules = makeCleanSchedules()
        #expect(schedules.appendSchedule(profile: "Delete", dateRun: Date.now.addingTimeInterval(3600).en_string_from_date(),
                                         schedule: "repeat", repeatIntervalMinutes: 60))
        #expect(schedules.appendSchedule(profile: "Keep", dateRun: Date.now.addingTimeInterval(5400).en_string_from_date(),
                                         schedule: "repeat", repeatIntervalMinutes: 120))
        let original = schedules.scheduleDataForPersistence()
        let target = try #require(original.first(where: { $0.profile == "Delete" }))
        let kept = try #require(original.first(where: { $0.profile == "Keep" }))
        let external = SchedulesConfigurations(profile: "Added externally", dateAdded: nil,
                                               dateRun: Date.now.addingTimeInterval(2700).en_string_from_date(), schedule: "once")
        let encoded = try JSONEncoder().encode(original + [external])
        var records = try #require(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        records[2]["customNote"] = "preserve this field"
        try JSONSerialization.data(withJSONObject: records).write(to: url, options: .atomic)

        try await schedules.deleteSeries([target], from: url)

        let reloaded = schedules.scheduleDataForPersistence()
        #expect(Set(reloaded.map(\.id)) == [kept.id, external.id])
        #expect(GlobalTimer.shared.allSchedules.allSatisfy { $0.scheduledata?.id != target.id })
        #expect(GlobalTimer.shared.firstscheduledate?.profile == "Added externally")
        #expect(GlobalTimer.shared.timerIsActive())
        let saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        #expect(saved.count == 2)
        #expect(saved.first(where: { $0["profile"] as? String == "Added externally" })?["customNote"] as? String == "preserve this field")
    }

    @Test("A file error leaves the saved data and existing series intact and rearms the tracker")
    func deleteFileFailure() async throws {
        defer { GlobalTimer.shared.invalidateAllSchedulesAndTimer() }
        let url = try temporaryScheduleURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let schedules = makeCleanSchedules()
        #expect(schedules.appendSchedule(profile: nil, dateRun: Date.now.addingTimeInterval(3600).en_string_from_date(),
                                         schedule: "repeat", repeatIntervalMinutes: 90))
        let definitions = schedules.scheduleDataForPersistence()
        let count = GlobalTimer.shared.allSchedules.count
        let corrupt = Data("invalid JSON".utf8)
        try corrupt.write(to: url)
        await #expect(throws: (any Error).self) {
            try await schedules.deleteSeries(definitions, from: url)
        }
        #expect(try Data(contentsOf: url) == corrupt)
        #expect(schedules.scheduleDataForPersistence() == definitions)
        #expect(GlobalTimer.shared.allSchedules.count == count)
        #expect(GlobalTimer.shared.timerIsActive())
        #expect(!schedules.isUpdatingScheduleFile)
    }

    @Test("Deleting an ID-less legacy series matches its definition and preserves other legacy records")
    func deleteLegacySeries() async throws {
        defer { GlobalTimer.shared.invalidateAllSchedulesAndTimer() }
        let url = try temporaryScheduleURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let run = Date.now.addingTimeInterval(3600).en_string_from_date()
        let records: [[String: Any]] = [
            ["profile": "Delete legacy", "dateRun": run, "schedule": "daily"],
            ["profile": "Keep legacy", "dateRun": run, "schedule": "weekly", "customNote": "untouched"]
        ]
        try JSONSerialization.data(withJSONObject: records).write(to: url)
        let decoded = try JSONDecoder().decode([DecodeSchedules].self, from: Data(contentsOf: url))
        let schedules = makeCleanSchedules()
        schedules.appendschdeuldatafromfile(decoded.map(SchedulesConfigurations.init))
        let target = try #require(schedules.scheduleDataForPersistence().first(where: { $0.profile == "Delete legacy" }))

        try await schedules.deleteSeries([target], from: url)

        let stored = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        #expect(stored.count == 1)
        #expect(stored.first?["profile"] as? String == "Keep legacy")
        #expect(stored.first?["customNote"] as? String == "untouched")
        #expect(stored.first?["id"] == nil)
        #expect(schedules.scheduleDataForPersistence().map(\.profile) == ["Keep legacy"])
        #expect(GlobalTimer.shared.firstscheduledate?.profile == "Keep legacy")
    }

    @Test("Conflicting additions are accepted and automatically spaced")
    func automaticSpacing() throws {
        let schedules = makeCleanSchedules()
        let time = Date.now.addingTimeInterval(3600).en_string_from_date()
        #expect(schedules.appendSchedule(profile: "A", dateRun: time, schedule: "once"))
        #expect(schedules.appendSchedule(profile: "B", dateRun: time, schedule: "once"))
        let rows = GlobalTimer.shared.allSchedules
        #expect(rows.count == 2)
        #expect(rows[1].time.timeIntervalSince(rows[0].time) == Double(SchedulePlanner.savedGapMinutes) * 60)
        #expect(rows[1].isAdjusted)
        let before = rows.map(\.time)
        schedules.recomputeschedules()
        #expect(GlobalTimer.shared.allSchedules.map(\.time) == before)
    }

    private func temporaryScheduleURL() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "schedule.json")
    }

    private func makeCleanSchedules() -> ObservableSchedules {
        GlobalTimer.shared.invalidateAllSchedulesAndTimer()
        GlobalTimer.shared.firstscheduledate = nil
        GlobalTimer.shared.scheduledprofile = ""
        GlobalTimer.shared.notExecutedSchedulesafterWakeUp.removeAll()
        GlobalTimer.shared.thereisnotexecutedschedulesafterwakeup = false
        let schedules = ObservableSchedules()
        schedules.lastdateinnextmonth = schedules.computelastdateinnextmonth()
        return schedules
    }
}
