//
//  LegacyDataMigration.swift
//  Colonnade
//
//  Created by Niels Hop on 2026-09-23.
//

import Foundation
import Scribe

/// Carries settings and saved layouts over from the builds that shipped before the rename to Colonnade.
///
/// Colonnade started as a personal fork of Loop with the bundle identifier `com.nielshop.Loop`. Because the
/// bundle identifier changed, macOS gives the renamed app an empty preferences domain and a fresh
/// Application Support folder. This one-time migration copies the old data across so an upgrade keeps the
/// trigger key, keybinds, dock mode and saved layouts. It never overwrites a value that already exists.
@Loggable(style: .static)
enum LegacyDataMigration {
    /// Bundle identifiers of earlier builds of this app, newest first.
    static let legacyBundleIdentifiers = ["com.nielshop.Loop"]

    /// Keys that belonged to features Colonnade no longer has, so copying them would only leave dead data.
    private static let skippedKeys: Set<String> = [
        "currentIcon",
        "timesLooped",
        "notificationWhenIconUnlocked"
    ]

    private static let completedKey = "legacyDataMigrationCompleted"

    /// Runs the migration once per account. Must be called before any settings are read.
    static func runIfNeeded(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        guard !defaults.bool(forKey: completedKey) else { return }
        defer { defaults.set(true, forKey: completedKey) }

        for identifier in legacyBundleIdentifiers {
            migratePreferences(from: identifier, into: defaults)
            migrateApplicationSupport(from: identifier, fileManager: fileManager)
        }
    }

    private static func migratePreferences(from identifier: String, into defaults: UserDefaults) {
        guard
            identifier != Bundle.main.bundleIdentifier,
            let legacy = defaults.persistentDomain(forName: identifier),
            !legacy.isEmpty
        else {
            return
        }

        let current = Bundle.main.bundleIdentifier.flatMap { defaults.persistentDomain(forName: $0) } ?? [:]
        var copied = 0

        for (key, value) in legacy where current[key] == nil && !skippedKeys.contains(key) {
            defaults.set(value, forKey: key)
            copied += 1
        }

        log.info("Migrated \(copied) preference(s) from \(identifier)")
    }

    private static func migrateApplicationSupport(from identifier: String, fileManager: FileManager) {
        guard
            let currentIdentifier = Bundle.main.bundleIdentifier,
            currentIdentifier != identifier,
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else {
            return
        }

        let legacyDirectory = base.appendingPathComponent(identifier, isDirectory: true)
        let currentDirectory = base.appendingPathComponent(currentIdentifier, isDirectory: true)

        guard
            fileManager.fileExists(atPath: legacyDirectory.path),
            !fileManager.fileExists(atPath: currentDirectory.path)
        else {
            return
        }

        do {
            try fileManager.copyItem(at: legacyDirectory, to: currentDirectory)
            log.info("Copied Application Support data from \(identifier)")
        } catch {
            log.error("Failed to copy Application Support data from \(identifier): \(error.localizedDescription)")
        }
    }
}
