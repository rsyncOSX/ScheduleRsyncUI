import Foundation
@testable import ScheduleRsync
import Testing

struct SchedulePlannerTests {
    let start = Date(timeIntervalSince1970: 1_900_000_000)

    private func item(_ profile: String, offset: Int = 0, series: UUID = UUID(), repeatMinutes: Int? = nil) -> ScheduledItem {
        ScheduledItem(time: start.addingTimeInterval(Double(offset) * 60), callback: {},
                      scheduledata: SchedulesConfigurations(id: series, profile: profile, dateAdded: nil,
                        dateRun: nil, schedule: repeatMinutes == nil ? "once" : "repeat", repeatIntervalMinutes: repeatMinutes))
    }

    @Test("Global gap applies to every profile", arguments: [5, 15, 45])
    func spacing(gap: Int) {
        let rows = [item("A"), item("B", offset: 1), item("A", offset: 2)]
        let plan = SchedulePlanner.plan(rows, now: start, horizon: start.addingTimeInterval(86400), gapMinutes: gap)
        #expect(plan[1].time == start.addingTimeInterval(Double(gap) * 60))
        #expect(plan[2].time == start.addingTimeInterval(Double(gap * 2) * 60))
        #expect(plan[1].isAdjusted)
    }

    @Test("Impossible repeats are informative and do not consume capacity")
    func overload() {
        let rows = [item("A"), item("B", offset: 1, repeatMinutes: 30), item("C", offset: 2)]
        let plan = SchedulePlanner.plan(rows, now: start, horizon: start.addingTimeInterval(86400), gapMinutes: 45)
        #expect(plan[1].skipReason != nil)
        #expect(plan[2].skipReason == nil)
        #expect(plan[2].time == start.addingTimeInterval(45 * 60))
    }

    @Test("The horizon is strict and replanning preserves requested times")
    func horizonAndRebuild() {
        let rows = [item("A"), item("B", offset: 1)]
        let horizon = start.addingTimeInterval(10 * 60)
        let plan = SchedulePlanner.plan(rows, now: start, horizon: horizon, gapMinutes: 15)
        #expect(plan[1].skipReason != nil)
        let expanded = SchedulePlanner.plan(plan, now: start, horizon: start.addingTimeInterval(3600), gapMinutes: 15)
        #expect(expanded[1].skipReason == nil)
        #expect(expanded[1].requestedTime == rows[1].requestedTime)
        #expect(expanded[1].time == start.addingTimeInterval(15 * 60))
    }

    @Test("Recent actual starts restrict the rebuilt queue")
    func triggerHistory() {
        let plan = SchedulePlanner.plan([item("A")], now: start, horizon: start.addingTimeInterval(86400),
                                        gapMinutes: 15, lastTrigger: start)
        #expect(plan[0].time == start.addingTimeInterval(15 * 60))
    }
}

struct QuietPeriodTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 30) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test("Overnight quiet period includes its start and excludes its end", arguments: [0, 6, 7, 22, 23])
    func overnight(hour: Int) {
        let input = date(hour)
        let expected = hour < 7 ? date(7) : hour >= 23 ? date(7, day: 31) : input
        #expect(SchedulePlanner.QuietPeriod().nextAllowedTime(input, calendar: calendar) == expected)
    }

    @Test("Daytime, disabled, and equal-endpoint periods")
    func variants() {
        let period = SchedulePlanner.QuietPeriod(startMinutes: 9 * 60, endMinutes: 17 * 60)
        #expect(period.nextAllowedTime(date(12), calendar: calendar) == date(17))
        #expect(period.nextAllowedTime(date(18), calendar: calendar) == date(18))
        #expect(SchedulePlanner.QuietPeriod(enabled: false).nextAllowedTime(date(23), calendar: calendar) == date(23))
        #expect(SchedulePlanner.QuietPeriod(startMinutes: 0, endMinutes: 0)
            .nextAllowedTime(date(12), calendar: calendar) == date(12))
    }

    @Test("Spacing into quiet hours defers work and respects series deadlines")
    func planning() {
        func item(_ hour: Int, _ minute: Int, repeatMinutes: Int? = nil) -> ScheduledItem {
            ScheduledItem(time: date(hour, minute), callback: {},
                          scheduledata: SchedulesConfigurations(profile: "A", dateAdded: nil, dateRun: nil,
                              schedule: repeatMinutes == nil ? "once" : "repeat", repeatIntervalMinutes: repeatMinutes))
        }
        let rows = [item(22, 55), item(22, 56, repeatMinutes: 60), item(22, 57), item(23, 0)]
        let plan = SchedulePlanner.plan(rows, now: date(22), horizon: date(12, day: 31), gapMinutes: 15,
                                        quietPeriod: .init(), calendar: calendar)
        #expect(plan[0].time == date(22, 55))
        #expect(plan[1].skipReason != nil)
        #expect(plan[2].time == date(7, day: 31))
        #expect(plan[3].time == date(7, 15, day: 31))
        #expect(plan[2].requestedTime == rows[2].requestedTime)
    }

    @Test("Quiet-period end follows the local clock across daylight saving")
    func daylightSaving() {
        let input = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 23))!
        let expected = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 7))!
        #expect(SchedulePlanner.QuietPeriod().nextAllowedTime(input, calendar: calendar) == expected)
        #expect(expected.timeIntervalSince(input) == 9 * 3600)
    }
}
