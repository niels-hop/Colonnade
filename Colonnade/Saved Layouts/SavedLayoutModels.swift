//
//  SavedLayoutModels.swift
//  Loop
//
//  Durable, privacy-conscious models for the three fixed saved-layout slots.
//

import CryptoKit
import Foundation

enum SavedLayoutSlot: String, Codable, CaseIterable, Identifiable, Sendable {
    case work
    case focus
    case macBook

    static let fixedSlots: [Self] = [.work, .focus, .macBook]

    var id: Self { self }

    var defaultName: String {
        switch self {
        case .work: "Work"
        case .focus: "Focus"
        case .macBook: "MacBook"
        }
    }
}

struct SavedLayoutLibrary: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    private(set) var work: [SavedLayoutVariant]
    private(set) var focus: [SavedLayoutVariant]
    private(set) var macBook: [SavedLayoutVariant]

    init(
        work: [SavedLayoutVariant] = [],
        focus: [SavedLayoutVariant] = [],
        macBook: [SavedLayoutVariant] = []
    ) throws {
        self.schemaVersion = Self.currentSchemaVersion
        self.work = try Self.validated(work)
        self.focus = try Self.validated(focus)
        self.macBook = try Self.validated(macBook)
    }

    private init(
        schemaVersion: Int,
        work: [SavedLayoutVariant],
        focus: [SavedLayoutVariant],
        macBook: [SavedLayoutVariant]
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw SavedLayoutError.unsupportedSchemaVersion(schemaVersion)
        }
        self.schemaVersion = schemaVersion
        self.work = try Self.validated(work)
        self.focus = try Self.validated(focus)
        self.macBook = try Self.validated(macBook)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            work: container.decode([SavedLayoutVariant].self, forKey: .work),
            focus: container.decode([SavedLayoutVariant].self, forKey: .focus),
            macBook: container.decode([SavedLayoutVariant].self, forKey: .macBook)
        )
    }

    func variants(in slot: SavedLayoutSlot) -> [SavedLayoutVariant] {
        switch slot {
        case .work: work
        case .focus: focus
        case .macBook: macBook
        }
    }

    mutating func replaceVariant(_ variant: SavedLayoutVariant, in slot: SavedLayoutSlot) {
        var variants = variants(in: slot)
        variants.removeAll { $0.displayConfiguration.fingerprint == variant.displayConfiguration.fingerprint }
        variants.append(variant)
        variants.sort { $0.capturedAt > $1.capturedAt }

        switch slot {
        case .work: work = variants
        case .focus: focus = variants
        case .macBook: macBook = variants
        }
    }

    private static func validated(_ variants: [SavedLayoutVariant]) throws -> [SavedLayoutVariant] {
        let keys = variants.map(\.displayConfiguration.fingerprint)
        guard Set(keys).count == keys.count else {
            throw SavedLayoutError.duplicateDisplayConfiguration
        }
        return variants.sorted { $0.capturedAt > $1.capturedAt }
    }
}

struct SavedLayoutVariant: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let capturedAt: Date
    let displayConfiguration: ConnectedDisplayConfiguration
    let displays: [WindowAwarenessSnapshot]

    init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        displayConfiguration: ConnectedDisplayConfiguration,
        displays: [WindowAwarenessSnapshot]
    ) throws {
        let savedIdentities = displays.map(\.display)
        guard displays.count == displayConfiguration.displays.count,
              Set(savedIdentities).count == savedIdentities.count,
              Set(savedIdentities) == Set(displayConfiguration.displays)
        else {
            throw SavedLayoutError.displaySetMismatch
        }

        self.id = id
        self.capturedAt = capturedAt
        self.displayConfiguration = displayConfiguration
        self.displays = displays.sorted {
            $0.display.stableSortKey < $1.display.stableSortKey
        }
    }
}

/// A key for a complete connected-display set, rather than for one display in isolation.
struct ConnectedDisplayConfiguration: Codable, Equatable, Hashable, Sendable {
    let displays: [DisplayIdentity]
    let fingerprint: String

    init(displays: [DisplayIdentity]) throws {
        guard !displays.isEmpty, Set(displays).count == displays.count else {
            throw SavedLayoutError.invalidDisplayConfiguration
        }

        let displays = displays.sorted { $0.stableSortKey < $1.stableSortKey }
        self.displays = displays
        self.fingerprint = Self.makeFingerprint(displays)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let displays = try container.decode([DisplayIdentity].self, forKey: .displays)
        let fingerprint = try container.decode(String.self, forKey: .fingerprint)
        let validated = try Self(displays: displays)
        guard fingerprint.lowercased() == validated.fingerprint else {
            throw SavedLayoutError.invalidDisplayConfiguration
        }
        self = validated
    }

    private static func makeFingerprint(_ displays: [DisplayIdentity]) -> String {
        let value = displays.map(\.stableSortKey).joined(separator: "||")
        return SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

enum SavedLayoutVariantSelector {
    enum Basis: Equatable, Sendable {
        case exactConfiguration
        case conservativeDisplayFallback
    }

    struct Selection: Equatable, Sendable {
        let variant: SavedLayoutVariant
        let basis: Basis
    }

    static func select(
        from variants: [SavedLayoutVariant],
        for current: ConnectedDisplayConfiguration
    ) -> Selection? {
        if let exact = variants.first(where: {
            $0.displayConfiguration.fingerprint == current.fingerprint
        }) {
            return Selection(variant: exact, basis: .exactConfiguration)
        }

        let fallbacks = variants.filter {
            conservativelyMatches($0.displayConfiguration, current)
        }
        guard fallbacks.count == 1, let fallback = fallbacks.first else { return nil }
        return Selection(variant: fallback, basis: .conservativeDisplayFallback)
    }

    private static func conservativelyMatches(
        _ saved: ConnectedDisplayConfiguration,
        _ current: ConnectedDisplayConfiguration
    ) -> Bool {
        guard saved.displays.count == current.displays.count else { return false }

        var claimed = Set<DisplayIdentity>()
        for persisted in saved.displays {
            guard case let .matched(match) = DisplayMatcher.match(persisted, against: current.displays),
                  claimed.insert(match.display).inserted
            else {
                return false
            }
        }
        return claimed.count == current.displays.count
    }
}

enum SavedLayoutError: Error, Equatable {
    case corruptData(String)
    case displaySetMismatch
    case duplicateDisplayConfiguration
    case invalidDisplayConfiguration
    case noEligibleWindows
    case noMatchingVariant
    case unsupportedSchemaVersion(Int)
    case writeFailed(String)
}

private extension DisplayIdentity {
    var stableSortKey: String {
        "\(uuid?.uuidString.lowercased() ?? "none")|\(fingerprint.value)"
    }
}
