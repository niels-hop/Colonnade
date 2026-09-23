//
//  ReleaseChecker.swift
//  Colonnade
//
//  Created by Niels Hop on 2026-09-23.
//

import AppKit
import Defaults
import Scribe

/// Checks GitHub for a newer Colonnade release and points the user to its download page.
///
/// Colonnade is distributed as a self-signed build, so it deliberately does not replace itself in place: a
/// swapped binary would lose its Accessibility permission anyway. Instead it tells the user a release is
/// available and opens the release page, where they download it like the first install.
@Loggable
@MainActor
final class ReleaseChecker: ObservableObject {
    static let shared = ReleaseChecker()

    /// GitHub `owner/name` of the repository that publishes releases.
    static let repository = "niels-hop/Colonnade"
    static let repositoryURL = URL(string: "https://github.com/\(repository)")!
    static let releasesURL = URL(string: "https://github.com/\(repository)/releases")!
    static let issuesURL = URL(string: "https://github.com/\(repository)/issues")!
    private static let latestReleaseAPI = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!

    /// How often the background check runs while automatic checks are enabled.
    private static let automaticInterval: Duration = .seconds(24 * 60 * 60)

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case failed
    }

    @Published private(set) var state: State = .idle

    var isUpdateAvailable: Bool {
        if case .available = state { return true }
        return false
    }

    private var automaticCheckTask: Task<(), Never>?
    private var settingObserver: Task<(), Never>?

    private init() {}

    /// Starts the daily background check, following the user's "check automatically" setting.
    func start() {
        settingObserver?.cancel()
        settingObserver = Task { [weak self] in
            for await enabled in Defaults.updates(.checkForUpdatesAutomatically) {
                guard let self, !Task.isCancelled else { return }
                automaticCheckTask?.cancel()
                automaticCheckTask = enabled ? makeAutomaticCheckTask() : nil
            }
        }
    }

    func stop() {
        settingObserver?.cancel()
        automaticCheckTask?.cancel()
        settingObserver = nil
        automaticCheckTask = nil
    }

    /// Fetches the latest release and updates `state`.
    func check() async {
        state = .checking

        do {
            var request = URLRequest(url: Self.latestReleaseAPI)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Colonnade/\(Bundle.main.appVersion ?? "0")", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 20

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                // 404 simply means nothing has been published yet.
                state = .upToDate
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let current = Bundle.main.appVersion ?? "0"

            if Self.isVersion(release.tagName, newerThan: current) {
                state = .available(version: Self.normalized(release.tagName), url: release.htmlURL)
                log.info("Release \(release.tagName) is available (running \(current))")
            } else {
                state = .upToDate
            }
        } catch {
            log.error("Release check failed: \(error.localizedDescription)")
            state = .failed
        }
    }

    /// Runs a check on behalf of the user and always reports the outcome.
    func checkInteractively() async {
        await check()

        switch state {
        case let .available(version, url):
            let alert = NSAlert()
            alert.messageText = String(localized: "Colonnade \(version) is available")
            alert.informativeText = String(localized: "Download the new version from GitHub and replace the app in your Applications folder.")
            alert.addButton(withTitle: String(localized: "Open Download Page"))
            alert.addButton(withTitle: String(localized: "Later"))
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(url)
            }
        case .failed:
            let alert = NSAlert()
            alert.messageText = String(localized: "Couldn't check for updates")
            alert.informativeText = String(localized: "Check your internet connection and try again.")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        default:
            let alert = NSAlert()
            alert.messageText = String(localized: "You're up to date")
            alert.informativeText = String(localized: "Colonnade \(Bundle.main.appVersion ?? "") is the latest version.")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private func makeAutomaticCheckTask() -> Task<(), Never> {
        Task { [weak self] in
            // Give the app time to settle before touching the network.
            try? await Task.sleep(for: .seconds(10))
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: Self.automaticInterval)
            }
        }
    }

    // MARK: Version comparison

    /// Strips a leading "v" and any pre-release/build suffix: "v1.2.3-beta" -> "1.2.3".
    nonisolated static func normalized(_ version: String) -> String {
        var trimmed = version.trimmingCharacters(in: .whitespaces)
        if trimmed.first == "v" || trimmed.first == "V" { trimmed.removeFirst() }
        return String(trimmed.prefix { $0.isNumber || $0 == "." })
    }

    /// Compares dotted numeric versions component by component; missing components count as 0.
    nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let lhs = normalized(candidate).split(separator: ".").map { Int($0) ?? 0 }
        let rhs = normalized(current).split(separator: ".").map { Int($0) ?? 0 }
        guard !lhs.isEmpty else { return false }

        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
