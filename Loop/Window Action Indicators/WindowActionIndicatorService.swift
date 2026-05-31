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

    func openAndUpdate(context: ResizeContext) {
        if Defaults[.hideOnNoSelection], context.action.direction == .noSelection {
            closeAll()
            return
        }

        if Defaults[.previewVisibility] {
            previewController.open(context: context)
        }

        // On ultrawide screens the dock replaces the radial menu as the primary placement UI.
        // It opens once and is then kept in sync via `setWindow`/`setAction`.
        if UltrawideDockController.shouldUseUltrawideDock(for: context.screen) {
            ultrawideDockController.open(
                screen: context.screen,
                window: context.window,
                startingAction: context.action
            )
            if let window = context.window {
                ultrawideDockController.setWindow(to: window)
            }
            ultrawideDockController.setAction(to: context.action)
        } else if Defaults[.radialMenuVisibility] {
            radialMenuController.open(context: context)
        }
    }

    func closeAll() {
        radialMenuController.close()
        previewController.close()
        ultrawideDockController.close()
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
}
