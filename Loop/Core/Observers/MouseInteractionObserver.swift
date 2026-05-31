//
//  MouseInteractionObserver.swift
//  Loop
//
//  Created by Kai Azim on 2025-11-11.
//

import Defaults
import Scribe
import SwiftUI

@Loggable
final class MouseInteractionObserver {
    private static let directionalActionDistance: CGFloat = 50
    private static let noActionDistance: CGFloat = 10

    // Parameters
    private let windowActionCache: WindowActionCache
    private let changeAction: (WindowAction) -> ()
    private let selectNextCycleItem: () -> ()
    private let canSelectNextCycleitem: () -> Bool
    private let checkIfLoopOpen: () -> Bool

    // Ultrawide Dock hooks. When the dock is active it replaces the radial menu: mouse movement
    // selects an anchor, clicks cycle the size, and the scroll wheel fine-tunes the width.
    private let isDockActive: () -> Bool
    private let dockMouseMoved: (CGFloat) -> ()
    private let cycleDockSize: () -> ()
    private let adjustDockSize: (Double) -> ()

    private var mouseMovementMonitor: PassiveEventMonitor?
    private var leftClickMonitor: ActiveEventMonitor?
    private var scrollWheelMonitor: PassiveEventMonitor?

    // State-keeping for previous calculations
    private var previousAngleToMouse: Angle = .zero
    private var previousDistanceToMouse: CGFloat = .zero

    private var screenBounds: CGRect?
    private var shouldAccountForAbsoluteMousePosition: Bool = false
    private var initialMousePosition: CGPoint = .zero
    private var latestMousePosition: CGPoint = .zero

    private var radialMenuActions: [RadialMenuAction] {
        RadialMenuAction.userConfiguredActions
    }

    private static let failedToResolveKeybindAction: WindowAction = .init(.noAction) // This helps to keep a stable ID

    init(
        windowActionCache: WindowActionCache,
        changeAction: @escaping (WindowAction) -> (),
        selectNextCycleItem: @escaping () -> (),
        canSelectNextCycleitem: @escaping () -> Bool,
        checkIfLoopOpen: @escaping () -> Bool,
        isDockActive: @escaping () -> Bool,
        dockMouseMoved: @escaping (CGFloat) -> (),
        cycleDockSize: @escaping () -> (),
        adjustDockSize: @escaping (Double) -> ()
    ) {
        self.windowActionCache = windowActionCache
        self.changeAction = changeAction
        self.selectNextCycleItem = selectNextCycleItem
        self.canSelectNextCycleitem = canSelectNextCycleitem
        self.checkIfLoopOpen = checkIfLoopOpen
        self.isDockActive = isDockActive
        self.dockMouseMoved = dockMouseMoved
        self.cycleDockSize = cycleDockSize
        self.adjustDockSize = adjustDockSize
    }

    func start(initialMousePosition: CGPoint) {
        stop()

        screenBounds = NSScreen.screens.first(where: { $0.frame.contains(initialMousePosition) })?.frame

        if let screenBounds {
            // If the current mouse position isn't sufficient for accessing direcitonal actions due to being close to the screen's edge, then enable `shouldAccountForAbsoluteMousePosition`
            let closeToMinX = abs(initialMousePosition.x - screenBounds.minX) < Self.directionalActionDistance
            let closeToMaxX = abs(initialMousePosition.x - screenBounds.maxX) < Self.directionalActionDistance
            let closeToMinY = abs(initialMousePosition.y - screenBounds.minY) < Self.directionalActionDistance
            let closeToMaxY = abs(initialMousePosition.y - screenBounds.maxY) < Self.directionalActionDistance

            if closeToMinX || closeToMaxX || closeToMinY || closeToMaxY {
                shouldAccountForAbsoluteMousePosition = true
            }
        }

        self.initialMousePosition = initialMousePosition
        latestMousePosition = initialMousePosition

        let mouseMovementMonitor = PassiveEventMonitor(
            "mouse_movement_monitor",
            events: [
                .mouseMoved, // switch action when mouse is moved
                .otherMouseDragged // switch action when mouse is moved with the middle mouse button clicked
            ],
            callback: processNewMouseLocation
        )
        mouseMovementMonitor.start()
        self.mouseMovementMonitor = mouseMovementMonitor

        let leftClickMonitor = ActiveEventMonitor(
            "left_click_monitor",
            events: [.leftMouseDown], // Increment a cycle action on a left click
            callback: activateNextCycleAction
        )
        leftClickMonitor.start()
        self.leftClickMonitor = leftClickMonitor

        // The scroll wheel only does anything while the Ultrawide Dock is active (fine-tuning the
        // width). It's harmless otherwise: the callback early-returns when the dock isn't driving.
        let scrollWheelMonitor = PassiveEventMonitor(
            "scroll_wheel_monitor",
            events: [.scrollWheel],
            callback: processScrollWheel
        )
        scrollWheelMonitor.start()
        self.scrollWheelMonitor = scrollWheelMonitor

        log.info("Started with initial mouse position: \(latestMousePosition.debugDescription)")
    }

    func stop() {
        mouseMovementMonitor?.stop()
        mouseMovementMonitor = nil

        leftClickMonitor?.stop()
        leftClickMonitor = nil

        scrollWheelMonitor?.stop()
        scrollWheelMonitor = nil

        previousAngleToMouse = .zero
        previousDistanceToMouse = .zero

        screenBounds = nil
        shouldAccountForAbsoluteMousePosition = false
        initialMousePosition = .zero
        latestMousePosition = .zero

        log.success("Stopped, all stored states cleared.")
    }

    private func processNewMouseLocation(_ event: CGEvent) {
        guard checkIfLoopOpen() else { return }

        Task {
            let currentMousePosition = computeLatestMousePosition(event)
            let angleToMouse = initialMousePosition.angle(to: currentMousePosition) + .radians(.pi / 2)
            let distanceToMouse = initialMousePosition.distance(to: currentMousePosition)

            // Return if the mouse didn't move
            guard
                angleToMouse != previousAngleToMouse ||
                distanceToMouse != previousDistanceToMouse
            else {
                return
            }

            // Get angle & distance to mouse
            previousAngleToMouse = angleToMouse
            previousDistanceToMouse = distanceToMouse

            // Ultrawide Dock: anchor selection is driven by the absolute screen mouse-X rather than
            // the radial angle/distance, so branch out before the radial-menu math runs.
            if isDockActive() {
                dockMouseMoved(currentMousePosition.x)
                return
            }

            var newAction: RadialMenuAction? = nil

            // If mouse over 50 points away, select half or quarter positions
            if distanceToMouse > Self.directionalActionDistance - Defaults[.radialMenuThickness] {
                guard radialMenuActions.count > 1 else {
                    newAction = radialMenuActions.first
                    return
                }

                let actions = radialMenuActions.dropLast()
                let actionAngleSpan = 360.0 / CGFloat(actions.count)
                let halfAngleSpan = actionAngleSpan / 2.0
                let index = Int((angleToMouse.normalized().degrees + halfAngleSpan) / actionAngleSpan) % actions.count
                newAction = actions[index]
            } else if distanceToMouse > Self.noActionDistance {
                newAction = radialMenuActions.last
            }

            switch newAction?.type {
            case let .custom(windowAction):
                changeAction(windowAction)
            case let .keybindReference(id):
                if let action = windowActionCache.actionsByIdentifier[id] {
                    changeAction(action)
                } else {
                    changeAction(Self.failedToResolveKeybindAction)
                }
            case nil:
                changeAction(.init(.noSelection))
            }
        }
    }

    /// Computes a resolved mouse position, compensating for macOS cursor clamping at screen edges.
    ///
    /// When enabled, this method continues tracking movement along an axis even after the system
    /// cursor becomes pinned to a screen edge by applying the event’s delta to the last known position,
    /// while clamping the result to a limited distance from the edge, just enough to access directional actions.
    ///
    /// - Parameter event: the CGEvent associated with this mouse movement
    /// - Returns: the computed absolute mouse position
    private func computeLatestMousePosition(_ event: CGEvent) -> CGPoint {
        let current = NSEvent.mouseLocation

        guard shouldAccountForAbsoluteMousePosition, let bounds = screenBounds else {
            latestMousePosition = current
            return latestMousePosition
        }

        let edgeThreshold: CGFloat = 1
        let deltaX = event.getDoubleValueField(.mouseEventDeltaX)
        let deltaY = event.getDoubleValueField(.mouseEventDeltaY)
        let maxOffset = Self.directionalActionDistance

        let atMinX = abs(current.x - bounds.minX) < edgeThreshold
        let atMaxX = abs(current.x - bounds.maxX) < edgeThreshold
        let atMinY = abs(current.y - bounds.minY) < edgeThreshold
        let atMaxY = abs(current.y - bounds.maxY) < edgeThreshold

        var resolved = current

        if atMinX || atMaxX {
            let unclampedX = latestMousePosition.x + deltaX
            let minX = bounds.minX - maxOffset
            let maxX = bounds.maxX + maxOffset

            resolved.x = min(max(unclampedX, minX), maxX)

        } else if atMinY || atMaxY {
            let unclampedY = latestMousePosition.y + deltaY
            let minY = bounds.minY - maxOffset
            let maxY = bounds.maxY + maxOffset

            resolved.y = min(max(unclampedY, minY), maxY)
        }

        latestMousePosition = resolved
        return resolved
    }

    private func activateNextCycleAction(_ event: CGEvent) -> ActiveEventMonitor.EventHandling {
        // Ensure that the source originates from the HID state ID.
        // Otherwise, this event was likely sent from Loop to focus the frontmost click (see `Window.focus` which sends a `SLSEvent` to the window)
        let sourceID = CGEventSourceStateID(rawValue: Int32(event.getIntegerValueField(.eventSourceStateID)))
        guard sourceID == .hidSystemState else {
            return .forward
        }

        // Ultrawide Dock: a click cycles the size at the active anchor (e.g. 1/2 → 1/3 → 2/3)
        // instead of advancing a radial cycle item.
        if isDockActive() {
            guard checkIfLoopOpen() else { return .forward }
            cycleDockSize()
            return .ignore
        }

        guard checkIfLoopOpen(), canSelectNextCycleitem() else {
            return .forward
        }

        selectNextCycleItem()

        return .ignore
    }

    /// Scroll-wheel fine-tunes the width at the current anchor while the Ultrawide Dock is open.
    /// One detent ≈ 4% of the available span; the sign follows the OS's natural-scroll setting.
    private func processScrollWheel(_ event: CGEvent) {
        guard checkIfLoopOpen(), isDockActive() else { return }

        // Use the vertical scroll axis: scroll up = grow, scroll down = shrink. The pixel value
        // gives sub-detent precision on trackpads; clamp so a fast flick can't overshoot one full
        // step in a single event.
        let dyPixels = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let dyLine = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
        let raw = dyPixels != 0 ? dyPixels / 200.0 : dyLine * 0.04
        let delta = max(-0.1, min(0.1, raw))
        guard delta != 0 else { return }

        adjustDockSize(delta)
    }
}
