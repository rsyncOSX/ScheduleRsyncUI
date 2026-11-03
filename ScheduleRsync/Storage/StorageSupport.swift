import Foundation
import Observation
import OSLog

@Observable @MainActor
final class StorageStatus {
    static let shared = StorageStatus()
    var message: String?
}

@MainActor
struct Homepath {
    var fullpathmacserial: String? {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".rsyncosx", isDirectory: true)
            .appendingPathComponent(Macserialnumber().getMacSerialNumber(), isDirectory: true).path
    }

    func profiles() -> [String] {
        guard let path = fullpathmacserial else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).filter {
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path + "/" + $0, isDirectory: &directory) && directory.boolValue
        }.sorted()
    }

    func propagateError(error: Error) {
        StorageStatus.shared.message = error.localizedDescription
    }
}

struct SharedConstants {
    let caldenarfilejson = "schedule.json"
}

actor SharedJSONStorageWriter {
    static let shared = SharedJSONStorageWriter()
    func write(_ value: some Encodable & Sendable, to fileURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Keep read-modify-write-reload on the same actor as regular saves.
    func deleteSeries(_ definitions: [SchedulesConfigurations], from fileURL: URL) throws -> [SchedulesConfigurations] {
        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode([DecodeSchedules].self, from: data)
        guard let records = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              records.count == decoded.count else { throw CocoaError(.fileReadCorruptFile) }
        let ids = Set(definitions.map(\.id))
        let remaining = zip(records, decoded).filter { _, record in
            if let id = record.id {
                return !ids.contains(id)
            }
            return !definitions.contains { $0.matchesDefinition(SchedulesConfigurations(record)) }
        }.map(\.0)
        // Preserve all fields on unrelated records, including any unknown to this version.
        let updatedData = try JSONSerialization.data(withJSONObject: remaining, options: [.prettyPrinted, .sortedKeys])
        try updatedData.write(to: fileURL, options: .atomic)
        let reloadedData = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([DecodeSchedules].self, from: reloadedData).map(SchedulesConfigurations.init)
    }
}

extension Logger {
    static let process = Logger(subsystem: "ScheduleRsync", category: "scheduler")
    func debugMessageOnly(_ message: String) {
        debug("\(message)")
    }

    func debugThreadOnly(_ message: String) {
        debug("\(message)")
    }

    func errorMessageOnly(_ message: String) {
        error("\(message)")
    }
}

enum ScheduleURL {
    static func make(profile: String) -> URL? {
        var components = URLComponents()
        components.scheme = "rsyncuiapp"
        components.host = "loadprofileandestimate"
        components.queryItems = [URLQueryItem(name: "profile", value: profile)]
        return components.url
    }
}
