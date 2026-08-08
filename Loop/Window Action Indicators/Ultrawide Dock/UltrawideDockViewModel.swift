import SwiftUI

@MainActor
final class UltrawideDockViewModel: ObservableObject {
    struct WindowFrame: Identifiable {
        let id: HorizontalLayoutTileID
        let cgWindowID: CGWindowID
        let frame: CGRect
        let isActive: Bool
        let zIndex: Int
    }

    struct PreviewFrame: Identifiable {
        let id: HorizontalLayoutTileID
        let frame: CGRect
        let isCurrent: Bool
    }

    struct Anchor: Identifiable {
        enum Edge { case leading, trailing, center }
        enum Kind { case screenEdge, windowAdjacent, gapCenter }

        let id: String
        let edge: Edge
        let kind: Kind
        let anchorX: Double
        let leftBound: Double
        let rightBound: Double

        var maxSpan: Double { max(0, rightBound - leftBound) }

        var cycleSteps: [Double] {
            switch kind {
            case .screenEdge: [0.5, 1.0 / 3.0, 2.0 / 3.0]
            case .windowAdjacent: [1.0, 2.0 / 3.0, 0.5, 1.0 / 3.0]
            case .gapCenter: [0.5, 1.0, 2.0 / 3.0]
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

    struct Divider: Identifiable {
        let id: String
        let afterID: HorizontalLayoutTileID
        let beforeID: HorizontalLayoutTileID
        let x: CGFloat
        let interactionRange: ClosedRange<CGFloat>
        let isCurrentAdjacent: Bool
    }

    fileprivate enum InteractionTarget: Equatable {
        case anchor(String)
        case tile(HorizontalLayoutTileID)
        case divider(String)

        var id: String {
            switch self {
            case let .anchor(id): "anchor:\(id)"
            case let .tile(id): "tile:\(id.rawValue)"
            case let .divider(id): "divider:\(id)"
            }
        }
    }

    private enum TileOperation {
        case swap
        case reorder
        case replace
        case insertBefore
        case insertAfter
    }

    private struct RowOperation {
        let title: String
        let intent: HorizontalLayoutIntent
    }

    @Published private(set) var currentAction: WindowAction?
    @Published private(set) var previewFrame: CGRect = .zero
    @Published private(set) var previewFrames: [PreviewFrame] = []
    @Published private(set) var existingWindows: [WindowFrame] = []
    @Published private(set) var anchors: [Anchor] = []
    @Published private(set) var dividers: [Divider] = []
    @Published private(set) var activeTargetID: String?
    @Published private(set) var operationTitle = "Move to an anchor"
    @Published private(set) var percentageFeedback = ""

    private let engine = try! HorizontalLayoutEngine(minimumWidth: HorizontalLayoutRuntimeAdapter.minimumWidth)
    private let adapter = HorizontalLayoutRuntimeAdapter()
    private var runtime: HorizontalLayoutRuntimeSnapshot?
    private var activeTarget: InteractionTarget?
    private var operationIndex = 0
    private var sizeStepIndex = 0
    private var scrollFractionDelta: Double = 0
    private var dividerPosition: CGFloat?
    private var window: Window?
    private var screen: NSScreen?

    private(set) var pendingExecution: HorizontalLayoutPendingExecution?
    let previewMode: Bool

    init(startingAction: WindowAction?, window: Window?, screen: NSScreen?, previewMode: Bool) {
        self.currentAction = startingAction
        self.window = window
        self.screen = screen
        self.previewMode = previewMode

        Task { @MainActor [weak self] in
            await Task.yield()
            self?.reloadRuntime()
        }
    }

    var invalidWindowSelected: Bool { window == nil && !previewMode }

    func setWindow(to newWindow: Window) {
        guard window?.cgWindowID != newWindow.cgWindowID else { return }
        window = newWindow
        reloadRuntime()
    }

    func setAction(to action: WindowAction) {
        guard previewMode else { return }
        currentAction = action
        let bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        let frame = WindowFrameResolver.getFrame(for: action, bounds: bounds, padding: .zero)
        previewFrame = frame
        previewFrames = []
    }

    func refresh() {
        reloadRuntime()
    }

    @discardableResult
    func updateForNormalizedX(_ normalizedX: Double) -> WindowAction? {
        let x = min(1, max(0, normalizedX))
        guard let target = interactionTarget(at: x) else { return currentAction }

        if target != activeTarget {
            activeTarget = target
            activeTargetID = target.id
            operationIndex = target.isDivider ? -1 : 0
            sizeStepIndex = 0
            scrollFractionDelta = 0
            dividerPosition = target.divider(in: dividers)?.x
        }
        recomputeInteraction(at: x)
        return currentAction
    }

    /// Click cycles the operations exposed by the active visual target. Anchors keep their historical
    /// size cycle when no row mutation is involved; tiles/dividers cycle safe row operations.
    @discardableResult
    func cycleSize() -> WindowAction? {
        guard let activeTarget else { return currentAction }
        switch activeTarget {
        case let .anchor(id):
            guard let anchor = anchors.first(where: { $0.id == id }) else { return currentAction }
            if runtime?.layout.tiles.isEmpty != false {
                sizeStepIndex = (sizeStepIndex + 1) % anchor.cycleSteps.count
                scrollFractionDelta = 0
            }
        case let .tile(id):
            let count = tileOperations(for: id).count
            let rowCount = id == runtime?.currentID ? rowOperations().count : 0
            let availableCount = max(count, rowCount)
            if availableCount > 0 { operationIndex = (operationIndex + 1) % availableCount }
        case .divider:
            let count = rowOperations().count
            if count > 0 { operationIndex = (operationIndex + 1) % count }
        }
        recomputeInteraction(at: dividerPosition ?? activeTarget.defaultX(in: self))
        return currentAction
    }

    /// Scroll push-pulls an adjacent divider. At a legacy single-window anchor it still fine-tunes width.
    @discardableResult
    func adjustSize(by delta: Double) -> WindowAction? {
        guard let activeTarget else { return currentAction }
        if case .divider = activeTarget {
            operationIndex = -1
            dividerPosition = min(1, max(0, (dividerPosition ?? 0.5) + delta))
            recomputeInteraction(at: dividerPosition ?? 0.5)
        } else if case let .anchor(id) = activeTarget,
                  let anchor = anchors.first(where: { $0.id == id }),
                  runtime?.layout.tiles.isEmpty != false {
            scrollFractionDelta += delta
            applySimpleAnchor(anchor)
        }
        return currentAction
    }

    // MARK: - Runtime capture

    private func reloadRuntime() {
        guard let screen else {
            runtime = nil
            existingWindows = []
            return
        }

        let capture = adapter.capture(currentWindow: window, screen: screen)
        runtime = capture.snapshot
        existingWindows = capture.displayWindows.map {
            WindowFrame(
                id: $0.id,
                cgWindowID: $0.window.cgWindowID,
                frame: $0.normalizedFrame,
                isActive: $0.isCurrent,
                zIndex: $0.zIndex
            )
        }
        rebuildInteractionGeometry()

        if let target = defaultTarget() {
            activeTarget = target
            activeTargetID = target.id
            operationIndex = target.isDivider ? -1 : 0
            dividerPosition = target.divider(in: dividers)?.x
            recomputeInteraction(at: target.defaultX(in: self))
        }
    }

    private func rebuildInteractionGeometry() {
        let occupancyTiles: [HorizontalLayoutTile]
        if let runtime {
            occupancyTiles = runtime.layout.tiles.filter { $0.id != runtime.currentID }
        } else {
            occupancyTiles = existingWindows
                .filter { !$0.isActive }
                .map { HorizontalLayoutTile(id: $0.id, frame: $0.frame) }
                .sorted { $0.frame.minX < $1.frame.minX }
        }

        let freeSpans = Self.freeSpans(in: occupancyTiles)
        anchors = freeSpans.flatMap { span in
            let leftEdge = span.x <= 0.001
            let rightEdge = span.x + span.width >= 0.999
            let base = "\(span.x):\(span.width)"
            return [
                Anchor(
                    id: "\(base):leading",
                    edge: .leading,
                    kind: leftEdge ? .screenEdge : .windowAdjacent,
                    anchorX: span.x,
                    leftBound: span.x,
                    rightBound: span.x + span.width
                ),
                Anchor(
                    id: "\(base):trailing",
                    edge: .trailing,
                    kind: rightEdge ? .screenEdge : .windowAdjacent,
                    anchorX: span.x + span.width,
                    leftBound: span.x,
                    rightBound: span.x + span.width
                ),
                Anchor(
                    id: "\(base):center",
                    edge: .center,
                    kind: leftEdge && rightEdge ? .screenEdge : .gapCenter,
                    anchorX: span.x + span.width / 2,
                    leftBound: span.x,
                    rightBound: span.x + span.width
                ),
            ]
        }

        guard let runtime else {
            dividers = []
            return
        }
        dividers = zip(runtime.layout.tiles, runtime.layout.tiles.dropFirst()).compactMap { left, right in
            guard abs(left.frame.maxX - right.frame.minX) <= 0.000_001 else { return nil }
            let id = "\(left.id.rawValue)|\(right.id.rawValue)"
            return Divider(
                id: id,
                afterID: left.id,
                beforeID: right.id,
                x: left.frame.maxX,
                interactionRange: left.frame.minX ... right.frame.maxX,
                isCurrentAdjacent: left.id == runtime.currentID || right.id == runtime.currentID
            )
        }
    }

    private func defaultTarget() -> InteractionTarget? {
        if let runtime,
           runtime.currentIsTile,
           runtime.layout.tiles.contains(where: { $0.id == runtime.currentID }) {
            return .tile(runtime.currentID)
        }
        if let center = anchors.min(by: { abs($0.anchorX - 0.5) < abs($1.anchorX - 0.5) }) {
            return .anchor(center.id)
        }
        return runtime?.layout.tiles.first.map { .tile($0.id) }
    }

    // MARK: - Interaction planning

    private func interactionTarget(at x: CGFloat) -> InteractionTarget? {
        if case let .divider(id) = activeTarget,
           let divider = dividers.first(where: { $0.id == id }),
           divider.isCurrentAdjacent,
           divider.interactionRange.contains(x) {
            return .divider(id)
        }

        if let divider = dividers
            .filter(\.isCurrentAdjacent)
            .min(by: { abs($0.x - x) < abs($1.x - x) }),
            abs(divider.x - x) <= 0.025 {
            return .divider(divider.id)
        }

        if let tile = runtime?.layout.tiles.first(where: { $0.frame.minX <= x && x <= $0.frame.maxX }) {
            return .tile(tile.id)
        }

        return anchors.min(by: { abs($0.anchorX - x) < abs($1.anchorX - x) }).map { .anchor($0.id) }
    }

    private func recomputeInteraction(at x: CGFloat) {
        guard let activeTarget else { return }
        do {
            switch activeTarget {
            case let .anchor(id):
                guard let anchor = anchors.first(where: { $0.id == id }) else { return }
                try applyAnchor(anchor)
            case let .tile(id):
                try applyTile(id)
            case let .divider(id):
                try applyDivider(id, at: dividerPosition ?? x)
            }
        } catch {
            pendingExecution = nil
            previewFrames = []
            operationTitle = "Unavailable for this row"
            percentageFeedback = "Minimum width would be exceeded"
        }
    }

    private func applyAnchor(_ anchor: Anchor) throws {
        guard let runtime, !runtime.layout.tiles.isEmpty else {
            applySimpleAnchor(anchor)
            return
        }

        let planningSnapshot: HorizontalLayoutSnapshot
        if runtime.currentIsTile {
            planningSnapshot = try HorizontalLayoutSnapshot(
                tiles: runtime.layout.tiles.filter { $0.id != runtime.currentID }
            )
        } else {
            planningSnapshot = runtime.layout
        }
        let plan = try engine.plan(.insert(runtime.currentID, near: anchor.anchorX), from: planningSnapshot)
        apply(plan, title: plan.adjustments.contains(.fullRowRebalanced) ? "Insert · rebalance row" : "Insert in free space")
    }

    private func applySimpleAnchor(_ anchor: Anchor) {
        let step = anchor.cycleSteps[sizeStepIndex]
        let fraction = max(0.1, min(1, step + scrollFractionDelta))
        let frame = anchor.frame(sizeFraction: fraction)
        pendingExecution = nil
        previewFrame = frame
        previewFrames = currentRuntimeID.map { [PreviewFrame(id: $0, frame: frame, isCurrent: true)] } ?? []
        currentAction = HorizontalLayoutRuntimeAdapter.action(for: frame, name: "ultrawide_anchor")
        operationTitle = "Place window · click to resize"
        percentageFeedback = Self.percentages([frame])
    }

    private func applyTile(_ id: HorizontalLayoutTileID) throws {
        guard let runtime else { return }
        if id == runtime.currentID {
            let operations = rowOperations()
            guard !operations.isEmpty else {
                operationTitle = "Current tile"
                percentageFeedback = Self.percentages(runtime.layout.tiles.map(\.frame))
                return
            }
            let operation = operations[operationIndex.clamped(to: 0 ... operations.count - 1)]
            let plan = try engine.plan(operation.intent, from: runtime.layout)
            apply(plan, title: operation.title)
            return
        }

        let operations = tileOperations(for: id)
        guard !operations.isEmpty else { return }
        let operation = operations[operationIndex.clamped(to: 0 ... operations.count - 1)]
        let plan: HorizontalLayoutPlan
        let title: String

        switch operation {
        case .swap:
            plan = try engine.plan(.swap(runtime.currentID, id), from: runtime.layout)
            title = "Swap tiles · click to cycle"
        case .reorder:
            let index = runtime.layout.tiles.firstIndex(where: { $0.id == id }) ?? 0
            plan = try engine.plan(.move(runtime.currentID, toIndex: index), from: runtime.layout)
            title = "Reorder row · click to cycle"
        case .replace:
            let currentTile = runtime.layout.tiles.first { $0.id == runtime.currentID }!
            let withoutCurrent = try HorizontalLayoutSnapshot(
                tiles: runtime.layout.tiles.filter { $0.id != runtime.currentID }
            )
            plan = try engine.plan(
                .replace(
                    target: id,
                    with: runtime.currentID,
                    displacedTo: HorizontalLayoutSpan(x: currentTile.frame.minX, width: currentTile.frame.width)
                ),
                from: withoutCurrent
            )
            title = "Safe replace · displaced to old tile"
        case .insertBefore:
            let target = runtime.layout.tiles.first { $0.id == id }!
            plan = try engine.plan(.insert(runtime.currentID, near: target.frame.minX), from: runtime.layout)
            title = "Insert before · rebalance row"
        case .insertAfter:
            let target = runtime.layout.tiles.first { $0.id == id }!
            plan = try engine.plan(.insert(runtime.currentID, near: target.frame.maxX), from: runtime.layout)
            title = "Insert after · rebalance row"
        }
        apply(plan, title: title)
    }

    private func applyDivider(_ id: String, at position: CGFloat) throws {
        guard let runtime, let divider = dividers.first(where: { $0.id == id }) else { return }
        if operationIndex >= 0 {
            let operations = rowOperations()
            guard !operations.isEmpty else { return }
            let operation = operations[operationIndex.clamped(to: 0 ... operations.count - 1)]
            apply(try engine.plan(operation.intent, from: runtime.layout), title: operation.title)
        } else {
            let plan = try engine.plan(.moveDivider(after: divider.afterID, to: position), from: runtime.layout)
            apply(plan, title: "Resize adjacent tiles · scroll or move")
        }
    }

    private func apply(_ plan: HorizontalLayoutPlan, title: String) {
        guard let runtime else { return }
        let originals = Dictionary(uniqueKeysWithValues: runtime.layout.tiles.map { ($0.id, $0.frame) })
        let changedIDs = plan.snapshot.tiles.compactMap { tile -> HorizontalLayoutTileID? in
            guard let original = originals[tile.id] else { return tile.id }
            return Self.framesEqual(original, tile.frame) ? nil : tile.id
        }
        let changedSet = Set(changedIDs)

        previewFrames = plan.snapshot.tiles.compactMap { tile in
            guard changedSet.contains(tile.id) else { return nil }
            return PreviewFrame(id: tile.id, frame: tile.frame, isCurrent: tile.id == runtime.currentID)
        }
        if let current = plan.snapshot.tiles.first(where: { $0.id == runtime.currentID }) {
            previewFrame = current.frame
            currentAction = HorizontalLayoutRuntimeAdapter.action(for: current.frame)
        }
        operationTitle = title
        percentageFeedback = Self.percentages(plan.snapshot.tiles.map(\.frame))

        if changedIDs.count > 1 {
            pendingExecution = HorizontalLayoutPendingExecution(
                plan: plan,
                changedIDs: changedIDs,
                windowsByID: runtime.windowsByID,
                usableBounds: runtime.usableBounds,
                padding: runtime.padding,
                screen: runtime.screen
            )
        } else {
            pendingExecution = nil
        }
    }

    private func tileOperations(for targetID: HorizontalLayoutTileID) -> [TileOperation] {
        guard let runtime, targetID != runtime.currentID else { return [] }
        if runtime.currentIsTile {
            var operations: [TileOperation] = [.swap, .reorder]
            if canSafelyReplace(targetID) { operations.append(.replace) }
            return operations
        }
        return [.insertBefore, .insertAfter]
    }

    private func canSafelyReplace(_ targetID: HorizontalLayoutTileID) -> Bool {
        guard let runtime,
              runtime.currentIsTile,
              let current = runtime.layout.tiles.first(where: { $0.id == runtime.currentID })
        else { return false }
        do {
            let withoutCurrent = try HorizontalLayoutSnapshot(
                tiles: runtime.layout.tiles.filter { $0.id != runtime.currentID }
            )
            _ = try engine.plan(
                .replace(
                    target: targetID,
                    with: runtime.currentID,
                    displacedTo: HorizontalLayoutSpan(x: current.frame.minX, width: current.frame.width)
                ),
                from: withoutCurrent
            )
            return true
        } catch {
            return false
        }
    }

    private func rowOperations() -> [RowOperation] {
        guard let runtime, Self.isCompleteRow(runtime.layout) else { return [] }
        var operations = [RowOperation(title: "Balance row", intent: .balance(.all))]
        switch runtime.layout.tiles.count {
        case 2:
            operations.append(RowOperation(title: "2 equal · 50 / 50", intent: .apply(.twoEqual)))
            operations.append(RowOperation(
                title: "Main + right sidebar · 75 / 25",
                intent: .apply(.mainAndSidebar(main: runtime.currentID, sidebar: .trailing))
            ))
            operations.append(RowOperation(
                title: "Left sidebar + main · 25 / 75",
                intent: .apply(.mainAndSidebar(main: runtime.currentID, sidebar: .leading))
            ))
        case 3:
            operations.append(RowOperation(title: "3 equal · 33 / 33 / 33", intent: .apply(.threeEqual)))
            operations.append(RowOperation(
                title: "Focus · 25 / 50 / 25",
                intent: .apply(.focus25_50_25(focus: runtime.currentID))
            ))
        default:
            break
        }
        return operations
    }

    private var currentRuntimeID: HorizontalLayoutTileID? {
        runtime?.currentID ?? window.map(HorizontalLayoutRuntimeAdapter.stableID)
    }

    private static func freeSpans(in tiles: [HorizontalLayoutTile]) -> [HorizontalLayoutSpan] {
        var result: [HorizontalLayoutSpan] = []
        var cursor: CGFloat = 0
        for tile in tiles.sorted(by: { $0.frame.minX < $1.frame.minX }) {
            if tile.frame.minX > cursor + 0.001 {
                result.append(HorizontalLayoutSpan(x: cursor, width: tile.frame.minX - cursor))
            }
            cursor = max(cursor, tile.frame.maxX)
        }
        if cursor < 0.999 { result.append(HorizontalLayoutSpan(x: cursor, width: 1 - cursor)) }
        if tiles.isEmpty { return [HorizontalLayoutSpan(x: 0, width: 1)] }
        return result
    }

    private static func isCompleteRow(_ snapshot: HorizontalLayoutSnapshot) -> Bool {
        guard let first = snapshot.tiles.first, let last = snapshot.tiles.last,
              first.frame.minX <= 0.001, last.frame.maxX >= 0.999
        else { return false }
        return zip(snapshot.tiles, snapshot.tiles.dropFirst()).allSatisfy {
            abs($0.frame.maxX - $1.frame.minX) <= 0.001
        }
    }

    private static func framesEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 0.000_001 && abs(lhs.width - rhs.width) <= 0.000_001
    }

    private static func percentages(_ frames: [CGRect]) -> String {
        frames.sorted(by: { $0.minX < $1.minX })
            .map { "\(Int(($0.width * 100).rounded()))%" }
            .joined(separator: " · ")
    }
}

private extension UltrawideDockViewModel.InteractionTarget {
    var isDivider: Bool {
        if case .divider = self { return true }
        return false
    }

    func divider(in dividers: [UltrawideDockViewModel.Divider]) -> UltrawideDockViewModel.Divider? {
        guard case let .divider(id) = self else { return nil }
        return dividers.first(where: { $0.id == id })
    }

    @MainActor
    func defaultX(in viewModel: UltrawideDockViewModel) -> CGFloat {
        switch self {
        case let .anchor(id): viewModel.anchors.first(where: { $0.id == id })?.anchorX ?? 0.5
        case let .tile(id): viewModel.existingWindows.first(where: { $0.id == id })?.frame.midX ?? 0.5
        case let .divider(id): viewModel.dividers.first(where: { $0.id == id })?.x ?? 0.5
        }
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
