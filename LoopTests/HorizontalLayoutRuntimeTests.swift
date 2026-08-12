import CoreGraphics
import XCTest

@MainActor
private final class FakeHorizontalLayoutTarget: HorizontalLayoutFrameTarget {
    var horizontalLayoutFrame: CGRect
    var appliedFrames: [CGRect] = []
    var failureOnApply: Int?

    init(frame: CGRect, failureOnApply: Int? = nil) {
        self.horizontalLayoutFrame = frame
        self.failureOnApply = failureOnApply
    }

    func applyHorizontalLayoutFrame(_ frame: CGRect) async throws {
        appliedFrames.append(frame)
        if appliedFrames.count == failureOnApply { throw FakeFailure.rejected }
        horizontalLayoutFrame = frame
    }

    private enum FakeFailure: Error { case rejected }
}

final class HorizontalLayoutRuntimeTests: XCTestCase {
    private let a = HorizontalLayoutTileID(rawValue: "a")
    private let b = HorizontalLayoutTileID(rawValue: "b")

    func testRuntimeGeometryBridgesOnlyPaddingSizedGaps() throws {
        let bridged = try HorizontalLayoutRuntimeGeometry.makeSnapshot(
            from: [tile(a, x: 0, width: 0.49), tile(b, x: 0.51, width: 0.49)],
            adjacencyTolerance: 0.025
        )
        XCTAssertEqual(bridged.tiles[0].frame.maxX, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(bridged.tiles[1].frame.minX, 0.5, accuracy: 0.000_001)

        let realGap = try HorizontalLayoutRuntimeGeometry.makeSnapshot(
            from: [tile(a, x: 0, width: 0.4), tile(b, x: 0.6, width: 0.4)],
            adjacencyTolerance: 0.025
        )
        XCTAssertEqual(realGap.tiles[0].frame.maxX, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(realGap.tiles[1].frame.minX, 0.6, accuracy: 0.000_001)
    }

    func testRuntimeGeometryRejectsExistingOverlap() {
        XCTAssertThrowsError(try HorizontalLayoutRuntimeGeometry.makeSnapshot(
            from: [tile(a, x: 0, width: 0.6), tile(b, x: 0.5, width: 0.5)],
            adjacencyTolerance: 0.025
        ))
    }

    func testRuntimeGeometryReversesInnerPaddingForExactStacking() {
        let centered = HorizontalLayoutRuntimeGeometry.rawFrameProducingPaddedWindow(
            CGRect(x: 0.255, y: 0, width: 0.49, height: 1),
            halfWindowPadding: 0.005,
            edgeTolerance: 0.001
        )
        XCTAssertEqual(centered.minX, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(centered.width, 0.5, accuracy: 0.000_001)

        let leading = HorizontalLayoutRuntimeGeometry.rawFrameProducingPaddedWindow(
            CGRect(x: 0, y: 0, width: 0.495, height: 1),
            halfWindowPadding: 0.005,
            edgeTolerance: 0.001
        )
        XCTAssertEqual(leading.minX, 0, accuracy: 0.000_001)
        XCTAssertEqual(leading.width, 0.5, accuracy: 0.000_001)
    }

    @MainActor
    func testBatchExecutorStagesThenSettlesCompletePlan() async throws {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let left = FakeHorizontalLayoutTarget(frame: CGRect(x: 0, y: 0, width: 500, height: 800))
        let right = FakeHorizontalLayoutTarget(frame: CGRect(x: 500, y: 0, width: 500, height: 800))
        let requests = [
            HorizontalLayoutBatchRequest(id: a, targetFrame: CGRect(x: 500, y: 0, width: 500, height: 800)),
            HorizontalLayoutBatchRequest(id: b, targetFrame: CGRect(x: 0, y: 0, width: 500, height: 800)),
        ]

        let result = try await HorizontalLayoutBatchExecutor(tolerance: 0.1).execute(
            requests,
            targets: [a: left, b: right],
            within: bounds
        )

        XCTAssertEqual(left.horizontalLayoutFrame, requests[0].targetFrame)
        XCTAssertEqual(right.horizontalLayoutFrame, requests[1].targetFrame)
        XCTAssertLessThan(left.appliedFrames[0].width, requests[0].targetFrame.width)
        XCTAssertEqual(result.actualFrames[a], requests[0].targetFrame)
        XCTAssertEqual(result.actualFrames[b], requests[1].targetFrame)
    }

    @MainActor
    func testBatchExecutorRollsBackEveryParticipantOnFailure() async {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let originalA = CGRect(x: 0, y: 0, width: 500, height: 800)
        let originalB = CGRect(x: 500, y: 0, width: 500, height: 800)
        let left = FakeHorizontalLayoutTarget(frame: originalA)
        let right = FakeHorizontalLayoutTarget(frame: originalB, failureOnApply: 2)

        do {
            _ = try await HorizontalLayoutBatchExecutor(tolerance: 0.1).execute(
                [
                    HorizontalLayoutBatchRequest(id: a, targetFrame: originalB),
                    HorizontalLayoutBatchRequest(id: b, targetFrame: originalA),
                ],
                targets: [a: left, b: right],
                within: bounds
            )
            XCTFail("Expected the batch to fail")
        } catch {
            XCTAssertEqual(left.horizontalLayoutFrame, originalA)
            XCTAssertEqual(right.horizontalLayoutFrame, originalB)
        }
    }

    private func tile(_ id: HorizontalLayoutTileID, x: CGFloat, width: CGFloat) -> HorizontalLayoutTile {
        HorizontalLayoutTile(id: id, frame: CGRect(x: x, y: 0, width: width, height: 1))
    }
}
