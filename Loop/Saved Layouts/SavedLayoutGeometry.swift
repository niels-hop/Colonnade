//
//  SavedLayoutGeometry.swift
//  Loop
//
//  Pure full-height rail normalization shared by capture and standalone tests.
//

import CoreGraphics
import Foundation

enum SavedLayoutGeometry {
    static func normalizedPlacement(
        for frame: CGRect,
        in bounds: CGRect
    ) -> NormalizedHorizontalPlacement? {
        guard bounds.width > 0, frame.width > 0 else { return nil }
        let minX = max(bounds.minX, min(frame.minX, bounds.maxX))
        let maxX = max(minX, min(frame.maxX, bounds.maxX))
        guard maxX > minX else { return nil }

        return try? NormalizedHorizontalPlacement(
            normalizedX: Double((minX - bounds.minX) / bounds.width),
            normalizedWidth: Double((maxX - minX) / bounds.width)
        )
    }

    static func isFullHeightRail(
        _ frame: CGRect,
        in bounds: CGRect,
        tolerance: CGFloat
    ) -> Bool {
        abs(frame.minY - bounds.minY) <= tolerance &&
            abs(frame.maxY - bounds.maxY) <= tolerance &&
            frame.minX >= bounds.minX - tolerance &&
            frame.maxX <= bounds.maxX + tolerance
    }
}
