//
//  RadialMenuAction.swift
//  Colonnade
//
//  Created by Kai Azim on 2025-11-11.
//

import Defaults
import Foundation

/// A safe, identifiable wrapper around `ActionType`.
/// This avoids duplicate IDs when the same action or keybind appears more than once in the radial menu.
/// By giving each wrapped value its own custom ID, we keep identities stable across updates and
/// can correctly distinguish duplicate items within the menu.
struct RadialMenuAction: Identifiable, Codable, Hashable, Defaults.Serializable {
    let id: UUID
    var type: ActionType

    /// Used to describe the "link" to an existing keybind, or to contain a WindowAction.
    enum ActionType: Identifiable, Codable, Hashable {
        case custom(WindowAction)
        case keybindReference(UUID)

        var id: UUID {
            switch self {
            case let .custom(windowAction):
                windowAction.id
            case let .keybindReference(id):
                id
            }
        }

        var resolvedAction: WindowAction? {
            switch self {
            case let .custom(windowAction):
                windowAction
            case let .keybindReference(id):
                if let action = Defaults[.keybinds].first(where: { $0.id == id }) {
                    action
                } else {
                    nil
                }
            }
        }

        var isKeybindReference: Bool {
            switch self {
            case .custom:
                false
            case .keybindReference:
                true
            }
        }
    }

    private init(id: UUID, type: ActionType) {
        self.id = id
        self.type = type
    }

    static func custom(_ action: WindowAction) -> Self {
        self.init(
            id: .init(),
            type: .custom(action)
        )
    }

    static func keybindReference(_ id: UUID) -> Self {
        self.init(
            id: .init(),
            type: .keybindReference(id)
        )
    }

    // MARK: Computed Helpers

    var associatedActionId: UUID {
        type.id
    }

    var resolved: WindowAction? {
        type.resolvedAction
    }
}

extension RadialMenuAction {
    /// Clockwise from the top; the last action is the center. All of them keep the full height,
    /// matching the dock.
    static let defaultRadialMenuActions: [RadialMenuAction] = [
        .custom(WindowAction(.maximize)),
        .custom(
            WindowAction(
                .init(localized: "Right Cycle"),
                cycle: [.init(.rightHalf), .init(.rightThird), .init(.rightTwoThirds)]
            )
        ),
        .custom(
            WindowAction(
                .init(localized: "Center Cycle"),
                cycle: [.init(.horizontalCenterThird), .init(.horizontalCenterHalf)]
            )
        ),
        .custom(
            WindowAction(
                .init(localized: "Left Cycle"),
                cycle: [.init(.leftHalf), .init(.leftThird), .init(.leftTwoThirds)]
            )
        ),
        .custom(WindowAction(.maximizeHeight))
    ]

    static var userConfiguredActions: [RadialMenuAction] {
        Defaults[.enableRadialMenuCustomization] ? Defaults[.radialMenuActions] : defaultRadialMenuActions
    }
}
