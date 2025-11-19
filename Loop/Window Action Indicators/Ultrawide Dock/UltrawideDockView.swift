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
    private let baseDockHeight: CGFloat = 150
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

            // Screen representation
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
                        .fill(Color.gray.opacity(opacity))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
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

                // Active Preview Window
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(
                                colors: [
                                    accentColorController.color1,
                                    accentColorController.color2
                                ]
                            ),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.white.opacity(0.5), lineWidth: 2)
                    )
                    .frame(
                        width: max(0, viewModel.previewFrame.width * width),
                        height: max(0, viewModel.previewFrame.height * height)
                    )
                    .position(
                        x: viewModel.previewFrame.midX * width,
                        y: viewModel.previewFrame.midY * height
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                    .zIndex(1000) // Always on top
            }
            .padding(10) // Inner padding
        }
        .frame(width: dockWidth, height: dockHeight)
        .shadow(radius: 10)
        .padding(20)
        .fixedSize()
        .animation(luminareAnimation, value: [accentColorController.color1, accentColorController.color2])
        .animation(luminareAnimation, value: viewModel.existingWindows.count)
    }
}
