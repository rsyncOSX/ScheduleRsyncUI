import Foundation

/// Builds a bounded queue from immutable requested times. Skipped rows never reserve a slot.
enum SchedulePlanner {
    struct QuietPeriod {
        static let enabledKey = "scheduleQuietPeriodEnabled"
        static let startKey = "scheduleQuietPeriodStartMinutes"
        static let endKey = "scheduleQuietPeriodEndMinutes"

        var enabled = true
        var startMinutes = 23 * 60
        var endMinutes = 7 * 60

        static var saved: QuietPeriod {
            let defaults = UserDefaults.standard
            return QuietPeriod(
                enabled: defaults.object(forKey: enabledKey) as? Bool ?? true,
                startMinutes: min(1439, max(0, defaults.object(forKey: startKey) as? Int ?? 23 * 60)),
                endMinutes: min(1439, max(0, defaults.object(forKey: endKey) as? Int ?? 7 * 60)))
        }

        /// The start is inclusive and the end exclusive. Equal times mean no quiet period.
        func nextAllowedTime(_ date: Date, calendar: Calendar) -> Date {
            guard enabled, startMinutes != endMinutes else { return date }
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            let isQuiet = startMinutes < endMinutes
                ? minute >= startMinutes && minute < endMinutes
                : minute >= startMinutes || minute < endMinutes
            guard isQuiet else { return date }
            // Calendar matching respects local time and daylight-saving transitions.
            return calendar.nextDate(after: date,
                                     matching: DateComponents(hour: endMinutes / 60, minute: endMinutes % 60, second: 0),
                                     matchingPolicy: .nextTime, repeatedTimePolicy: .first) ?? date
        }
    }

    static let gapKey = "minimumScheduleGapMinutes"
    static var savedGapMinutes: Int {
        let value = UserDefaults.standard.object(forKey: gapKey) as? Int ?? 15
        return min(1440, max(1, value))
    }

    static func plan(_ items: [ScheduledItem], now: Date, horizon: Date, gapMinutes: Int,
                     lastTrigger: Date? = nil, quietPeriod: QuietPeriod = QuietPeriod(enabled: false),
                     calendar: Calendar = .current) -> [ScheduledItem] {
        let sorted = items.sorted {
            if $0.requestedTime != $1.requestedTime { return $0.requestedTime < $1.requestedTime }
            let left = ($0.scheduledata?.profile ?? "Default") + ($0.scheduledata?.scheduleDescription ?? "")
            let right = ($1.scheduledata?.profile ?? "Default") + ($1.scheduledata?.scheduleDescription ?? "")
            if left != right { return left < right }
            return ($0.scheduledata?.id.uuidString ?? $0.id.uuidString) < ($1.scheduledata?.id.uuidString ?? $1.id.uuidString)
        }
        var nextBySeries: [UUID: Date] = [:]
        var deadlines: [UUID: Date] = [:]
        for item in sorted.reversed() {
            guard let id = item.scheduledata?.id else { continue }
            if let next = nextBySeries[id] { deadlines[item.id] = next }
            nextBySeries[id] = item.requestedTime
        }
        var previous = lastTrigger
        return sorted.map { original in
            var item = original
            item.skipReason = nil
            var time = max(item.requestedTime, now)
            if let previous { time = max(time, previous.addingTimeInterval(Double(gapMinutes) * 60)) }
            time = quietPeriod.nextAllowedTime(time, calendar: calendar)
            var deadline = deadlines[item.id]
            if let minutes = item.scheduledata?.repeatIntervalMinutes {
                deadline = item.requestedTime.addingTimeInterval(Double(minutes) * 60)
            }
            if time > horizon {
                item.skipReason = "Skipped: no space before the end of next month."
            } else if let deadline, time >= deadline {
                item.skipReason = "Skipped: adjustment would reach the next occurrence in this series."
            }
            if item.skipReason == nil {
                item.time = time
                item.scheduledata?.dateRun = time.en_string_from_date()
                previous = time
            }
            return item
        }
    }
}
