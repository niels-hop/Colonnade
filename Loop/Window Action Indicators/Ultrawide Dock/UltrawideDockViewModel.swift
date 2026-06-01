//
//  UltrawideDockViewModel.swift
//  Loop
//
//  Created by Antigravity on 2025-11-18.
//

import Defaults
import SwiftUI

@MainActor
final class UltrawideDockViewModel: ObservableObject {
    struct WindowFrame: Identifiable {
        let id: CGWindowID
        let frame: CGRect // Normalized to 0-1 coordinate space
        let isActive: Bool
        let zIndex: Int // Z-order position (0 = frontmost)
    }

    /// A snap point on the dock. Each anchor represents a position where the new window's
    /// leading/trailing edge (or center) wants to snap. Anchors arise from screen edges and
    /// from the edges of already-positioned windows, so the set grows organically as the
    /// user places windows.
    struct Anchor: Identifiable {
        enum Edge { case leading, trailing, center }

        /// Distinguishes anchors at screen extremes (default to half-screen sizing) from
        /// anchors that abut an existing window (default to filling the available gap).
        enum Kind { case screenEdge, windowAdjacent, gapCenter }

        let id = UUID()
        let edge: Edge
        let kind: Kind
        /// X position on the screen where this anchor "lives" — used for mouse hit testing.
        let anchorX: Double
        /// Left/right bounds of the free range this anchor belongs to (normalized 0..1).
        let leftBound: Double
        let rightBound: Double

        var maxSpan: Double { max(0, rightBound - leftBound) }

        /// The size stops the user can cycle through by clicking.
        var cycleSteps: [Double] {
            switch kind {
            case .screenEdge:
                // Mirrors the historical "1/2, 1/3, 2/3" feel for empty edges.
                [0.5, 1.0 / 3.0, 2.0 / 3.0]
            case .windowAdjacent:
                // Default = fill the gap (lijmen aan zijkant), then progressively smaller.
                [1.0, 2.0 / 3.0, 0.5, 1.0 / 3.0]
            case .gapCenter:
                [0.5, 1.0, 2.0 / 3.0]
            }
        }

        func frame(sizeFraction: Double) -> CGRect {
            let span = max(0.05, min(maxSpan, sizeFraction * maxSpan))
            let x: Double = switch edge {
            case .leading: leftBound
            case .trailing: rightBound - span
            case .center: (leftBound + rightBound) / 2 - span / 2
            }
            return CGRect(x: x, y: 0, width: span, height: 1)
        }
    }

    @Published private(set) var currentAction: WindowAction?
    @Published private(set) var previewFrame: CGRect = .zero
    @Published private(set) var existingWindows: [WindowFrame] = []
    @Published private(set) var anchors: [Anchor] = []
    @Published private(set) var activeAnchorID: UUID?

    /// Index into the active anchor's cycleSteps. Reset whenever the active anchor changes.
    private var sizeStepIndex: Int = 0
    /// Extra ± offset on top of the cycle step, as a fraction of maxSpan. Driven by scroll wheel.
    private var scrollFractionDelta: Double = 0

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

        // Loading existing windows hops to the `WindowRecords` actor, so it runs asynchronously.
        // The dock opens immediately and the anchors/preview populate a tick later.
        Task { @MainActor in
            await loadExistingWindows()
            rebuildAnchors()
            // Default to the center anchor so the initial preview is centered, like before.
            if let center = anchors.first(where: { $0.edge == .center }) {
                setActiveAnchor(center)
            } else if let first = anchors.first {
                setActiveAnchor(first)
            }
        }
    }

    /// Reloads the on-screen window set from `WindowRecords` and recomputes anchors + preview.
    private func reload() async {
        await loadExistingWindows()
        rebuildAnchors()
        recomputePreview()
    }

    var invalidWindowSelected: Bool {
        window == nil && !previewMode
    }

    func setWindow(to newWindow: Window) {
        // `openAndUpdate` (and thus `setWindow`) fires on every mouse move. Reloading only makes
        // sense when the window we're positioning actually changes — otherwise the repeated
        // `reload()` re-enumerates all windows and rebuilds anchors with fresh UUIDs each tick,
        // which is both expensive and resets the active anchor selection. The nil→window
        // transition still reloads (recomputes anchors now skipping the known current window).
        guard window?.cgWindowID != newWindow.cgWindowID else { return }
        window = newWindow
        Task { @MainActor in await reload() }
    }

    /// In live (non-preview) mode the viewmodel is the source of truth for the preview, so we
    /// only honor externally pushed actions when used as a settings-UI preview.
    func setAction(to action: WindowAction) {
        currentAction = action
        if previewMode {
            let bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
            let frame = WindowFrameResolver.getFrame(for: action, bounds: bounds, padding: .zero)
            withAnimation(.snappy) { previewFrame = frame }
        }
    }

    func refresh() {
        Task { @MainActor in await reload() }
    }

    // MARK: - Anchor interaction

    /// Updates the active anchor based on a normalized cursor X (0 = left edge, 1 = right edge of
    /// the dock's mini-screen). The controller maps the raw cursor position into this dock-relative
    /// space, so a small physical movement across the dock spans the whole screen's anchors.
    @discardableResult
    func updateForNormalizedX(_ normalizedX: Double) -> WindowAction? {
        guard !anchors.isEmpty else { return currentAction }

        let nearest = anchors.min(by: { abs($0.anchorX - normalizedX) < abs($1.anchorX - normalizedX) })
        guard let nearest else { return currentAction }

        if nearest.id != activeAnchorID {
            setActiveAnchor(nearest)
        }
        return currentAction
    }

    @discardableResult
    func cycleSize() -> WindowAction? {
        guard let active = activeAnchor else { return currentAction }
        sizeStepIndex = (sizeStepIndex + 1) % active.cycleSteps.count
        scrollFractionDelta = 0
        recomputePreview()
        return currentAction
    }

    /// Scroll wheel fine-tune. `delta` is in fraction-of-maxSpan units (e.g. ±0.04 per tick).
    @discardableResult
    func adjustSize(by delta: Double) -> WindowAction? {
        scrollFractionDelta += delta
        recomputePreview()
        return currentAction
    }

    // MARK: - Internals

    private var activeAnchor: Anchor? {
        anchors.first(where: { $0.id == activeAnchorID })
    }

    private func setActiveAnchor(_ anchor: Anchor) {
        activeAnchorID = anchor.id
        sizeStepIndex = 0
        scrollFractionDelta = 0
        recomputePreview()
    }

    private func recomputePreview() {
        guard let active = activeAnchor else {
            previewFrame = .zero
            currentAction = WindowAction(.noAction)
            return
        }

        let step = active.cycleSteps[sizeStepIndex]
        let fraction = max(0.1, min(1.0, step + scrollFractionDelta))
        let frame = active.frame(sizeFraction: fraction)

        withAnimation(.snappy) {
            previewFrame = frame
        }
        currentAction = makeCustomAction(from: frame)
    }

    private func makeCustomAction(from frame: CGRect) -> WindowAction {
        // Coordinates positionMode + percentage unit lets us express any (x, width) on the
        // current screen. Height is full screen so the dock stays a single horizontal rail.
        WindowAction(
            .custom,
            keybind: [],
            name: nil,
            unit: .percentage,
            anchor: nil,
            width: Double(frame.width * 100),
            height: 100.0,
            xPoint: Double(frame.minX * 100),
            yPoint: 0.0,
            positionMode: .coordinates,
            sizeMode: nil,
            cycle: nil
        )
    }

    private func rebuildAnchors() {
        // Compute free horizontal ranges on the screen that are not covered by any existing
        // Loop-positioned window (these are full-height tiles in this dock's model).
        let occupied = existingWindows
            .map { ($0.frame.minX, $0.frame.maxX) }
            .sorted { $0.0 < $1.0 }

        var ranges: [(Double, Double)] = []
        var cursor: Double = 0
        for (a, b) in occupied {
            if b <= cursor { continue }
            if a > cursor + 0.02 {
                ranges.append((cursor, a))
            }
            cursor = max(cursor, b)
        }
        if cursor < 1.0 - 0.02 {
            ranges.append((cursor, 1.0))
        }
        if ranges.isEmpty {
            // Screen entirely covered — fall back to a full-screen range so the user can still
            // place a window (overlap is fine; placed-window detection is just a hint).
            ranges = [(0, 1)]
        }

        var newAnchors: [Anchor] = []
        let tolerance = 0.001
        for (a, b) in ranges {
            let leftIsScreenEdge = a < tolerance
            let rightIsScreenEdge = b > 1 - tolerance

            newAnchors.append(Anchor(
                edge: .leading,
                kind: leftIsScreenEdge ? .screenEdge : .windowAdjacent,
                anchorX: a,
                leftBound: a,
                rightBound: b
            ))
            newAnchors.append(Anchor(
                edge: .trailing,
                kind: rightIsScreenEdge ? .screenEdge : .windowAdjacent,
                anchorX: b,
                leftBound: a,
                rightBound: b
            ))
            let isFullScreen = leftIsScreenEdge && rightIsScreenEdge
            newAnchors.append(Anchor(
                edge: .center,
                kind: isFullScreen ? .screenEdge : .gapCenter,
                anchorX: (a + b) / 2,
                leftBound: a,
                rightBound: b
            ))
        }

        anchors = newAnchors

        if activeAnchorID == nil || !anchors.contains(where: { $0.id == activeAnchorID }) {
            if let center = anchors.first(where: { $0.edge == .center }) {
                activeAnchorID = center.id
                sizeStepIndex = 0
                scrollFractionDelta = 0
            }
        }
    }

    private func loadExistingWindows() async {
        guard let screen else {
            existingWindows = []
            return
        }

        let screenFrame = screen.frame
        let safeScreenFrame = screen.safeScreenFrame
        var windowFrames: [WindowFrame] = []

        let allWindows = WindowUtility.windowList()

        for (index, win) in allWindows.enumerated() {
            let isCurrentWindow = window.map { win.cgWindowID == $0.cgWindowID } ?? false

            let winFrame = win.frame
            guard screenFrame.intersects(winFrame) else {
                continue
            }

            // Skip the window we're currently positioning — it shouldn't constrain its own placement.
            if isCurrentWindow {
                continue
            }

            guard let action = await WindowRecords.shared.getCurrentAction(for: win) else {
                continue
            }
            let targetFrame = WindowFrameResolver.getFrame(
                for: action,
                bounds: safeScreenFrame,
                padding: PaddingConfiguration.getConfiguredPadding(for: screen)
            )
            guard winFrame.approximatelyEqual(to: targetFrame, tolerance: 10) else {
                continue
            }

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
                zIndex: index
            ))
        }

        withAnimation(.snappy) {
            existingWindows = windowFrames
        }
    }
}
