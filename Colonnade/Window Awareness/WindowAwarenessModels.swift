//
//  WindowAwarenessModels.swift
//  Colonnade
//
//  Persistent, privacy-conscious descriptions of Loop-managed windows.
//

import CryptoKit
import Foundation

// MARK: - WindowAwarenessSnapshot

/// A versioned, display-scoped description of Loop's horizontal window arrangement.
///
/// The snapshot intentionally contains no process or WindowServer identifiers. Those
/// identifiers only live in ``RuntimeWindowBinding`` while Loop is running.
struct WindowAwarenessSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    let capturedAt: Date
    let display: DisplayIdentity
    let windows: [ManagedWindowSnapshot]
    let primaryTileID: UUID?

    init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        display: DisplayIdentity,
        windows: [ManagedWindowSnapshot],
        primaryTileID: UUID?
    ) throws {
        try self.init(
            schemaVersion: Self.currentSchemaVersion,
            id: id,
            capturedAt: capturedAt,
            display: display,
            windows: windows,
            primaryTileID: primaryTileID
        )
    }

    private init(
        schemaVersion: Int,
        id: UUID,
        capturedAt: Date,
        display: DisplayIdentity,
        windows: [ManagedWindowSnapshot],
        primaryTileID: UUID?
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw SnapshotValidationError.unsupportedSchemaVersion(schemaVersion)
        }

        let tileIDs = windows.map(\.id)
        guard Set(tileIDs).count == tileIDs.count else {
            throw SnapshotValidationError.duplicateTileID
        }

        let relativeOrders = windows.map(\.relativeOrder)
        guard Set(relativeOrders).count == relativeOrders.count,
              Set(relativeOrders) == Set(windows.indices)
        else {
            throw SnapshotValidationError.invalidRelativeOrder
        }

        if let primaryTileID, !tileIDs.contains(primaryTileID) {
            throw SnapshotValidationError.primaryTileNotFound
        }

        self.schemaVersion = schemaVersion
        self.id = id
        self.capturedAt = capturedAt
        self.display = display
        self.windows = windows.sorted { $0.relativeOrder < $1.relativeOrder }
        self.primaryTileID = primaryTileID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            id: container.decode(UUID.self, forKey: .id),
            capturedAt: container.decode(Date.self, forKey: .capturedAt),
            display: container.decode(DisplayIdentity.self, forKey: .display),
            windows: container.decode([ManagedWindowSnapshot].self, forKey: .windows),
            primaryTileID: container.decodeIfPresent(UUID.self, forKey: .primaryTileID)
        )
    }
}

// MARK: - ManagedWindowSnapshot

/// One full-height tile in a snapshot.
struct ManagedWindowSnapshot: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let identity: PersistentWindowIdentity
    let placement: NormalizedHorizontalPlacement
    let relativeOrder: Int

    init(
        id: UUID = UUID(),
        identity: PersistentWindowIdentity,
        placement: NormalizedHorizontalPlacement,
        relativeOrder: Int
    ) throws {
        guard relativeOrder >= 0 else {
            throw SnapshotValidationError.invalidRelativeOrder
        }

        self.id = id
        self.identity = identity
        self.placement = placement
        self.relativeOrder = relativeOrder
    }
}

// MARK: - NormalizedHorizontalPlacement

/// A display-relative horizontal frame whose vertical extent is always the full visible frame.
///
/// `normalizedX` and `normalizedWidth` use the display's usable horizontal range, so a
/// snapshot can be reconciled after resolution or scale changes without encoding pixels.
struct NormalizedHorizontalPlacement: Codable, Equatable, Sendable {
    enum FullHeightReference: String, Codable, Sendable {
        case displayVisibleFrame
    }

    let normalizedX: Double
    let normalizedWidth: Double
    let fullHeightReference: FullHeightReference

    init(normalizedX: Double, normalizedWidth: Double) throws {
        guard normalizedX.isFinite, normalizedWidth.isFinite,
              normalizedX >= 0, normalizedWidth > 0,
              normalizedX <= 1, normalizedX + normalizedWidth <= 1.000_001
        else {
            throw SnapshotValidationError.invalidHorizontalPlacement
        }

        self.normalizedX = normalizedX
        self.normalizedWidth = min(normalizedWidth, 1 - normalizedX)
        self.fullHeightReference = .displayVisibleFrame
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fullHeightReference = try container.decode(FullHeightReference.self, forKey: .fullHeightReference)
        guard fullHeightReference == .displayVisibleFrame else {
            throw SnapshotValidationError.invalidFullHeightInvariant
        }

        try self.init(
            normalizedX: container.decode(Double.self, forKey: .normalizedX),
            normalizedWidth: container.decode(Double.self, forKey: .normalizedWidth)
        )
    }
}

// MARK: - PersistentWindowIdentity

/// Privacy-conscious signals that can survive app and Loop restarts.
///
/// Title, document, and Accessibility values must be salted and hashed before they
/// enter this type. Position and ordinal values are hints, never durable identifiers.
struct PersistentWindowIdentity: Codable, Equatable, Sendable {
    let bundleIdentifier: String
    let titleOrDocumentHint: PrivateWindowHint?
    let stableAccessibilityHint: PrivateWindowHint?
    let role: String?
    let subrole: String?
    let ordinalHint: Int?
    let frameHint: NormalizedHorizontalPlacement?

    init(
        bundleIdentifier: String,
        titleOrDocumentHint: PrivateWindowHint? = nil,
        stableAccessibilityHint: PrivateWindowHint? = nil,
        role: String? = nil,
        subrole: String? = nil,
        ordinalHint: Int? = nil,
        frameHint: NormalizedHorizontalPlacement? = nil
    ) throws {
        let bundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleIdentifier.isEmpty, ordinalHint.map({ $0 >= 0 }) ?? true else {
            throw SnapshotValidationError.invalidWindowIdentity
        }

        self.bundleIdentifier = bundleIdentifier
        self.titleOrDocumentHint = titleOrDocumentHint
        self.stableAccessibilityHint = stableAccessibilityHint
        self.role = role
        self.subrole = subrole
        self.ordinalHint = ordinalHint
        self.frameHint = frameHint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            bundleIdentifier: container.decode(String.self, forKey: .bundleIdentifier),
            titleOrDocumentHint: container.decodeIfPresent(PrivateWindowHint.self, forKey: .titleOrDocumentHint),
            stableAccessibilityHint: container.decodeIfPresent(PrivateWindowHint.self, forKey: .stableAccessibilityHint),
            role: container.decodeIfPresent(String.self, forKey: .role),
            subrole: container.decodeIfPresent(String.self, forKey: .subrole),
            ordinalHint: container.decodeIfPresent(Int.self, forKey: .ordinalHint),
            frameHint: container.decodeIfPresent(NormalizedHorizontalPlacement.self, forKey: .frameHint)
        )
    }
}

// MARK: - PrivateWindowHint

/// A salted SHA-256 digest of a title, document URL, or stable Accessibility value.
/// Raw user content cannot be initialized into the persistent schema accidentally.
struct PrivateWindowHint: Codable, Equatable, Hashable, Sendable {
    private static let algorithm = "sha256-salted-v1"

    let digest: String

    init(rawValue: String, salt: Data) throws {
        guard salt.count >= 16 else {
            throw SnapshotValidationError.insufficientPrivacySalt
        }

        var input = salt
        input.append(contentsOf: rawValue.utf8)
        self.digest = SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    private enum CodingKeys: String, CodingKey {
        case algorithm
        case digest
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let algorithm = try container.decode(String.self, forKey: .algorithm)
        let digest = try container.decode(String.self, forKey: .digest)
        guard algorithm == Self.algorithm,
              digest.count == 64,
              digest.allSatisfy(\.isHexDigit)
        else {
            throw SnapshotValidationError.invalidPrivateWindowHint
        }
        self.digest = digest.lowercased()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.algorithm, forKey: .algorithm)
        try container.encode(digest, forKey: .digest)
    }
}

// MARK: - DisplayIdentity

/// A persistent display identity. UUID is authoritative when both sides have one;
/// otherwise the deterministic hardware/configuration fingerprint is the fallback.
struct DisplayIdentity: Codable, Equatable, Hashable, Sendable {
    let uuid: UUID?
    let fingerprint: DisplayFingerprint

    init(uuid: UUID?, configuration: DisplayConfiguration) {
        self.uuid = uuid
        self.fingerprint = DisplayFingerprint(configuration: configuration)
    }
}

/// Non-sensitive display characteristics used to create a deterministic fallback.
struct DisplayConfiguration: Codable, Equatable, Hashable, Sendable {
    let vendorID: UInt32
    let modelID: UInt32
    let serialNumber: UInt32
    let pixelWidth: Int
    let pixelHeight: Int
    let physicalWidthMillimeters: Int
    let physicalHeightMillimeters: Int
    let isBuiltin: Bool
}

/// An opaque deterministic digest of ``DisplayConfiguration``.
struct DisplayFingerprint: Codable, Equatable, Hashable, Sendable {
    let value: String

    init(configuration: DisplayConfiguration) {
        let canonicalValue = [
            "vendor=\(configuration.vendorID)",
            "model=\(configuration.modelID)",
            "serial=\(configuration.serialNumber)",
            "pixels=\(configuration.pixelWidth)x\(configuration.pixelHeight)",
            "millimeters=\(configuration.physicalWidthMillimeters)x\(configuration.physicalHeightMillimeters)",
            "builtin=\(configuration.isBuiltin ? 1 : 0)"
        ].joined(separator: "|")

        self.value = SHA256.hash(data: Data(canonicalValue.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decode(String.self, forKey: .value)
        guard value.count == 64, value.allSatisfy(\.isHexDigit) else {
            throw SnapshotValidationError.invalidDisplayFingerprint
        }
        self.value = value.lowercased()
    }
}

// MARK: - Runtime observations

/// An opaque, launch-local key that lets matching stay independent of CGWindowID and PID.
struct RuntimeWindowToken: Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// Privacy-conscious signals observed for a currently running window.
struct ObservedWindow: Equatable, Sendable {
    let token: RuntimeWindowToken
    let identity: PersistentWindowIdentity
}

// MARK: - SnapshotValidationError

enum SnapshotValidationError: Error, Equatable {
    case duplicateTileID
    case insufficientPrivacySalt
    case invalidDisplayFingerprint
    case invalidFullHeightInvariant
    case invalidHorizontalPlacement
    case invalidPrivateWindowHint
    case invalidRelativeOrder
    case invalidWindowIdentity
    case primaryTileNotFound
    case unsupportedSchemaVersion(Int)
}
