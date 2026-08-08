import CoreGraphics
import Foundation

/// Deterministically plans horizontal, full-height layout mutations without observing or mutating app state.
public struct HorizontalLayoutEngine: Sendable {
    public let minimumWidth: CGFloat

    public init(minimumWidth: CGFloat = 0.1) throws {
        guard minimumWidth.isFinite, minimumWidth > 0, minimumWidth <= 1 else {
            throw HorizontalLayoutError.invalidMinimumWidth
        }
        self.minimumWidth = minimumWidth
    }

    public func plan(
        _ intent: HorizontalLayoutIntent,
        from snapshot: HorizontalLayoutSnapshot
    ) throws -> HorizontalLayoutPlan {
        try validateMinimumWidths(in: snapshot)

        switch intent {
        case let .moveDivider(id, position):
            return try moveDivider(after: id, to: position, in: snapshot)
        case let .insert(id, position):
            return try insert(id, near: position, in: snapshot)
        case let .swap(first, second):
            return try swap(first, second, in: snapshot)
        case let .move(id, index):
            return try move(id, to: index, in: snapshot)
        case let .replace(target, incoming, destination):
            return try replace(target: target, with: incoming, displacedTo: destination, in: snapshot)
        case let .balance(range):
            return try balance(range, in: snapshot)
        case let .apply(profile):
            return try apply(profile, to: snapshot)
        }
    }

    private func moveDivider(
        after id: HorizontalLayoutTileID,
        to requestedPosition: CGFloat,
        in snapshot: HorizontalLayoutSnapshot
    ) throws -> HorizontalLayoutPlan {
        guard requestedPosition.isFinite else {
            throw HorizontalLayoutError.nonFinitePosition
        }
        guard let leftIndex = snapshot.tiles.firstIndex(where: { $0.id == id }) else {
            throw HorizontalLayoutError.missingTile(id)
        }
        let rightIndex = leftIndex + 1
        guard snapshot.tiles.indices.contains(rightIndex) else {
            throw HorizontalLayoutError.invalidRange
        }

        let left = snapshot.tiles[leftIndex]
        let right = snapshot.tiles[rightIndex]
        guard left.frame.maxX == right.frame.minX else {
            throw HorizontalLayoutError.tilesNotAdjacent(left.id, right.id)
        }

        let minimumDividerX = left.frame.minX + minimumWidth
        let maximumDividerX = right.frame.maxX - minimumWidth
        guard minimumDividerX <= maximumDividerX else {
            throw HorizontalLayoutError.minimumWidthsDoNotFit
        }

        let dividerX = requestedPosition.clamped(to: minimumDividerX ... maximumDividerX)
        var tiles = snapshot.tiles
        tiles[leftIndex] = tile(left.id, x: left.frame.minX, width: dividerX - left.frame.minX)
        tiles[rightIndex] = tile(right.id, x: dividerX, width: right.frame.maxX - dividerX)

        let adjustment: [HorizontalLayoutAdjustment] = dividerX == requestedPosition
            ? []
            : [.dividerClamped(requested: requestedPosition, applied: dividerX)]
        return try makePlan(tiles, adjustments: adjustment)
    }

    private func insert(
        _ id: HorizontalLayoutTileID,
        near requestedPosition: CGFloat,
        in snapshot: HorizontalLayoutSnapshot
    ) throws -> HorizontalLayoutPlan {
        guard !id.rawValue.isEmpty else {
            throw HorizontalLayoutError.emptyTileID
        }
        guard requestedPosition.isFinite else {
            throw HorizontalLayoutError.nonFinitePosition
        }
        guard !snapshot.tiles.contains(where: { $0.id == id }) else {
            throw HorizontalLayoutError.duplicateTileID(id)
        }

        let position = requestedPosition.clamped(to: 0 ... 1)
        var adjustments: [HorizontalLayoutAdjustment] = []
        if position != requestedPosition {
            adjustments.append(.positionClamped(requested: requestedPosition, applied: position))
        }

        let eligibleGaps = freeSpans(in: snapshot).filter { $0.width >= minimumWidth }
        if let destination = eligibleGaps.min(by: { gapDistance($0, to: position) < gapDistance($1, to: position) }) {
            let inserted = tile(id, x: destination.x, width: destination.width)
            let tiles = (snapshot.tiles + [inserted]).sortedByPosition()
            adjustments.append(.insertedIntoFreeSpace(destination))
            return try makePlan(tiles, adjustments: adjustments)
        }

        let ids = inserting(id, near: position, into: snapshot.tiles)
        let width = 1 / CGFloat(ids.count)
        guard width >= minimumWidth else {
            throw HorizontalLayoutError.minimumWidthsDoNotFit
        }

        adjustments.append(.fullRowRebalanced)
        return try makePlan(equalTiles(ids: ids, x: 0, width: 1), adjustments: adjustments)
    }

    private func swap(
        _ firstID: HorizontalLayoutTileID,
        _ secondID: HorizontalLayoutTileID,
        in snapshot: HorizontalLayoutSnapshot
    ) throws -> HorizontalLayoutPlan {
        guard let firstIndex = snapshot.tiles.firstIndex(where: { $0.id == firstID }) else {
            throw HorizontalLayoutError.missingTile(firstID)
        }
        guard let secondIndex = snapshot.tiles.firstIndex(where: { $0.id == secondID }) else {
            throw HorizontalLayoutError.missingTile(secondID)
        }
        guard firstIndex != secondIndex else {
            return HorizontalLayoutPlan(snapshot: snapshot)
        }

        var tiles = snapshot.tiles
        tiles[firstIndex] = HorizontalLayoutTile(id: firstID, frame: snapshot.tiles[secondIndex].frame)
        tiles[secondIndex] = HorizontalLayoutTile(id: secondID, frame: snapshot.tiles[firstIndex].frame)
        return try makePlan(tiles.sortedByPosition())
    }

    private func move(
        _ id: HorizontalLayoutTileID,
        to index: Int,
        in snapshot: HorizontalLayoutSnapshot
    ) throws -> HorizontalLayoutPlan {
        guard snapshot.tiles.indices.contains(index) else {
            throw HorizontalLayoutError.indexOutOfBounds(index)
        }
        guard let sourceIndex = snapshot.tiles.firstIndex(where: { $0.id == id }) else {
            throw HorizontalLayoutError.missingTile(id)
        }

        var ids = snapshot.tiles.map(\.id)
        ids.remove(at: sourceIndex)
        ids.insert(id, at: index)
        let tiles = zip(ids, snapshot.tiles.map(\.frame)).map(HorizontalLayoutTile.init)
        return try makePlan(tiles)
    }

    private func replace(
        target targetID: HorizontalLayoutTileID,
        with incomingID: HorizontalLayoutTileID,
        displacedTo destination: HorizontalLayoutSpan,
        in snapshot: HorizontalLayoutSnapshot
    ) throws -> HorizontalLayoutPlan {
        guard !incomingID.rawValue.isEmpty else {
            throw HorizontalLayoutError.emptyTileID
        }
        guard !snapshot.tiles.contains(where: { $0.id == incomingID }) else {
            throw HorizontalLayoutError.duplicateTileID(incomingID)
        }
        guard let targetIndex = snapshot.tiles.firstIndex(where: { $0.id == targetID }) else {
            throw HorizontalLayoutError.missingTile(targetID)
        }
        guard destination.x.isFinite,
              destination.width.isFinite,
              destination.x >= 0,
              destination.width >= minimumWidth,
              destination.x + destination.width <= 1
        else {
            throw HorizontalLayoutError.invalidDestination
        }
        guard snapshot.tiles.allSatisfy({ !$0.frame.intersects(destination.frame) }) else {
            throw HorizontalLayoutError.destinationOccupied
        }

        var tiles = snapshot.tiles
        let targetFrame = tiles[targetIndex].frame
        tiles[targetIndex] = HorizontalLayoutTile(id: incomingID, frame: targetFrame)
        tiles.append(HorizontalLayoutTile(id: targetID, frame: destination.frame))
        return try makePlan(tiles.sortedByPosition())
    }

    private func balance(
        _ range: HorizontalLayoutRange,
        in snapshot: HorizontalLayoutSnapshot
    ) throws -> HorizontalLayoutPlan {
        guard !snapshot.tiles.isEmpty else {
            return HorizontalLayoutPlan(snapshot: snapshot)
        }

        let indices: ClosedRange<Int>
        switch range {
        case .all:
            indices = snapshot.tiles.startIndex ... snapshot.tiles.index(before: snapshot.tiles.endIndex)
        case let .between(firstID, lastID):
            guard let first = snapshot.tiles.firstIndex(where: { $0.id == firstID }) else {
                throw HorizontalLayoutError.missingTile(firstID)
            }
            guard let last = snapshot.tiles.firstIndex(where: { $0.id == lastID }) else {
                throw HorizontalLayoutError.missingTile(lastID)
            }
            guard first <= last else {
                throw HorizontalLayoutError.invalidRange
            }
            indices = first ... last
        }

        let outerX = snapshot.tiles[indices.lowerBound].frame.minX
        let outerMaxX = snapshot.tiles[indices.upperBound].frame.maxX
        let ids = indices.map { snapshot.tiles[$0].id }
        let width = (outerMaxX - outerX) / CGFloat(ids.count)
        guard width >= minimumWidth else {
            throw HorizontalLayoutError.minimumWidthsDoNotFit
        }

        var tiles = snapshot.tiles
        for (offset, balancedTile) in equalTiles(ids: ids, x: outerX, width: outerMaxX - outerX).enumerated() {
            tiles[indices.lowerBound + offset] = balancedTile
        }
        return try makePlan(tiles)
    }

    private func apply(
        _ profile: HorizontalLayoutQuickProfile,
        to snapshot: HorizontalLayoutSnapshot
    ) throws -> HorizontalLayoutPlan {
        let ids = snapshot.tiles.map(\.id)
        let tiles: [HorizontalLayoutTile]

        switch profile {
        case .twoEqual:
            try requireTileCount(2, actual: ids.count)
            tiles = equalTiles(ids: ids, x: 0, width: 1)
        case .threeEqual:
            try requireTileCount(3, actual: ids.count)
            tiles = equalTiles(ids: ids, x: 0, width: 1)
        case let .focus25_50_25(focusID):
            try requireTileCount(3, actual: ids.count)
            guard ids.contains(focusID) else {
                throw HorizontalLayoutError.missingTile(focusID)
            }
            let sideIDs = ids.filter { $0 != focusID }
            tiles = [
                tile(sideIDs[0], x: 0, width: 0.25),
                tile(focusID, x: 0.25, width: 0.5),
                tile(sideIDs[1], x: 0.75, width: 0.25),
            ]
        case let .mainAndSidebar(mainID, sidebarEdge):
            try requireTileCount(2, actual: ids.count)
            guard ids.contains(mainID) else {
                throw HorizontalLayoutError.missingTile(mainID)
            }
            let sidebarID = ids.first { $0 != mainID }!
            switch sidebarEdge {
            case .leading:
                tiles = [tile(sidebarID, x: 0, width: 0.25), tile(mainID, x: 0.25, width: 0.75)]
            case .trailing:
                tiles = [tile(mainID, x: 0, width: 0.75), tile(sidebarID, x: 0.75, width: 0.25)]
            }
        }

        guard tiles.allSatisfy({ $0.frame.width >= minimumWidth }) else {
            throw HorizontalLayoutError.minimumWidthsDoNotFit
        }
        return try makePlan(tiles)
    }

    private func validateMinimumWidths(in snapshot: HorizontalLayoutSnapshot) throws {
        if let tile = snapshot.tiles.first(where: { $0.frame.width < minimumWidth }) {
            throw HorizontalLayoutError.tileBelowMinimumWidth(tile.id)
        }
    }

    private func freeSpans(in snapshot: HorizontalLayoutSnapshot) -> [HorizontalLayoutSpan] {
        var spans: [HorizontalLayoutSpan] = []
        var cursor: CGFloat = 0

        for tile in snapshot.tiles {
            if tile.frame.minX > cursor {
                spans.append(HorizontalLayoutSpan(x: cursor, width: tile.frame.minX - cursor))
            }
            cursor = tile.frame.maxX
        }
        if cursor < 1 {
            spans.append(HorizontalLayoutSpan(x: cursor, width: 1 - cursor))
        }
        return spans
    }

    private func gapDistance(_ span: HorizontalLayoutSpan, to position: CGFloat) -> CGFloat {
        if position < span.x { return span.x - position }
        if position > span.x + span.width { return position - (span.x + span.width) }
        return 0
    }

    private func inserting(
        _ id: HorizontalLayoutTileID,
        near position: CGFloat,
        into tiles: [HorizontalLayoutTile]
    ) -> [HorizontalLayoutTileID] {
        var ids = tiles.map(\.id)
        let insertionIndex = tiles.firstIndex(where: { position < $0.frame.midX }) ?? tiles.endIndex
        ids.insert(id, at: insertionIndex)
        return ids
    }

    private func equalTiles(
        ids: [HorizontalLayoutTileID],
        x: CGFloat,
        width outerWidth: CGFloat
    ) -> [HorizontalLayoutTile] {
        let width = outerWidth / CGFloat(ids.count)
        return ids.enumerated().map { index, id in
            let tileX = index == ids.indices.last ? x + outerWidth - width : x + CGFloat(index) * width
            let tileWidth = index == ids.indices.last ? x + outerWidth - tileX : width
            return tile(id, x: tileX, width: tileWidth)
        }
    }

    private func tile(_ id: HorizontalLayoutTileID, x: CGFloat, width: CGFloat) -> HorizontalLayoutTile {
        HorizontalLayoutTile(id: id, frame: CGRect(x: x, y: 0, width: width, height: 1))
    }

    private func requireTileCount(_ expected: Int, actual: Int) throws {
        guard expected == actual else {
            throw HorizontalLayoutError.profileRequiresTileCount(expected: expected, actual: actual)
        }
    }

    private func makePlan(
        _ tiles: [HorizontalLayoutTile],
        adjustments: [HorizontalLayoutAdjustment] = []
    ) throws -> HorizontalLayoutPlan {
        try HorizontalLayoutPlan(snapshot: HorizontalLayoutSnapshot(tiles: tiles), adjustments: adjustments)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension Array where Element == HorizontalLayoutTile {
    func sortedByPosition() -> Self {
        sorted {
            if $0.frame.minX == $1.frame.minX {
                return $0.id.rawValue < $1.id.rawValue
            }
            return $0.frame.minX < $1.frame.minX
        }
    }
}
