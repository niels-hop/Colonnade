import CoreGraphics
import Foundation

/// Pure geometry used by the Accessibility adapter and its standalone tests.
enum HorizontalLayoutRuntimeGeometry {
    /// Bridges only tiny visual gaps introduced by configured inner padding. Real free space remains
    /// explicit and overlapping rows are rejected by `HorizontalLayoutSnapshot`.
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
            guard gap >= 0 else {
                return try HorizontalLayoutSnapshot(tiles: sorted)
            }
            guard gap <= adjacencyTolerance else { continue }
            let boundary = (frames[index].maxX + frames[index + 1].minX) / 2
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
}
