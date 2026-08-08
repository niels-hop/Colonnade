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
        if Defaults[.hideOnNoSelection], context.action.direction == .noSelection {
            closeAll()
            return
        }

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

    /// Hover: maps the absolute screen mouse-X to the nearest anchor and returns the resulting action.
    func dockActionForMouseX(_ screenMouseX: CGFloat) -> WindowAction? {
        ultrawideDockController.updateForMouseX(Double(screenMouseX))
    }

    /// Click cycles through the size stops at the active anchor (e.g. 1/2 → 1/3 → 2/3).
    func cycleDockSize() -> WindowAction? {
        ultrawideDockController.cycleSize()
    }

    /// Scroll-wheel fine-tunes the width at the current anchor. `delta` is in fraction-of-span units.
    func adjustDockSize(by delta: Double) -> WindowAction? {
        ultrawideDockController.adjustSize(by: delta)
    }

    var pendingHorizontalLayoutExecution: HorizontalLayoutPendingExecution? {
        ultrawideDockController.pendingExecution
    }

    private func updateDockPreview(context: ResizeContext) {
        guard Defaults[.previewVisibility] else {
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
