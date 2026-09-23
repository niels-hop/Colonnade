//
//  DockConfigurationView.swift
//  Colonnade
//
//  Created by Niels Hop on 2026-09-23.
//

import Defaults
import Luminare
import SwiftUI

/// The home tab of the settings window: how to use the dock, when it appears and how it feels.
struct DockConfigurationView: View {
    @Environment(\.luminareAnimation) private var luminareAnimation
    @EnvironmentObject private var windowModel: SettingsWindowManager

    @Default(.triggerKey) private var triggerKey
    @Default(.ultrawideDockTriggerMode) private var triggerMode
    @Default(.ultrawideDockAutomaticAspectRatio) private var automaticAspectRatio
    @Default(.ultrawideDockBaseWidth) private var baseWidth
    @Default(.ultrawideDockPointerSensitivity) private var pointerSensitivity
    @Default(.ultrawideDockClickCycle) private var clickCycle

    var body: some View {
        LuminareForm {
            howItWorksSection
            activationSection
            feelSection
        }
        .animation(luminareAnimation, value: triggerMode)
    }

    // MARK: How it works

    private var howItWorksSection: some View {
        LuminareSection(String(localized: "How it works", comment: "Section header shown in settings")) {
            VStack(alignment: .leading, spacing: 10) {
                instruction(
                    systemImage: "keyboard",
                    title: Text("Hold \(Text(triggerDescription).fontWeight(.semibold))"),
                    detail: Text("The dock appears as a miniature of your screen.")
                )
                instruction(
                    systemImage: "arrow.left.and.right",
                    title: Text("Move the mouse sideways"),
                    detail: Text("Pick a column, a gap or a window to stack on. Windows always fill the full height.")
                )
                instruction(
                    systemImage: "cursorarrow.click",
                    title: Text("Click or scroll to change the width"),
                    detail: Text("Drag a divider to resize neighbours. Move down to place freely.")
                )
                instruction(
                    systemImage: "hand.raised",
                    title: Text("Release to place the window"),
                    detail: Text("Press Escape to cancel.")
                )
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)

            LuminareButton("Trigger key", "Change…") {
                windowModel.currentTab = .keybinds
            }
        }
    }

    private func instruction(systemImage: String, title: Text, detail: Text) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                title
                detail
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// e.g. "⌃ ⌥" for the modifiers, or the key names for anything else.
    private var triggerDescription: String {
        // macOS lists modifiers as ⌃ ⌥ ⇧ ⌘; anything else follows them.
        let order: [CGKeyCode] = [.kVK_Function, .kVK_Control, .kVK_Option, .kVK_Shift, .kVK_Command]
        let names = triggerKey
            .sorted { (order.firstIndex(of: $0.baseModifier) ?? order.count) < (order.firstIndex(of: $1.baseModifier) ?? order.count) }
            .compactMap { key -> String? in
                switch key.baseModifier {
                case .kVK_Function: "fn"
                case .kVK_Shift: "⇧"
                case .kVK_Command: "⌘"
                case .kVK_Control: "⌃"
                case .kVK_Option: "⌥"
                default: key.humanReadable?.uppercased()
                }
            }
        return names.isEmpty
            ? String(localized: "the trigger key")
            : names.joined(separator: " ")
    }

    // MARK: Activation

    private var activationSection: some View {
        LuminareSection(String(localized: "When to use the dock", comment: "Section header shown in settings")) {
            LuminareSliderPicker(
                UltrawideDockTriggerMode.allCases,
                selection: $triggerMode
            ) { item in
                Text(item.label)
            } label: {
                Text("Use the dock")
            }

            if triggerMode == .automatic {
                LuminareSlider(
                    "Wide from aspect ratio",
                    value: $automaticAspectRatio,
                    in: 1.4...3.6,
                    step: 0.1,
                    format: .number.precision(.fractionLength(1...1)),
                    clampsUpper: true,
                    clampsLower: true,
                    suffix: Text(":1", comment: "Suffix for an aspect ratio, e.g. 2.0:1")
                )
            }

            Text(triggerMode.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
    }

    // MARK: Feel

    private var feelSection: some View {
        LuminareSection(String(localized: "Feel", comment: "Section header shown in settings")) {
            LuminareSlider(
                "Dock size",
                value: $baseWidth,
                in: 450...900,
                step: 10,
                format: .number.precision(.fractionLength(0...0)),
                clampsUpper: true,
                clampsLower: true,
                suffix: Text("pt", comment: "Unit symbol: points")
            )

            LuminareSlider(
                "Pointer sensitivity",
                value: $pointerSensitivity,
                in: 0.5...2.5,
                step: 0.1,
                format: .number.precision(.fractionLength(1...1)),
                clampsUpper: true,
                clampsLower: true,
                suffix: Text("×", comment: "Suffix for a multiplier, e.g. 1.5×")
            )

            LuminareSliderPicker(
                UltrawideDockClickCycle.allCases,
                selection: $clickCycle
            ) { item in
                Text(item.label)
                    .monospaced()
            } label: {
                Text("Click cycles widths")
            }

            LuminareButton("Restore defaults", "Reset") {
                Defaults.reset(
                    .ultrawideDockAutomaticAspectRatio,
                    .ultrawideDockBaseWidth,
                    .ultrawideDockPointerSensitivity,
                    .ultrawideDockClickCycle
                )
            }
        }
    }
}
