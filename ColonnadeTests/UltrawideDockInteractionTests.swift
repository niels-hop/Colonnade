import CoreGraphics
import XCTest

final class UltrawideDockInteractionTests: XCTestCase {
    private let a = HorizontalLayoutTileID(rawValue: "a")
    private let a2 = HorizontalLayoutTileID(rawValue: "a2")
    private let b = HorizontalLayoutTileID(rawValue: "b")
    private let current = HorizontalLayoutTileID(rawValue: "current")

    func testInteractionStartsNeutralAndCancelClearsPendingPlacement() throws {
        var interaction = try makeInteraction(windows: [])

        XCTAssertEqual(interaction.output.operation, .idle)
        XCTAssertNil(interaction.output.commit)

        let placement = interaction.handle(.move(to: 0.1))
        guard case let .window(id, frame, kind) = placement.commit else {
            return XCTFail("Expected a single-window placement")
        }
        XCTAssertEqual(id, current)
        XCTAssertEqual(kind, .placement)
        assertFrame(frame, x: 0, width: 0.5)

        let cancelled = interaction.handle(.cancel)
        XCTAssertEqual(cancelled.operation, .idle)
        XCTAssertNil(cancelled.commit)
        XCTAssertTrue(cancelled.previews.isEmpty)
    }

    func testStandalonePointerZonesPlaceLeftCenterAndRight() throws {
        var interaction = try makeInteraction(windows: [])

        assertWindowCommit(interaction.handle(.move(to: 0.1)), x: 0, width: 0.5)
        assertWindowCommit(interaction.handle(.move(to: 0.5)), x: 0.25, width: 0.5)
        assertWindowCommit(interaction.handle(.move(to: 0.9)), x: 0.5, width: 0.5)
    }

    func testSingleCurrentWindowStillOffersCenteredStandalonePlacement() throws {
        var interaction = try makeInteraction(
            windows: [window(current, x: 0, width: 1, zIndex: 0)]
        )

        let output = interaction.handle(.move(to: 0.5))

        XCTAssertEqual(output.target, .place(edge: .center))
        assertWindowCommit(output, x: 0.25, width: 0.5)
    }

    func testScrollFineTunesStandaloneWidthAtStableStops() throws {
        var interaction = try makeInteraction(windows: [])

        _ = interaction.handle(.move(to: 0.1))
        let adjusted = interaction.handle(.scroll(delta: 1 / 6))

        assertWindowCommit(adjusted, x: 0, width: 2 / 3)
    }

    func testClickCyclesStandaloneWidthThroughHalfThirdQuarter() throws {
        var interaction = try makeInteraction(windows: [])

        _ = interaction.handle(.move(to: 0.1))
        _ = interaction.handle(.pointerDown(at: 0.1))
        assertWindowCommit(interaction.handle(.pointerUp(at: 0.1)), x: 0, width: 1 / 3)

        _ = interaction.handle(.pointerDown(at: 0.1))
        assertWindowCommit(interaction.handle(.pointerUp(at: 0.1)), x: 0, width: 0.25)

        _ = interaction.handle(.pointerDown(at: 0.1))
        assertWindowCommit(interaction.handle(.pointerUp(at: 0.1)), x: 0, width: 0.5)
    }

    func testClickFollowsConfiguredWidthCycle() throws {
        var interaction = try makeInteraction(windows: [], clickWidthCycle: [1 / 3, 0.5, 2 / 3])

        // The default half-width placement is part of this cycle, so the first click steps past it.
        _ = interaction.handle(.move(to: 0.1))
        _ = interaction.handle(.pointerDown(at: 0.1))
        assertWindowCommit(interaction.handle(.pointerUp(at: 0.1)), x: 0, width: 2 / 3)

        _ = interaction.handle(.pointerDown(at: 0.1))
        assertWindowCommit(interaction.handle(.pointerUp(at: 0.1)), x: 0, width: 1 / 3)
    }

    func testClickSelectedWidthFollowsLaterHorizontalMouseMovement() throws {
        var interaction = try makeInteraction(windows: [])

        _ = interaction.handle(.move(to: 0.1))
        _ = interaction.handle(.pointerDown(at: 0.1))
        _ = interaction.handle(.pointerUp(at: 0.1))

        assertWindowCommit(interaction.handle(.move(to: 0.9)), x: 2 / 3, width: 1 / 3)
    }

    func testPlacementDragDoesNotAlsoCycleWidthOnRelease() throws {
        var interaction = try makeInteraction(windows: [])

        _ = interaction.handle(.move(to: 0.1))
        _ = interaction.handle(.pointerDown(at: 0.1))
        _ = interaction.handle(.drag(to: 0.9))
        let released = interaction.handle(.pointerUp(at: 0.9))

        assertWindowCommit(released, x: 0.5, width: 0.5)
    }

    func testOccupiedTileCenterStacksWithoutChangingExistingSlots() throws {
        let windows = [
            window(a, x: 0, width: 0.5, zIndex: 0),
            window(b, x: 0.5, width: 0.5, zIndex: 1)
        ]
        var interaction = try makeInteraction(windows: windows)
        let originalSlots = interaction.scene.slots

        let output = interaction.handle(.move(to: 0.25))

        XCTAssertEqual(output.operation, .stack(existingCount: 1))
        XCTAssertEqual(output.target, .stack(slotID: a))
        guard case let .window(id, frame, kind) = output.commit else {
            return XCTFail("Expected stacking to move only the current window")
        }
        XCTAssertEqual(id, current)
        XCTAssertEqual(kind, .stack)
        assertFrame(frame, x: 0, width: 0.5)
        XCTAssertEqual(interaction.scene.slots, originalSlots)
    }

    func testStackUsesVisibleWindowFrameInsteadOfBridgedLogicalSlot() throws {
        var interaction = try makeInteraction(windows: [
            window(a, x: 0, width: 0.49, zIndex: 0),
            window(b, x: 0.51, width: 0.49, zIndex: 1)
        ])

        let output = interaction.handle(.move(to: 0.25))

        guard case let .window(_, frame, kind) = output.commit else {
            return XCTFail("Expected an exact stack placement")
        }
        XCTAssertEqual(kind, .stack)
        assertFrame(frame, x: 0, width: 0.49)
    }

    func testOccupiedTileEdgeInsertsInsteadOfStacking() throws {
        var interaction = try makeInteraction(windows: [
            window(a, x: 0, width: 0.5, zIndex: 0),
            window(b, x: 0.5, width: 0.5, zIndex: 1)
        ])

        let output = interaction.handle(.move(to: 0.46))

        guard case .insert = output.operation else {
            return XCTFail("Expected an insertion target near the tile edge")
        }
        guard case let .layout(plan, membersByTileID) = output.commit else {
            return XCTFail("Expected a row plan")
        }
        XCTAssertEqual(plan.snapshot.tiles.map(\.id), [a, current, b])
        XCTAssertEqual(membersByTileID[current], [current])
        for tile in plan.snapshot.tiles {
            XCTAssertEqual(tile.frame.width, 1 / 3, accuracy: 0.000_001)
        }
    }

    func testFreeSpaceInsertionDoesNotStageAnUnchangedNeighbour() throws {
        var interaction = try makeInteraction(windows: [
            window(a, x: 0, width: 0.5, zIndex: 0)
        ])

        let output = interaction.handle(.move(to: 0.8))
        guard case let .layout(plan, membersByTileID) = output.commit else {
            return XCTFail("Expected insertion into the free half")
        }

        let changes = UltrawideDockLayoutDiffer.changes(
            for: plan,
            membersByTileID: membersByTileID,
            in: interaction.scene
        )
        XCTAssertEqual(changes.windowIDs, [current])
        XCTAssertEqual(changes.tileIDs, [current])
        assertFrame(plan.snapshot.tiles[0].frame, x: 0, width: 0.5)
        assertFrame(plan.snapshot.tiles[1].frame, x: 0.5, width: 0.5)
    }

    func testDividerIsNeutralUntilPointerDownAndFollowsDrag() throws {
        var interaction = try makeInteraction(
            windows: [
                window(a, x: 0, width: 0.5, zIndex: 0),
                window(b, x: 0.5, width: 0.5, zIndex: 1)
            ],
            currentID: a
        )

        let hover = interaction.handle(.move(to: 0.5))
        XCTAssertEqual(hover.target, .divider(after: a))
        XCTAssertEqual(hover.operation, .resizeReady)
        XCTAssertNil(hover.commit)

        XCTAssertNil(interaction.handle(.pointerDown(at: 0.5)).commit)
        let dragged = interaction.handle(.drag(to: 0.7))

        XCTAssertEqual(dragged.operation, .resize)
        XCTAssertEqual(dragged.cursor, .resizeLeftRight)
        guard case let .layout(plan, _) = dragged.commit else {
            return XCTFail("Expected a divider layout plan")
        }
        assertFrame(plan.snapshot.tiles[0].frame, x: 0, width: 0.7)
        assertFrame(plan.snapshot.tiles[1].frame, x: 0.7, width: 0.3)
        XCTAssertNotNil(interaction.handle(.pointerUp(at: 0.7)).commit)
    }

    func testDividerClickWithoutDragStaysNeutral() throws {
        var interaction = try makeInteraction(
            windows: [
                window(a, x: 0, width: 0.5, zIndex: 0),
                window(b, x: 0.5, width: 0.5, zIndex: 1)
            ],
            currentID: a
        )

        _ = interaction.handle(.move(to: 0.5))
        XCTAssertNil(interaction.handle(.pointerDown(at: 0.5)).commit)

        let released = interaction.handle(.pointerUp(at: 0.5))
        XCTAssertEqual(released.operation, .resizeReady)
        XCTAssertNil(released.commit)
    }

    func testDividerHoverClearsAnEarlierPlacementCommit() throws {
        var interaction = try makeInteraction(windows: [
            window(a, x: 0, width: 0.5, zIndex: 0),
            window(b, x: 0.5, width: 0.5, zIndex: 1)
        ])

        XCTAssertNotNil(interaction.handle(.move(to: 0.25)).commit)
        let divider = interaction.handle(.move(to: 0.5))

        XCTAssertEqual(divider.operation, .resizeReady)
        XCTAssertNil(divider.commit)
    }

    func testDragWithoutADividerContinuesSelectingTargets() throws {
        var interaction = try makeInteraction(windows: [])

        _ = interaction.handle(.move(to: 0.1))
        _ = interaction.handle(.pointerDown(at: 0.1))
        let dragged = interaction.handle(.drag(to: 0.9))

        assertWindowCommit(dragged, x: 0.5, width: 0.5)
    }

    func testExactOverlapsBecomeOneStackAndResizeMovesEveryMember() throws {
        var interaction = try makeInteraction(
            windows: [
                window(a, x: 0, width: 0.5, zIndex: 0),
                window(a2, x: 0, width: 0.5, zIndex: 1),
                window(b, x: 0.5, width: 0.5, zIndex: 2)
            ],
            currentID: a
        )

        XCTAssertEqual(interaction.scene.slots.count, 2)
        XCTAssertEqual(interaction.scene.slots[0].memberIDs, [a, a2])

        _ = interaction.handle(.move(to: 0.5))
        _ = interaction.handle(.pointerDown(at: 0.5))
        let dragged = interaction.handle(.drag(to: 0.6))

        guard case let .layout(plan, membersByTileID) = dragged.commit else {
            return XCTFail("Expected a stacked divider plan")
        }
        XCTAssertEqual(membersByTileID[a], [a, a2])
        assertFrame(plan.snapshot.tiles[0].frame, x: 0, width: 0.6)
        assertFrame(plan.snapshot.tiles[1].frame, x: 0.6, width: 0.4)
    }

    func testMovingCurrentWindowOutOfStackLeavesUnderlyingWindowInOldSlot() throws {
        var interaction = try makeInteraction(
            windows: [
                window(a, x: 0, width: 0.5, zIndex: 0),
                window(a2, x: 0, width: 0.5, zIndex: 1),
                window(b, x: 0.5, width: 0.5, zIndex: 2)
            ],
            currentID: a
        )

        let output = interaction.handle(.move(to: 0.9))

        guard case let .layout(plan, membersByTileID) = output.commit else {
            return XCTFail("Expected the current stack member to become its own slot")
        }
        XCTAssertEqual(plan.snapshot.tiles.count, 3)
        XCTAssertEqual(Set(membersByTileID.values.flatMap(\.self)), Set([a, a2, b]))
        XCTAssertTrue(membersByTileID.values.contains([a2]))
        XCTAssertTrue(membersByTileID.values.contains([a]))
    }

    func testPartialOverlapExcludesOneWindowInsteadOfDisablingTheDock() throws {
        var interaction = try makeInteraction(windows: [
            window(a, x: 0, width: 0.6, zIndex: 0),
            window(b, x: 0.5, width: 0.5, zIndex: 1)
        ])

        // The narrower window loses its place in the row, but it is never planned and therefore
        // never moved — the dock stays usable instead of going inert.
        XCTAssertEqual(interaction.scene.slots.map(\.id), [a])
        XCTAssertEqual(interaction.scene.excludedWindowIDs, [b])

        let output = interaction.handle(.move(to: 0.8))
        guard case let .layout(plan, membersByTileID) = output.commit else {
            return XCTFail("Expected the dock to still offer a placement")
        }
        XCTAssertFalse(plan.snapshot.tiles.contains { $0.id == b })
        XCTAssertFalse(membersByTileID.values.flatMap(\.self).contains(b))
    }

    func testOneNarrowOverlappingWindowDoesNotEvictTheWideOnesAroundIt() throws {
        let scene = try UltrawideDockScene(
            windows: [
                window(a, x: 0, width: 0.5, zIndex: 2),
                window(current, x: 0.45, width: 0.1, zIndex: 0),
                window(b, x: 0.55, width: 0.45, zIndex: 1)
            ],
            currentID: HorizontalLayoutTileID(rawValue: "absent"),
            frameTolerance: 0.001
        )

        XCTAssertEqual(scene.slots.map(\.id), [a, b])
        XCTAssertEqual(scene.excludedWindowIDs, [current])
    }

    func testCurrentOverlappingWindowCanReenterAnOtherwiseValidRow() throws {
        let scene = try UltrawideDockScene(
            windows: [
                window(a, x: 0, width: 0.5, zIndex: 1),
                window(b, x: 0.5, width: 0.5, zIndex: 2),
                window(current, x: 0.25, width: 0.5, zIndex: 0)
            ],
            currentID: current,
            frameTolerance: 0.001
        )

        XCTAssertEqual(scene.slots.map(\.id), [a, b])
        XCTAssertNil(scene.currentSlot)
        XCTAssertTrue(scene.excludedWindowIDs.isEmpty)
    }

    func testFinishedResizeSurvivesPointerJitterAfterTheButtonIsReleased() throws {
        var interaction = try makeInteraction(
            windows: [
                window(a, x: 0, width: 0.5, zIndex: 0),
                window(b, x: 0.5, width: 0.5, zIndex: 1)
            ],
            currentID: a
        )

        _ = interaction.handle(.move(to: 0.5))
        _ = interaction.handle(.pointerDown(at: 0.5))
        _ = interaction.handle(.drag(to: 0.7))
        _ = interaction.handle(.pointerUp(at: 0.7))

        let jittered = interaction.handle(.move(to: 0.702))

        XCTAssertEqual(jittered.operation, .resize)
        guard case let .layout(plan, _) = jittered.commit else {
            return XCTFail("Expected the finished resize to survive")
        }
        assertFrame(plan.snapshot.tiles[0].frame, x: 0, width: 0.7)
    }

    func testMovingAwayAfterAResizeStillPicksANewTarget() throws {
        var interaction = try makeInteraction(
            windows: [
                window(a, x: 0, width: 0.5, zIndex: 0),
                window(b, x: 0.5, width: 0.5, zIndex: 1)
            ],
            currentID: a
        )

        _ = interaction.handle(.move(to: 0.5))
        _ = interaction.handle(.pointerDown(at: 0.5))
        _ = interaction.handle(.drag(to: 0.7))
        _ = interaction.handle(.pointerUp(at: 0.7))

        let moved = interaction.handle(.move(to: 0.75))

        XCTAssertEqual(moved.target, .stack(slotID: b))
    }

    func testScrollResizesAWindowBeingInsertedIntoFreeSpace() throws {
        var interaction = try makeInteraction(windows: [
            window(a, x: 0, width: 0.5, zIndex: 0)
        ])

        _ = interaction.handle(.move(to: 0.8))
        let scrolled = interaction.handle(.scroll(delta: -0.2))

        guard case let .layout(plan, _) = scrolled.commit else {
            return XCTFail("Expected a narrower insertion")
        }
        assertFrame(plan.snapshot.tiles[0].frame, x: 0, width: 0.5)
        assertFrame(plan.snapshot.tiles[1].frame, x: 0.65, width: 0.3)
    }

    /// A gap whose width does not round-trip cleanly through subtraction. Computing the placement
    /// bounds in the wrong order produces an inverted range here, so this pins the exact fit.
    func testInsertionFillsAGapWithAnAwkwardBoundaryExactly() throws {
        for tileWidth in [0.1, 0.37, 0.45] {
            var interaction = try makeInteraction(windows: [
                window(a, x: 0, width: tileWidth, zIndex: 0)
            ])

            let output = interaction.handle(.move(to: 0.9))

            guard case let .layout(plan, _) = output.commit else {
                return XCTFail("Expected the free gap after \(tileWidth) to be filled, not rejected")
            }
            assertFrame(plan.snapshot.tiles[1].frame, x: tileWidth, width: 1 - tileWidth)
        }
    }

    func testInsertionWidthStaysInsideItsFreeGap() throws {
        var interaction = try makeInteraction(windows: [
            window(a, x: 0, width: 0.7, zIndex: 0)
        ])

        _ = interaction.handle(.move(to: 0.9))
        let scrolled = interaction.handle(.scroll(delta: 0.5))

        guard case let .layout(plan, _) = scrolled.commit else {
            return XCTFail("Expected an insertion clamped to the free gap")
        }
        assertFrame(plan.snapshot.tiles[1].frame, x: 0.7, width: 0.3)
    }

    // MARK: - Free placement

    func testFreeformPlacesOverAFullRowWithoutPlanningAnything() throws {
        var interaction = try makeInteraction(windows: [
            window(a, x: 0, width: 0.5, zIndex: 0),
            window(b, x: 0.5, width: 0.5, zIndex: 1),
            window(current, x: 0, width: 0.5, zIndex: 2)
        ])

        _ = interaction.handle(.move(to: 0.5))
        let free = interaction.handle(.setFreeform(true))

        XCTAssertEqual(free.target, .free(position: 0.5))
        guard case let .window(id, frame, kind) = free.commit else {
            return XCTFail("Free placement must never produce a layout plan")
        }
        XCTAssertEqual(id, current)
        XCTAssertEqual(kind, .free)
        assertFrame(frame, x: 0.25, width: 0.5)
    }

    func testFreeformStartsAtTheWindowsOwnWidthAndScrollResizesIt() throws {
        var interaction = try makeInteraction(windows: [
            window(a, x: 0, width: 0.7, zIndex: 0),
            window(current, x: 0.7, width: 0.3, zIndex: 1)
        ])

        _ = interaction.handle(.move(to: 0.4))
        let free = interaction.handle(.setFreeform(true))
        guard case let .window(_, frame, _) = free.commit else {
            return XCTFail("Expected a free placement")
        }
        assertFrame(frame, x: 0.25, width: 0.3)

        let widened = interaction.handle(.scroll(delta: 0.2))
        guard case let .window(_, widenedFrame, kind) = widened.commit else {
            return XCTFail("Scrolling must keep the placement free")
        }
        XCTAssertEqual(kind, .free)
        assertFrame(widenedFrame, x: 0.15, width: 0.5)
    }

    func testFreeformAlignsToANeighbouringEdgeWithoutTouchingThatNeighbour() throws {
        var interaction = try makeInteraction(windows: [
            window(a, x: 0, width: 0.4, zIndex: 0),
            window(b, x: 0.4, width: 0.6, zIndex: 1)
        ])
        let originalSlots = interaction.scene.slots

        _ = interaction.handle(.setFreeform(true))
        // A 0.5-wide window centred at 0.653 starts at 0.403 — inside the alignment tolerance of
        // the boundary at 0.4, so it snaps flush against it.
        let output = interaction.handle(.move(to: 0.653))

        XCTAssertEqual(output.operation, .freePlacement(aligned: true))
        guard case let .window(_, frame, _) = output.commit else {
            return XCTFail("Expected a free placement")
        }
        assertFrame(frame, x: 0.4, width: 0.5)
        XCTAssertEqual(interaction.scene.slots, originalSlots)
    }

    func testFreeformIgnoresDividersAndLeavingItRestoresRowTargets() throws {
        var interaction = try makeInteraction(windows: [
            window(a, x: 0, width: 0.5, zIndex: 0),
            window(b, x: 0.5, width: 0.5, zIndex: 1)
        ])

        XCTAssertEqual(interaction.handle(.move(to: 0.5)).target, .divider(after: a))

        _ = interaction.handle(.setFreeform(true))
        let onDivider = interaction.handle(.move(to: 0.5))
        XCTAssertEqual(onDivider.target, .free(position: 0.5))
        _ = interaction.handle(.pointerDown(at: 0.5))
        XCTAssertEqual(interaction.handle(.drag(to: 0.52)).target, .free(position: 0.52))

        let back = interaction.handle(.setFreeform(false))
        XCTAssertEqual(back.target, .divider(after: a))
    }

    func testFreeformSwitchMidDividerDragKeepsTheResize() throws {
        var interaction = try makeInteraction(windows: [
            window(a, x: 0, width: 0.5, zIndex: 0),
            window(b, x: 0.5, width: 0.5, zIndex: 1)
        ])

        _ = interaction.handle(.move(to: 0.5))
        _ = interaction.handle(.pointerDown(at: 0.5))
        _ = interaction.handle(.drag(to: 0.62))

        let duringDrag = interaction.handle(.setFreeform(true))

        XCTAssertEqual(duringDrag.target, .divider(after: a))
        XCTAssertEqual(duringDrag.operation, .resize)
    }

    func testFreeformBeforeAnyPointerMovementStaysNeutral() throws {
        var interaction = try makeInteraction(windows: [
            window(a, x: 0, width: 1, zIndex: 0)
        ])

        let output = interaction.handle(.setFreeform(true))

        XCTAssertEqual(output.operation, .idle)
        XCTAssertNil(output.commit)
    }

    private func makeInteraction(
        windows: [UltrawideDockWindowSnapshot],
        currentID: HorizontalLayoutTileID? = nil,
        clickWidthCycle: [CGFloat] = UltrawideDockInteraction.defaultClickWidthCycle
    ) throws -> UltrawideDockInteraction {
        let scene = try UltrawideDockScene(
            windows: windows,
            currentID: currentID ?? current,
            frameTolerance: 0.001
        )
        return try UltrawideDockInteraction(scene: scene, minimumWidth: 0.1, clickWidthCycle: clickWidthCycle)
    }

    private func window(
        _ id: HorizontalLayoutTileID,
        x: CGFloat,
        width: CGFloat,
        zIndex: Int
    ) -> UltrawideDockWindowSnapshot {
        UltrawideDockWindowSnapshot(
            id: id,
            frame: CGRect(x: x, y: 0, width: width, height: 1),
            zIndex: zIndex
        )
    }

    private func assertWindowCommit(
        _ output: UltrawideDockOutput,
        x: CGFloat,
        width: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .window(id, frame, kind) = output.commit else {
            return XCTFail("Expected a window commit", file: file, line: line)
        }
        XCTAssertEqual(id, current, file: file, line: line)
        XCTAssertEqual(kind, .placement, file: file, line: line)
        assertFrame(frame, x: x, width: width, file: file, line: line)
    }

    private func assertFrame(
        _ frame: CGRect,
        x: CGFloat,
        width: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(frame.minX, x, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(frame.width, width, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(frame.minY, 0, file: file, line: line)
        XCTAssertEqual(frame.height, 1, file: file, line: line)
    }
}
