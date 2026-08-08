//
//  UltrawideDockView.swift
//  Loop
//
//  Created by Antigravity on 2025-11-18.
//

import Defaults
import Luminare
import SwiftUI

struct UltrawideDockView: View {
    @Environment(\.luminareAnimation) private var luminareAnimation
    @ObservedObject private var accentColorController: AccentColorController = .shared
    @ObservedObject private var viewModel: UltrawideDockViewModel

    private let screen: NSScreen?
    private let baseDockWidth: CGFloat = 600
    private let baseDockHeight: CGFloat = 176
    private let cornerRadius: CGFloat = 10

    // Compute dynamic dock width based on screen aspect ratio
    private var dockWidth: CGFloat {
        guard let screen else { return baseDockWidth }

        let aspectRatio = screen.frame.width / screen.frame.height
        let isUltrawide = aspectRatio >= 2.0 // 21:9 is ~2.33, 32:9 is ~3.55

        if isUltrawide {
            // Scale dock width for ultrawide displays (max 800px for 32:9)
            let scaleFactor = min(aspectRatio / 1.6, 1.33) // 1.6 = standard 16:10
            return baseDockWidth * scaleFactor
        }

        return baseDockWidth
    }

    private var dockHeight: CGFloat {
        baseDockHeight
    }

    init(viewModel: UltrawideDockViewModel, screen: NSScreen?) {
        self.viewModel = viewModel
        self.screen = screen
    }

    var body: some View {
        ZStack {
            // Background
            if #available(macOS 26.0, *) {
                Color.clear
                    .glassEffect(
                        .regular,
                        in: .rect(cornerRadius: cornerRadius)
                    )
            } else {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }

            VStack(spacing: 7) {
                // Screen representation. Tiles, shared dividers, and free-space anchors are all
                // explicit targets; the footer explains the operation that will commit on release.
                GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height

                // Existing windows (already positioned with Loop)
                // Sort by z-order: render from back to front (higher zIndex first)
                ForEach(viewModel.existingWindows.sorted(by: { $0.zIndex > $1.zIndex })) { windowFrame in
                    // Calculate opacity based on z-order (frontmost windows are more opaque)
                    let maxZIndex = viewModel.existingWindows.map(\.zIndex).max() ?? 0
                    let normalizedDepth = maxZIndex > 0 ? CGFloat(windowFrame.zIndex) / CGFloat(maxZIndex) : 0
                    let opacity = 0.5 - (normalizedDepth * 0.2) // Range: 0.3 (back) to 0.5 (front)

                    RoundedRectangle(cornerRadius: 5)
                        .fill(windowFrame.isActive ? Color.gray.opacity(opacity + 0.12) : Color.gray.opacity(opacity))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(
                                    viewModel.activeTargetID == "tile:\(windowFrame.id.rawValue)"
                                        ? accentColorController.color1
                                        : Color.white.opacity(0.3),
                                    lineWidth: viewModel.activeTargetID == "tile:\(windowFrame.id.rawValue)" ? 2 : 1
                                )
                        )
                        .frame(
                            width: max(0, windowFrame.frame.width * width),
                            height: max(0, windowFrame.frame.height * height)
                        )
                        .position(
                            x: windowFrame.frame.midX * width,
                            y: windowFrame.frame.midY * height
                        )
                        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                        .zIndex(Double(-windowFrame.zIndex)) // SwiftUI zIndex (negative so lower values are behind)
                }

                // Anchor tickmarks — short vertical lines at each snap point along the top
                // and bottom edges. The active anchor is rendered in the accent color so the
                // user can see which snap point will commit when releasing the loop trigger.
                ForEach(viewModel.anchors) { anchor in
                    let isActive = "anchor:\(anchor.id)" == viewModel.activeTargetID
                    let tickColor: Color = isActive
                        ? accentColorController.color1
                        : Color.white.opacity(0.35)
                    let tickHeight: CGFloat = isActive ? 10 : 6
                    let tickWidth: CGFloat = isActive ? 2 : 1

                    RoundedRectangle(cornerRadius: tickWidth / 2)
                        .fill(tickColor)
                        .frame(width: tickWidth, height: tickHeight)
                        .position(x: anchor.anchorX * width, y: tickHeight / 2)
                        .zIndex(500)

                    RoundedRectangle(cornerRadius: tickWidth / 2)
                        .fill(tickColor)
                        .frame(width: tickWidth, height: tickHeight)
                        .position(x: anchor.anchorX * width, y: height - tickHeight / 2)
                        .zIndex(500)
                }

                // Shared divider handles. Only adjacent handles are bright enough to invite a
                // push-pull, while the remaining handles still explain the row's structure.
                ForEach(viewModel.dividers) { divider in
                    let isActive = "divider:\(divider.id)" == viewModel.activeTargetID
                    Capsule()
                        .fill(
                            isActive
                                ? accentColorController.color1
                                : Color.white.opacity(divider.isCurrentAdjacent ? 0.55 : 0.2)
                        )
                        .frame(width: isActive ? 7 : 4, height: isActive ? 30 : 20)
                        .position(x: divider.x * width, y: height / 2)
                        .shadow(color: Color.black.opacity(0.25), radius: 2)
                        .zIndex(600)
                }

                // Every affected member of a multi-window plan is previewed, not just the current
                // window. This makes swaps, profiles, and divider changes legible before release.
                ForEach(viewModel.previewFrames) { preview in
                    RoundedRectangle(cornerRadius: 5)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    accentColorController.color1,
                                    accentColorController.color2
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .opacity(preview.isCurrent ? 0.9 : 0.58)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.white.opacity(0.65), lineWidth: preview.isCurrent ? 2 : 1)
                        )
                        .frame(
                            width: max(0, preview.frame.width * width),
                            height: max(0, preview.frame.height * height)
                        )
                        .position(x: preview.frame.midX * width, y: preview.frame.midY * height)
                        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                        .zIndex(preview.isCurrent ? 1000 : 900)
                }
            }
            .frame(maxHeight: .infinity)

                HStack(spacing: 8) {
                    Text(viewModel.operationTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(viewModel.percentageFeedback)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
                .frame(height: 18)
            }
            .padding(10)
        }
        .frame(width: dockWidth, height: dockHeight)
        .shadow(radius: 10)
        .padding(20)
        .fixedSize()
        .animation(luminareAnimation, value: [accentColorController.color1, accentColorController.color2])
        .animation(luminareAnimation, value: viewModel.existingWindows.count)
        .animation(luminareAnimation, value: viewModel.anchors.count)
        .animation(luminareAnimation, value: viewModel.activeTargetID)
        .animation(luminareAnimation, value: viewModel.previewFrames.map(\.frame))
    }
}
