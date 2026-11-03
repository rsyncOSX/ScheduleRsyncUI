//
//  SharedJSONStorageReader.swift
//  RsyncUI
//

import Foundation
import OSLog

actor SharedJSONStorageReader {
    static let shared = SharedJSONStorageReader()

    private init() {}

    func decode<T: Decodable & Sendable>(_ type: T.Type, from fileURL: URL) async throws -> T {
        Logger.process.debugMessageOnly("SharedJSONStorageReader: reading from \(fileURL)")
        let data = try await Task.detached(priority: .utility) {
            try Data(contentsOf: fileURL)
        }.value
        return try await decode(type, from: data)
    }

    func decode<T: Decodable & Sendable>(_ type: T.Type, fromRemoteURL remoteURL: URL) async throws -> T {
        Logger.process.debugMessageOnly("SharedJSONStorageReader: reading from remote \(remoteURL)")
        let (data, _) = try await URLSession.shared.data(from: remoteURL)
        return try await decode(type, from: data)
    }

    func decodeArray<T: Decodable & Sendable>(_: T.Type, from fileURL: URL) async throws -> [T] {
        try await decode([T].self, from: fileURL)
    }

    func decodeArray<T: Decodable & Sendable>(_: T.Type, fromRemoteURL remoteURL: URL) async throws -> [T] {
        try await decode([T].self, fromRemoteURL: remoteURL)
    }

    private func decode<T: Decodable & Sendable>(_ type: T.Type, from data: Data) async throws -> T {
        try await Task.detached(priority: .utility) {
            try JSONDecoder().decode(type, from: data)
        }.value
    }
}
