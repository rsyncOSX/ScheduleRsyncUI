import AppKit
import Foundation
import Observation

// MARK: - Types

struct ScheduledItem: Identifiable, Hashable {
    let id: UUID
    var time: Date
    var requestedTime: Date
    var skipReason: String?
    var isAdjusted: Bool { time != requestedTime }
    private let callbackWrapper: CallbackWrapper
    var scheduledata: SchedulesConfigurations?

    private class CallbackWrapper: Hashable {
        let callback: () -> Void
        init(_ callback: @escaping () -> Void) {
            self.callback = callback
        }

        static func == (lhs: CallbackWrapper, rhs: CallbackWrapper) -> Bool {
            lhs === rhs
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(self))
        }
    }

    init(time: Date, callback: @escaping () -> Void, scheduledata: SchedulesConfigurations?) {
        id = UUID()
        self.time = time
        requestedTime = time
        callbackWrapper = CallbackWrapper(callback)
        self.scheduledata = scheduledata
    }

    /// Execute the wrapped callback
    func execute() {
        callbackWrapper.callback()
    }

    /// Hashable and Equatable based on id only
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ScheduledItem, rhs: ScheduledItem) -> Bool {
        lhs.id == rhs.id
    }
}

@Observable
@MainActor
final class GlobalTimer {
    // The existing facade name is retained for callers; scheduling uses a cancellable Task.
    @MainActor static let shared = GlobalTimer()

    /// Exposed Array of not executed Schedule
    var allSchedules = [ScheduledItem]()
    var skippedSchedules = [ScheduledItem]()
    var displayedSchedules: [ScheduledItem] {
        (allSchedules + skippedSchedules).sorted { $0.time < $1.time }
    }
    var minimumGapMinutes: Int { SchedulePlanner.savedGapMinutes }
    var planningHorizon: Date = .distantFuture

    /// Retained for manually requeued legacy items; wake catch-up is now automatic.
    var notExecutedSchedulesafterWakeUp: [ScheduledItem] = []

    // MARK: - Properties

    /// First schedule to execute
    var firstscheduledate: SchedulesConfigurations?
    /// Trigger execution
    var scheduledprofile: String = ""
    /// Trigger for not executed tasks after wakeup
    var thereisnotexecutedschedulesafterwakeup: Bool = false
    private(set) var lastSleepDelayNotice: String?
    private(set) var lastTriggerDate: Date?

    @ObservationIgnored
    private var runner: Task<Void, Never>?
    @ObservationIgnored
    private var runnerGeneration = UUID()
    @ObservationIgnored
    private var isProcessingDueSchedules = false
    private(set) var isSleeping = false
    private(set) var isStopped = false

    @ObservationIgnored
    private var isPaused = false
    @ObservationIgnored
    private var needsWakeValidation = false
    @ObservationIgnored
    private var handledOccurrences: Set<OccurrenceKey> = []

    private struct OccurrenceKey: Hashable {
        let definitionID: UUID
        let time: Date
    }

    var canRun: Bool { !isSleeping && !isStopped && !isPaused }
    @ObservationIgnored
    private var isCollectingSchedules = false
    @ObservationIgnored
    private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored
    private var clockObserver: NSObjectProtocol?

    // MARK: - Initialization

    init(observeSystemEvents: Bool = true) {
        if observeSystemEvents { setupSystemNotifications() }
    }

    /// Terminal for this app session: late file reads, wake events, and callbacks cannot restart it.
    func shutdown() {
        isStopped = true
        invalidateAllSchedulesAndTimer()
        handledOccurrences.removeAll()
        notExecutedSchedulesafterWakeUp.removeAll()
        thereisnotexecutedschedulesafterwakeup = false
        firstscheduledate = nil
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        if let clockObserver {
            NotificationCenter.default.removeObserver(clockObserver)
            self.clockObserver = nil
        }
    }

    // MARK: - Public API

    private func validatescheduleinset(_ schedule: ScheduledItem) -> Bool {
        allSchedules.contains { item in
            item.time == schedule.time &&
                item.scheduledata?.profile == schedule.scheduledata?.profile &&
                item.scheduledata?.schedule == schedule.scheduledata?.schedule &&
                item.scheduledata?.id == schedule.scheduledata?.id
        }
    }

    /// Check whether the pending runner already targets an earlier occurrence.
    private func validateallschedulesalreadyintimer(_ schedule: ScheduledItem) -> Bool {
        allSchedules.contains(where: { $0.time < schedule.time })
    }

    func timerIsActive() -> Bool {
        runner != nil
    }

    func nextScheduleDate(format: Date.FormatStyle = .dateTime) -> String? {
        let earliest = allSchedules.min(by: { $0.time < $1.time })
        return earliest?.time.formatted(format)
    }

    func pauseTimer() {
        isPaused = true
        cancelRunner()
    }

    private func cancelRunner() {
        runnerGeneration = UUID()
        runner?.cancel()
        runner = nil
    }

    func invalidateAllSchedulesAndTimer() {
        cancelRunner()
        isPaused = false
        allSchedules.removeAll()
    }

    /// Generate recurring occurrences without sorting and rearming for every item.
    func replaceSchedules(_ build: () -> Void) {
        guard !isStopped else { return }
        invalidateAllSchedulesAndTimer()
        isCollectingSchedules = true
        build()
        applyPlan(at: .now)
        isCollectingSchedules = false
        refreshTimerAfterScheduleMutation()
    }

    func applyPlan(at now: Date) {
        let retainedSkipped = skippedSchedules.filter { $0.requestedTime > now }
        let plan = SchedulePlanner.plan(allSchedules, now: now, horizon: planningHorizon,
                                        gapMinutes: minimumGapMinutes,
                                        lastTrigger: lastTriggerDate, quietPeriod: .saved)
        allSchedules = plan.filter { $0.skipReason == nil }
        skippedSchedules = retainedSkipped + plan.filter { $0.skipReason != nil }
    }

    func refreshTimerAfterScheduleMutation() {
        guard !isStopped, !isProcessingDueSchedules else { return }
        isPaused = false
        if allSchedules.isEmpty {
            invalidateAllSchedulesAndTimer()
            firstscheduledate = nil
        } else {
            allSchedules = allSchedules.sorted(by: { $0.time < $1.time })
            setfirsscheduledate()
            scheduleNextTimer()
        }
    }

    /// Schedule a task to run at a specific time
    /// - Parameters:
    ///   - time: Target execution time
    ///   - callback: Closure to execute when due (use [weak self] to avoid retain cycles)
    ///   - scheduledata: Optional configuration data for the schedule
    func addSchedule(
        time: Date,
        callback: @escaping () -> Void,
        scheduledata: SchedulesConfigurations?
    ) {
        guard !isStopped else { return }
        if let scheduledata,
           handledOccurrences.contains(OccurrenceKey(definitionID: scheduledata.id, time: time)) { return }

        let scheduleitem = ScheduledItem(
            time: time,
            callback: callback,
            scheduledata: scheduledata
        )

        if isCollectingSchedules {
            allSchedules.append(scheduleitem)
            return
        }
        guard validatescheduleinset(scheduleitem) == false else { return }
        allSchedules.append(scheduleitem)
        allSchedules = allSchedules.sorted(by: { $0.time < $1.time })

        if validateallschedulesalreadyintimer(scheduleitem) == false {
            scheduleNextTimer()
        }
    }

    func scheduleNextTimer() {
        cancelRunner()
        guard canRun, !isProcessingDueSchedules, let item = allSchedules.first else { return }

        let generation = runnerGeneration
        // Bound the wait so wall-clock adjustments are also noticed without a notification.
        // Waiting suspends a task; no thread or external process is kept running.
        let delay = max(0, min(30, item.time.timeIntervalSinceNow))
        runner = Task { @concurrent [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(100))
                try Task.checkCancellation()
            } catch { return }
            await self?.runnerDidWake(generation: generation)
        }
    }

    private func runnerDidWake(generation: UUID) {
        guard generation == runnerGeneration, canRun else { return }
        processDueSchedules()
    }

    /// Only set when loading data, when new schedules added or deleted
    func setfirsscheduledate() {
        firstscheduledate = allSchedules.min(by: { $0.time < $1.time })?.scheduledata
    }

    /// Remove the whole due batch before callbacks can mutate or rearm the queue.
    /// After sleep, coalesce overdue repeats to one trigger per saved definition.
    func processDueSchedules(at now: Date = .now, coalescing: Bool = true) {
        guard canRun, !isProcessingDueSchedules else { return }
        cancelRunner()
        let due = allSchedules.filter { $0.time <= now }.sorted { $0.time < $1.time }
        let validatingWake = needsWakeValidation
        needsWakeValidation = false
        if validatingWake, !due.isEmpty {
            lastSleepDelayNotice = "Missed runs are coalesced per series and automatically spaced after waking."
        }
        if !due.isEmpty {
            // Replan late delivery too: actual starts must obey the same spacing as planned starts.
            var latest: [UUID: Date] = [:]
            for item in due {
                if let id = item.scheduledata?.id { latest[id] = max(latest[id] ?? .distantPast, item.requestedTime) }
            }
            allSchedules.removeAll { item in
                guard item.time <= now, let id = item.scheduledata?.id else { return false }
                if item.requestedTime != latest[id] {
                    handledOccurrences.insert(OccurrenceKey(definitionID: id, time: item.requestedTime))
                    return true
                }
                return false
            }
            applyPlan(at: now)
        }
        let executable = allSchedules.filter { $0.time <= now }
        allSchedules.removeAll { $0.time <= now }
        isProcessingDueSchedules = true
        var triggeredDefinitions: Set<UUID> = []
        for item in executable {
            guard !isStopped else { break }
            if let data = item.scheduledata {
                let key = OccurrenceKey(definitionID: data.id, time: item.requestedTime)
                guard handledOccurrences.insert(key).inserted else { continue }
            }
            // Consume skipped occurrences too, so rebuilding cannot replay them later.
            if coalescing, let definitionID = item.scheduledata?.id,
               !triggeredDefinitions.insert(definitionID).inserted { continue }
            lastTriggerDate = now
            item.execute()
        }
        isProcessingDueSchedules = false
        refreshTimerAfterScheduleMutation()
    }

    // MARK: - Sleep and clock changes

    /// Reports whether the configured global gap remains before the next run.
    /// A run due exactly at wake takes priority over postponed work.
    func canRunPostponedSchedule(at now: Date = .now) -> Bool {
        guard let next = allSchedules.filter({ $0.time >= now }).map(\.time).min() else { return true }
        return next.timeIntervalSince(now) >= Double(minimumGapMinutes) * 60
    }

    private func setupSystemNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // The notification is delivered on the main queue; handle it synchronously
            // so a queued deadline callback cannot get ahead of the sleep transition.
            MainActor.assumeIsolated { self?.handleSleep() }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleWake() }
        })
        clockObserver = NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.processDueSchedules() }
        }
    }

    func handleSleep() {
        guard !isStopped else { return }
        isSleeping = true
        cancelRunner()
    }

    func handleWake(at now: Date = .now) {
        guard !isStopped else { return }
        // Keep the check pending if a file update has temporarily paused delivery.
        needsWakeValidation = needsWakeValidation || isSleeping
        isSleeping = false
        processDueSchedules(at: now, coalescing: true)
    }

}

extension GlobalTimer {
    // FIX: `scheduledata` is a struct, so mutations on a local `var newItem`
    // copy were previously lost. The fix uses an index-based in-place update
    // via a helper mutating function on ScheduledItem, ensuring the new time
    // and dateRun string are actually stored in the array element.
    func moveToSchedules(itemIDs: [ScheduledItem.ID]) {
        guard !isStopped else { return }
        var itemsToMove = notExecutedSchedulesafterWakeUp.filter { itemIDs.contains($0.id) }
        notExecutedSchedulesafterWakeUp.removeAll { itemIDs.contains($0.id) }

        // Requeued legacy items use the same planner.
        for index in itemsToMove.indices {
            let newTime = Date.now.addingTimeInterval(TimeInterval(index + 1) * Double(minimumGapMinutes) * 60)
            itemsToMove[index].time = newTime
            itemsToMove[index].scheduledata?.dateRun = newTime.en_string_from_date()
        }

        allSchedules.append(contentsOf: itemsToMove)
        applyPlan(at: .now)
        refreshTimerAfterScheduleMutation()
        thereisnotexecutedschedulesafterwakeup = notExecutedSchedulesafterWakeUp.isEmpty == false
    }
}
