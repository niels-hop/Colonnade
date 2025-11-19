//
//  UltrawideDockController.swift
//  Loop
//
//  Created by Antigravity on 2025-11-18.
//

import Defaults
import OSLog
import SwiftUI

final class UltrawideDockController {
    private var controller: NSWindowController?
    private var viewModel: UltrawideDockViewModel?
    private let logger = Logger(category: "UltrawideDockController")

    func open(
        position _: CGPoint,
        window: Window?,
        startingAction: WindowAction?
    ) {
        if let windowController = controller {
            // Refresh window data before re-opening to ensure accuracy
            viewModel?.refresh()

            windowController.window?.orderFrontRegardless()

            // Snap mouse cursor to center of dock when re-opening
            if let panelFrame = windowController.window?.frame {
                let dockCenter = CGPoint(
                    x: panelFrame.midX,
                    y: panelFrame.midY
                )
                CGWarpMouseCursorPosition(dockCenter)
            }
            return
        }

        guard let screen = NSApp.keyWindow?.screen ?? NSScreen.main else {
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
        let height: CGFloat = 190 // 150 base + 40 padding

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
        logger.log("UltrawideDockController: Set action to '\(newAction.debugDescription)'")
    }

    var dockFrame: CGRect? {
        controller?.window?.frame
    }
}
