//
//  UltrawideDockView.swift
//  Loop
//

import Luminare
import SwiftUI

struct UltrawideDockView: View {
    @Environment(\.luminareAnimation) private var luminareAnimation
    @ObservedObject private var accentColorController: AccentColorController = .shared
    @ObservedObject private var viewModel: UltrawideDockViewModel

    private let screen: NSScreen?
    private let cornerRadius: CGFloat = 10

    private var dockWidth: CGFloat { UltrawideDockMetrics.dockWidth(for: screen) }

    init(viewModel: UltrawideDockViewModel, screen: NSScreen?) {
        self.viewModel = viewModel
        self.screen = screen
    }

    var body: some View {
        ZStack {
            dockBackground

            VStack(spacing: UltrawideDockMetrics.sectionSpacing) {
                GeometryReader { geometry in
                    screenMap(size: geometry.size)
                }
                .frame(height: UltrawideDockMetrics.mapHeight)

                freeLane

                VStack(spacing: 2) {
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
                    Text(viewModel.interactionHint)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
                .frame(height: UltrawideDockMetrics.footerHeight)
            }
            .padding(UltrawideDockMetrics.contentPadding)
        }
        .frame(width: dockWidth, height: UltrawideDockMetrics.dockHeight)
        .shadow(radius: 10)
        .padding(UltrawideDockMetrics.shadowPadding)
        .fixedSize()
        .animation(luminareAnimation, value: [accentColorController.color1, accentColorController.color2])
        .animation(luminareAnimation, value: viewModel.slots.count)
        .animation(luminareAnimation, value: viewModel.activeTargetID)
        .animation(luminareAnimation, value: viewModel.isFreeformActive)
        .animation(luminareAnimation, value: viewModel.previewFrames.map(\.frame))
    }

    /// The lane the pointer drops into for a free placement. It is always visible, because a mode
    /// reachable only by moving the mouse somewhere is a mode nobody finds by accident.
    private var freeLane: some View {
        let active = viewModel.isFreeformActive
        return ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(active ? accentColorController.color1.opacity(0.22) : Color.black.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(
                            active ? accentColorController.color1 : Color.white.opacity(0.16),
                            style: StrokeStyle(lineWidth: active ? 2 : 1, dash: active ? [] : [4, 3])
                        )
                )

            Label(
                active ? "Free placement · nothing else moves" : "Move down for free placement",
                systemImage: active ? "rectangle.on.rectangle" : "arrow.down"
            )
            .font(.system(size: 10, weight: active ? .semibold : .medium))
            .foregroundStyle(active ? .primary : .secondary)
        }
        .frame(height: UltrawideDockMetrics.freeLaneHeight)
    }

    @ViewBuilder
    private var dockBackground: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    private func screenMap(size: CGSize) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.black.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.16)))

            ForEach(viewModel.slots.sorted(by: { $0.zIndex > $1.zIndex })) { slot in
                slotView(slot, mapSize: size)
            }

            if viewModel.activeTargetID == "insert", let x = viewModel.activeTargetPosition {
                insertionMarker(x: x, mapSize: size)
            }

            ForEach(viewModel.dividers) { divider in
                dividerView(divider, mapSize: size)
            }

            ForEach(viewModel.previewFrames) { preview in
                previewView(preview, mapSize: size)
            }
        }
    }

    private func slotView(
        _ slot: UltrawideDockViewModel.SlotFrame,
        mapSize: CGSize
    ) -> some View {
        let stackTarget = viewModel.activeTargetID == "stack:\(slot.id.rawValue)"
        let currentTarget = viewModel.activeTargetID == "current:\(slot.id.rawValue)"
        let targetColor = stackTarget ? accentColorController.color1 : Color.white.opacity(0.32)
        // An excluded window is real but outside the row: shown so its space never looks free,
        // drawn flatter so it reads as "not part of this layout".
        let fill = slot.isExcluded
            ? Color.gray.opacity(0.22)
            : Color.gray.opacity(slot.containsCurrent ? 0.52 : 0.4)
        let frameSize = CGSize(
            width: max(0, slot.frame.width * mapSize.width),
            height: max(0, slot.frame.height * mapSize.height)
        )

        return ZStack {
            if slot.stackCount > 1 {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.gray.opacity(0.25))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.2)))
                    .frame(width: max(0, frameSize.width - 8), height: max(0, frameSize.height - 8))
                    .offset(x: 5, y: -5)
            }

            RoundedRectangle(cornerRadius: 5)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(
                            targetColor,
                            style: StrokeStyle(
                                lineWidth: stackTarget || currentTarget ? 2.5 : 1,
                                dash: slot.isExcluded ? [3, 3] : []
                            )
                        )
                )
                .shadow(color: Color.black.opacity(slot.isExcluded ? 0 : 0.2), radius: 2, x: 0, y: 1)

            if stackTarget {
                VStack(spacing: 3) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 20, weight: .semibold))
                    Text("STACK")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Color.white)
            } else if slot.stackCount > 1 {
                Label("\(slot.stackCount)", systemImage: "rectangle.stack.fill")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.38), in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .frame(width: frameSize.width, height: frameSize.height)
        .position(x: slot.frame.midX * mapSize.width, y: slot.frame.midY * mapSize.height)
        .zIndex(Double(-slot.zIndex))
    }

    private func dividerView(
        _ divider: UltrawideDockViewModel.Divider,
        mapSize: CGSize
    ) -> some View {
        let active = viewModel.activeTargetID == "divider:\(divider.afterID.rawValue)"
        return ZStack {
            Capsule()
                .fill(active ? accentColorController.color1 : Color.white.opacity(0.5))
                .frame(width: active ? 8 : 5, height: active ? 38 : 24)
            if active {
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(.white)
            }
        }
        .shadow(color: Color.black.opacity(0.25), radius: 2)
        .position(
            x: (active ? viewModel.activeTargetPosition ?? divider.x : divider.x) * mapSize.width,
            y: mapSize.height / 2
        )
        .zIndex(active ? 1200 : 600)
    }

    private func insertionMarker(x: CGFloat, mapSize: CGSize) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 8))
            Capsule().frame(width: 3, height: max(10, mapSize.height - 15))
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 8))
        }
        .foregroundStyle(accentColorController.color1)
        .position(x: x * mapSize.width, y: mapSize.height / 2)
        .zIndex(1100)
    }

    private func previewView(
        _ preview: UltrawideDockViewModel.PreviewFrame,
        mapSize: CGSize
    ) -> some View {
        // A floating preview is inset and lifted so it reads as lying on top of the row. Inside a
        // free gap it would otherwise be pixel-identical to an insertion, which is the one thing it
        // is not: nothing around it moves.
        let verticalInset: CGFloat = preview.isFloating ? 9 : 0
        return RoundedRectangle(cornerRadius: preview.isFloating ? 7 : 5)
            .fill(
                LinearGradient(
                    colors: [accentColorController.color1, accentColorController.color2],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .opacity(preview.isCurrent ? 0.88 : 0.5)
            .overlay(
                RoundedRectangle(cornerRadius: preview.isFloating ? 7 : 5)
                    .stroke(Color.white.opacity(0.68), lineWidth: preview.isCurrent ? 2 : 1)
            )
            .overlay {
                if preview.memberCount > 1 {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                } else if preview.isCurrent,
                          let fraction = Self.commonFractionLabel(for: preview.frame.width) {
                    Text(fraction)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.22), in: Capsule())
                }
            }
            .frame(
                width: max(0, preview.frame.width * mapSize.width),
                height: max(0, preview.frame.height * mapSize.height - verticalInset * 2)
            )
            .position(x: preview.frame.midX * mapSize.width, y: preview.frame.midY * mapSize.height)
            .shadow(
                color: Color.black.opacity(preview.isFloating ? 0.5 : 0.3),
                radius: preview.isFloating ? 9 : 4,
                x: 0,
                y: preview.isFloating ? 4 : 2
            )
            .zIndex(preview.isFloating ? 1300 : (preview.isCurrent ? 1000 : 900))
    }

    private static func commonFractionLabel(for width: CGFloat) -> String? {
        let fractions: [(width: CGFloat, label: String)] = [
            (0.5, "1/2"),
            (1 / 3, "1/3"),
            (0.25, "1/4")
        ]
        return fractions.first { abs($0.width - width) <= 0.005 }?.label
    }
}
