import Foundation
@testable import ScheduleRsync
import Testing

struct RepeatScheduleTests {
    @Test("Repeat intervals below thirty minutes are rejected", arguments: [nil, -1, 0, 1, 29] as [Int?])
    func invalidInterval(_ minutes: Int?) {
        #expect(!RepeatSchedule.isValid(minutes: minutes))
    }

    @Test("Whole-minute intervals of at least thirty minutes are accepted", arguments: [30, 31, 60, 61, 90, 120, 1440])
    func validInterval(_ minutes: Int) {
        #expect(RepeatSchedule.isValid(minutes: minutes))
    }

    @Test("The start is included and every occurrence stays anchored to its interval", arguments: [60, 90, 120])
    func anchoredIntervals(_ minutes: Int) {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let interval = Double(minutes) * 60
        let times = RepeatSchedule.occurrences(start: start, everyMinutes: minutes,
                                               after: start.addingTimeInterval(-1),
                                               through: start.addingTimeInterval(interval * 6))
        #expect(times == (0 ... 6).map { start.addingTimeInterval(Double($0) * interval) })
    }

    @Test("Restarting skips elapsed occurrences without shifting the original start")
    func restartAlignment() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let now = start.addingTimeInterval(110 * 60)
        let times = RepeatSchedule.occurrences(start: start, everyMinutes: 90, after: now,
                                               through: start.addingTimeInterval(360 * 60))
        #expect(times == [180, 270, 360].map { start.addingTimeInterval(Double($0) * 60) })
        let afterExactRun = RepeatSchedule.occurrences(start: start, everyMinutes: 90,
                                                       after: start.addingTimeInterval(180 * 60),
                                                       through: start.addingTimeInterval(360 * 60))
        #expect(afterExactRun.first == start.addingTimeInterval(270 * 60))
    }

    @Test("Hourly intervals remain sixty elapsed minutes across daylight-saving changes", arguments: [3, 10])
    func daylightSaving(_ month: Int) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Oslo"))
        let start = try #require(calendar.date(from: DateComponents(year: 2027, month: month,
                                                                    day: month == 3 ? 28 : 31, hour: 0, minute: 30)))
        let times = RepeatSchedule.occurrences(start: start, everyMinutes: 60,
                                               after: start.addingTimeInterval(-1), through: start.addingTimeInterval(5 * 3600))
        #expect(times.count == 6)
        #expect(zip(times, times.dropFirst()).allSatisfy { $1.timeIntervalSince($0) == 3600 })
        #expect(times.filter { calendar.component(.hour, from: $0) == 2 }.count == (month == 3 ? 0 : 2))
    }

    @Test("An old start jumps directly to future runs and very large intervals remain safe")
    func oldStartAndLargeInterval() {
        let start = Date(timeIntervalSince1970: 0)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let times = RepeatSchedule.occurrences(start: start, everyMinutes: 60, after: now,
                                               through: now.addingTimeInterval(86400))
        #expect(times.count == 24)
        #expect(times.allSatisfy { $0 > now && $0.timeIntervalSince(start).truncatingRemainder(dividingBy: 3600) == 0 })
        #expect(RepeatSchedule.occurrences(start: now.addingTimeInterval(60), everyMinutes: Int.max,
                                           after: now, through: now.addingTimeInterval(86400)) == [now.addingTimeInterval(60)])
        #expect(RepeatSchedule.occurrences(start: now, everyMinutes: 29, after: now,
                                           through: now.addingTimeInterval(86400)).isEmpty)
    }

    @Test("Repeat interval and exact start survive the schedule JSON round-trip")
    func persistence() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let original = SchedulesConfigurations(profile: "Work", dateAdded: nil, dateRun: start.en_string_from_date(),
                                               schedule: "repeat", repeatIntervalMinutes: 90,
                                               repeatStartTimestamp: start.timeIntervalSince1970)
        let data = try JSONEncoder().encode([original])
        let decoded = try #require(JSONDecoder().decode([DecodeSchedules].self, from: data).first)
        let restored = SchedulesConfigurations(decoded)
        #expect(restored.repeatIntervalMinutes == 90)
        #expect(restored.repeatStartTimestamp == start.timeIntervalSince1970)
        #expect(restored.dateRun == original.dateRun)
        #expect(restored.scheduleDescription == "Every 90 min")
        let legacy = try JSONDecoder().decode([DecodeSchedules].self, from: Data(#"[{"dateRun":"01 Jan 2027 08:00","schedule":"daily"}]"#.utf8))
        #expect(legacy.first?.repeatIntervalMinutes == nil)
        #expect(legacy.first?.repeatStartTimestamp == nil)
    }
}
