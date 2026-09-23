//
//  SettingsTab.swift
//  Colonnade
//
//  Created by Kai Azim on 2025-12-05.
//

import AppKit
import Defaults
import Luminare
import SwiftUI

@MainActor
enum SettingsTab: @MainActor LuminareTabItem, CaseIterable {
    var id: String { title }

    case dock

    case keybinds
    case behavior

    case accentColor
    case preview
    case radialMenu

    case advanced
    case excludedApps
    case about

    var icon: some View {
        SettingsTabIconView(tab: self)
    }

    var color: Color {
        switch self {
        case .dock:
            Color(#colorLiteral(red: 0.2549019608, green: 0.4705882353, blue: 0.7843137255, alpha: 1))
        case .keybinds:
            Color(#colorLiteral(red: 0.3882352941, green: 0.2823529412, blue: 0.1960784314, alpha: 1))
        case .behavior:
            Color(#colorLiteral(red: 0.4373228079, green: 0.6609574352, blue: 0.2663080928, alpha: 1))
        case .accentColor:
            Color(#colorLiteral(red: 0.8235294118, green: 0.3529411765, blue: 0.337254902, alpha: 1))
        case .preview:
            Color(#colorLiteral(red: 0.2901960784, green: 0.5647058824, blue: 0.7882352941, alpha: 1))
        case .radialMenu:
            Color(#colorLiteral(red: 0.8078431373, green: 0.6235294118, blue: 0.3254901961, alpha: 1))
        case .advanced:
            Color(#colorLiteral(red: 0.4823529412, green: 0.4745098039, blue: 0.6588235294, alpha: 1))
        case .excludedApps:
            Color(#colorLiteral(red: 0.5882352941, green: 0.3137254902, blue: 0.3019607843, alpha: 1))
        case .about:
            Color(#colorLiteral(red: 0.4509803922, green: 0.4509803922, blue: 0.4509803922, alpha: 1))
        }
    }

    var title: String {
        switch self {
        case .dock: .init(localized: "Settings tab: Dock", defaultValue: "Dock")
        case .keybinds: .init(localized: "Settings tab: Trigger & Shortcuts", defaultValue: "Trigger & Shortcuts")
        case .behavior: .init(localized: "Settings tab: Behavior", defaultValue: "Behavior")
        case .accentColor: .init(localized: "Settings tab: Accent Color", defaultValue: "Accent Color")
        case .preview: .init(localized: "Settings tab: Preview", defaultValue: "Preview")
        case .radialMenu: .init(localized: "Settings tab: Radial Menu", defaultValue: "Radial Menu")
        case .advanced: .init(localized: "Settings tab: Advanced", defaultValue: "Advanced")
        case .excludedApps: .init(localized: "Settings tab: Excluded Apps", defaultValue: "Excluded Apps")
        case .about: .init(localized: "Settings tab: About", defaultValue: "About")
        }
    }

    var image: Image {
        switch self {
        case .dock: Image(systemName: "rectangle.split.3x1.fill")
        case .keybinds: Image(systemName: "keyboard.fill")
        case .behavior: Image(systemName: "gearshape.fill")
        case .accentColor: Image(systemName: "paintbrush.pointed.fill")
        case .preview: Image(systemName: "inset.filled.center.rectangle")
        case .radialMenu: Image(systemName: "circle.dashed")
        case .advanced: Image(systemName: "wrench.adjustable.fill")
        case .excludedApps: Image(systemName: "xmark.octagon.fill")
        case .about: Image(systemName: "info.circle.fill")
        }
    }

    var showIndicator: Bool {
        switch self {
        case .about: ReleaseChecker.shared.isUpdateAvailable
        default: false
        }
    }

    /// What the inspector beside this tab shows.
    var inspector: SettingsInspector {
        switch self {
        case .keybinds, .preview: .screenPreview
        case .radialMenu: .radialMenu
        default: .dockIllustration
        }
    }

    @ViewBuilder func view() -> some View {
        switch self {
        case .dock: DockConfigurationView()
        case .keybinds: KeybindsConfigurationView()
        case .behavior: BehaviorConfigurationView()
        case .accentColor: AccentColorConfigurationView()
        case .preview: PreviewConfigurationView()
        case .radialMenu: RadialMenuConfigurationView()
        case .advanced: AdvancedConfigurationView()
        case .excludedApps: ExcludedAppsConfigurationView()
        case .about: AboutConfigurationView()
        }
    }

    static let dockTabs: [Self] = [.dock]
    static let appearanceTabs: [Self] = [.accentColor, .preview]
    static let appTabs: [Self] = [.advanced, .excludedApps, .about]

    /// The radial menu tab is only listed while the radial menu can actually appear.
    static var controlTabs: [Self] {
        isRadialMenuAvailable ? [.keybinds, .behavior, .radialMenu] : [.keybinds, .behavior]
    }

    /// The radial menu is the fallback for screens where the dock isn't used.
    static var isRadialMenuAvailable: Bool {
        Defaults[.ultrawideDockTriggerMode] != .alwaysOn
    }
}

/// The inspector content beside a settings tab.
enum SettingsInspector {
    /// The looping dock demo.
    case dockIllustration
    /// A wide screen showing the placement preview for full-height columns.
    case screenPreview
    /// The radial menu fallback with its preview.
    case radialMenu
}

struct SettingsTabIconView: View {
    @Environment(\.colorScheme) private var colorScheme

    let tab: SettingsTab

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .foregroundStyle(tab.color.gradient)
            .opacity(0.8)
            .overlay {
                // Only add shine in dark mode; in light mode it makes the icon look fuzzy/blurred.
                if colorScheme == .dark, #available(macOS 26.0, *) {
                    borderShine(in: .rect(cornerRadius: 6))
                }

                tab.image
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 1)
            }
            .frame(width: 22, height: 22)
    }

    /// Mimics macOS Tahoe's icon shine
    private func borderShine(in shape: some InsettableShape) -> some View {
        shape
            .strokeBorder(.white, lineWidth: 1)
            .mask {
                LinearGradient(
                    colors: [
                        .white,
                        .clear,
                        .white.opacity(0.5)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .opacity(0.4)
    }
}
