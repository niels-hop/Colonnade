import CoreGraphics
import Foundation

/// A frame-mutating target used by the batch executor. Keeping this seam independent from Accessibility
/// makes collision ordering, failure handling, and rollback testable without moving real windows.
@MainActor
protocol HorizontalLayoutFrameTarget: AnyObject {
    var horizontalLayoutFrame: CGRect { get }
    func applyHorizontalLayoutFrame(_ frame: CGRect) async throws
}

struct HorizontalLayoutBatchRequest: Equatable {
    let id: HorizontalLayoutTileID
    let targetFrame: CGRect
}

struct HorizontalLayoutBatchResult: Equatable {
    let originalFrames: [HorizontalLayoutTileID: CGRect]
    let actualFrames: [HorizontalLayoutTileID: CGRect]
}

enum HorizontalLayoutExecutionError: LocalizedError, Equatable {
    case duplicateTarget(HorizontalLayoutTileID)
    case missingTarget(HorizontalLayoutTileID)
    case invalidFrame(HorizontalLayoutTileID)
    case targetDidNotSettle(HorizontalLayoutTileID, rollbackSucceeded: Bool)
    case applyFailed(HorizontalLayoutTileID, rollbackSucceeded: Bool)

    var errorDescription: String? {
        switch self {
        case let .duplicateTarget(id):
            "Horizontal layout contains duplicate target \(id)."
        case let .missingTarget(id):
            "Horizontal layout target \(id) is no longer available."
        case let .invalidFrame(id):
            "Horizontal layout target \(id) has invalid geometry."
        case let .targetDidNotSettle(id, rollbackSucceeded):
            "Window \(id) did not reach its target frame; rollback \(rollbackSucceeded ? "succeeded" : "was incomplete")."
        case let .applyFailed(id, rollbackSucceeded):
            "Window \(id) rejected its target frame; rollback \(rollbackSucceeded ? "succeeded" : "was incomplete")."
        }
    }
}

/// Applies a row as a deterministic transaction: shrink every participant, move the narrow staging
/// frames, then expand from leading to trailing. Recording is intentionally left to the runtime wrapper
/// and only happens after this core has verified the complete batch.
@MainActor
struct HorizontalLayoutBatchExecutor {
    let tolerance: CGFloat

    init(tolerance: CGFloat = 10) {
        self.tolerance = tolerance
    }

    func execute(
        _ requests: [HorizontalLayoutBatchRequest],
        targets: [HorizontalLayoutTileID: any HorizontalLayoutFrameTarget],
        within bounds: CGRect
    ) async throws -> HorizontalLayoutBatchResult {
        var seen = Set<HorizontalLayoutTileID>()
        var originals: [HorizontalLayoutTileID: CGRect] = [:]

        for request in requests {
            guard seen.insert(request.id).inserted else {
                throw HorizontalLayoutExecutionError.duplicateTarget(request.id)
            }
            guard request.targetFrame.isUsableHorizontalLayoutFrame, bounds.contains(request.targetFrame) else {
                throw HorizontalLayoutExecutionError.invalidFrame(request.id)
            }
            guard let target = targets[request.id] else {
                throw HorizontalLayoutExecutionError.missingTarget(request.id)
            }
            originals[request.id] = target.horizontalLayoutFrame
        }

        let ordered = requests.sorted {
            if $0.targetFrame.minX == $1.targetFrame.minX {
                return $0.id.rawValue < $1.id.rawValue
            }
            return $0.targetFrame.minX < $1.targetFrame.minX
        }
        let stagingWidth = max(1, min(
            bounds.width / max(CGFloat(ordered.count * 8), 1),
            ordered.map(\.targetFrame.width).min() ?? 1,
            originals.values.map(\.width).min() ?? 1
        ))

        do {
            // Shrinking first prevents a swap/reorder from sweeping a full-width window through peers.
            for request in ordered {
                try Task.checkCancellation()
                guard let target = targets[request.id], let original = originals[request.id] else { continue }
                let frame = CGRect(
                    x: original.minX,
                    y: request.targetFrame.minY,
                    width: stagingWidth,
                    height: request.targetFrame.height
                )
                try await target.applyHorizontalLayoutFrame(frame)
            }

            // Every window is narrow now, so deterministic jumps to final origins cannot cover a peer.
            for request in ordered {
                try Task.checkCancellation()
                guard let target = targets[request.id] else { continue }
                let frame = CGRect(
                    x: request.targetFrame.minX,
                    y: request.targetFrame.minY,
                    width: stagingWidth,
                    height: request.targetFrame.height
                )
                try await target.applyHorizontalLayoutFrame(frame)
            }

            // Leading-to-trailing expansion ends at the next tile's origin and stays collision-free.
            for request in ordered {
                try Task.checkCancellation()
                guard let target = targets[request.id] else { continue }
                try await target.applyHorizontalLayoutFrame(request.targetFrame)
            }
        } catch {
            let failedID = ordered.first(where: { targets[$0.id] == nil })?.id ?? ordered.first?.id
            let rollbackSucceeded = await rollback(originals, targets: targets)
            if let failedID {
                throw HorizontalLayoutExecutionError.applyFailed(failedID, rollbackSucceeded: rollbackSucceeded)
            }
            throw error
        }

        var actuals: [HorizontalLayoutTileID: CGRect] = [:]
        for request in ordered {
            guard let actual = targets[request.id]?.horizontalLayoutFrame else {
                _ = await rollback(originals, targets: targets)
                throw HorizontalLayoutExecutionError.missingTarget(request.id)
            }
            guard actual.approximatelyEquals(request.targetFrame, tolerance: tolerance) else {
                let rollbackSucceeded = await rollback(originals, targets: targets)
                throw HorizontalLayoutExecutionError.targetDidNotSettle(
                    request.id,
                    rollbackSucceeded: rollbackSucceeded
                )
            }
            actuals[request.id] = actual
        }

        return HorizontalLayoutBatchResult(originalFrames: originals, actualFrames: actuals)
    }

    private func rollback(
        _ originals: [HorizontalLayoutTileID: CGRect],
        targets: [HorizontalLayoutTileID: any HorizontalLayoutFrameTarget]
    ) async -> Bool {
        var succeeded = true
        for id in originals.keys.sorted(by: { $0.rawValue > $1.rawValue }) {
            guard let target = targets[id], let original = originals[id] else {
                succeeded = false
                continue
            }
            do {
                try await target.applyHorizontalLayoutFrame(original)
            } catch {
                succeeded = false
            }
        }
        for (id, original) in originals {
            guard let actual = targets[id]?.horizontalLayoutFrame,
                  actual.approximatelyEquals(original, tolerance: tolerance)
            else {
                succeeded = false
                continue
            }
        }
        return succeeded
    }
}

extension CGRect {
    fileprivate var isUsableHorizontalLayoutFrame: Bool {
        minX.isFinite && minY.isFinite && width.isFinite && height.isFinite && width > 0 && height > 0
    }

    fileprivate func approximatelyEquals(_ other: CGRect, tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance &&
            abs(minY - other.minY) <= tolerance &&
            abs(width - other.width) <= tolerance &&
            abs(height - other.height) <= tolerance
    }
}
