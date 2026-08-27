import SwiftUI

@MainActor
final class UltrawideDockViewModel: ObservableObject {
    struct SlotFrame: Identifiable {
        let id: HorizontalLayoutTileID
        let memberIDs: [HorizontalLayoutTileID]
        let frame: CGRect
        let containsCurrent: Bool
        let zIndex: Int
        /// Overlapping windows that the row cannot represent. They are drawn so the dock never shows
        /// free space where a real window is, but they are never a target and never get moved.
        let isExcluded: Bool

        var stackCount: Int { memberIDs.count }
    }

    struct PreviewFrame: Identifiable {
        let id: HorizontalLayoutTileID
        let frame: CGRect
        let isCurrent: Bool
        let memberCount: Int
        /// A free placement sits on top of the row instead of in it. Inside a gap it would look
        /// exactly like an insertion, so it is drawn hovering above the other windows.
        let isFloating: Bool
    }

    struct Divider: Identifiable {
        let id: String
        let afterID: HorizontalLayoutTileID
        let x: CGFloat
    }

    @Published private(set) var currentAction: WindowAction? = .init(.noSelection)
    @Published private(set) var slots: [SlotFrame] = []
    @Published private(set) var previewFrames: [PreviewFrame] = []
    @Published private(set) var dividers: [Divider] = []
    @Published private(set) var activeTargetID: String?
    @Published private(set) var activeTargetPosition: CGFloat?
    @Published private(set) var operationTitle = "Move to place · window center stacks"
    @Published private(set) var percentageFeedback = ""
    @Published private(set) var interactionHint = "Click: 1/2 → 1/3 → 1/4 · scroll fine-tunes · Esc cancels"
    @Published private(set) var cursor: UltrawideDockCursor = .arrow
    /// Drives the free-placement lane in the view. It follows the pointer's mode, not the reducer's
    /// output, so the lane also lights up on a screen where no row could be built.
    @Published private(set) var isFreeformActive = false

    private let adapter = HorizontalLayoutRuntimeAdapter()
    private var runtime: HorizontalLayoutRuntimeSnapshot?
    private var interaction: UltrawideDockInteraction?
    private var lastCommit: UltrawideDockCommit?
    private var window: Window?
    private var screen: NSScreen?

    private(set) var pendingExecution: HorizontalLayoutPendingExecution?
    private(set) var hasPendingCommit = false
    /// Survives a reducer rebuild: the pointer stays in the free lane while the window changes, so
    /// the mode has to be re-asserted on the fresh interaction instead of silently resetting.
    private var isFreeformRequested = false

    init(
        startingAction _: WindowAction?,
        window: Window?,
        screen: NSScreen?,
        previewMode _: Bool
    ) {
        self.window = window
        self.screen = screen
        reloadRuntime()
    }

    var invalidWindowSelected: Bool { window == nil }

    func setWindow(to newWindow: Window) {
        guard window?.cgWindowID != newWindow.cgWindowID else { return }
        window = newWindow
        reloadRuntime()
    }

    /// The dock owns its action while it is open. Manager updates must not feed the generated
    /// action back into the interaction reducer and accidentally replace its neutral/drag state.
    func setAction(to _: WindowAction) {}

    func refresh() {
        reloadRuntime()
    }

    @discardableResult
    func updateForNormalizedX(_ normalizedX: Double) -> WindowAction? {
        dispatch(.move(to: CGFloat(normalizedX)))
    }

    @discardableResult
    func pointerDown(at normalizedX: Double) -> WindowAction? {
        dispatch(.pointerDown(at: CGFloat(normalizedX)))
    }

    @discardableResult
    func drag(to normalizedX: Double) -> WindowAction? {
        dispatch(.drag(to: CGFloat(normalizedX)))
    }

    @discardableResult
    func pointerUp(at normalizedX: Double) -> WindowAction? {
        dispatch(.pointerUp(at: CGFloat(normalizedX)))
    }

    @discardableResult
    func adjustSize(by delta: Double) -> WindowAction? {
        dispatch(.scroll(delta: CGFloat(delta)))
    }

    /// Enters or leaves free placement. The controller derives this from the pointer's vertical
    /// position and only calls in on an actual change.
    @discardableResult
    func setFreeform(_ enabled: Bool) -> WindowAction? {
        guard isFreeformRequested != enabled else { return currentAction }
        isFreeformRequested = enabled
        isFreeformActive = enabled
        return dispatch(.setFreeform(enabled))
    }

    func cancel() {
        _ = dispatch(.cancel)
    }

    // MARK: - Runtime

    private func reloadRuntime() {
        currentAction = .init(.noSelection)
        lastCommit = nil
        pendingExecution = nil
        hasPendingCommit = false
        previewFrames = []
        activeTargetID = nil
        activeTargetPosition = nil
        cursor = .arrow
        operationTitle = "Move to place · window center stacks"
        interactionHint = "Click: 1/2 → 1/3 → 1/4 · scroll fine-tunes · Esc cancels"

        guard let screen else {
            runtime = nil
            interaction = nil
            slots = []
            dividers = []
            percentageFeedback = ""
            return
        }

        let capture = adapter.capture(currentWindow: window, screen: screen)
        runtime = capture.snapshot

        guard let runtime else {
            interaction = nil
            slots = capture.displayWindows.map {
                SlotFrame(
                    id: $0.id,
                    memberIDs: [$0.id],
                    frame: $0.normalizedFrame,
                    containsCurrent: $0.isCurrent,
                    zIndex: $0.zIndex,
                    isExcluded: true
                )
            }
            dividers = []
            operationTitle = window == nil ? "No movable window selected" : "No usable row on this screen"
            interactionHint = "Esc cancels"
            percentageFeedback = Self.percentages(slots.map(\.frame))
            return
        }

        slots = runtime.scene.slots.map { slot in
            let memberWindows = runtime.windows.filter { slot.memberIDs.contains($0.id) }
            return SlotFrame(
                id: slot.id,
                memberIDs: slot.memberIDs,
                frame: slot.frame,
                containsCurrent: slot.contains(runtime.currentID),
                zIndex: memberWindows.map(\.zIndex).min() ?? 0,
                isExcluded: false
            )
        }
        slots += runtime.scene.excludedWindowIDs.compactMap { windowID in
            guard let window = runtime.windows.first(where: { $0.id == windowID }) else { return nil }
            return SlotFrame(
                id: window.id,
                memberIDs: [window.id],
                frame: window.normalizedFrame,
                containsCurrent: false,
                zIndex: window.zIndex,
                isExcluded: true
            )
        }
        dividers = Self.dividers(in: runtime.scene.layout)
        interaction = try? UltrawideDockInteraction(
            scene: runtime.scene,
            minimumWidth: HorizontalLayoutRuntimeAdapter.minimumWidth
        )
        // The fresh reducer has no pointer position yet, so this only restores the mode; the next
        // pointer event is still what produces a target.
        if isFreeformRequested {
            interaction?.handle(.setFreeform(true))
        }
        percentageFeedback = Self.percentages(runtime.scene.slots.map(\.frame))
    }

    @discardableResult
    private func dispatch(_ event: UltrawideDockEvent) -> WindowAction? {
        guard var interaction else { return currentAction }
        let output = interaction.handle(event)
        self.interaction = interaction
        apply(output)
        return currentAction
    }

    private func apply(_ output: UltrawideDockOutput) {
        activeTargetID = Self.targetID(output.target)
        activeTargetPosition = Self.targetPosition(
            output.target,
            commit: output.commit,
            scene: runtime?.scene
        )
        operationTitle = Self.title(for: output.operation)
        interactionHint = Self.hint(for: output.operation)
        cursor = output.cursor

        // Pointer motion within one visual target should update its marker, but must not mint a
        // fresh WindowAction UUID and reopen the preview on every mouse event.
        guard output.commit != lastCommit else { return }
        lastCommit = output.commit

        currentAction = .init(.noSelection)
        pendingExecution = nil
        hasPendingCommit = false
        previewFrames = []

        guard let commit = output.commit else {
            percentageFeedback = Self.percentages(runtime?.scene.slots.map(\.frame) ?? [])
            return
        }

        switch commit {
        case let .window(id, frame, kind):
            let actionFrame: CGRect = if kind == .stack, let runtime {
                HorizontalLayoutRuntimeGeometry.rawFrameProducingPaddedWindow(
                    frame,
                    halfWindowPadding: runtime.padding.window / 2 / runtime.usableBounds.width,
                    edgeTolerance: 1 / runtime.usableBounds.width
                )
            } else {
                frame
            }
            currentAction = HorizontalLayoutRuntimeAdapter.action(
                for: actionFrame,
                name: Self.actionName(for: kind)
            )
            let memberCount: Int = if case let .stack(existingCount) = output.operation {
                existingCount + 1
            } else {
                1
            }
            previewFrames = [PreviewFrame(
                id: id,
                frame: frame,
                isCurrent: true,
                memberCount: memberCount,
                isFloating: kind == .free
            )]
            percentageFeedback = Self.percentages([frame])
            hasPendingCommit = true

        case let .layout(plan, membersByTileID):
            applyLayout(plan, membersByTileID: membersByTileID)
        }
    }

    private func applyLayout(
        _ plan: HorizontalLayoutPlan,
        membersByTileID: [HorizontalLayoutTileID: [HorizontalLayoutTileID]]
    ) {
        guard let runtime else { return }

        let changes = UltrawideDockLayoutDiffer.changes(
            for: plan,
            membersByTileID: membersByTileID,
            in: runtime.scene
        )

        guard !changes.windowIDs.isEmpty else {
            percentageFeedback = Self.percentages(runtime.scene.slots.map(\.frame))
            return
        }

        previewFrames = plan.snapshot.tiles.compactMap { tile in
            guard changes.tileIDs.contains(tile.id) else { return nil }
            let members = membersByTileID[tile.id] ?? [tile.id]
            return PreviewFrame(
                id: tile.id,
                frame: tile.frame,
                isCurrent: members.contains(runtime.currentID),
                memberCount: members.count,
                isFloating: false
            )
        }

        if let currentTile = plan.snapshot.tiles.first(where: {
            (membersByTileID[$0.id] ?? [$0.id]).contains(runtime.currentID)
        }) {
            currentAction = HorizontalLayoutRuntimeAdapter.action(for: currentTile.frame)
        }

        if changes.windowIDs != [runtime.currentID] {
            pendingExecution = HorizontalLayoutPendingExecution(
                plan: plan,
                membersByTileID: membersByTileID,
                changedWindowIDs: changes.windowIDs,
                windowsByID: runtime.windowsByID,
                usableBounds: runtime.usableBounds,
                padding: runtime.padding,
                screen: runtime.screen
            )
        }
        percentageFeedback = Self.percentages(plan.snapshot.tiles.map(\.frame))
        hasPendingCommit = true
    }

    // MARK: - Presentation

    private static func dividers(in snapshot: HorizontalLayoutSnapshot) -> [Divider] {
        guard snapshot.tiles.count > 1 else { return [] }
        var result: [Divider] = []
        for index in 0 ..< snapshot.tiles.count - 1 {
            let leading = snapshot.tiles[index]
            let trailing = snapshot.tiles[index + 1]
            guard abs(leading.frame.maxX - trailing.frame.minX) <= 0.000_001 else { continue }
            result.append(Divider(
                id: "\(leading.id.rawValue)|\(trailing.id.rawValue)",
                afterID: leading.id,
                x: leading.frame.maxX
            ))
        }
        return result
    }

    private static func actionName(for kind: UltrawideDockWindowCommitKind) -> String {
        switch kind {
        case .placement: "ultrawide_place"
        case .free: "ultrawide_free"
        case .stack: "ultrawide_stack"
        }
    }

    private static func targetID(_ target: UltrawideDockTarget?) -> String? {
        switch target {
        case let .place(edge): "place:\(edge)"
        case .free: "free"
        case .insert: "insert"
        case let .stack(slotID): "stack:\(slotID.rawValue)"
        case let .current(slotID): "current:\(slotID.rawValue)"
        case let .divider(afterID): "divider:\(afterID.rawValue)"
        case nil: nil
        }
    }

    private static func targetPosition(
        _ target: UltrawideDockTarget?,
        commit: UltrawideDockCommit?,
        scene: UltrawideDockScene?
    ) -> CGFloat? {
        switch target {
        case let .insert(position), let .free(position):
            return position
        case let .divider(afterID):
            if case let .layout(plan, _) = commit,
               let movedDivider = plan.snapshot.tiles.first(where: { $0.id == afterID }) {
                return movedDivider.frame.maxX
            }
            return scene?.layout.tiles.first(where: { $0.id == afterID })?.frame.maxX
        case let .stack(slotID), let .current(slotID):
            return scene?.slot(id: slotID)?.frame.midX
        case let .place(edge):
            switch edge {
            case .leading:
                return 0.17
            case .center:
                return 0.5
            case .trailing:
                return 0.83
            }
        case nil:
            return nil
        }
    }

    private static func title(for operation: UltrawideDockOperation) -> String {
        switch operation {
        case .idle: "Move to place · window center stacks"
        case .placement: "Place window"
        case let .freePlacement(aligned):
            aligned ? "Free placement · aligned to an edge" : "Free placement · nothing else moves"
        case let .stack(existingCount):
            existingCount == 1 ? "Stack on this window" : "Add to stack of \(existingCount)"
        case let .insert(rebalanced): rebalanced ? "Place alongside · row rebalances" : "Place in free space"
        case .move: "Move to this slot"
        case .current: "Window is already here"
        case .resizeReady: "Drag this divider"
        case .resize: "Resize adjacent slots"
        case .unavailable: "Unavailable at the minimum width"
        }
    }

    private static func hint(for operation: UltrawideDockOperation) -> String {
        switch operation {
        case .idle: "Click: 1/2 → 1/3 → 1/4 · scroll fine-tunes · Esc cancels"
        case .stack: "Release stacks · existing windows stay put · Esc cancels"
        case .resizeReady: "Hold click and drag · scroll fine-tunes · Esc cancels"
        case .resize: "Release applies · move away to pick something else"
        case .placement: "Click: 1/2 → 1/3 → 1/4 · scroll fine-tunes · release applies"
        case .freePlacement: "Click cycles size · scroll fine-tunes · move up to rejoin row"
        case let .insert(rebalanced):
            rebalanced
                ? "Row splits evenly · drag a divider afterwards · Esc cancels"
                : "Click: 1/2 → 1/3 → 1/4 · scroll fine-tunes · release applies"
        case .current: "Move away or press Esc"
        case .unavailable: "Choose more space · Esc cancels"
        default: "Release applies · Esc cancels"
        }
    }

    private static func percentages(_ frames: [CGRect]) -> String {
        frames.sorted(by: { $0.minX < $1.minX })
            .map { "\(Int(($0.width * 100).rounded()))%" }
            .joined(separator: " · ")
    }
}
