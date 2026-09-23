//
//  ColonnadeApp.swift
//  Colonnade
//
//  Created by Kai Azim on 2023-01-23.
//

import Defaults
import SwiftUI

@main
struct ColonnadeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var releaseChecker = ReleaseChecker.shared
    @Default(.hideMenuBarIcon) var hideMenuBarIcon
    @Default(.ultrawideDockTriggerMode) var ultrawideDockTriggerMode

    init() {
        // Must run before any setting is read, so upgrades from the pre-rename build keep their data.
        LegacyDataMigration.runIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra(Bundle.main.appName, image: "menubarIcon", isInserted: Binding.constant(!hideMenuBarIcon)) {
            Picker(selection: $ultrawideDockTriggerMode) {
                ForEach(UltrawideDockTriggerMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            } label: {
                Label("Use the Dock", systemImage: "rectangle.split.3x1")
            }

            Menu {
                ForEach(SavedLayoutSlot.fixedSlots) { slot in
                    Menu(slot.displayName) {
                        Button("Restore") {
                            Task { await SavedLayoutManager.shared.restoreWithFeedback(slot) }
                        }

                        Button("Save Current Layout") {
                            Task { await SavedLayoutManager.shared.saveWithFeedback(slot) }
                        }
                    }
                }
            } label: {
                Label("Layouts", systemImage: "rectangle.3.group")
            }

            Divider()

            Button("Settings…") {
                SettingsWindowManager.shared.show()
            }
            .keyboardShortcut(",", modifiers: .command)

            Button {
                Task { await releaseChecker.checkInteractively() }
            } label: {
                if case let .available(version, _) = releaseChecker.state {
                    Text("Download \(version)…", comment: "Menu bar item shown when a new release is available")
                } else {
                    Text("Check for Updates…", comment: "Button to check for updates in menubar dropdown menu")
                }
            }

            Divider()

            Text(
                "Version \(VersionDisplay.current.fullDisplay)",
                comment: "Format: Version [version, e.g. 1.3.0] ([build number, e.g. 1500])"
            )
            .font(.system(size: 11, weight: .semibold))

            Button("Quit \(Bundle.main.appName)") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .menuBarExtraStyle(.menu)
    }
}
