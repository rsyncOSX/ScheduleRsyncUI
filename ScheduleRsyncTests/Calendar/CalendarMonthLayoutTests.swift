import Foundation
@testable import ScheduleRsync
import Testing

struct MonthCase: Sendable {
    let year: Int
    let month: Int
    let firstWeekday: Int
    let zone: String

    static let all: [MonthCase] = [2000, 2024, 2025, 2026, 2027, 2100].flatMap { year in
        (1 ... 12).flatMap { month in
            [1, 2, 7].flatMap { weekday in
                ["Europe/Oslo", "America/Los_Angeles"].map {
                    MonthCase(year: year, month: month, firstWeekday: weekday, zone: $0)
                }
            }
        }
    }
}

struct CalendarMonthLayoutTests {
    @Test("Month grids contain every day exactly once and align with weekday headers", arguments: MonthCase.all)
    func monthGrid(_ sample: MonthCase) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: sample.zone))
        calendar.firstWeekday = sample.firstWeekday
        let date = try #require(calendar.date(from: DateComponents(year: sample.year, month: sample.month, day: 15)))
        let grid = CalendarMonthLayout.days(in: date, calendar: calendar)
        let monthDays = grid.filter { calendar.isDate($0, equalTo: date, toGranularity: .month) }
        let expected = try #require(calendar.range(of: .day, in: .month, for: date))
        #expect(grid.count == 42)
        #expect(Set(grid).count == 42)
        #expect(monthDays.map { calendar.component(.day, from: $0) } == Array(expected))
        #expect(try calendar.component(.weekday, from: #require(grid.first)) == sample.firstWeekday)
        let headers = CalendarMonthLayout.weekdays(calendar: calendar)
        #expect(headers.map(\.id) == grid.prefix(7).map { calendar.component(.weekday, from: $0) })
        for (first, second) in zip(grid, grid.dropFirst()) {
            #expect(calendar.date(byAdding: .day, value: 1, to: first) == second)
        }
    }

    @Test("Month navigation from the 31st does not skip or drift through February")
    func monthNavigation() throws {
        let calendar = Calendar(identifier: .gregorian)
        let january = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 31)))
        let february = CalendarMonthLayout.month(byAdding: 1, to: january, calendar: calendar)
        let march = CalendarMonthLayout.month(byAdding: 1, to: february, calendar: calendar)
        #expect(calendar.component(.month, from: february) == 2)
        #expect(calendar.component(.day, from: february) == 1)
        #expect(calendar.component(.month, from: march) == 3)
        #expect(calendar.component(.day, from: march) == 1)
        let december = CalendarMonthLayout.month(byAdding: -1, to: january, calendar: calendar)
        #expect(calendar.component(.year, from: december) == 2026)
        #expect(calendar.component(.month, from: december) == 12)
    }

    @Test("Today and multiple profile runs are grouped by the full local date")
    func occurrenceMarkers() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Oslo"))
        let day = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 7)))
        let nextYear = try #require(calendar.date(byAdding: .year, value: 1, to: day))
        let first = ScheduledItem(time: day.addingTimeInterval(3600), callback: {}, scheduledata: nil)
        let second = ScheduledItem(time: day.addingTimeInterval(7200), callback: {}, scheduledata: nil)
        let third = ScheduledItem(time: nextYear, callback: {}, scheduledata: nil)
        let grouped = CalendarMonthLayout.groupedOccurrences([second, third, first], calendar: calendar)
        #expect(grouped[day]?.map(\.id) == [first.id, second.id])
        #expect(grouped[nextYear]?.count == 1)
    }

    @Test("Selecting a day keeps its year and time, while today never defaults to a past time")
    func selectingDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 7, hour: 16)))
        let morning = try #require(calendar.date(bySettingHour: 8, minute: 30, second: 0, of: now))
        let today = CalendarMonthLayout.selecting(now, keepingTimeFrom: morning, calendar: calendar, now: now)
        #expect(today > now)
        let nextYear = try #require(calendar.date(byAdding: .year, value: 1, to: now))
        let selected = CalendarMonthLayout.selecting(nextYear, keepingTimeFrom: morning, calendar: calendar, now: now)
        #expect(calendar.component(.year, from: selected) == 2028)
        #expect(calendar.component(.hour, from: selected) == 8)
        #expect(calendar.component(.minute, from: selected) == 30)
    }
}
