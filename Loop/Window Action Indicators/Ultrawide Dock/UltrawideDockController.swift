//
//  UltrawideDockController.swift
//  Loop
//

import Defaults
import Scribe
import SwiftUI

@MainActor
@Loggable
final class UltrawideDockController {
    private static let pointerDeadZone: CGFloat = 6

    private var controller: NSWindowController?
    private var viewModel: UltrawideDockViewModel?
    private var activationMouseX: CGFloat = 0
    private var interactionSpan: CGFloat = 1
    private var hasLeftDeadZone = false

    static func shouldUseUltrawideDock(for screen: NSScreen?) -> Bool {
        switch Defaults[.ultrawideDockTriggerMode] {
        case .alwaysOn:
            return true
        case .never:
            return false
        case .automatic:
            guard let screen else { return false }
            return screen.frame.width / screen.frame.height >= 2
        }
    }

    func open(
        screen screenOverride: NSScreen?,
        window: Window?,
        startingAction: WindowAction?
    ) {
        guard controller == nil else { return }
        guard let screen = screenOverride ?? NSApp.keyWindow?.screen ?? NSScreen.main else { return }

        let viewModel = UltrawideDockViewModel(
            startingAction: startingAction,
            window: window,
            screen: screen,
            previewMode: false
        )
        self.viewModel = viewModel

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

        let aspectRatio = screen.frame.width / screen.frame.height
        let baseDockWidth: CGFloat = 600
        let dockWidth = aspectRatio >= 2 ? baseDockWidth * min(aspectRatio / 1.6, 1.33) : baseDockWidth
        let panelWidth = dockWidth + 40
        let panelHeight: CGFloat = 242
        let pointer = NSEvent.mouseLocation
        let screenFrame = screen.frame.insetBy(dx: 8, dy: 8)
        let originX = min(
            max(pointer.x - panelWidth / 2, screenFrame.minX),
            max(screenFrame.minX, screenFrame.maxX - panelWidth)
        )
        let originY = min(
            max(pointer.y - panelHeight / 2, screenFrame.minY),
            max(screenFrame.minY, screenFrame.maxY - panelHeight)
        )

        panel.setFrame(
            NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight),
            display: true
        )
        panel.orderFrontRegardless()
        controller = NSWindowController(window: panel)

        // Keep the user's cursor exactly where it was. Horizontal motion from this activation
        // point maps across the mini-screen, which keeps the two-keys-plus-mouse gesture compact.
        activationMouseX = pointer.x
        interactionSpan = max(1, dockWidth - 20)
        hasLeftDeadZone = false

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        guard let windowController = controller else { return }
        viewModel?.cancel()
        controller = nil
        viewModel = nil
        hasLeftDeadZone = false
        NSCursor.arrow.set()

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
    }

    var dockFrame: CGRect? { controller?.window?.frame }
    var isActive: Bool { controller != nil }

    @discardableResult
    func updateForMouseX(_ screenMouseX: Double) -> WindowAction? {
        let screenX = CGFloat(screenMouseX)
        if !hasLeftDeadZone {
            guard abs(screenX - activationMouseX) >= Self.pointerDeadZone else {
                return viewModel?.currentAction
            }
            hasLeftDeadZone = true
        }
        let action = viewModel?.updateForNormalizedX(normalizedX(for: screenX))
        updateCursor()
        return action
    }

    @discardableResult
    func pointerDown(at screenMouseX: Double) -> WindowAction? {
        let action = viewModel?.pointerDown(at: normalizedX(for: CGFloat(screenMouseX)))
        updateCursor()
        return action
    }

    @discardableResult
    func drag(to screenMouseX: Double) -> WindowAction? {
        hasLeftDeadZone = true
        let action = viewModel?.drag(to: normalizedX(for: CGFloat(screenMouseX)))
        updateCursor()
        return action
    }

    @discardableResult
    func pointerUp(at screenMouseX: Double) -> WindowAction? {
        let action = viewModel?.pointerUp(at: normalizedX(for: CGFloat(screenMouseX)))
        updateCursor()
        return action
    }

    @discardableResult
    func adjustSize(by delta: Double) -> WindowAction? {
        let action = viewModel?.adjustSize(by: delta)
        updateCursor()
        return action
    }

    var currentAction: WindowAction? { viewModel?.currentAction }
    var pendingExecution: HorizontalLayoutPendingExecution? { viewModel?.pendingExecution }
    var hasPendingCommit: Bool { viewModel?.hasPendingCommit ?? false }

    private func normalizedX(for screenMouseX: CGFloat) -> Double {
        Double(min(1, max(0, 0.5 + (screenMouseX - activationMouseX) / interactionSpan)))
    }

    private func updateCursor() {
        switch viewModel?.cursor {
        case .resizeLeftRight: NSCursor.resizeLeftRight.set()
        default: NSCursor.arrow.set()
        }
    }
}
