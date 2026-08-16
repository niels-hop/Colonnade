import CoreGraphics
import Foundation

struct UltrawideDockWindowSnapshot: Equatable, Sendable {
    let id: HorizontalLayoutTileID
    let frame: CGRect
    let zIndex: Int
}

struct UltrawideDockSlot: Equatable, Identifiable, Sendable {
    let id: HorizontalLayoutTileID
    let memberIDs: [HorizontalLayoutTileID]
    let frame: CGRect

    func contains(_ windowID: HorizontalLayoutTileID) -> Bool {
        memberIDs.contains(windowID)
    }
}

/// A dock scene groups windows with the same full-height frame into one horizontal slot. The
/// horizontal engine still sees a non-overlapping row, while the interaction layer can place
/// multiple windows in one slot without moving any of its existing members.
///
/// Windows that genuinely overlap cannot all be part of one row. Instead of rejecting the whole
/// scene — which used to leave the dock completely inert — the conflicting ones are excluded from
/// the row. They are never planned and never moved, but callers must keep drawing them: showing
/// free space where a real window sits would be worse than the row being incomplete.
struct UltrawideDockScene: Equatable, Sendable {
    let windows: [UltrawideDockWindowSnapshot]
    let currentID: HorizontalLayoutTileID
    let slots: [UltrawideDockSlot]
    let excludedWindowIDs: [HorizontalLayoutTileID]
    let layout: HorizontalLayoutSnapshot

    init(
        windows: [UltrawideDockWindowSnapshot],
        currentID: HorizontalLayoutTileID,
        frameTolerance: CGFloat
    ) throws {
        guard frameTolerance.isFinite, frameTolerance >= 0 else {
            throw HorizontalLayoutError.invalidDestination
        }

        var seen = Set<HorizontalLayoutTileID>()
        for window in windows {
            guard seen.insert(window.id).inserted else {
                throw HorizontalLayoutError.duplicateTileID(window.id)
            }
        }

        var grouped: [(frame: CGRect, members: [UltrawideDockWindowSnapshot])] = []
        for window in windows.sorted(by: Self.zOrder) {
            if let index = grouped.firstIndex(where: {
                Self.framesRepresentSameSlot($0.frame, window.frame, tolerance: frameTolerance)
            }) {
                grouped[index].members.append(window)
            } else {
                grouped.append((window.frame, [window]))
            }
        }

        let candidates = grouped.map { group -> UltrawideDockSlot in
            let members = group.members.sorted(by: Self.zOrder)
            return UltrawideDockSlot(
                id: members[0].id,
                memberIDs: members.map(\.id),
                frame: group.frame
            )
        }

        // Widest first: a single narrow window straddling a boundary should lose its place in the
        // row, not evict the two large windows it happens to overlap.
        let others = candidates
            .filter { !$0.contains(currentID) }
            .sorted { lhs, rhs in
                if lhs.frame.width != rhs.frame.width { return lhs.frame.width > rhs.frame.width }
                if lhs.frame.minX != rhs.frame.minX { return lhs.frame.minX < rhs.frame.minX }
                return lhs.id.rawValue < rhs.id.rawValue
            }

        var accepted: [UltrawideDockSlot] = []
        var excluded: [UltrawideDockSlot] = []
        for candidate in others {
            let conflicts = accepted.contains {
                Self.framesConflict($0.frame, candidate.frame, tolerance: frameTolerance)
            }
            if conflicts { excluded.append(candidate) } else { accepted.append(candidate) }
        }

        // The current window is the incoming one, so it goes last and never pushes an existing
        // window out of the row. If it does not fit it simply stays outside, ready to be placed.
        if let currentCandidate = candidates.first(where: { $0.contains(currentID) }) {
            let conflicts = accepted.contains {
                Self.framesConflict($0.frame, currentCandidate.frame, tolerance: frameTolerance)
            }
            if conflicts {
                let bystanders = currentCandidate.memberIDs.filter { $0 != currentID }
                if let representative = bystanders.first {
                    excluded.append(UltrawideDockSlot(
                        id: representative,
                        memberIDs: bystanders,
                        frame: currentCandidate.frame
                    ))
                }
            } else {
                accepted.append(currentCandidate)
            }
        }

        let ordered = accepted.sorted { $0.frame.minX < $1.frame.minX }
        let orderedByID = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
        let layout = try HorizontalLayoutRuntimeGeometry.makeSnapshot(
            from: ordered.map { HorizontalLayoutTile(id: $0.id, frame: $0.frame) },
            adjacencyTolerance: frameTolerance
        )

        self.windows = windows
        self.currentID = currentID
        self.layout = layout
        self.slots = layout.tiles.compactMap { tile in
            guard let slot = orderedByID[tile.id] else { return nil }
            return UltrawideDockSlot(id: slot.id, memberIDs: slot.memberIDs, frame: tile.frame)
        }
        self.excludedWindowIDs = excluded
            .sorted { $0.frame.minX < $1.frame.minX }
            .flatMap(\.memberIDs)
    }

    var currentSlot: UltrawideDockSlot? {
        slots.first { $0.contains(currentID) }
    }

    func slot(id: HorizontalLayoutTileID) -> UltrawideDockSlot? {
        slots.first { $0.id == id }
    }

    private static func zOrder(
        _ lhs: UltrawideDockWindowSnapshot,
        _ rhs: UltrawideDockWindowSnapshot
    ) -> Bool {
        if lhs.zIndex == rhs.zIndex { return lhs.id.rawValue < rhs.id.rawValue }
        return lhs.zIndex < rhs.zIndex
    }

    private static func framesRepresentSameSlot(
        _ lhs: CGRect,
        _ rhs: CGRect,
        tolerance: CGFloat
    ) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance &&
            abs(lhs.minY - rhs.minY) <= tolerance &&
            abs(lhs.height - rhs.height) <= tolerance
    }

    /// Padding-sized intersections are bridged by the runtime geometry, so only a real overlap
    /// counts as a conflict.
    private static func framesConflict(
        _ lhs: CGRect,
        _ rhs: CGRect,
        tolerance: CGFloat
    ) -> Bool {
        min(lhs.maxX, rhs.maxX) - max(lhs.minX, rhs.minX) > tolerance
    }
}

enum UltrawideDockEdge: Equatable, Sendable {
    case leading
    case center
    case trailing
}

enum UltrawideDockTarget: Equatable, Sendable {
    case place(edge: UltrawideDockEdge)
    case insert(position: CGFloat)
    case stack(slotID: HorizontalLayoutTileID)
    case current(slotID: HorizontalLayoutTileID)
    case divider(after: HorizontalLayoutTileID)
}

enum UltrawideDockOperation: Equatable, Sendable {
    case idle
    case placement
    case stack(existingCount: Int)
    case insert(rebalanced: Bool)
    case move
    case current
    case resizeReady
    case resize
    case unavailable
}

enum UltrawideDockCursor: Equatable, Sendable {
    case arrow
    case resizeLeftRight
}

enum UltrawideDockWindowCommitKind: Equatable, Sendable {
    case placement
    case stack
}

enum UltrawideDockCommit: Equatable, Sendable {
    case window(
        id: HorizontalLayoutTileID,
        frame: CGRect,
        kind: UltrawideDockWindowCommitKind
    )
    case layout(
        plan: HorizontalLayoutPlan,
        membersByTileID: [HorizontalLayoutTileID: [HorizontalLayoutTileID]]
    )
}

struct UltrawideDockPreview: Equatable, Identifiable, Sendable {
    let id: HorizontalLayoutTileID
    let memberIDs: [HorizontalLayoutTileID]
    let frame: CGRect
    let containsCurrent: Bool
}

struct UltrawideDockOutput: Equatable, Sendable {
    let target: UltrawideDockTarget?
    let operation: UltrawideDockOperation
    let previews: [UltrawideDockPreview]
    let commit: UltrawideDockCommit?
    let cursor: UltrawideDockCursor

    static let idle = UltrawideDockOutput(
        target: nil,
        operation: .idle,
        previews: [],
        commit: nil,
        cursor: .arrow
    )
}

struct UltrawideDockLayoutChanges: Equatable, Sendable {
    let windowIDs: [HorizontalLayoutTileID]
    let tileIDs: Set<HorizontalLayoutTileID>
}

/// Finds the real windows affected by a logical row plan. Comparisons use grouped slot frames so
/// padding-sized visual gaps do not turn an otherwise unchanged window into a batch participant.
enum UltrawideDockLayoutDiffer {
    static func changes(
        for plan: HorizontalLayoutPlan,
        membersByTileID: [HorizontalLayoutTileID: [HorizontalLayoutTileID]],
        in scene: UltrawideDockScene,
        tolerance: CGFloat = 0.000_001
    ) -> UltrawideDockLayoutChanges {
        var originalFrames: [HorizontalLayoutTileID: CGRect] = [:]
        for slot in scene.slots {
            for memberID in slot.memberIDs {
                originalFrames[memberID] = slot.frame
            }
        }

        var windowIDs: [HorizontalLayoutTileID] = []
        var tileIDs = Set<HorizontalLayoutTileID>()
        for tile in plan.snapshot.tiles {
            for memberID in membersByTileID[tile.id] ?? [tile.id] {
                let changed = originalFrames[memberID].map {
                    abs($0.minX - tile.frame.minX) > tolerance ||
                        abs($0.width - tile.frame.width) > tolerance
                } ?? true
                if changed {
                    windowIDs.append(memberID)
                    tileIDs.insert(tile.id)
                }
            }
        }
        return UltrawideDockLayoutChanges(windowIDs: windowIDs, tileIDs: tileIDs)
    }
}

enum UltrawideDockEvent: Equatable, Sendable {
    case move(to: CGFloat)
    case pointerDown(at: CGFloat)
    case drag(to: CGFloat)
    case pointerUp(at: CGFloat)
    case scroll(delta: CGFloat)
    case cancel
}

/// Pure event reducer for the dock. Callers provide one immutable scene and feed pointer events;
/// every observable preview and commit plan comes back through `output`.
struct UltrawideDockInteraction {
    private static let maximumDividerHitRadius: CGFloat = 0.03
    private static let maximumResizeHoldRadius: CGFloat = 0.04
    private static let stackZone: ClosedRange<CGFloat> = 0.22 ... 0.78
    private static let widthStops: [CGFloat] = [0.25, 1 / 3, 0.5, 2 / 3, 0.75, 1]

    let scene: UltrawideDockScene
    private(set) var output: UltrawideDockOutput = .idle

    private let engine: HorizontalLayoutEngine
    private var draggingDividerAfterID: HorizontalLayoutTileID?
    /// `nil` lets the geometry decide: half the screen for a standalone placement, the whole free
    /// gap for an insertion. Scrolling pins it to an explicit fraction of the screen.
    private var requestedWidth: CGFloat?
    /// Where the pointer was when a divider drag ended. Small movements around that spot keep the
    /// finished resize instead of silently trading it for whatever target sits under the pointer.
    private var heldResizeAtX: CGFloat?
    private var lastPointerX: CGFloat = 0.5

    init(scene: UltrawideDockScene, minimumWidth: CGFloat) throws {
        self.scene = scene
        self.engine = try HorizontalLayoutEngine(minimumWidth: minimumWidth)
    }

    @discardableResult
    mutating func handle(_ event: UltrawideDockEvent) -> UltrawideDockOutput {
        switch event {
        case let .move(position), let .drag(position):
            lastPointerX = position.clamped(to: 0 ... 1)
            if let draggingDividerAfterID {
                output = resizeDivider(after: draggingDividerAfterID, to: lastPointerX)
            } else if !isHoldingFinishedResize(at: lastPointerX) {
                heldResizeAtX = nil
                output = selectTarget(at: lastPointerX)
            }
        case let .pointerDown(position):
            lastPointerX = position.clamped(to: 0 ... 1)
            let target = interactionTarget(at: lastPointerX)
            if case let .divider(afterID) = target {
                heldResizeAtX = nil
                draggingDividerAfterID = afterID
                output = UltrawideDockOutput(
                    target: target,
                    operation: .resizeReady,
                    previews: [],
                    commit: nil,
                    cursor: .resizeLeftRight
                )
            }
        case let .pointerUp(position):
            lastPointerX = position.clamped(to: 0 ... 1)
            if draggingDividerAfterID != nil {
                draggingDividerAfterID = nil
                heldResizeAtX = output.operation == .resize ? lastPointerX : nil
            }
        case let .scroll(delta):
            output = adjust(by: delta)
        case .cancel:
            draggingDividerAfterID = nil
            heldResizeAtX = nil
            requestedWidth = nil
            output = .idle
        }
        return output
    }

    /// A finished resize survives pointer jitter, but moving away deliberately still picks a new
    /// target — the row underneath is unchanged until the trigger is released.
    private func isHoldingFinishedResize(at x: CGFloat) -> Bool {
        guard let heldResizeAtX, case let .divider(afterID) = output.target else { return false }
        let radius = min(
            Self.maximumResizeHoldRadius,
            0.25 * narrowestTileWidth(around: afterID, in: currentPlan?.snapshot ?? scene.layout)
        )
        return abs(x - heldResizeAtX) <= radius
    }

    private func interactionTarget(at x: CGFloat) -> UltrawideDockTarget {
        if scene.slots.isEmpty || isOnlyCurrentWindowInScene {
            return .place(edge: standaloneEdge(at: x))
        }

        if let divider = nearestDivider(to: x),
           abs(divider.position - x) <= dividerHitRadius(after: divider.afterID) {
            return .divider(after: divider.afterID)
        }

        if let slot = scene.slots.first(where: { $0.frame.minX <= x && x <= $0.frame.maxX }) {
            let relativeX = slot.frame.width > 0 ? (x - slot.frame.minX) / slot.frame.width : 0.5
            if Self.stackZone.contains(relativeX) {
                return slot.contains(scene.currentID)
                    ? .current(slotID: slot.id)
                    : .stack(slotID: slot.id)
            }
            return .insert(position: x)
        }

        return .insert(position: x)
    }

    private func selectTarget(at x: CGFloat) -> UltrawideDockOutput {
        let target = interactionTarget(at: x)
        switch target {
        case let .place(edge):
            return standaloneOutput(edge: edge)
        case let .insert(position):
            return placementOutput(at: position)
        case let .stack(slotID):
            guard let slot = scene.slot(id: slotID) else { return .idle }
            let visibleTargetFrame = slot.memberIDs.lazy.compactMap { memberID in
                scene.windows.first(where: { $0.id == memberID })?.frame
            }.first ?? slot.frame
            return UltrawideDockOutput(
                target: target,
                operation: .stack(existingCount: slot.memberIDs.count),
                previews: [UltrawideDockPreview(
                    id: scene.currentID,
                    memberIDs: [scene.currentID],
                    frame: visibleTargetFrame,
                    containsCurrent: true
                )],
                commit: .window(id: scene.currentID, frame: visibleTargetFrame, kind: .stack),
                cursor: .arrow
            )
        case .current:
            return UltrawideDockOutput(
                target: target,
                operation: .current,
                previews: [],
                commit: nil,
                cursor: .arrow
            )
        case .divider:
            return UltrawideDockOutput(
                target: target,
                operation: .resizeReady,
                previews: [],
                commit: nil,
                cursor: .resizeLeftRight
            )
        }
    }

    private func placementOutput(at x: CGFloat) -> UltrawideDockOutput {
        if scene.slots.isEmpty || isOnlyCurrentWindowInScene {
            return standaloneOutput(edge: standaloneEdge(at: x))
        }

        do {
            if let currentSlot = scene.currentSlot,
               currentSlot.memberIDs == [scene.currentID],
               isCompleteRow(scene.layout),
               scene.slots.count > 1 {
                let sourceIndex = scene.slots.firstIndex(where: { $0.id == currentSlot.id })!
                var destinationIndex = scene.slots.filter { $0.frame.midX < x }.count
                if sourceIndex < destinationIndex { destinationIndex -= 1 }
                destinationIndex = destinationIndex.clamped(to: 0 ... scene.slots.count - 1)

                guard destinationIndex != sourceIndex else {
                    return UltrawideDockOutput(
                        target: .current(slotID: currentSlot.id),
                        operation: .current,
                        previews: [],
                        commit: nil,
                        cursor: .arrow
                    )
                }

                let plan = try engine.plan(.move(currentSlot.id, toIndex: destinationIndex), from: scene.layout)
                return layoutOutput(
                    target: .insert(position: x),
                    operation: .move,
                    plan: plan,
                    membersByTileID: membersBySlotID
                )
            }

            let base = try layoutRemovingCurrentWindow()
            guard !base.snapshot.tiles.isEmpty else {
                return standaloneOutput(edge: standaloneEdge(at: x))
            }
            var members = base.membersByTileID
            members[scene.currentID] = [scene.currentID]

            // Free space is placed explicitly rather than through `.insert`, so the scroll wheel can
            // size the incoming window instead of it always swallowing the entire gap.
            if let span = insertionSpan(at: x, in: base.snapshot) {
                let plan = try engine.plan(.place(scene.currentID, at: span), from: base.snapshot)
                return layoutOutput(
                    target: .insert(position: x),
                    operation: .insert(rebalanced: false),
                    plan: plan,
                    membersByTileID: members
                )
            }

            let plan = try engine.plan(.insert(scene.currentID, near: x), from: base.snapshot)
            return layoutOutput(
                target: .insert(position: x),
                operation: .insert(rebalanced: plan.adjustments.contains(.fullRowRebalanced)),
                plan: plan,
                membersByTileID: members
            )
        } catch {
            return UltrawideDockOutput(
                target: .insert(position: x),
                operation: .unavailable,
                previews: [],
                commit: nil,
                cursor: .arrow
            )
        }
    }

    /// The free gap nearest the pointer, narrowed to the requested width and kept inside that gap.
    /// Returns `nil` when no gap can hold a window, which is what makes the row rebalance instead.
    private func insertionSpan(
        at x: CGFloat,
        in snapshot: HorizontalLayoutSnapshot
    ) -> HorizontalLayoutSpan? {
        let gaps = engine.freeSpans(in: snapshot).filter { $0.width >= engine.minimumWidth }
        guard let gap = gaps.min(by: {
            Self.distance(from: x, to: $0) < Self.distance(from: x, to: $1)
        }) else {
            return nil
        }

        // Subtracting the widths first keeps an exact fit exactly at the gap's origin: rounding the
        // other way round would push the span a fraction outside the gap and reject the placement.
        let width = (requestedWidth ?? gap.width).clamped(to: engine.minimumWidth ... gap.width)
        let maximumOriginX = max(gap.x, gap.x + (gap.width - width))
        let originX = (x - width / 2).clamped(to: gap.x ... maximumOriginX)
        return HorizontalLayoutSpan(
            x: originX,
            width: min(width, gap.x + gap.width - originX)
        )
    }

    private static func distance(from x: CGFloat, to span: HorizontalLayoutSpan) -> CGFloat {
        if x < span.x { return span.x - x }
        if x > span.x + span.width { return x - (span.x + span.width) }
        return 0
    }

    private func standaloneOutput(edge: UltrawideDockEdge) -> UltrawideDockOutput {
        let frame = standaloneFrame(edge: edge, width: requestedWidth ?? 0.5)
        return UltrawideDockOutput(
            target: .place(edge: edge),
            operation: .placement,
            previews: [UltrawideDockPreview(
                id: scene.currentID,
                memberIDs: [scene.currentID],
                frame: frame,
                containsCurrent: true
            )],
            commit: .window(id: scene.currentID, frame: frame, kind: .placement),
            cursor: .arrow
        )
    }

    private func resizeDivider(
        after afterID: HorizontalLayoutTileID,
        to position: CGFloat
    ) -> UltrawideDockOutput {
        do {
            let plan = try engine.plan(.moveDivider(after: afterID, to: position), from: scene.layout)
            return layoutOutput(
                target: .divider(after: afterID),
                operation: .resize,
                plan: plan,
                membersByTileID: membersBySlotID,
                cursor: .resizeLeftRight
            )
        } catch {
            return UltrawideDockOutput(
                target: .divider(after: afterID),
                operation: .unavailable,
                previews: [],
                commit: nil,
                cursor: .resizeLeftRight
            )
        }
    }

    private mutating func adjust(by delta: CGFloat) -> UltrawideDockOutput {
        guard delta.isFinite else { return output }

        if case let .divider(afterID) = output.target,
           let tile = currentPlan?.snapshot.tiles.first(where: { $0.id == afterID }) ??
           scene.layout.tiles.first(where: { $0.id == afterID }) {
            return resizeDivider(after: afterID, to: tile.frame.maxX + delta)
        }

        switch output.target {
        case .place, .insert:
            let base = requestedWidth ?? currentPreviewWidth ?? 0.5
            requestedWidth = Self.snapped((base + delta).clamped(to: engine.minimumWidth ... 1))
            return placementOutput(at: lastPointerX)
        default:
            return output
        }
    }

    /// Keeps the common fractions exactly reachable while the wheel is otherwise continuous.
    private static func snapped(_ width: CGFloat) -> CGFloat {
        guard let stop = widthStops.min(by: { abs($0 - width) < abs($1 - width) }),
              abs(stop - width) <= 0.015
        else {
            return width
        }
        return stop
    }

    private var currentPreviewWidth: CGFloat? {
        output.previews.first { $0.containsCurrent }?.frame.width
    }

    private func layoutOutput(
        target: UltrawideDockTarget,
        operation: UltrawideDockOperation,
        plan: HorizontalLayoutPlan,
        membersByTileID: [HorizontalLayoutTileID: [HorizontalLayoutTileID]],
        cursor: UltrawideDockCursor = .arrow
    ) -> UltrawideDockOutput {
        let previews = plan.snapshot.tiles.map { tile in
            let members = membersByTileID[tile.id] ?? [tile.id]
            return UltrawideDockPreview(
                id: tile.id,
                memberIDs: members,
                frame: tile.frame,
                containsCurrent: members.contains(scene.currentID)
            )
        }
        return UltrawideDockOutput(
            target: target,
            operation: operation,
            previews: previews,
            commit: .layout(plan: plan, membersByTileID: membersByTileID),
            cursor: cursor
        )
    }

    private var membersBySlotID: [HorizontalLayoutTileID: [HorizontalLayoutTileID]] {
        Dictionary(uniqueKeysWithValues: scene.slots.map { ($0.id, $0.memberIDs) })
    }

    private var isOnlyCurrentWindowInScene: Bool {
        scene.slots.count == 1 && scene.slots[0].memberIDs == [scene.currentID]
    }

    private var currentPlan: HorizontalLayoutPlan? {
        guard case let .layout(plan, _) = output.commit else { return nil }
        return plan
    }

    /// Wide enough to grab without precision aiming, but never so wide that it swallows the stack
    /// zone of a narrow neighbour.
    private func dividerHitRadius(after afterID: HorizontalLayoutTileID) -> CGFloat {
        min(
            Self.maximumDividerHitRadius,
            0.2 * narrowestTileWidth(around: afterID, in: scene.layout)
        )
    }

    private func narrowestTileWidth(
        around afterID: HorizontalLayoutTileID,
        in snapshot: HorizontalLayoutSnapshot
    ) -> CGFloat {
        guard let index = snapshot.tiles.firstIndex(where: { $0.id == afterID }),
              snapshot.tiles.indices.contains(index + 1)
        else {
            return 1
        }
        return min(snapshot.tiles[index].frame.width, snapshot.tiles[index + 1].frame.width)
    }

    private func nearestDivider(to x: CGFloat) -> (afterID: HorizontalLayoutTileID, position: CGFloat)? {
        var nearest: (afterID: HorizontalLayoutTileID, position: CGFloat)?
        for index in 0 ..< max(scene.layout.tiles.count - 1, 0) {
            let leadingTile = scene.layout.tiles[index]
            let trailingTile = scene.layout.tiles[index + 1]
            let position = leadingTile.frame.maxX
            guard abs(position - trailingTile.frame.minX) <= 0.000_001 else { continue }

            if nearest == nil || abs(position - x) < abs(nearest!.position - x) {
                nearest = (leadingTile.id, position)
            }
        }
        return nearest
    }

    private func layoutRemovingCurrentWindow() throws -> (
        snapshot: HorizontalLayoutSnapshot,
        membersByTileID: [HorizontalLayoutTileID: [HorizontalLayoutTileID]]
    ) {
        var tiles: [HorizontalLayoutTile] = []
        var membersByTileID: [HorizontalLayoutTileID: [HorizontalLayoutTileID]] = [:]

        for slot in scene.slots {
            let members = slot.memberIDs.filter { $0 != scene.currentID }
            guard let representative = members.first else { continue }
            tiles.append(HorizontalLayoutTile(id: representative, frame: slot.frame))
            membersByTileID[representative] = members
        }
        return (try HorizontalLayoutSnapshot(tiles: tiles), membersByTileID)
    }

    private func isCompleteRow(_ snapshot: HorizontalLayoutSnapshot) -> Bool {
        guard let first = snapshot.tiles.first, let last = snapshot.tiles.last,
              first.frame.minX <= 0.001, last.frame.maxX >= 0.999
        else { return false }

        for index in 0 ..< snapshot.tiles.count - 1 {
            let leadingTile = snapshot.tiles[index]
            let trailingTile = snapshot.tiles[index + 1]
            if abs(leadingTile.frame.maxX - trailingTile.frame.minX) > 0.001 {
                return false
            }
        }
        return true
    }

    private func standaloneEdge(at x: CGFloat) -> UltrawideDockEdge {
        if x < 1 / 3 { return .leading }
        if x > 2 / 3 { return .trailing }
        return .center
    }

    private func standaloneFrame(edge: UltrawideDockEdge, width: CGFloat) -> CGRect {
        let x: CGFloat = switch edge {
        case .leading: 0
        case .center: (1 - width) / 2
        case .trailing: 1 - width
        }
        return CGRect(x: x, y: 0, width: width, height: 1)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
