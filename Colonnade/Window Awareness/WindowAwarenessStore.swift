//
//  WindowAwarenessStore.swift
//  Colonnade
//
//  Atomic local persistence and schema migration for window awareness snapshots.
//

import Foundation

// MARK: - WindowAwarenessStoring

/// The persistence seam. The file adapter serializes access and never replaces a
/// readable snapshot with partially encoded or corrupt data.
protocol WindowAwarenessStoring: Sendable {
    func load() async throws -> WindowAwarenessSnapshot?
    func save(_ snapshot: WindowAwarenessSnapshot) async throws
}

// MARK: - AtomicFileWindowAwarenessStore

actor AtomicFileWindowAwarenessStore: WindowAwarenessStoring {
    private let fileManager: FileManager
    private let fileURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager

        self.decoder = JSONDecoder()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    func load() throws -> WindowAwarenessSnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            return try WindowAwarenessSnapshotMigrator.decodeAndMigrate(data, using: decoder)
        } catch let error as WindowAwarenessStoreError {
            throw error
        } catch {
            // Keep the original bytes in place for diagnosis or manual recovery.
            // A later save is therefore an explicit choice by the coordinator.
            throw WindowAwarenessStoreError.corruptData(
                fileURL: fileURL,
                description: String(describing: error)
            )
        }
    }

    func save(_ snapshot: WindowAwarenessSnapshot) throws {
        guard snapshot.schemaVersion == WindowAwarenessSnapshot.currentSchemaVersion else {
            throw WindowAwarenessStoreError.unsupportedSchemaVersion(snapshot.schemaVersion)
        }

        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw WindowAwarenessStoreError.writeFailed(
                fileURL: fileURL,
                description: String(describing: error)
            )
        }
    }
}

// MARK: - WindowAwarenessStoreError

enum WindowAwarenessStoreError: Error, Equatable {
    case corruptData(fileURL: URL, description: String)
    case unsupportedSchemaVersion(Int)
    case writeFailed(fileURL: URL, description: String)
}

// MARK: - WindowAwarenessSnapshotMigrator

enum WindowAwarenessSnapshotMigrator {
    static func decodeAndMigrate(
        _ data: Data,
        using decoder: JSONDecoder = JSONDecoder()
    ) throws -> WindowAwarenessSnapshot {
        let version = try decoder.decode(SchemaVersionProbe.self, from: data).schemaVersion

        switch version {
        case 0:
            return try migrate(decoder.decode(LegacySnapshotV0.self, from: data))
        case WindowAwarenessSnapshot.currentSchemaVersion:
            return try decoder.decode(WindowAwarenessSnapshot.self, from: data)
        default:
            throw WindowAwarenessStoreError.unsupportedSchemaVersion(version)
        }
    }

    private static func migrate(_ legacy: LegacySnapshotV0) throws -> WindowAwarenessSnapshot {
        let windows = try legacy.windows.enumerated().map { index, window in
            try ManagedWindowSnapshot(
                id: window.id,
                identity: window.identity,
                placement: NormalizedHorizontalPlacement(
                    normalizedX: window.normalizedX,
                    normalizedWidth: window.normalizedWidth
                ),
                relativeOrder: index
            )
        }

        let primaryTileID = legacy.primaryWindowIndex.flatMap { index in
            windows.indices.contains(index) ? windows[index].id : nil
        }
        if legacy.primaryWindowIndex != nil, primaryTileID == nil {
            throw SnapshotValidationError.primaryTileNotFound
        }

        return try WindowAwarenessSnapshot(
            id: legacy.id,
            capturedAt: legacy.capturedAt,
            display: legacy.display,
            windows: windows,
            primaryTileID: primaryTileID
        )
    }

    private struct SchemaVersionProbe: Decodable {
        let schemaVersion: Int
    }

    /// Version zero predates explicit full-height metadata and stored primary tiles by index.
    private struct LegacySnapshotV0: Decodable {
        let id: UUID
        let capturedAt: Date
        let display: DisplayIdentity
        let windows: [LegacyWindowV0]
        let primaryWindowIndex: Int?
    }

    private struct LegacyWindowV0: Decodable {
        let id: UUID
        let identity: PersistentWindowIdentity
        let normalizedX: Double
        let normalizedWidth: Double
    }
}
