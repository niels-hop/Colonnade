//
//  UltrawideDockController.swift
//  Colonnade
//

import Defaults
import Scribe
import SwiftUI

/// Panel geometry shared by the controller, which sizes the panel and maps the pointer onto it, and
/// the view, which draws it. The free-placement lane only works if both agree on where it sits.
enum UltrawideDockMetrics {
    /// User-configurable in Settings → Dock. Read live so a change applies the next time the dock opens.
    static var baseDockWidth: CGFloat {
        min(max(CGFloat(Defaults[.ultrawideDockBaseWidth]), 400), 1000)
    }

    static let mapHeight: CGFloat = 142
    static let freeLaneHeight: CGFloat = 34
    static let footerHeight: CGFloat = 32
    static let sectionSpacing: CGFloat = 8
    static let contentPadding: CGFloat = 10
    static let shadowPadding: CGFloat = 20

    static func dockWidth(for screen: NSScreen?) -> CGFloat {
        guard let screen else { return baseDockWidth }
        let aspectRatio = screen.frame.width / screen.frame.height
        guard aspectRatio >= 2 else { return baseDockWidth }
        return baseDockWidth * min(aspectRatio / 1.6, 1.33)
    }

    static let dockHeight = contentPadding * 2 + mapHeight + freeLaneHeight + footerHeight + sectionSpacing * 2

    static func panelWidth(for screen: NSScreen?) -> CGFloat {
        dockWidth(for: screen) + shadowPadding * 2
    }

    static let panelHeight = dockHeight + shadowPadding * 2

    /// How far below the panel's centre the row map ends and the free lane begins.
    static let freeLaneDistanceBelowCentre =
        (shadowPadding + contentPadding + mapHeight + sectionSpacing / 2) - panelHeight / 2
}

@MainActor
@Loggable
final class UltrawideDockController {
    private static let pointerDeadZone: CGFloat = 6
    /// Keeps a hovering pointer from flickering between the row and the free lane.
    private static let freeLaneHysteresis: CGFloat = 4

    private var controller: NSWindowController?
    private var viewModel: UltrawideDockViewModel?
    /// Maps pointer movement onto the mini-screen. Anchored on the panel, not on the pointer.
    private var activationMouseX: CGFloat = 0
    /// Where the pointer actually was at activation. Only the dead zone uses this, so opening the
    /// dock near a screen edge still requires real movement before anything is selected.
    private var activationPointerX: CGFloat = 0
    private var activationPointerY: CGFloat = 0
    /// Below this the pointer selects a free placement instead of a row target. Anchored on the
    /// pointer rather than the panel: near the bottom of the screen the panel is clamped upwards,
    /// and a panel-anchored boundary would then sit above the cursor and put the user in free mode
    /// before they moved at all. A fixed downward gesture always works.
    private var freeLaneBoundaryY: CGFloat = 0
    private var isFreeform = false
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
            return screen.frame.width / screen.frame.height >= Defaults[.ultrawideDockAutomaticAspectRatio]
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

        let dockWidth = UltrawideDockMetrics.dockWidth(for: screen)
        let panelWidth = UltrawideDockMetrics.panelWidth(for: screen)
        let panelHeight = UltrawideDockMetrics.panelHeight
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
        //
        // The anchor is the panel's centre, not the raw pointer: near a screen edge the panel gets
        // clamped away from the cursor, and anchoring on the pointer would then put the highlighted
        // target somewhere other than where the cursor sits on the mini-screen. Unclamped, the two
        // are identical.
        activationMouseX = originX + panelWidth / 2
        activationPointerX = pointer.x
        activationPointerY = pointer.y
        freeLaneBoundaryY = pointer.y - UltrawideDockMetrics.freeLaneDistanceBelowCentre
        isFreeform = false
        // Higher sensitivity means less mouse travel to sweep across the whole mini-screen.
        let sensitivity = min(max(CGFloat(Defaults[.ultrawideDockPointerSensitivity]), 0.25), 4)
        interactionSpan = max(1, (dockWidth - 20) / sensitivity)
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
        isFreeform = false
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
    func updateForMouse(_ pointer: CGPoint) -> WindowAction? {
        updateFreeform(for: pointer.y)
        if !hasLeftDeadZone {
            // Radial, not horizontal: dropping straight down into the free lane is a deliberate
            // choice too, and must break the dead zone just like sideways motion does.
            let travelled = hypot(pointer.x - activationPointerX, pointer.y - activationPointerY)
            guard travelled >= Self.pointerDeadZone else {
                return viewModel?.currentAction
            }
            hasLeftDeadZone = true
        }
        let action = viewModel?.updateForNormalizedX(normalizedX(for: pointer.x))
        updateCursor()
        return action
    }

    @discardableResult
    func pointerDown(at pointer: CGPoint) -> WindowAction? {
        updateFreeform(for: pointer.y)
        let action = viewModel?.pointerDown(at: normalizedX(for: pointer.x))
        updateCursor()
        return action
    }

    @discardableResult
    func drag(to pointer: CGPoint) -> WindowAction? {
        hasLeftDeadZone = true
        updateFreeform(for: pointer.y)
        let action = viewModel?.drag(to: normalizedX(for: pointer.x))
        updateCursor()
        return action
    }

    @discardableResult
    func pointerUp(at pointer: CGPoint) -> WindowAction? {
        updateFreeform(for: pointer.y)
        let action = viewModel?.pointerUp(at: normalizedX(for: pointer.x))
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

    /// Translates the pointer's height into the one bit the reducer needs. Only a change is
    /// forwarded, so hovering inside a lane never restarts the current selection.
    private func updateFreeform(for screenMouseY: CGFloat) {
        let threshold = freeLaneBoundaryY + (isFreeform ? Self.freeLaneHysteresis : -Self.freeLaneHysteresis)
        let shouldBeFreeform = screenMouseY < threshold
        guard shouldBeFreeform != isFreeform else { return }
        isFreeform = shouldBeFreeform
        viewModel?.setFreeform(shouldBeFreeform)
    }

    private func updateCursor() {
        switch viewModel?.cursor {
        case .resizeLeftRight: NSCursor.resizeLeftRight.set()
        default: NSCursor.arrow.set()
        }
    }
}
