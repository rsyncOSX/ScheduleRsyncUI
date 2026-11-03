import Foundation

struct CalendarWeekday: Identifiable {
    let id: Int
    let title: String
    let fullName: String
}

enum CalendarMonthLayout {
    static func monthStart(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func month(byAdding offset: Int, to date: Date, calendar: Calendar) -> Date {
        let start = monthStart(containing: date, calendar: calendar)
        return calendar.date(byAdding: .month, value: offset, to: start) ?? start
    }

    static func days(in month: Date, calendar: Calendar) -> [Date] {
        let start = monthStart(containing: month, calendar: calendar)
        let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        guard let first = calendar.date(byAdding: .day, value: -offset, to: start) else { return [] }
        // Six complete weeks keep every month aligned and prevent resizing on navigation.
        return (0 ..< 42).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    static func weekdays(calendar: Calendar) -> [CalendarWeekday] {
        (0 ..< 7).map { offset in
            let index = (calendar.firstWeekday - 1 + offset) % 7
            return CalendarWeekday(id: index + 1,
                                   title: calendar.shortStandaloneWeekdaySymbols[index],
                                   fullName: calendar.standaloneWeekdaySymbols[index])
        }
    }

    static func groupedOccurrences(_ items: [ScheduledItem], calendar: Calendar) -> [Date: [ScheduledItem]] {
        Dictionary(grouping: items, by: { calendar.startOfDay(for: $0.time) })
            .mapValues { $0.sorted { $0.time < $1.time } }
    }

    static func selecting(_ day: Date, keepingTimeFrom plannedDate: Date, calendar: Calendar, now: Date) -> Date {
        let time = calendar.dateComponents([.hour, .minute], from: plannedDate)
        let selected = calendar.date(bySettingHour: time.hour ?? 8, minute: time.minute ?? 0, second: 0, of: day) ?? day
        return calendar.isDate(day, inSameDayAs: now) && selected <= now ? now.addingTimeInterval(300) : selected
    }
}
