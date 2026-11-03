import Foundation
@testable import ScheduleRsync
import Testing

@MainActor
struct GlobalTimerTests {
    @Test("Simultaneous starts are delivered once and spaced")
    func dueBatch() {
        let runner = GlobalTimer(observeSystemEvents: false)
        defer { runner.shutdown() }
        let start = Date.now.addingTimeInterval(3600)
        var calls = 0
        for profile in ["A", "B"] {
            runner.addSchedule(time: start, callback: { calls += 1 }, scheduledata: definition(profile))
        }
        runner.processDueSchedules(at: start)
        runner.processDueSchedules(at: start)
        #expect(calls == 1)
        #expect(runner.allSchedules.count == 1)
        runner.processDueSchedules(at: start.addingTimeInterval(Double(runner.minimumGapMinutes) * 60))
        #expect(calls == 2)
    }

    @Test("Wake coalesces missed repeats and spaces different profiles")
    func sleepAndWake() {
        let runner = GlobalTimer(observeSystemEvents: false)
        defer { runner.shutdown() }
        let start = Date.now.addingTimeInterval(3600)
        let series = definition("Repeat")
        var calls = 0
        for offset in [0.0, 3600, 7200] {
            runner.addSchedule(time: start.addingTimeInterval(offset), callback: { calls += 1 }, scheduledata: series)
        }
        runner.addSchedule(time: start.addingTimeInterval(3600), callback: { calls += 1 }, scheduledata: definition("Other"))
        runner.handleSleep()
        let wake = start.addingTimeInterval(4000)
        runner.handleWake(at: wake)
        #expect(calls == 1)
        #expect(runner.lastSleepDelayNotice != nil)
        runner.processDueSchedules(at: wake.addingTimeInterval(Double(runner.minimumGapMinutes) * 60))
        #expect(calls == 2)
        #expect(runner.allSchedules.count == 1)
    }

    @Test("Shutdown clears waiting work and prevents late wake, reload, and refresh from restarting it")
    func shutdownIsTerminal() {
        let runner = GlobalTimer(observeSystemEvents: false)
        let date = Date.now.addingTimeInterval(3600)
        var count = 0
        runner.addSchedule(time: date, callback: { count += 1 }, scheduledata: nil)
        #expect(runner.timerIsActive())
        runner.shutdown()
        runner.handleWake(at: date)
        runner.addSchedule(time: date, callback: { count += 1 }, scheduledata: nil)
        runner.replaceSchedules {
            runner.addSchedule(time: date, callback: { count += 1 }, scheduledata: nil)
        }
        runner.refreshTimerAfterScheduleMutation()
        runner.processDueSchedules(at: date)
        runner.shutdown()
        #expect(count == 0)
        #expect(runner.allSchedules.isEmpty)
        #expect(!runner.timerIsActive())
        #expect(!runner.canRun)
    }

    @Test("A shutdown inside a callback prevents remaining callbacks in the same batch")
    func shutdownDuringDelivery() {
        let runner = GlobalTimer(observeSystemEvents: false)
        let date = Date.now.addingTimeInterval(3600)
        var count = 0
        runner.addSchedule(time: date, callback: {
            count += 1
            runner.shutdown()
        }, scheduledata: nil)
        runner.addSchedule(time: date.addingTimeInterval(1), callback: { count += 1 }, scheduledata: nil)
        runner.processDueSchedules(at: date.addingTimeInterval(2))
        #expect(count == 1)
        #expect(!runner.timerIsActive())
    }

    @Test("Wake and clock reconciliation respect a pause during an asynchronous file update")
    func pausedUpdate() {
        let runner = GlobalTimer(observeSystemEvents: false)
        defer { runner.shutdown() }
        let date = Date.now.addingTimeInterval(3600)
        var count = 0
        runner.addSchedule(time: date, callback: { count += 1 }, scheduledata: nil)
        runner.pauseTimer()
        runner.handleSleep()
        runner.handleWake(at: date)
        runner.processDueSchedules(at: date)
        #expect(count == 0)
        #expect(!runner.timerIsActive())
        runner.refreshTimerAfterScheduleMutation()
        runner.processDueSchedules(at: date)
        #expect(count == 1)
    }

    @Test("Rebuilding after a backward clock change cannot replay a handled occurrence")
    func rebuildDoesNotReplay() {
        let runner = GlobalTimer(observeSystemEvents: false)
        defer { runner.shutdown() }
        let date = Date.now.addingTimeInterval(3600)
        let series = definition("Work")
        var count = 0
        runner.addSchedule(time: date, callback: { count += 1 }, scheduledata: series)
        runner.processDueSchedules(at: date)
        runner.replaceSchedules {
            runner.addSchedule(time: date, callback: { count += 1 }, scheduledata: series)
            runner.addSchedule(time: date.addingTimeInterval(60), callback: { count += 1 }, scheduledata: series)
        }
        runner.processDueSchedules(at: date.addingTimeInterval(-60))
        #expect(count == 1)
        #expect(runner.allSchedules.count == 1)
        runner.processDueSchedules(at: date.addingTimeInterval(30 * 60))
        #expect(count == 2)
    }

    @Test("Replacing a pending queue removes the original trigger")
    func replacePendingQueue() {
        let runner = GlobalTimer(observeSystemEvents: false)
        defer { runner.shutdown() }
        let date = Date.now.addingTimeInterval(3600)
        var calls: [String] = []
        runner.addSchedule(time: date, callback: { calls.append("Old") }, scheduledata: nil)
        runner.replaceSchedules {
            runner.addSchedule(time: date, callback: { calls.append("New") }, scheduledata: nil)
        }
        runner.processDueSchedules(at: date)
        #expect(calls == ["New"])
    }

    @Test("The asynchronous runner delivers a due callback and can stop itself", .timeLimit(.minutes(1)))
    func actualRunnerDelivery() async {
        let runner = GlobalTimer(observeSystemEvents: false)
        defer { runner.shutdown() }
        await withCheckedContinuation { continuation in
            runner.addSchedule(time: .now, callback: {
                runner.shutdown()
                continuation.resume()
            }, scheduledata: nil)
        }
        #expect(runner.isStopped)
        #expect(!runner.timerIsActive())
    }

    private func definition(_ profile: String) -> SchedulesConfigurations {
        SchedulesConfigurations(profile: profile, dateAdded: nil, dateRun: nil, schedule: "repeat",
                                repeatIntervalMinutes: 60)
    }
}
