import CoreGraphics
import Foundation

/// Pure geometry used by the Accessibility adapter and its standalone tests.
enum HorizontalLayoutRuntimeGeometry {
    /// Bridges only the tiny gaps and rounding-sized intersections introduced by configured inner
    /// padding. Real free space remains explicit and genuinely overlapping rows are rejected by
    /// `HorizontalLayoutSnapshot`.
    static func makeSnapshot(
        from input: [HorizontalLayoutTile],
        adjacencyTolerance: CGFloat
    ) throws -> HorizontalLayoutSnapshot {
        let sorted = input.sorted {
            if $0.frame.minX == $1.frame.minX { return $0.id.rawValue < $1.id.rawValue }
            return $0.frame.minX < $1.frame.minX
        }
        guard sorted.count > 1 else {
            return try HorizontalLayoutSnapshot(tiles: sorted)
        }

        var frames = sorted.map(\.frame)
        for index in 0 ..< frames.count - 1 {
            let gap = frames[index + 1].minX - frames[index].maxX
            guard abs(gap) <= adjacencyTolerance else {
                // A real overlap is reported rather than repaired; a real gap stays a real gap.
                if gap < 0 { return try HorizontalLayoutSnapshot(tiles: sorted) }
                continue
            }
            let boundary = (frames[index].maxX + frames[index + 1].minX) / 2
            guard boundary > frames[index].minX, boundary < frames[index + 1].maxX else {
                return try HorizontalLayoutSnapshot(tiles: sorted)
            }
            frames[index].size.width = boundary - frames[index].minX
            let nextMaxX = frames[index + 1].maxX
            frames[index + 1].origin.x = boundary
            frames[index + 1].size.width = nextMaxX - boundary
        }

        return try HorizontalLayoutSnapshot(tiles: zip(sorted, frames).map { tile, frame in
            HorizontalLayoutTile(id: tile.id, frame: frame)
        })
    }

    static func logicalFrame(_ normalized: CGRect, in bounds: CGRect) -> CGRect {
        CGRect(
            x: bounds.minX + normalized.minX * bounds.width,
            y: bounds.minY,
            width: normalized.width * bounds.width,
            height: bounds.height
        )
    }

    /// Reconstructs the raw horizontal action frame that produces an already-padded visible frame.
    /// This is used for stacking: applying Loop's inner padding again must still land exactly on the
    /// window underneath instead of making the newly stacked window slightly narrower.
    static func rawFrameProducingPaddedWindow(
        _ paddedFrame: CGRect,
        halfWindowPadding: CGFloat,
        edgeTolerance: CGFloat
    ) -> CGRect {
        let padding = max(0, halfWindowPadding)
        let tolerance = max(0, edgeTolerance)
        let expandsLeading = paddedFrame.minX > tolerance
        let expandsTrailing = paddedFrame.maxX < 1 - tolerance
        let minX = max(0, paddedFrame.minX - (expandsLeading ? padding : 0))
        let maxX = min(1, paddedFrame.maxX + (expandsTrailing ? padding : 0))
        return CGRect(
            x: minX,
            y: paddedFrame.minY,
            width: max(0, maxX - minX),
            height: paddedFrame.height
        )
    }
}
