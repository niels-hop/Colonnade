//
//  DockIllustrationView.swift
//  Colonnade
//
//  Created by Niels Hop on 2026-09-23.
//

import Luminare
import SwiftUI

/// A looping, schematic demo of the dock for the settings inspector: a wide screen divided into
/// full-height columns, with the highlighted target stepping through the ways a window can be placed.
struct DockIllustrationView: View {
    @Environment(\.luminareAnimation) private var animation
    @ObservedObject private var accentColorController: AccentColorController = .shared

    private struct Step {
        let target: ClosedRange<CGFloat>
        let caption: LocalizedStringKey
    }

    /// Windows already on screen, as horizontal fractions. Everything is full height.
    private let existingColumns: [ClosedRange<CGFloat>] = [0 ... 0.28, 0.28 ... 0.62]

    private let steps: [Step] = [
        .init(target: 0.62 ... 1, caption: "Fill the free space"),
        .init(target: 0.62 ... 0.81, caption: "Click to change the width"),
        .init(target: 0.28 ... 0.62, caption: "Stack on an existing window"),
        .init(target: 0.2 ... 0.4, caption: "Insert beside a window"),
        .init(target: 0.35 ... 0.65, caption: "Move down to place freely")
    ]

    @State private var stepIndex = 0

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            screen
                .aspectRatio(32 / 9, contentMode: .fit)
                .padding(.horizontal, 12)

            Text(steps[stepIndex].caption)
                .font(.title3)
                .fontWeight(.medium)
                .contentTransition(.opacity)
                .id(stepIndex)
                .transition(.opacity)

            Text("Hold the trigger, move the mouse, release.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .animation(animation, value: stepIndex)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.8))
                stepIndex = (stepIndex + 1) % steps.count
            }
        }
    }

    private var screen: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let inset: CGFloat = 6

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.black.opacity(0.35))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    }

                ForEach(Array(existingColumns.enumerated()), id: \.offset) { _, column in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(0.12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                        }
                        .frame(
                            width: max(0, (column.upperBound - column.lowerBound) * (size.width - inset * 2) - 4),
                            height: size.height - inset * 2
                        )
                        .offset(x: inset + column.lowerBound * (size.width - inset * 2) + 2, y: inset)
                }

                let target = steps[stepIndex].target
                RoundedRectangle(cornerRadius: 8)
                    .fill(accentColorController.color1.opacity(0.35))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(accentColorController.color1, lineWidth: 2)
                    }
                    .frame(
                        width: max(0, (target.upperBound - target.lowerBound) * (size.width - inset * 2) - 4),
                        height: size.height - inset * 2
                    )
                    .offset(x: inset + target.lowerBound * (size.width - inset * 2) + 2, y: inset)
            }
        }
    }
}
