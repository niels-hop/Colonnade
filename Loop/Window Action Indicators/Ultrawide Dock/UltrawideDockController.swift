//
//  UltrawideDockController.swift
//  Loop
//
//  Created by Antigravity on 2025-11-18.
//

import Defaults
import Scribe
import SwiftUI

@MainActor
@Loggable
final class UltrawideDockController {
    private var controller: NSWindowController?
    private var viewModel: UltrawideDockViewModel?

    /// Whether the Ultrawide Dock should drive placement for the given screen, based on the
    /// configured trigger mode. `.automatic` enables it on screens with an aspect ratio ≥ 2.0.
    static func shouldUseUltrawideDock(for screen: NSScreen?) -> Bool {
        switch Defaults[.ultrawideDockTriggerMode] {
        case .alwaysOn:
            return true
        case .never:
            return false
        case .automatic:
            guard let screen else { return false }
            return screen.frame.width / screen.frame.height >= 2.0
        }
    }

    func open(
        screen screenOverride: NSScreen?,
        window: Window?,
        startingAction: WindowAction?
    ) {
        // Already open: action/window updates flow through `setAction`/`setWindow`, so don't
        // re-create the panel or re-warp the cursor (which would fight the user's mouse).
        // Crucially, do NOT `refresh()` here: `openAndUpdate` runs on every mouse move, and a
        // reload would re-enumerate all windows + rebuild anchors with fresh UUIDs each tick,
        // resetting the active anchor and minting a new action identity → endless churn.
        if controller != nil {
            return
        }

        guard let screen = screenOverride ?? NSApp.keyWindow?.screen ?? NSScreen.main else {
            return
        }

        let viewModel = UltrawideDockViewModel(
            startingAction: startingAction,
            window: window,
            screen: screen,
            previewMode: false
        )
        self.viewModel = viewModel

        // These dimensions should match the view's frame + padding
        // View is 600x150 + 20 padding = 640x190 approx?
        // Actually the view has .padding(20) on the outside.
        // Let's just use a large enough rect, the view is fixedSize.

        let panel = ActivePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true,
            screen: screen
        )

        panel.collectionBehavior = .canJoinAllSpaces
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver
        panel.contentView = NSHostingView(rootView: UltrawideDockView(viewModel: viewModel, screen: screen))
        panel.alphaValue = 0

        // Position the panel at the center of the screen
        let screenFrame = screen.frame

        // Calculate dynamic width based on screen aspect ratio (for ultrawide support)
        let aspectRatio = screenFrame.width / screenFrame.height
        let isUltrawide = aspectRatio >= 2.0
        let baseDockWidth: CGFloat = 600
        let dockWidth: CGFloat
        if isUltrawide {
            let scaleFactor = min(aspectRatio / 1.6, 1.33)
            dockWidth = baseDockWidth * scaleFactor
        } else {
            dockWidth = baseDockWidth
        }

        // Add padding (view has .padding(20))
        let width = dockWidth + 40
        let height: CGFloat = 216 // 176 base + 40 padding

        panel.setFrame(
            NSRect(
                x: screenFrame.midX - width / 2,
                y: screenFrame.midY - height / 2,
                width: width,
                height: height
            ),
            display: true
        )

        panel.orderFrontRegardless()

        controller = .init(window: panel)

        // Snap mouse cursor to center of dock
        let panelFrame = panel.frame
        let dockCenter = CGPoint(
            x: panelFrame.midX,
            y: panelFrame.midY
        )
        CGWarpMouseCursorPosition(dockCenter)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        guard let windowController = controller else { return }
        controller = nil
        viewModel = nil

        windowController.window?.animator().alphaValue = 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            windowController.window?.animator().alphaValue = 0
        } completionHandler: {
            windowController.close()
        }
    }

    func setWindow(to newWindow: Window) {
        viewModel?.setWindow(to: newWindow)
    }

    func setAction(to newAction: WindowAction) {
        viewModel?.setAction(to: newAction)
        log.info("Set action to '\(newAction.description)'")
    }

    var dockFrame: CGRect? {
        controller?.window?.frame
    }

    /// True while the dock panel is open and driving placement.
    var isActive: Bool {
        controller != nil
    }

    /// Hover: maps the cursor to the nearest anchor and returns the resulting action.
    ///
    /// The dock view is a scaled mini-map of the screen, so we map the cursor *within the dock
    /// panel* to 0..1 instead of across the full (super ultrawide) screen width. That way a small
    /// cursor movement across the dock spans every anchor — the user no longer has to drag the
    /// cursor all the way to the physical screen edge to reach the rightmost anchor.
    @discardableResult
    func updateForMouseX(_ screenMouseX: Double) -> WindowAction? {
        guard let frame = controller?.window?.frame else {
            return viewModel?.currentAction
        }
        // The mini-screen rectangle inside the panel is inset by the view's outer (20) + inner
        // (10) padding on each side; map only across that visible rectangle so it lines up with
        // what the user sees.
        let inset = 30.0
        let repMinX = frame.minX + inset
        let repWidth = max(1, frame.width - inset * 2)
        let normalized = min(1, max(0, (screenMouseX - repMinX) / repWidth))
        return viewModel?.updateForNormalizedX(normalized)
    }

    /// Click on the current anchor cycles through its size stops (e.g. 1/2 → 1/3 → 2/3).
    @discardableResult
    func cycleSize() -> WindowAction? {
        viewModel?.cycleSize()
    }

    /// Scroll wheel fine-tune. `delta` is in fraction-of-maxSpan units.
    @discardableResult
    func adjustSize(by delta: Double) -> WindowAction? {
        viewModel?.adjustSize(by: delta)
    }

    /// The currently computed action — source of truth while the dock is open.
    var currentAction: WindowAction? {
        viewModel?.currentAction
    }

    /// Latest complete multi-window transaction. It is replaced on every dock interaction and is
    /// consumed exactly once by `LoopManager` when the trigger is released.
    var pendingExecution: HorizontalLayoutPendingExecution? {
        viewModel?.pendingExecution
    }
}
