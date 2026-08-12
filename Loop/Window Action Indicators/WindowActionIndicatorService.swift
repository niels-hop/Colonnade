//
//  WindowActionIndicatorService.swift
//  Loop
//
//  Created by Kai Azim on 2026-01-19.
//

import AppKit
import Defaults

@MainActor
final class WindowActionIndicatorService {
    private let radialMenuController = RadialMenuController()
    private let previewController = PreviewController()
    private let ultrawideDockController = UltrawideDockController()
    private let horizontalLayoutPreviewController = HorizontalLayoutPlanPreviewController()

    func openAndUpdate(context: ResizeContext) {
        // On ultrawide screens the dock replaces the radial menu as the primary placement UI.
        // It opens once and is then kept in sync via `setWindow`/`setAction`. The screen is only
        // resolved on a later `openAndUpdate` call, so the radial menu may have opened on the first
        // (screen-less) call — explicitly close the other indicator so the two can't both show.
        if UltrawideDockController.shouldUseUltrawideDock(for: context.screen) {
            radialMenuController.close()
            ultrawideDockController.open(
                screen: context.screen,
                window: context.window,
                startingAction: context.action
            )
            if let window = context.window {
                ultrawideDockController.setWindow(to: window)
            }
            ultrawideDockController.setAction(to: context.action)
            updateDockPreview(context: context)
        } else if Defaults[.hideOnNoSelection], context.action.direction == .noSelection {
            closeAll()
        } else if Defaults[.radialMenuVisibility] {
            ultrawideDockController.close()
            horizontalLayoutPreviewController.close()
            if Defaults[.previewVisibility] {
                previewController.open(context: context)
            }
            radialMenuController.open(context: context)
        } else if Defaults[.previewVisibility] {
            previewController.open(context: context)
        }
    }

    func closeAll() {
        radialMenuController.close()
        previewController.close()
        ultrawideDockController.close()
        horizontalLayoutPreviewController.close()
    }

    // MARK: - Ultrawide Dock interaction

    /// True while the dock panel is open and driving placement.
    var isDockActive: Bool {
        ultrawideDockController.isActive
    }

    /// Hover: maps compact horizontal pointer motion to a direct dock target.
    func dockActionForMouseX(_ screenMouseX: CGFloat) -> WindowAction? {
        ultrawideDockController.updateForMouseX(Double(screenMouseX))
    }

    func dockPointerDown(at screenMouseX: CGFloat) -> WindowAction? {
        ultrawideDockController.pointerDown(at: Double(screenMouseX))
    }

    func dockPointerDragged(to screenMouseX: CGFloat) -> WindowAction? {
        ultrawideDockController.drag(to: Double(screenMouseX))
    }

    func dockPointerUp(at screenMouseX: CGFloat) -> WindowAction? {
        ultrawideDockController.pointerUp(at: Double(screenMouseX))
    }

    /// Scroll-wheel fine-tunes the current placement or divider.
    func adjustDockSize(by delta: Double) -> WindowAction? {
        ultrawideDockController.adjustSize(by: delta)
    }

    var pendingHorizontalLayoutExecution: HorizontalLayoutPendingExecution? {
        ultrawideDockController.pendingExecution
    }

    var hasPendingDockCommit: Bool {
        ultrawideDockController.hasPendingCommit
    }

    private func updateDockPreview(context: ResizeContext) {
        guard Defaults[.previewVisibility] else {
            previewController.close()
            horizontalLayoutPreviewController.close()
            return
        }
        guard ultrawideDockController.hasPendingCommit else {
            previewController.close()
            horizontalLayoutPreviewController.close()
            return
        }
        if let execution = ultrawideDockController.pendingExecution {
            previewController.close()
            horizontalLayoutPreviewController.open(execution)
        } else {
            horizontalLayoutPreviewController.close()
            previewController.open(context: context)
        }
    }
}
