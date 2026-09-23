//
//  SavedLayoutStore.swift
//  Colonnade
//
//  Atomic, per-account persistence for saved layouts and their privacy salt.
//

import Foundation
import Security

protocol SavedLayoutStoring: Sendable {
    func load() async throws -> SavedLayoutLibrary
    func save(_ library: SavedLayoutLibrary) async throws
}

actor AtomicFileSavedLayoutStore: SavedLayoutStoring {
    private let fileManager: FileManager
    private let fileURL: URL
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    func load() throws -> SavedLayoutLibrary {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return try SavedLayoutLibrary()
        }

        do {
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            return try SavedLayoutLibraryMigrator.decodeAndMigrate(data, using: decoder)
        } catch let error as SavedLayoutError {
            throw error
        } catch {
            throw SavedLayoutError.corruptData(String(describing: error))
        }
    }

    func save(_ library: SavedLayoutLibrary) throws {
        guard library.schemaVersion == SavedLayoutLibrary.currentSchemaVersion else {
            throw SavedLayoutError.unsupportedSchemaVersion(library.schemaVersion)
        }

        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(library).write(to: fileURL, options: .atomic)
        } catch {
            throw SavedLayoutError.writeFailed(String(describing: error))
        }
    }
}

enum SavedLayoutLibraryMigrator {
    static func decodeAndMigrate(
        _ data: Data,
        using decoder: JSONDecoder = JSONDecoder()
    ) throws -> SavedLayoutLibrary {
        let version = try decoder.decode(SchemaVersionProbe.self, from: data).schemaVersion
        switch version {
        case 0:
            let legacy = try decoder.decode(LegacyLibraryV0.self, from: data)
            return try SavedLayoutLibrary(
                work: legacy.work,
                focus: legacy.focus,
                macBook: legacy.macBook
            )
        case SavedLayoutLibrary.currentSchemaVersion:
            return try decoder.decode(SavedLayoutLibrary.self, from: data)
        default:
            throw SavedLayoutError.unsupportedSchemaVersion(version)
        }
    }

    private struct SchemaVersionProbe: Decodable {
        let schemaVersion: Int
    }

    private struct LegacyLibraryV0: Decodable {
        let work: [SavedLayoutVariant]
        let focus: [SavedLayoutVariant]
        let macBook: [SavedLayoutVariant]
    }
}

actor SavedLayoutPrivacySaltStore {
    private let fileManager: FileManager
    private let fileURL: URL

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func loadOrCreate() throws -> Data {
        if fileManager.fileExists(atPath: fileURL.path) {
            let salt = try Data(contentsOf: fileURL)
            guard salt.count >= 16 else {
                throw SnapshotValidationError.insufficientPrivacySalt
            }
            return salt
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw SavedLayoutError.writeFailed("Could not generate privacy salt")
        }

        let salt = Data(bytes)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try salt.write(to: fileURL, options: .atomic)
        return salt
    }
}

enum SavedLayoutSupportPaths {
    static func directory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.nielshop.Colonnade", isDirectory: true)
            .appendingPathComponent("Saved Layouts", isDirectory: true)
    }
}
