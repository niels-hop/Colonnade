//
//  RadialMenuConfiguration.swift
//  Loop
//
//  Created by Kai Azim on 2024-04-19.
//

import Defaults
import Luminare
import SwiftUI

struct RadialMenuConfigurationView: View {
    @Default(.radialMenuVisibility) private var radialMenuVisibility
    @Default(.radialMenuCornerRadius) private var radialMenuCornerRadius
    @Default(.radialMenuThickness) private var radialMenuThickness
    @Default(.ultrawideDockTriggerMode) private var ultrawideDockTriggerMode

    var body: some View {
        LuminareSection {
            LuminareToggle(isOn: $radialMenuVisibility) {
                Text("Radial menu")
                    .padding(.trailing, 4)
                    .luminarePopover(
                        attachedTo: .topTrailing,
                        hidden: ultrawideDockTriggerMode == .never
                    ) {
                        Text("The Ultrawide Dock replaces the radial menu when it's active.\nAdjust its behavior under Behavior → Ultrawide Dock.")
                            .padding(6)
                    }
            }

            if radialMenuVisibility {
                LuminareSlider(
                    "Corner radius",
                    value: $radialMenuCornerRadius.doubleBinding,
                    in: 30...50,
                    format: .number.precision(.fractionLength(0...0)),
                    clampsUpper: true,
                    clampsLower: true,
                    suffix: Text("px", comment: "Unit symbol: pixels")
                )
                .onChange(of: radialMenuCornerRadius) { _ in
                    if radialMenuCornerRadius - 1 < radialMenuThickness {
                        radialMenuThickness = radialMenuCornerRadius - 1
                    }
                }

                LuminareSlider(
                    "Thickness",
                    value: $radialMenuThickness.doubleBinding,
                    in: 10...35,
                    format: .number.precision(.fractionLength(0...0)),
                    clampsUpper: true,
                    clampsLower: true,
                    suffix: Text("px", comment: "Unit symbol: pixels")
                )
                .onChange(of: radialMenuThickness) { _ in
                    if radialMenuThickness + 1 > radialMenuCornerRadius {
                        radialMenuCornerRadius = radialMenuThickness + 1
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: radialMenuVisibility)
    }
}
