import Foundation

/// Fixed elapsed-time intervals, anchored to the original start rather than app launch.
enum RepeatSchedule {
    static let minimumMinutes = 30

    static func isValid(minutes: Int?) -> Bool {
        guard let minutes else { return false }
        return minutes >= minimumMinutes
    }

    static func occurrences(start: Date, everyMinutes minutes: Int, after now: Date, through horizon: Date) -> [Date] {
        guard isValid(minutes: minutes),
              start.timeIntervalSince1970.isFinite,
              now.timeIntervalSince1970.isFinite,
              horizon.timeIntervalSince1970.isFinite,
              horizon > now else { return [] }
        let interval = Double(minutes) * 60
        var index = start > now ? 0 : floor(now.timeIntervalSince(start) / interval) + 1
        var occurrence = start.addingTimeInterval(index * interval)
        var result: [Date] = []
        while occurrence <= horizon {
            result.append(occurrence)
            index += 1
            let next = start.addingTimeInterval(index * interval)
            guard next > occurrence else { break }
            occurrence = next
        }
        return result
    }
}
