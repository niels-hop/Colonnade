import CoreGraphics
import Foundation

/// A stable, app-independent identity for a tile in a horizontal layout.
public struct HorizontalLayoutTileID: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

/// A normalized, full-height tile. Snapshots validate its frame before accepting it.
public struct HorizontalLayoutTile: Equatable, Sendable {
    public let id: HorizontalLayoutTileID
    public let frame: CGRect

    public init(id: HorizontalLayoutTileID, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}

/// A normalized horizontal destination that always spans the full height.
public struct HorizontalLayoutSpan: Equatable, Sendable {
    public let x: CGFloat
    public let width: CGFloat

    public init(x: CGFloat, width: CGFloat) {
        self.x = x
        self.width = width
    }

    public var frame: CGRect {
        CGRect(x: x, y: 0, width: width, height: 1)
    }
}

/// An ordered, non-overlapping row of normalized, full-height tiles.
///
/// Input is rejected rather than silently repaired. Callers therefore know that every snapshot crossing
/// the module seam already satisfies the same geometric invariants as an engine-produced plan.
public struct HorizontalLayoutSnapshot: Equatable, Sendable {
    public let tiles: [HorizontalLayoutTile]

    public init(tiles: [HorizontalLayoutTile]) throws {
        try Self.validate(tiles)
        self.tiles = tiles
    }

    public static let empty = try! HorizontalLayoutSnapshot(tiles: [])

    private static func validate(_ tiles: [HorizontalLayoutTile]) throws {
        var ids = Set<HorizontalLayoutTileID>()
        var previousMaxX: CGFloat = 0

        for (index, tile) in tiles.enumerated() {
            guard !tile.id.rawValue.isEmpty else {
                throw HorizontalLayoutError.emptyTileID
            }
            guard ids.insert(tile.id).inserted else {
                throw HorizontalLayoutError.duplicateTileID(tile.id)
            }
            guard tile.frame.hasFiniteHorizontalLayoutGeometry else {
                throw HorizontalLayoutError.nonFiniteGeometry(tile.id)
            }
            guard tile.frame.origin.y == 0, tile.frame.height == 1 else {
                throw HorizontalLayoutError.notFullHeight(tile.id)
            }
            guard tile.frame.width > 0,
                  tile.frame.minX >= 0,
                  tile.frame.maxX <= 1
            else {
                throw HorizontalLayoutError.outOfBounds(tile.id)
            }
            guard index == 0 || tile.frame.minX >= previousMaxX else {
                throw HorizontalLayoutError.overlappingOrUnordered(tile.id)
            }

            previousMaxX = tile.frame.maxX
        }
    }
}

public enum HorizontalLayoutRange: Equatable, Sendable {
    case all
    case between(HorizontalLayoutTileID, HorizontalLayoutTileID)
}

public enum HorizontalLayoutEdge: Equatable, Sendable {
    case leading
    case trailing
}

public enum HorizontalLayoutQuickProfile: Equatable, Sendable {
    case twoEqual
    case threeEqual
    case focus25_50_25(focus: HorizontalLayoutTileID)
    case mainAndSidebar(main: HorizontalLayoutTileID, sidebar: HorizontalLayoutEdge)
}

/// Every supported row mutation. Intents describe desired layout semantics, not app/window actions.
public enum HorizontalLayoutIntent: Equatable, Sendable {
    case moveDivider(after: HorizontalLayoutTileID, to: CGFloat)
    case insert(HorizontalLayoutTileID, near: CGFloat)
    case swap(HorizontalLayoutTileID, HorizontalLayoutTileID)
    case move(HorizontalLayoutTileID, toIndex: Int)
    case replace(
        target: HorizontalLayoutTileID,
        with: HorizontalLayoutTileID,
        displacedTo: HorizontalLayoutSpan
    )
    case balance(HorizontalLayoutRange)
    case apply(HorizontalLayoutQuickProfile)
}

/// An explicit description of any deterministic normalization performed while planning.
public enum HorizontalLayoutAdjustment: Equatable, Sendable {
    case positionClamped(requested: CGFloat, applied: CGFloat)
    case dividerClamped(requested: CGFloat, applied: CGFloat)
    case insertedIntoFreeSpace(HorizontalLayoutSpan)
    case fullRowRebalanced
}

public struct HorizontalLayoutPlan: Equatable, Sendable {
    public let snapshot: HorizontalLayoutSnapshot
    public let adjustments: [HorizontalLayoutAdjustment]

    public init(snapshot: HorizontalLayoutSnapshot, adjustments: [HorizontalLayoutAdjustment] = []) {
        self.snapshot = snapshot
        self.adjustments = adjustments
    }
}

public enum HorizontalLayoutError: Error, Equatable, Sendable {
    case invalidMinimumWidth
    case emptyTileID
    case duplicateTileID(HorizontalLayoutTileID)
    case missingTile(HorizontalLayoutTileID)
    case nonFiniteGeometry(HorizontalLayoutTileID)
    case nonFinitePosition
    case notFullHeight(HorizontalLayoutTileID)
    case outOfBounds(HorizontalLayoutTileID)
    case invalidDestination
    case overlappingOrUnordered(HorizontalLayoutTileID)
    case tileBelowMinimumWidth(HorizontalLayoutTileID)
    case tilesNotAdjacent(HorizontalLayoutTileID, HorizontalLayoutTileID)
    case destinationOccupied
    case indexOutOfBounds(Int)
    case invalidRange
    case profileRequiresTileCount(expected: Int, actual: Int)
    case minimumWidthsDoNotFit
}

private extension CGRect {
    var hasFiniteHorizontalLayoutGeometry: Bool {
        origin.x.isFinite && origin.y.isFinite && width.isFinite && height.isFinite
    }
}
