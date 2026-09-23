//
//  WindowAction+Defaults.swift
//  Colonnade
//
//  Created by Kai Azim on 2025-11-11.
//

import Defaults
import Foundation

// MARK: Keybinds

extension WindowAction {
    /// Colonnade only divides the screen horizontally: every default keeps the full height.
    static let defaultKeybinds: [WindowAction] = [
        WindowAction(.maximize, keybind: [.kVK_Space]),
        WindowAction(
            .init(localized: "Center Cycle"),
            cycle: [.init(.horizontalCenterThird), .init(.horizontalCenterHalf)],
            keybind: [.kVK_Return]
        ),
        WindowAction(
            .init(localized: "Right Cycle"),
            cycle: [.init(.rightHalf), .init(.rightThird), .init(.rightTwoThirds)],
            keybind: [.kVK_RightArrow]
        ),
        WindowAction(
            .init(localized: "Left Cycle"),
            cycle: [.init(.leftHalf), .init(.leftThird), .init(.leftTwoThirds)],
            keybind: [.kVK_LeftArrow]
        )
    ]
}
