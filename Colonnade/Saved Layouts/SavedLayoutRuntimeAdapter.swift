//
//  SavedLayoutRuntimeAdapter.swift
//  Colonnade
//
//  Ephemeral bindings from manageable windows to privacy-conscious awareness identities.
//

import AppKit
import Foundation

@MainActor
final class SavedLayoutRuntimeAdapter {
    struct RuntimeSet {
        let observations: [ObservedWindow]
        let bindings: [RuntimeWindowToken: Window]
    }

    struct CapturedDisplay {
        let screen: NSScreen
        let snapshot: WindowAwarenessSnapshot
    }

    func captureCurrentLayout(salt: Data) throws -> [CapturedDisplay] {
        let screens = eligibleScreens()
        let windows = eligibleWindows()
        let ordinals = ordinalHints(for: windows)
        var captured: [CapturedDisplay] = []
        var capturedWindowCount = 0

        for screen in screens {
            let bounds = Self.workingBounds(for: screen)
            let tolerance = fullHeightTolerance(for: screen)
            // WindowUtility returns visible windows front-to-back. Keep that order long enough
            // to identify the primary tile before arranging the snapshot from left to right.
            let visibleRailWindows = windows.compactMap { window -> (Window, NormalizedHorizontalPlacement)? in
                guard screenContaining(window) == screen,
                      SavedLayoutGeometry.isFullHeightRail(window.frame, in: bounds, tolerance: tolerance),
                      let placement = SavedLayoutGeometry.normalizedPlacement(for: window.frame, in: bounds)
                else {
                    return nil
                }
                return (window, placement)
            }
            let primaryWindowID = visibleRailWindows.first?.0.cgWindowID
            let railWindows = visibleRailWindows.sorted { $0.1.normalizedX < $1.1.normalizedX }

            let snapshots = try railWindows.enumerated().map { index, item in
                try ManagedWindowSnapshot(
                    identity: identity(
                        for: item.0,
                        placement: item.1,
                        ordinal: ordinals[item.0.cgWindowID],
                        salt: salt
                    ),
                    placement: item.1,
                    relativeOrder: index
                )
            }
            capturedWindowCount += snapshots.count
            let primaryTileID = primaryWindowID.flatMap { windowID in
                railWindows.firstIndex { $0.0.cgWindowID == windowID }.map { snapshots[$0].id }
            }

            guard let displayID = screen.displayID else { continue }
            let display = CoreGraphicsDisplayIdentityAdapter.identity(for: displayID)
            let snapshot = try WindowAwarenessSnapshot(
                display: display,
                windows: snapshots,
                primaryTileID: primaryTileID
            )
            captured.append(CapturedDisplay(screen: screen, snapshot: snapshot))
        }

        guard capturedWindowCount > 0 else { throw SavedLayoutError.noEligibleWindows }
        return captured
    }

    func observeCurrentWindows(salt: Data) throws -> RuntimeSet {
        let windows = eligibleWindows()
        let ordinals = ordinalHints(for: windows)
        var observations: [ObservedWindow] = []
        var bindings: [RuntimeWindowToken: Window] = [:]

        for window in windows {
            let placement = screenContaining(window).flatMap {
                SavedLayoutGeometry.normalizedPlacement(for: window.frame, in: Self.workingBounds(for: $0))
            }
            let token = RuntimeWindowToken()
            let observed = try ObservedWindow(
                token: token,
                identity: identity(
                    for: window,
                    placement: placement,
                    ordinal: ordinals[window.cgWindowID],
                    salt: salt
                )
            )
            observations.append(observed)
            bindings[token] = window
        }

        return RuntimeSet(observations: observations, bindings: bindings)
    }

    func connectedDisplayConfiguration() throws -> ConnectedDisplayConfiguration {
        try ConnectedDisplayConfiguration(displays: eligibleScreens().compactMap { screen in
            screen.displayID.map(CoreGraphicsDisplayIdentityAdapter.identity)
        })
    }

    func screen(matching identity: DisplayIdentity) -> NSScreen? {
        let candidates = eligibleScreens().compactMap { screen -> (NSScreen, DisplayIdentity)? in
            guard let displayID = screen.displayID else { return nil }
            return (screen, CoreGraphicsDisplayIdentityAdapter.identity(for: displayID))
        }
        guard case let .matched(match) = DisplayMatcher.match(identity, against: candidates.map(\.1)) else {
            return nil
        }
        return candidates.first { $0.1 == match.display }?.0
    }

    static func workingBounds(for screen: NSScreen) -> CGRect {
        let safeBounds = screen.cgSafeScreenFrame
        let padding = PaddingConfiguration.getConfiguredPadding(for: screen)
        return padding.applyToBounds(safeBounds, screen: screen)
    }

    private func eligibleScreens() -> [NSScreen] {
        NSScreen.screens.filter { $0.displayID != nil }
    }

    private func eligibleWindows() -> [Window] {
        var seen = Set<CGWindowID>()
        return WindowUtility.windowList().filter { window in
            guard seen.insert(window.cgWindowID).inserted else { return false }
            return !window.isOwnWindow &&
                !window.isAppExcluded &&
                !window.minimized &&
                !window.isWindowHidden &&
                window.nsRunningApplication?.bundleIdentifier != nil
        }
    }

    private func screenContaining(_ window: Window) -> NSScreen? {
        NSScreen.screens.max { first, second in
            intersectionArea(first.cgSafeScreenFrame, window.frame) <
                intersectionArea(second.cgSafeScreenFrame, window.frame)
        }.flatMap {
            intersectionArea($0.cgSafeScreenFrame, window.frame) > 0 ? $0 : nil
        }
    }

    private func intersectionArea(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let intersection = first.intersection(second)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private func ordinalHints(for windows: [Window]) -> [CGWindowID: Int] {
        let grouped = Dictionary(grouping: windows) {
            $0.nsRunningApplication?.bundleIdentifier ?? ""
        }
        var result: [CGWindowID: Int] = [:]
        for group in grouped.values {
            let sorted = group.sorted {
                if $0.frame.minX != $1.frame.minX {
                    return $0.frame.minX < $1.frame.minX
                }
                if $0.frame.minY != $1.frame.minY {
                    return $0.frame.minY < $1.frame.minY
                }
                return $0.cgWindowID < $1.cgWindowID
            }
            for (index, window) in sorted.enumerated() {
                result[window.cgWindowID] = index
            }
        }
        return result
    }

    private func identity(
        for window: Window,
        placement: NormalizedHorizontalPlacement?,
        ordinal: Int?,
        salt: Data
    ) throws -> PersistentWindowIdentity {
        guard let bundleIdentifier = window.nsRunningApplication?.bundleIdentifier else {
            throw SnapshotValidationError.invalidWindowIdentity
        }

        let document: String? = try? window.axWindow.getValue(.init(rawValue: "AXDocument"))
        let accessibilityIdentifier: String? = try? window.axWindow.getValue(.init(rawValue: "AXIdentifier"))
        let titleOrDocument = firstNonEmpty(document, window.title)
        let stableAccessibility = firstNonEmpty(accessibilityIdentifier)

        return try PersistentWindowIdentity(
            bundleIdentifier: bundleIdentifier,
            titleOrDocumentHint: titleOrDocument.map { try PrivateWindowHint(rawValue: $0, salt: salt) },
            stableAccessibilityHint: stableAccessibility.map { try PrivateWindowHint(rawValue: $0, salt: salt) },
            role: window.role?.rawValue,
            subrole: window.subrole?.rawValue,
            ordinalHint: ordinal,
            frameHint: placement
        )
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        values.lazy.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }.first
    }

    private func fullHeightTolerance(for screen: NSScreen) -> CGFloat {
        let padding = PaddingConfiguration.getConfiguredPadding(for: screen)
        return max(4, padding.window / 2 + 2)
    }
}
