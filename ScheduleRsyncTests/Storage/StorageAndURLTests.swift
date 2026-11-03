import Foundation
@testable import ScheduleRsync
import Testing

struct StorageAndURLTests {
    @Test("Default profile uses the supplied RsyncUI command")
    func defaultURL() throws {
        let url = try #require(ScheduleURL.make(profile: "Default"))
        #expect(url.absoluteString == "rsyncuiapp://loadprofileandestimate?profile=Default")
    }

    @Test("Profile names round-trip through URL query encoding", arguments: ["Work files", "Photos & Videos", "Økonomi", "A+B?#"])
    func encodedProfile(_ profile: String) throws {
        let url = try #require(ScheduleURL.make(profile: profile))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems == [URLQueryItem(name: "profile", value: profile)])
    }

    @Test("Existing RsyncUI schedules without identifiers remain readable and writable")
    func legacyScheduleStorage() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let legacy = Data(#"[{"dateRun":"01 Jan 2027 08:00","dateAdded":"27 Oct 2026 08:00","schedule":"daily"}]"#.utf8)
        let records = try JSONDecoder().decode([DecodeSchedules].self, from: legacy)
        let configuration = try SchedulesConfigurations(#require(records.first))
        #expect(configuration.profile == nil)
        let url = folder.appendingPathComponent("schedule.json")
        try await SharedJSONStorageWriter.shared.write([configuration], to: url)
        let reloaded = try await SharedJSONStorageReader.shared.decodeArray(DecodeSchedules.self, from: url)
        #expect(reloaded.first?.dateRun == "01 Jan 2027 08:00")
        #expect(reloaded.first?.schedule == "daily")
        #expect(reloaded.first?.profile == nil)
    }
}
