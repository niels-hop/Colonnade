//
//  AboutConfiguration.swift
//  Colonnade
//
//  Created by Kai Azim on 2024-04-26.
//  Rewritten for Colonnade by Niels Hop on 2026-09-23.
//

import Defaults
import Luminare
import SwiftUI

@MainActor
final class AboutConfigurationModel: ObservableObject {
    @Published var isHoveringOverVersionCopier = false
    @Published var didCompleteCopyToClipboard: Bool = false

    let credits: [CreditItem] = [
        .init(
            "Kai Azim",
            Text("Created Loop, the app Colonnade is built on"),
            url: .init(string: "https://github.com/MrKai77")!,
            systemImage: "person.crop.circle"
        ),
        .init(
            "Kami",
            Text("Loop development"),
            url: .init(string: "https://github.com/senpaihunters")!,
            systemImage: "person.crop.circle"
        ),
        .init(
            "Jace",
            Text("Loop design"),
            url: .init(string: "https://x.com/jacethings")!,
            systemImage: "person.crop.circle"
        ),
        .init(
            String(localized: "Loop contributors"),
            Text("Everyone who made Loop what it is"),
            url: .init(string: "https://github.com/MrKai77/Loop/graphs/contributors")!,
            systemImage: "person.3"
        )
    ]

    func copyVersionToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            "\(Bundle.main.appName) \(VersionDisplay.current.fullDisplay)",
            forType: NSPasteboard.PasteboardType.string
        )

        didCompleteCopyToClipboard = true

        Task { @MainActor in
            try await Task.sleep(for: .seconds(2))
            didCompleteCopyToClipboard = false
        }
    }
}

struct CreditItem: Identifiable, Equatable {
    var id: String { name }

    let name: String
    let description: Text?
    let url: URL
    let systemImage: String

    init(_ name: String, _ description: Text? = nil, url: URL, systemImage: String) {
        self.name = name
        self.description = description
        self.url = url
        self.systemImage = systemImage
    }

    static func == (lhs: CreditItem, rhs: CreditItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct AboutConfigurationView: View {
    @Environment(\.luminareAnimation) private var luminareAnimation
    @Environment(\.luminareAnimationFast) private var luminareAnimationFast
    @Environment(\.openURL) private var openURL

    @StateObject private var model = AboutConfigurationModel()
    @ObservedObject private var releaseChecker = ReleaseChecker.shared

    @Default(.checkForUpdatesAutomatically) private var checkForUpdatesAutomatically

    private var updateButtonText: String {
        switch releaseChecker.state {
        case .idle: String(localized: "Check for Updates")
        case .checking: String(localized: "Checking…")
        case .upToDate: String(localized: "You're up to date")
        case let .available(version, _): String(localized: "Download \(version)")
        case .failed: String(localized: "Couldn't check. Try again")
        }
    }

    var body: some View {
        LuminareForm {
            header
            updateSection
            projectSection
            creditsSection
        }
    }

    private var header: some View {
        LuminareSection {
            HStack {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 60)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Bundle.main.appName)
                        .fontWeight(.medium)

                    Text(
                        model.isHoveringOverVersionCopier
                            ? "Version \(Text(VersionDisplay.current.fullDisplay))"
                            : "Horizontal window management for wide screens"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if model.isHoveringOverVersionCopier {
                    Button {
                        model.copyVersionToClipboard()
                    } label: {
                        Image(systemName: "document.on.clipboard")
                            .padding(4)
                            .contentShape(.rect)
                    }
                    .luminareContentSize(
                        aspectRatio: 1.0,
                        contentMode: .fit,
                        hasFixedHeight: true
                    )
                    .luminareRoundingBehavior(top: true, bottom: true)
                    .luminareSurfaceStyle(.flat)
                    .luminarePopover(
                        isPresented: $model.didCompleteCopyToClipboard,
                        arrowEdge: .bottom,
                        shouldHideAnchor: true
                    ) {
                        Text("Copied!")
                            .padding(6)
                    }
                }
            }
            .padding(.trailing, 8)
            .padding(4)
            .onHover { model.isHoveringOverVersionCopier = $0 }
            .animation(luminareAnimationFast, value: model.isHoveringOverVersionCopier)
        }
    }

    private var updateSection: some View {
        LuminareSection {
            LuminareButtonRow {
                Button {
                    if case let .available(_, url) = releaseChecker.state {
                        openURL(url)
                    } else {
                        Task { await releaseChecker.check() }
                    }
                } label: {
                    Text(updateButtonText)
                        .contentTransition(.numericText())
                        .animation(luminareAnimation, value: updateButtonText)
                }
                .disabled(releaseChecker.state == .checking)
            }
            .luminareRoundingBehavior(top: true)

            LuminareToggle("Check for updates automatically", isOn: $checkForUpdatesAutomatically)
        }
    }

    private var projectSection: some View {
        LuminareSection {
            Text("Colonnade is free and open source. Found a bug or have an idea? Let us know on GitHub.")
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)

            LuminareButtonRow {
                Button("GitHub") {
                    openURL(ReleaseChecker.repositoryURL)
                }

                Button("Report an Issue") {
                    openURL(ReleaseChecker.issuesURL)
                }

                Button("Releases") {
                    openURL(ReleaseChecker.releasesURL)
                }
            }
            .luminareRoundingBehavior(bottom: true)
        }
    }

    private var creditsSection: some View {
        LuminareSection(String(localized: "Built on Loop", comment: "Section header shown in settings")) {
            Text("Colonnade is a fork of Loop by Kai Azim, released under the GNU General Public License v3.0. Its window engine, settings framework and much more come from the Loop project.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .luminareRoundingBehavior(top: true)

            ForEach(model.credits) { credit in
                creditView(credit)
                    .luminareRoundingBehavior(bottom: (credit == model.credits.last) == true)
            }
        }
    }

    private func creditView(_ credit: CreditItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: credit.systemImage)
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading) {
                Text(credit.name)

                if let description = credit.description {
                    description
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                openURL(credit.url)
            } label: {
                Image(systemName: "link")
                    .padding(4)
                    .contentShape(.rect)
            }
            .luminareContentSize(
                aspectRatio: 1.0,
                contentMode: .fit,
                hasFixedHeight: true
            )
            .luminareRoundingBehavior(top: true, bottom: true)
            .luminareSurfaceStyle(.flat)
        }
        .padding(12)
    }
}
