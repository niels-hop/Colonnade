//
//  SavedLayoutManager.swift
//  Loop
//
//  Small save/restore coordinator built on Window Awareness and WindowActionEngine.
//

import AppKit
import Defaults
import Foundation

struct SavedLayoutSaveReport: Equatable, Sendable {
    let slot: SavedLayoutSlot
    let displayCount: Int
    let windowCount: Int
}

struct SavedLayoutRestoreReport: Equatable, Sendable {
    enum Issue: Equatable, Sendable {
        case accessibilityNotGranted
        case ambiguousDisplay(windowCount: Int)
        case ambiguousWindow
        case engineRejectedWindow
        case loopIsActive
        case missingDisplay(windowCount: Int)
        case missingWindow
        case runtimeBindingUnavailable
        case runtimeWindowClaimedTwice
    }

    let slot: SavedLayoutSlot
    let variantID: UUID?
    let selectionBasis: SavedLayoutVariantSelector.Basis?
    let appliedWindowCount: Int
    let issues: [Issue]

    var isSuccess: Bool { appliedWindowCount > 0 }
}

@MainActor
final class SavedLayoutManager {
    static let shared = SavedLayoutManager()

    private let store: any SavedLayoutStoring
    private let saltStore: SavedLayoutPrivacySaltStore
    private let adapter: SavedLayoutRuntimeAdapter
    private let isLoopActive: () -> Bool
    private var operationInProgress = false

    init(
        store: (any SavedLayoutStoring)? = nil,
        saltStore: SavedLayoutPrivacySaltStore? = nil,
        adapter: SavedLayoutRuntimeAdapter? = nil,
        isLoopActive: (() -> Bool)? = nil
    ) {
        let directory = SavedLayoutSupportPaths.directory()
        self.store = store ?? AtomicFileSavedLayoutStore(
            fileURL: directory.appendingPathComponent("layouts.json")
        )
        self.saltStore = saltStore ?? SavedLayoutPrivacySaltStore(
            fileURL: directory.appendingPathComponent("privacy-salt.bin")
        )
        self.adapter = adapter ?? SavedLayoutRuntimeAdapter()
        self.isLoopActive = isLoopActive ?? { LoopManager.shared.isLoopActiveAtomic }
    }

    func saveCurrentLayout(in slot: SavedLayoutSlot) async throws -> SavedLayoutSaveReport {
        guard !operationInProgress else { throw SavedLayoutOperationError.operationInProgress }
        operationInProgress = true
        defer { operationInProgress = false }

        let salt = try await saltStore.loadOrCreate()
        let captures = try adapter.captureCurrentLayout(salt: salt)
        let configuration = try ConnectedDisplayConfiguration(
            displays: captures.map(\.snapshot.display)
        )
        let variant = try SavedLayoutVariant(
            displayConfiguration: configuration,
            displays: captures.map(\.snapshot)
        )
        var library = try await store.load()
        library.replaceVariant(variant, in: slot)
        try await store.save(library)

        return SavedLayoutSaveReport(
            slot: slot,
            displayCount: captures.count,
            windowCount: captures.reduce(0) { $0 + $1.snapshot.windows.count }
        )
    }

    func restore(_ slot: SavedLayoutSlot) async throws -> SavedLayoutRestoreReport {
        guard !operationInProgress else { throw SavedLayoutOperationError.operationInProgress }
        guard AccessibilityManager.shared.isGranted else {
            return SavedLayoutRestoreReport(
                slot: slot,
                variantID: nil,
                selectionBasis: nil,
                appliedWindowCount: 0,
                issues: [.accessibilityNotGranted]
            )
        }
        guard !isLoopActive() else {
            return SavedLayoutRestoreReport(
                slot: slot,
                variantID: nil,
                selectionBasis: nil,
                appliedWindowCount: 0,
                issues: [.loopIsActive]
            )
        }

        operationInProgress = true
        defer { operationInProgress = false }

        let library = try await store.load()
        let currentConfiguration = try adapter.connectedDisplayConfiguration()
        guard let selection = SavedLayoutVariantSelector.select(
            from: library.variants(in: slot),
            for: currentConfiguration
        ) else {
            throw SavedLayoutError.noMatchingVariant
        }

        let salt = try await saltStore.loadOrCreate()
        let runtime = try adapter.observeCurrentWindows(salt: salt)
        var issues: [SavedLayoutRestoreReport.Issue] = []
        var planned: [(MatchedWindow, Window, NSScreen)] = []
        var claimedTokens = Set<RuntimeWindowToken>()

        for snapshot in selection.variant.displays {
            let reconciliation = WindowAwareness.reconcile(
                snapshot,
                displays: currentConfiguration.displays,
                windows: runtime.observations
            )

            switch reconciliation.display {
            case .missing:
                issues.append(.missingDisplay(windowCount: snapshot.windows.count))
                continue
            case .ambiguous:
                issues.append(.ambiguousDisplay(windowCount: snapshot.windows.count))
                continue
            case .matched:
                break
            }

            issues.append(contentsOf: reconciliation.windows.missing.map { _ in .missingWindow })
            issues.append(contentsOf: reconciliation.windows.ambiguous.map { _ in .ambiguousWindow })

            guard let screen = adapter.screen(matching: snapshot.display) else {
                issues.append(.missingDisplay(windowCount: snapshot.windows.count))
                continue
            }

            for match in reconciliation.automaticallyRestorableWindows {
                guard claimedTokens.insert(match.runtimeToken).inserted else {
                    issues.append(.runtimeWindowClaimedTwice)
                    continue
                }
                guard let window = runtime.bindings[match.runtimeToken] else {
                    issues.append(.runtimeBindingUnavailable)
                    continue
                }
                planned.append((match, window, screen))
            }
        }

        // WindowEngine's regular preference may warp after each action. Saved-layout
        // restore is intentionally cursor-neutral, so suppress it for this serialized run.
        let previousMoveCursor = Defaults[.moveCursorWithWindow]
        Defaults[.moveCursorWithWindow] = false
        defer { Defaults[.moveCursorWithWindow] = previousMoveCursor }

        var applied = 0
        for (match, window, screen) in planned {
            let action = Self.action(for: match.tile.placement)
            let context = ResizeContext(
                window: window,
                screen: screen,
                bounds: SavedLayoutRuntimeAdapter.workingBounds(for: screen),
                padding: .zero,
                action: action
            )
            await context.refreshResolvedState()

            do {
                let result = try await WindowActionEngine.shared.apply(context: context)
                if result.success {
                    applied += 1
                } else {
                    issues.append(.engineRejectedWindow)
                }
            } catch {
                issues.append(.engineRejectedWindow)
            }
        }

        return SavedLayoutRestoreReport(
            slot: slot,
            variantID: selection.variant.id,
            selectionBasis: selection.basis,
            appliedWindowCount: applied,
            issues: issues
        )
    }

    func saveWithFeedback(_ slot: SavedLayoutSlot) async {
        do {
            let report = try await saveCurrentLayout(in: slot)
            AppDelegate.sendNotification(
                "Layout saved",
                "\(slot.displayName): \(report.windowCount) windows across \(report.displayCount) displays."
            )
        } catch {
            AppDelegate.sendNotification("Layout not saved", feedbackDescription(for: error))
        }
    }

    func restoreWithFeedback(_ slot: SavedLayoutSlot) async {
        do {
            let report = try await restore(slot)
            if report.isSuccess {
                let skipped = report.issues.count
                let suffix = skipped == 0 ? "" : " \(skipped) skipped."
                AppDelegate.sendNotification(
                    "Layout restored",
                    "\(slot.displayName): \(report.appliedWindowCount) windows.\(suffix)"
                )
            } else {
                AppDelegate.sendNotification(
                    "Layout not restored",
                    report.issues.first?.feedbackDescription ?? "No windows could be restored."
                )
            }
        } catch {
            AppDelegate.sendNotification("Layout not restored", feedbackDescription(for: error))
        }
    }

    private static func action(for placement: NormalizedHorizontalPlacement) -> WindowAction {
        WindowAction(
            .custom,
            keybind: [],
            name: "Saved Layout",
            unit: .percentage,
            width: placement.normalizedWidth * 100,
            height: 100,
            xPoint: placement.normalizedX * 100,
            yPoint: 0,
            positionMode: .coordinates,
            sizeMode: .custom
        )
    }

    private func feedbackDescription(for error: Error) -> String {
        switch error {
        case SavedLayoutError.noEligibleWindows:
            "No full-height horizontal windows were found."
        case SavedLayoutError.noMatchingVariant:
            "No layout is saved for this display configuration."
        case SavedLayoutOperationError.operationInProgress:
            "Another layout operation is still running."
        default:
            "The saved layout data could not be used."
        }
    }
}

enum SavedLayoutOperationError: Error, Equatable {
    case operationInProgress
}

extension SavedLayoutSlot {
    var displayName: String {
        switch self {
        case .work: Defaults[.savedLayoutWorkName].nonEmpty ?? defaultName
        case .focus: Defaults[.savedLayoutFocusName].nonEmpty ?? defaultName
        case .macBook: Defaults[.savedLayoutMacBookName].nonEmpty ?? defaultName
        }
    }
}

private extension SavedLayoutRestoreReport.Issue {
    var feedbackDescription: String {
        switch self {
        case .accessibilityNotGranted: "Accessibility permission is required."
        case .loopIsActive: "Release the trigger before restoring."
        case .missingDisplay: "A saved display is not connected."
        case .ambiguousDisplay: "The connected displays cannot be identified safely."
        case .missingWindow: "A saved window is not currently visible."
        case .ambiguousWindow: "A saved window could not be matched safely."
        case .engineRejectedWindow, .runtimeBindingUnavailable, .runtimeWindowClaimedTwice:
            "A matched window could not be restored safely."
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
