//
//  LayoutsConfigurationView.swift
//  Colonnade
//
//  Created by Niels Hop on 2026-09-23.
//

import Defaults
import Luminare
import SwiftUI

/// Saved layouts: named snapshots of every window's column, restorable from the menu bar or automatically.
struct LayoutsConfigurationView: View {
    @Environment(\.luminareAnimation) private var luminareAnimation

    @Default(.savedLayoutWorkName) private var savedLayoutWorkName
    @Default(.savedLayoutFocusName) private var savedLayoutFocusName
    @Default(.savedLayoutMacBookName) private var savedLayoutMacBookName
    @Default(.defaultSavedLayoutSlot) private var defaultSavedLayoutSlot
    @Default(.restoreSavedLayoutOnLaunch) private var restoreSavedLayoutOnLaunch
    @Default(.restoreSavedLayoutOnWake) private var restoreSavedLayoutOnWake
    @Default(.restoreSavedLayoutOnDisplayChange) private var restoreSavedLayoutOnDisplayChange
    @Default(.restoreSavedLayoutOnSpaceChange) private var restoreSavedLayoutOnSpaceChange

    var body: some View {
        LuminareForm {
            slotsSection
            restoreSection
        }
        .animation(luminareAnimation, value: defaultSavedLayoutSlot)
    }

    private var slotsSection: some View {
        LuminareSection(String(localized: "Slots", comment: "Section header shown in settings")) {
            Text("Save the current arrangement of your windows to a slot from the menu bar, and restore it whenever you need it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            LuminareTextField(
                "Work slot",
                text: Binding<String?>(get: { savedLayoutWorkName }, set: { savedLayoutWorkName = $0 ?? "" })
            )
            LuminareTextField(
                "Focus slot",
                text: Binding<String?>(get: { savedLayoutFocusName }, set: { savedLayoutFocusName = $0 ?? "" })
            )
            LuminareTextField(
                "MacBook slot",
                text: Binding<String?>(get: { savedLayoutMacBookName }, set: { savedLayoutMacBookName = $0 ?? "" })
            )

            LuminareButtonRow {
                ForEach(SavedLayoutSlot.fixedSlots) { slot in
                    Button("Save \(slot.displayName)") {
                        Task { await SavedLayoutManager.shared.saveWithFeedback(slot) }
                    }
                }
            }
            .luminareRoundingBehavior(bottom: true)
        }
    }

    private var restoreSection: some View {
        LuminareSection(String(localized: "Automatic restore", comment: "Section header shown in settings")) {
            LuminareSliderPicker(
                SavedLayoutSlot.fixedSlots,
                selection: $defaultSavedLayoutSlot
            ) { slot in
                Text(slot.displayName)
            } label: {
                Text("Default layout")
            }

            LuminareToggle("Restore on launch or login", isOn: $restoreSavedLayoutOnLaunch)
            LuminareToggle("Restore after wake", isOn: $restoreSavedLayoutOnWake)
            LuminareToggle("Restore when displays change", isOn: $restoreSavedLayoutOnDisplayChange)
            LuminareToggle("Restore when Spaces change", isOn: $restoreSavedLayoutOnSpaceChange)
        }
    }
}
