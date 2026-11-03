//
//  SchedulesConfigurations.swift
//  Calendar
//
//  Created by Thomas Evensen on 25/03/2025.
//

import Foundation

enum ScheduleType: String, CaseIterable, Identifiable, CustomStringConvertible {
    case once
    case daily
    case weekly
    case repeating = "repeat"

    var id: String {
        rawValue
    }

    var description: String {
        rawValue.localizedCapitalized
    }
}

struct SchedulesConfigurations: Identifiable, Codable {
    var id = UUID()
    var profile: String?
    var dateAdded: String?
    var dateRun: String?
    var schedule: String?
    var repeatIntervalMinutes: Int?
    var repeatStartTimestamp: TimeInterval?

    init(_ data: DecodeSchedules) {
        id = data.id ?? UUID()
        dateRun = data.dateRun
        dateAdded = data.dateAdded
        schedule = data.schedule
        profile = data.profile
        repeatIntervalMinutes = data.repeatIntervalMinutes
        repeatStartTimestamp = data.repeatStartTimestamp
    }

    init(id: UUID = UUID(), profile: String?, dateAdded: String?, dateRun: String?, schedule: String?,
         repeatIntervalMinutes: Int? = nil, repeatStartTimestamp: TimeInterval? = nil) {
        self.id = id
        self.profile = profile
        self.dateAdded = dateAdded
        self.dateRun = dateRun
        self.schedule = schedule
        self.repeatIntervalMinutes = repeatIntervalMinutes
        self.repeatStartTimestamp = repeatStartTimestamp
    }

    /// Legacy files may lack IDs; their original definition fields identify the series.
    func matchesDefinition(_ other: SchedulesConfigurations) -> Bool {
        profile == other.profile && dateRun == other.dateRun && schedule == other.schedule
            && repeatIntervalMinutes == other.repeatIntervalMinutes
            && repeatStartTimestamp == other.repeatStartTimestamp
    }

    var scheduleDescription: String {
        if schedule == ScheduleType.repeating.rawValue, let repeatIntervalMinutes {
            return "Every \(repeatIntervalMinutes) min"
        }
        return ScheduleType(rawValue: schedule ?? "")?.description ?? schedule ?? ""
    }
}

extension SchedulesConfigurations: Hashable, Equatable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(profile)
        hasher.combine(dateRun)
        hasher.combine(dateAdded)
        hasher.combine(id)
        hasher.combine(schedule)
        hasher.combine(repeatIntervalMinutes)
        hasher.combine(repeatStartTimestamp)
    }
}

struct DecodeSchedules: Codable {
    let id: UUID?
    let dateRun: String?
    let dateAdded: String?
    let schedule: String?
    let profile: String?
    let repeatIntervalMinutes: Int?
    let repeatStartTimestamp: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case id
        case dateRun
        case dateAdded
        case schedule
        case profile
        case repeatIntervalMinutes
        case repeatStartTimestamp
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id)
        dateRun = try values.decodeIfPresent(String.self, forKey: .dateRun)
        dateAdded = try values.decodeIfPresent(String.self, forKey: .dateAdded)
        schedule = try values.decodeIfPresent(String.self, forKey: .schedule)
        profile = try values.decodeIfPresent(String.self, forKey: .profile)
        repeatIntervalMinutes = try values.decodeIfPresent(Int.self, forKey: .repeatIntervalMinutes)
        repeatStartTimestamp = try values.decodeIfPresent(TimeInterval.self, forKey: .repeatStartTimestamp)
    }
}
