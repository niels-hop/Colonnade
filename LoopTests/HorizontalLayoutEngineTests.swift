import CoreGraphics
import XCTest

final class HorizontalLayoutEngineTests: XCTestCase {
    private let a = HorizontalLayoutTileID(rawValue: "a")
    private let b = HorizontalLayoutTileID(rawValue: "b")
    private let c = HorizontalLayoutTileID(rawValue: "c")
    private let d = HorizontalLayoutTileID(rawValue: "d")

    func testSnapshotRejectsInvalidInputExplicitly() throws {
        XCTAssertThrowsError(try snapshot([
            tile(a, x: 0.5, width: 0.5),
            tile(b, x: 0, width: 0.5),
        ])) { error in
            XCTAssertEqual(error as? HorizontalLayoutError, .overlappingOrUnordered(b))
        }

        XCTAssertThrowsError(try snapshot([
            tile(a, x: 0, width: 0.6),
            tile(b, x: 0.5, width: 0.5),
        ])) { error in
            XCTAssertEqual(error as? HorizontalLayoutError, .overlappingOrUnordered(b))
        }

        XCTAssertThrowsError(try snapshot([
            tile(a, x: 0, width: 0.5),
            tile(a, x: 0.5, width: 0.5),
        ])) { error in
            XCTAssertEqual(error as? HorizontalLayoutError, .duplicateTileID(a))
        }

        let partialHeight = HorizontalLayoutTile(
            id: a,
            frame: CGRect(x: 0, y: 0.25, width: 1, height: 0.75)
        )
        XCTAssertThrowsError(try snapshot([partialHeight])) { error in
            XCTAssertEqual(error as? HorizontalLayoutError, .notFullHeight(a))
        }
    }

    func testDividerPushPullPreservesOuterBoundsAndClampsMinimums() throws {
        let engine = try HorizontalLayoutEngine(minimumWidth: 0.2)
        let input = try snapshot([
            tile(a, x: 0.1, width: 0.4),
            tile(b, x: 0.5, width: 0.4),
        ])

        let plan = try engine.plan(.moveDivider(after: a, to: 0.85), from: input)

        assertFrame(plan.snapshot.tiles[0], x: 0.1, width: 0.6)
        assertFrame(plan.snapshot.tiles[1], x: 0.7, width: 0.2)
        XCTAssertEqual(plan.adjustments, [.dividerClamped(requested: 0.85, applied: 0.7)])
        assertInvariants(plan)
    }

    func testDividerRejectsNonAdjacentTiles() throws {
        let engine = try HorizontalLayoutEngine(minimumWidth: 0.1)
        let input = try snapshot([
            tile(a, x: 0, width: 0.4),
            tile(b, x: 0.6, width: 0.4),
        ])

        XCTAssertThrowsError(try engine.plan(.moveDivider(after: a, to: 0.5), from: input)) { error in
            XCTAssertEqual(error as? HorizontalLayoutError, .tilesNotAdjacent(a, b))
        }
    }

    func testInsertionUsesNearestEligibleFreeSpaceWithoutMovingExistingTiles() throws {
        let engine = try HorizontalLayoutEngine(minimumWidth: 0.1)
        let input = try snapshot([
            tile(a, x: 0, width: 0.2),
            tile(b, x: 0.4, width: 0.3),
            tile(c, x: 0.9, width: 0.1),
        ])

        let plan = try engine.plan(.insert(d, near: 0.82), from: input)

        XCTAssertEqual(plan.snapshot.tiles.map(\.id), [a, b, d, c])
        assertFrame(plan.snapshot.tiles[2], x: 0.7, width: 0.2)
        guard case let .insertedIntoFreeSpace(destination) = plan.adjustments.first else {
            return XCTFail("Expected an explicit free-space insertion adjustment")
        }
        XCTAssertEqual(destination.x, 0.7, accuracy: 0.000_000_001)
        XCTAssertEqual(destination.width, 0.2, accuracy: 0.000_000_001)
        XCTAssertEqual(plan.snapshot.tiles.filter { $0.id != d }, input.tiles)
        assertInvariants(plan)
    }

    func testInsertionIntoFullRowRebalancesDeterministically() throws {
        let engine = try HorizontalLayoutEngine(minimumWidth: 0.2)
        let input = try snapshot([
            tile(a, x: 0, width: 0.5),
            tile(b, x: 0.5, width: 0.5),
        ])

        let plan = try engine.plan(.insert(c, near: 0.8), from: input)

        XCTAssertEqual(plan.snapshot.tiles.map(\.id), [a, b, c])
        for (index, result) in plan.snapshot.tiles.enumerated() {
            assertFrame(result, x: CGFloat(index) / 3, width: 1 / 3)
        }
        XCTAssertEqual(plan.adjustments, [.fullRowRebalanced])
        assertInvariants(plan)
    }

    func testInsertionNeverDropsTileWhenMinimumWidthsCannotFit() throws {
        let engine = try HorizontalLayoutEngine(minimumWidth: 0.34)
        let input = try snapshot([
            tile(a, x: 0, width: 0.5),
            tile(b, x: 0.5, width: 0.5),
        ])

        XCTAssertThrowsError(try engine.plan(.insert(c, near: 0.5), from: input)) { error in
            XCTAssertEqual(error as? HorizontalLayoutError, .minimumWidthsDoNotFit)
        }
        XCTAssertEqual(input.tiles.map(\.id), [a, b])
    }

    func testSwapAndMovePreserveStableIDsAndGeometrySlots() throws {
        let engine = try HorizontalLayoutEngine(minimumWidth: 0.1)
        let input = try snapshot([
            tile(a, x: 0, width: 0.2),
            tile(b, x: 0.2, width: 0.3),
            tile(c, x: 0.5, width: 0.5),
        ])

        let swapped = try engine.plan(.swap(a, c), from: input)
        XCTAssertEqual(swapped.snapshot.tiles.map(\.id), [c, b, a])
        XCTAssertEqual(swapped.snapshot.tiles.map(\.frame), input.tiles.map(\.frame))

        let moved = try engine.plan(.move(c, toIndex: 1), from: input)
        XCTAssertEqual(moved.snapshot.tiles.map(\.id), [a, c, b])
        XCTAssertEqual(moved.snapshot.tiles.map(\.frame), input.tiles.map(\.frame))
        assertInvariants(swapped)
        assertInvariants(moved)
    }

    func testSafeReplaceRequiresAFreeDestinationForDisplacedTile() throws {
        let engine = try HorizontalLayoutEngine(minimumWidth: 0.1)
        let incoming = HorizontalLayoutTileID(rawValue: "incoming")
        let input = try snapshot([
            tile(a, x: 0, width: 0.3),
            tile(b, x: 0.3, width: 0.3),
        ])

        let plan = try engine.plan(
            .replace(target: b, with: incoming, displacedTo: HorizontalLayoutSpan(x: 0.6, width: 0.4)),
            from: input
        )
        XCTAssertEqual(plan.snapshot.tiles.map(\.id), [a, incoming, b])
        assertFrame(plan.snapshot.tiles[1], x: 0.3, width: 0.3)
        assertFrame(plan.snapshot.tiles[2], x: 0.6, width: 0.4)
        assertInvariants(plan)

        XCTAssertThrowsError(try engine.plan(
            .replace(target: b, with: incoming, displacedTo: HorizontalLayoutSpan(x: 0.2, width: 0.2)),
            from: input
        )) { error in
            XCTAssertEqual(error as? HorizontalLayoutError, .destinationOccupied)
        }
    }

    func testPlaceAcceptsOnlyAFreeSpanThatFitsTheMinimumWidth() throws {
        let engine = try HorizontalLayoutEngine(minimumWidth: 0.1)
        let incoming = HorizontalLayoutTileID(rawValue: "incoming")
        let input = try snapshot([
            tile(a, x: 0, width: 0.37),
            tile(b, x: 0.8, width: 0.2),
        ])

        let plan = try engine.plan(
            .place(incoming, at: HorizontalLayoutSpan(x: 0.37, width: 0.43)),
            from: input
        )
        XCTAssertEqual(plan.snapshot.tiles.map(\.id), [a, incoming, b])
        assertFrame(plan.snapshot.tiles[1], x: 0.37, width: 0.43)
        assertInvariants(plan)

        XCTAssertThrowsError(try engine.plan(
            .place(incoming, at: HorizontalLayoutSpan(x: 0.3, width: 0.3)),
            from: input
        )) { error in
            XCTAssertEqual(error as? HorizontalLayoutError, .destinationOccupied)
        }

        XCTAssertThrowsError(try engine.plan(
            .place(incoming, at: HorizontalLayoutSpan(x: 0.5, width: 0.05)),
            from: input
        )) { error in
            XCTAssertEqual(error as? HorizontalLayoutError, .invalidDestination)
        }

        XCTAssertThrowsError(try engine.plan(
            .place(a, at: HorizontalLayoutSpan(x: 0.4, width: 0.3)),
            from: input
        )) { error in
            XCTAssertEqual(error as? HorizontalLayoutError, .duplicateTileID(a))
        }
    }

    func testBalanceWholeRowAndContiguousRangePreserveOuterBounds() throws {
        let engine = try HorizontalLayoutEngine(minimumWidth: 0.1)
        let input = try snapshot([
            tile(a, x: 0, width: 0.15),
            tile(b, x: 0.15, width: 0.25),
            tile(c, x: 0.4, width: 0.4),
            tile(d, x: 0.8, width: 0.2),
        ])

        let rangePlan = try engine.plan(.balance(.between(b, c)), from: input)
        assertFrame(rangePlan.snapshot.tiles[0], x: 0, width: 0.15)
        assertFrame(rangePlan.snapshot.tiles[1], x: 0.15, width: 0.325)
        assertFrame(rangePlan.snapshot.tiles[2], x: 0.475, width: 0.325)
        assertFrame(rangePlan.snapshot.tiles[3], x: 0.8, width: 0.2)

        let wholePlan = try engine.plan(.balance(.all), from: input)
        for (index, result) in wholePlan.snapshot.tiles.enumerated() {
            assertFrame(result, x: CGFloat(index) * 0.25, width: 0.25)
        }
        assertInvariants(rangePlan)
        assertInvariants(wholePlan)
    }

    func testQuickProfilesProduceExpectedFullHeightRows() throws {
        let engine = try HorizontalLayoutEngine(minimumWidth: 0.1)
        let two = try snapshot([tile(a, x: 0, width: 0.4), tile(b, x: 0.4, width: 0.6)])
        let three = try snapshot([
            tile(a, x: 0, width: 0.2),
            tile(b, x: 0.2, width: 0.3),
            tile(c, x: 0.5, width: 0.5),
        ])

        let twoEqual = try engine.plan(.apply(.twoEqual), from: two)
        XCTAssertEqual(twoEqual.snapshot.tiles.map(\.frame.width), [0.5, 0.5])

        let threeEqual = try engine.plan(.apply(.threeEqual), from: three)
        for (index, tile) in threeEqual.snapshot.tiles.enumerated() {
            assertFrame(tile, x: CGFloat(index) / 3, width: 1 / 3)
        }

        let focused = try engine.plan(.apply(.focus25_50_25(focus: c)), from: three)
        XCTAssertEqual(focused.snapshot.tiles.map(\.id), [a, c, b])
        XCTAssertEqual(focused.snapshot.tiles.map(\.frame.width), [0.25, 0.5, 0.25])

        let leadingSidebar = try engine.plan(.apply(.mainAndSidebar(main: a, sidebar: .leading)), from: two)
        XCTAssertEqual(leadingSidebar.snapshot.tiles.map(\.id), [b, a])
        XCTAssertEqual(leadingSidebar.snapshot.tiles.map(\.frame.width), [0.25, 0.75])

        let trailingSidebar = try engine.plan(.apply(.mainAndSidebar(main: a, sidebar: .trailing)), from: two)
        XCTAssertEqual(trailingSidebar.snapshot.tiles.map(\.id), [a, b])
        XCTAssertEqual(trailingSidebar.snapshot.tiles.map(\.frame.width), [0.75, 0.25])

        for plan in [twoEqual, threeEqual, focused, leadingSidebar, trailingSidebar] {
            assertInvariants(plan)
        }
    }

    func testInvalidProfileAndInvalidRangeAreRejected() throws {
        let engine = try HorizontalLayoutEngine(minimumWidth: 0.1)
        let input = try snapshot([tile(a, x: 0, width: 0.5), tile(b, x: 0.5, width: 0.5)])

        XCTAssertThrowsError(try engine.plan(.apply(.threeEqual), from: input)) { error in
            XCTAssertEqual(
                error as? HorizontalLayoutError,
                .profileRequiresTileCount(expected: 3, actual: 2)
            )
        }
        XCTAssertThrowsError(try engine.plan(.balance(.between(b, a)), from: input)) { error in
            XCTAssertEqual(error as? HorizontalLayoutError, .invalidRange)
        }
    }

    private func snapshot(_ tiles: [HorizontalLayoutTile]) throws -> HorizontalLayoutSnapshot {
        try HorizontalLayoutSnapshot(tiles: tiles)
    }

    private func tile(
        _ id: HorizontalLayoutTileID,
        x: CGFloat,
        width: CGFloat
    ) -> HorizontalLayoutTile {
        HorizontalLayoutTile(id: id, frame: CGRect(x: x, y: 0, width: width, height: 1))
    }

    private func assertFrame(
        _ tile: HorizontalLayoutTile,
        x: CGFloat,
        width: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(tile.frame.minX, x, accuracy: 0.000_000_001, file: file, line: line)
        XCTAssertEqual(tile.frame.width, width, accuracy: 0.000_000_001, file: file, line: line)
        XCTAssertEqual(tile.frame.minY, 0, file: file, line: line)
        XCTAssertEqual(tile.frame.height, 1, file: file, line: line)
    }

    private func assertInvariants(
        _ plan: HorizontalLayoutPlan,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var previousMaxX: CGFloat = 0
        var ids = Set<HorizontalLayoutTileID>()

        for tile in plan.snapshot.tiles {
            XCTAssertTrue(ids.insert(tile.id).inserted, file: file, line: line)
            XCTAssertGreaterThan(tile.frame.width, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(tile.frame.minX, 0, file: file, line: line)
            XCTAssertLessThanOrEqual(tile.frame.maxX, 1, file: file, line: line)
            XCTAssertGreaterThanOrEqual(tile.frame.minX, previousMaxX, file: file, line: line)
            XCTAssertEqual(tile.frame.minY, 0, file: file, line: line)
            XCTAssertEqual(tile.frame.height, 1, file: file, line: line)
            previousMaxX = tile.frame.maxX
        }
    }
}
