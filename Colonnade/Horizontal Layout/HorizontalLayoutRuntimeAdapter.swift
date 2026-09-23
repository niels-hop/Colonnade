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
    let scene: UltrawideDockScene
    let windows: [HorizontalLayoutRuntimeWindow]
    let windowsByID: [HorizontalLayoutTileID: Window]
    let currentID: HorizontalLayoutTileID
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
    let membersByTileID: [HorizontalLayoutTileID: [HorizontalLayoutTileID]]
    let changedWindowIDs: [HorizontalLayoutTileID]
    let windowsByID: [HorizontalLayoutTileID: Window]
    let usableBounds: CGRect
    let padding: PaddingConfiguration
    let screen: NSScreen

    var normalizedFrames: [HorizontalLayoutTileID: CGRect] {
        var result: [HorizontalLayoutTileID: CGRect] = [:]
        for tile in plan.snapshot.tiles {
            for windowID in membersByTileID[tile.id] ?? [tile.id] {
                result[windowID] = tile.frame
            }
        }
        return result
    }

    var changedTileIDs: Set<HorizontalLayoutTileID> {
        let changed = Set(changedWindowIDs)
        return Set(plan.snapshot.tiles.compactMap { tile in
            let members = membersByTileID[tile.id] ?? [tile.id]
            return members.contains(where: changed.contains) ? tile.id : nil
        })
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
            let scene = try UltrawideDockScene(
                windows: displayWindows.map {
                    UltrawideDockWindowSnapshot(id: $0.id, frame: $0.normalizedFrame, zIndex: $0.zIndex)
                },
                currentID: currentID,
                frameTolerance: Self.adjacencyTolerance / usableBounds.width
            )
            let runtime = HorizontalLayoutRuntimeSnapshot(
                scene: scene,
                windows: displayWindows,
                windowsByID: windowsByID,
                currentID: currentID,
                usableBounds: usableBounds,
                padding: padding,
                screen: screen
            )
            return HorizontalLayoutRuntimeCapture(displayWindows: displayWindows, snapshot: runtime)
        } catch {
            // `UltrawideDockScene` stacks exact overlaps and excludes partially intersecting windows
            // from the row, so this is only reached for genuinely unusable geometry.
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
