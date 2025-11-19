//
//  UltrawideDockViewModel.swift
//  Loop
//
//  Created by Antigravity on 2025-11-18.
//

import Defaults
import SwiftUI

final class UltrawideDockViewModel: ObservableObject {
    struct WindowFrame: Identifiable {
        let id: CGWindowID
        let frame: CGRect // Normalized to 0-1 coordinate space
        let isActive: Bool
        let zIndex: Int // Z-order position (0 = frontmost)
    }

    @Published private(set) var currentAction: WindowAction?
    @Published private(set) var previewFrame: CGRect = .zero
    @Published private(set) var existingWindows: [WindowFrame] = []

    private var window: Window?
    private var screen: NSScreen?
    let previewMode: Bool

    init(
        startingAction: WindowAction?,
        window: Window?,
        screen: NSScreen?,
        previewMode: Bool
    ) {
        self.currentAction = startingAction
        self.window = window
        self.screen = screen
        self.previewMode = previewMode

        recomputePreviewFrame()
        loadExistingWindows()
    }

    var invalidWindowSelected: Bool {
        window == nil && !previewMode
    }

    func setWindow(to newWindow: Window) {
        window = newWindow
        recomputePreviewFrame()
        loadExistingWindows()
    }

    func setAction(to action: WindowAction) {
        currentAction = action
        recomputePreviewFrame()
    }

    func refresh() {
        recomputePreviewFrame()
        loadExistingWindows()
    }

    private func recomputePreviewFrame() {
        guard let action = currentAction else {
            previewFrame = .zero
            return
        }

        // Calculate the frame as if the screen is 1x1
        let bounds = CGRect(x: 0, y: 0, width: 1, height: 1)

        // We need to handle the case where window is nil (e.g. preview mode or no window selected yet)
        // But getFrame usually handles nil window by assuming some defaults or centering.

        let frame = action.getFrame(
            window: window,
            bounds: bounds,
            disablePadding: true
        )

        withAnimation(.snappy) {
            previewFrame = frame
        }
    }

    private func loadExistingWindows() {
        guard let screen else {
            existingWindows = []
            return
        }

        let screenFrame = screen.frame
        let safeScreenFrame = screen.safeScreenFrame
        var windowFrames: [WindowFrame] = []

        // Get all windows on screen (already z-ordered, frontmost first)
        let allWindows = WindowUtility.windowList()

        for (index, win) in allWindows.enumerated() {
            // Only include windows that have been positioned with Loop
            guard WindowRecords.hasBeenRecorded(win) else {
                continue
            }

            // Check if this is the current window we're positioning
            let isCurrentWindow = window.map { win.cgWindowID == $0.cgWindowID } ?? false

            // Check if window is on the current screen
            let winFrame = win.frame
            guard screenFrame.intersects(winFrame) else {
                continue
            }

            // For windows OTHER than the current one, validate they're still at Loop position
            if !isCurrentWindow {
                // Validate that window is still at its Loop-assigned position
                // Get the action that was used to position this window
                guard let action = WindowRecords.getCurrentAction(for: win) else {
                    continue
                }

                // Calculate the target frame this window should be at
                let targetFrame = action.getFrame(
                    window: win,
                    bounds: safeScreenFrame,
                    screen: screen
                )

                // Only show windows that are still at their Loop-assigned position (within 10px tolerance)
                guard winFrame.approximatelyEqual(to: targetFrame, tolerance: 10) else {
                    continue
                }
            }

            // Normalize frame to 0-1 coordinate space
            let normalizedFrame = CGRect(
                x: (winFrame.minX - screenFrame.minX) / screenFrame.width,
                y: (winFrame.minY - screenFrame.minY) / screenFrame.height,
                width: winFrame.width / screenFrame.width,
                height: winFrame.height / screenFrame.height
            )

            windowFrames.append(WindowFrame(
                id: win.cgWindowID,
                frame: normalizedFrame,
                isActive: false,
                zIndex: index // Z-order position (0 = frontmost)
            ))
        }

        withAnimation(.snappy) {
            existingWindows = windowFrames
        }
    }
}
