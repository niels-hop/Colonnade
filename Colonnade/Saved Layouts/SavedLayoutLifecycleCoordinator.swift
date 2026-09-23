//
//  SavedLayoutLifecycleCoordinator.swift
//  Loop
//
//  Debounced launch, wake, display-change, and Space-change restore integration.
//

import AppKit
import Defaults
import Foundation

@MainActor
final class SavedLayoutLifecycleCoordinator {
    static let shared = SavedLayoutLifecycleCoordinator()

    private let manager: SavedLayoutManager
    private var observers: [NSObjectProtocol] = []
    private var pendingRestore: Task<Void, Never>?

    init(manager: SavedLayoutManager? = nil) {
        self.manager = manager ?? .shared
    }

    func start() {
        guard observers.isEmpty else { return }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [coordinator = self] _ in
            Task { @MainActor in
                guard Defaults[.restoreSavedLayoutOnWake] else { return }
                coordinator.scheduleRestore()
            }
        })

        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [coordinator = self] _ in
            Task { @MainActor in
                guard Defaults[.restoreSavedLayoutOnSpaceChange] else { return }
                coordinator.scheduleRestore()
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [coordinator = self] _ in
            Task { @MainActor in
                guard Defaults[.restoreSavedLayoutOnDisplayChange] else { return }
                coordinator.scheduleRestore()
            }
        })

        if Defaults[.restoreSavedLayoutOnLaunch] {
            scheduleRestore()
        }
    }

    func stop() {
        pendingRestore?.cancel()
        pendingRestore = nil
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func scheduleRestore() {
        pendingRestore?.cancel()
        pendingRestore = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(1500))
                guard !Task.isCancelled, let self else { return }

                for attempt in 0 ..< 2 {
                    guard !Task.isCancelled else { return }
                    do {
                        let report = try await manager.restore(Defaults[.defaultSavedLayoutSlot])
                        if report.isSuccess || report.issues.contains(.loopIsActive) ||
                            report.issues.contains(.accessibilityNotGranted) {
                            return
                        }
                    } catch SavedLayoutError.noMatchingVariant {
                        return
                    } catch SavedLayoutOperationError.operationInProgress {
                        // A manual operation may finish before the retry.
                    } catch {
                        return
                    }

                    if attempt == 0 {
                        try await Task.sleep(for: .milliseconds(1200))
                    }
                }
            } catch {
                // Cancellation is the normal debounce path.
            }
        }
    }
}
