//
//  LoopApp.swift
//  Loop
//
//  Created by Kai Azim on 2023-01-23.
//

import Defaults
import SwiftUI

@main
struct LoopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var updater = Updater.shared
    @Default(.hideMenuBarIcon) var hideMenuBarIcon
    @Default(.ultrawideDockTriggerMode) var ultrawideDockTriggerMode

    var body: some Scene {
        MenuBarExtra(Bundle.main.appName, image: "menubarIcon", isInserted: Binding.constant(!hideMenuBarIcon)) {
            Picker(selection: $ultrawideDockTriggerMode) {
                ForEach(UltrawideDockTriggerMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            } label: {
                HStack {
                    Image(systemName: "rectangle.split.3x1")
                    Text("Ultrawide Dock")
                }
            }

            Divider()

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

            Button {
                if let url = URL(string: "https://github.com/sponsors/MrKai77") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Donate", systemImage: "heart")
            }

            Divider()

            Text(
                "Version \(VersionDisplay.current.fullDisplay)",
                comment: "Format: Version [version, e.g. 1.3.0] ([build number, e.g. 1500])"
            )
            .font(.system(size: 11, weight: .semibold))

            Button {
                Task {
                    await updater.fetchLatestInfo()
                    await updater.showUpdateWindowIfEligible()
                }
            } label: {
                if updater.updateState == .available {
                    Text(
                        "Update…",
                        comment: "Button to update app in menubar dropdown menu"
                    )
                } else {
                    Text(
                        "Check for Updates…",
                        comment: "Button to check for updates in menubar dropdown menu"
                    )
                }
            }

            Button("Settings…") {
                SettingsWindowManager.shared.show()
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit \(Bundle.main.appName)") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .menuBarExtraStyle(.menu)
    }
}
