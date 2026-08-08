import AppKit
import CoreGraphics

struct HorizontalLayoutRuntimeWindow {
    let id: HorizontalLayoutTileID
    let window: Window
    let normalizedFrame: CGRect
    let zIndex: Int
    let isCurrent: Bool
}

@MainActor
struct HorizontalLayoutRuntimeSnapshot {
    let layout: HorizontalLayoutSnapshot
    let windows: [HorizontalLayoutRuntimeWindow]
    let windowsByID: [HorizontalLayoutTileID: Window]
    let currentID: HorizontalLayoutTileID
    let currentIsTile: Bool
    let usableBounds: CGRect
    let padding: PaddingConfiguration
    let screen: NSScreen
}

@MainActor
struct HorizontalLayoutRuntimeCapture {
    let displayWindows: [HorizontalLayoutRuntimeWindow]
    let snapshot: HorizontalLayoutRuntimeSnapshot?
}

@MainActor
struct HorizontalLayoutPendingExecution {
    let plan: HorizontalLayoutPlan
    let changedIDs: [HorizontalLayoutTileID]
    let windowsByID: [HorizontalLayoutTileID: Window]
    let usableBounds: CGRect
    let padding: PaddingConfiguration
    let screen: NSScreen

    var normalizedFrames: [HorizontalLayoutTileID: CGRect] {
        Dictionary(uniqueKeysWithValues: plan.snapshot.tiles.map { ($0.id, $0.frame) })
    }
}

/// Adapts real, visible Accessibility windows to the pure horizontal-layout engine.
@MainActor
struct HorizontalLayoutRuntimeAdapter {
    static let minimumWidth: CGFloat = 0.1
    private static let fullHeightTolerance: CGFloat = 12
    private static let adjacencyTolerance: CGFloat = 14

    func capture(currentWindow: Window?, screen: NSScreen) -> HorizontalLayoutRuntimeCapture {
        let padding = PaddingConfiguration.getConfiguredPadding(for: screen)
        let usableBounds = padding.applyToBounds(screen.cgSafeScreenFrame, screen: screen)
        guard usableBounds.width > 0, usableBounds.height > 0 else {
            return HorizontalLayoutRuntimeCapture(displayWindows: [], snapshot: nil)
        }

        let currentID = currentWindow.map(Self.stableID)
        var seen = Set<CGWindowID>()
        var displayWindows: [HorizontalLayoutRuntimeWindow] = []

        for (zIndex, window) in WindowUtility.windowList().enumerated() {
            guard seen.insert(window.cgWindowID).inserted,
                  !window.isOwnWindow,
                  !window.isAppExcluded,
                  !window.fullscreen,
                  !window.minimized,
                  !window.isApplicationHidden,
                  window.isResizable
            else {
                continue
            }

            let frame = window.frame
            guard frame.midX >= usableBounds.minX,
                  frame.midX <= usableBounds.maxX,
                  abs(frame.minY - usableBounds.minY) <= Self.fullHeightTolerance,
                  abs(frame.maxY - usableBounds.maxY) <= Self.fullHeightTolerance,
                  frame.width > 0
            else {
                continue
            }

            let id = Self.stableID(window)
            let normalized = CGRect(
                x: max(0, (frame.minX - usableBounds.minX) / usableBounds.width),
                y: 0,
                width: min(1, frame.width / usableBounds.width),
                height: 1
            )
            guard normalized.minX < 1 else { continue }

            displayWindows.append(HorizontalLayoutRuntimeWindow(
                id: id,
                window: window,
                normalizedFrame: CGRect(
                    x: normalized.minX,
                    y: 0,
                    width: min(normalized.width, 1 - normalized.minX),
                    height: 1
                ),
                zIndex: zIndex,
                isCurrent: id == currentID
            ))
        }

        guard let currentWindow, let currentID else {
            return HorizontalLayoutRuntimeCapture(displayWindows: displayWindows, snapshot: nil)
        }

        // The target window may not be present in the on-screen enumeration during a transient app switch.
        // It still needs a binding as the incoming tile, but only full-height visible windows enter the row.
        var windowsByID = Dictionary(uniqueKeysWithValues: displayWindows.map { ($0.id, $0.window) })
        windowsByID[currentID] = currentWindow

        do {
            let layout = try HorizontalLayoutRuntimeGeometry.makeSnapshot(
                from: displayWindows.map { HorizontalLayoutTile(id: $0.id, frame: $0.normalizedFrame) },
                adjacencyTolerance: Self.adjacencyTolerance / usableBounds.width
            )
            let runtime = HorizontalLayoutRuntimeSnapshot(
                layout: layout,
                windows: displayWindows,
                windowsByID: windowsByID,
                currentID: currentID,
                currentIsTile: layout.tiles.contains(where: { $0.id == currentID }),
                usableBounds: usableBounds,
                padding: padding,
                screen: screen
            )
            return HorizontalLayoutRuntimeCapture(displayWindows: displayWindows, snapshot: runtime)
        } catch {
            // An already-overlapping row is not silently repaired. The dock keeps its single-window
            // anchors available, but multi-window operations stay disabled until the row is valid.
            return HorizontalLayoutRuntimeCapture(displayWindows: displayWindows, snapshot: nil)
        }
    }

    static func stableID(_ window: Window) -> HorizontalLayoutTileID {
        HorizontalLayoutTileID(rawValue: "\(window.pid):\(window.cgWindowID)")
    }

    static func logicalFrame(_ normalized: CGRect, in bounds: CGRect) -> CGRect {
        HorizontalLayoutRuntimeGeometry.logicalFrame(normalized, in: bounds)
    }

    static func action(for normalized: CGRect, name: String = "horizontal_layout") -> WindowAction {
        WindowAction(
            .custom,
            keybind: [],
            name: name,
            unit: .percentage,
            anchor: nil,
            width: normalized.width * 100,
            height: 100,
            xPoint: normalized.minX * 100,
            yPoint: 0,
            positionMode: .coordinates,
            sizeMode: .custom,
            cycle: nil
        )
    }
}
