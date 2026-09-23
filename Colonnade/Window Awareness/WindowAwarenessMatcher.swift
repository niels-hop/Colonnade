//
//  WindowAwarenessMatcher.swift
//  Colonnade
//
//  Conservative pure matching and reconciliation for persisted window snapshots.
//

import Foundation

// MARK: - WindowAwareness

/// The small seam used by future startup, wake, display, and Space coordinators.
enum WindowAwareness {
    /// Reconciles one persisted display snapshot with current pure observations.
    ///
    /// Ambiguous candidates never appear in `matched`. A missing window does not make
    /// other high-confidence matches unsafe, while a missing or ambiguous display does.
    static func reconcile(
        _ snapshot: WindowAwarenessSnapshot,
        displays: [DisplayIdentity],
        windows: [ObservedWindow]
    ) -> WindowAwarenessReconciliation {
        WindowAwarenessReconciliation(
            snapshotID: snapshot.id,
            display: DisplayMatcher.match(snapshot.display, against: displays),
            windows: WindowMatcher.match(snapshot.windows, against: windows)
        )
    }
}

// MARK: - WindowAwarenessReconciliation

struct WindowAwarenessReconciliation: Equatable, Sendable {
    let snapshotID: UUID
    let display: DisplayMatchResult
    let windows: WindowMatchResult

    /// Safe matches may be applied only when the display itself is unambiguous.
    var automaticallyRestorableWindows: [MatchedWindow] {
        guard case .matched = display else { return [] }
        return windows.matched
    }
}

// MARK: - Display matching

enum DisplayMatchBasis: Equatable, Sendable {
    case uuid
    case configurationFingerprint
}

struct MatchedDisplay: Equatable, Sendable {
    let display: DisplayIdentity
    let basis: DisplayMatchBasis
}

enum DisplayMatchResult: Equatable, Sendable {
    case matched(MatchedDisplay)
    case missing
    case ambiguous([DisplayIdentity])
}

enum DisplayMatcher {
    static func match(_ persisted: DisplayIdentity, against observed: [DisplayIdentity]) -> DisplayMatchResult {
        if let persistedUUID = persisted.uuid {
            let uuidMatches = observed.filter { $0.uuid == persistedUUID }
            if uuidMatches.count == 1, let match = uuidMatches.first {
                return .matched(MatchedDisplay(display: match, basis: .uuid))
            }
            if uuidMatches.count > 1 {
                return .ambiguous(uuidMatches)
            }

            // A different known UUID is authoritative. Fingerprint fallback is only
            // permitted when the current adapter could not obtain a UUID.
            let fallbackMatches = observed.filter {
                $0.uuid == nil && $0.fingerprint == persisted.fingerprint
            }
            return fallbackResult(fallbackMatches)
        }

        return fallbackResult(observed.filter { $0.fingerprint == persisted.fingerprint })
    }

    private static func fallbackResult(_ matches: [DisplayIdentity]) -> DisplayMatchResult {
        if matches.count == 1, let match = matches.first {
            return .matched(MatchedDisplay(display: match, basis: .configurationFingerprint))
        }
        return matches.isEmpty ? .missing : .ambiguous(matches)
    }
}

// MARK: - Window matching

struct MatchedWindow: Equatable, Sendable {
    let tile: ManagedWindowSnapshot
    let runtimeToken: RuntimeWindowToken
    let score: Int
}

struct AmbiguousWindowMatch: Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        case scoresTooClose
        case runtimeWindowClaimedByMultipleTiles
    }

    let tile: ManagedWindowSnapshot
    let candidateTokens: [RuntimeWindowToken]
    let reason: Reason
}

struct WindowMatchResult: Equatable, Sendable {
    let matched: [MatchedWindow]
    let missing: [ManagedWindowSnapshot]
    let ambiguous: [AmbiguousWindowMatch]
}

/// A deliberately conservative scored matcher. It accepts an automatic match only
/// when the score is high enough, a strong hash or precise fallback is present, and
/// the lead over the next candidate is decisive.
enum WindowMatcher {
    private static let minimumScore = 65
    private static let minimumScoreMargin = 12

    static func match(
        _ persisted: [ManagedWindowSnapshot],
        against observed: [ObservedWindow]
    ) -> WindowMatchResult {
        var tentativeMatches: [MatchedWindow] = []
        var missing: [ManagedWindowSnapshot] = []
        var ambiguous: [AmbiguousWindowMatch] = []

        for tile in persisted.sorted(by: { $0.relativeOrder < $1.relativeOrder }) {
            let ranked = observed.compactMap { candidate -> ScoredCandidate? in
                guard let result = score(tile.identity, against: candidate.identity), result.isEligible else {
                    return nil
                }
                return ScoredCandidate(token: candidate.token, score: result.value)
            }.sorted {
                if $0.score == $1.score {
                    return $0.token.rawValue.uuidString < $1.token.rawValue.uuidString
                }
                return $0.score > $1.score
            }

            guard let best = ranked.first, best.score >= minimumScore else {
                missing.append(tile)
                continue
            }

            if ranked.dropFirst().first.map({ best.score - $0.score < minimumScoreMargin }) == true {
                let closeCandidates = ranked
                    .prefix { best.score - $0.score < minimumScoreMargin }
                    .map(\.token)
                ambiguous.append(
                    AmbiguousWindowMatch(
                        tile: tile,
                        candidateTokens: closeCandidates,
                        reason: .scoresTooClose
                    )
                )
                continue
            }

            tentativeMatches.append(MatchedWindow(tile: tile, runtimeToken: best.token, score: best.score))
        }

        let matchesByToken = Dictionary(grouping: tentativeMatches, by: \.runtimeToken)
        let multiplyClaimedTokens = Set(matchesByToken.compactMap { token, matches in
            matches.count > 1 ? token : nil
        })

        let safeMatches = tentativeMatches.filter { !multiplyClaimedTokens.contains($0.runtimeToken) }
        for token in multiplyClaimedTokens.sorted(by: { $0.rawValue.uuidString < $1.rawValue.uuidString }) {
            for match in matchesByToken[token, default: []] {
                ambiguous.append(
                    AmbiguousWindowMatch(
                        tile: match.tile,
                        candidateTokens: [token],
                        reason: .runtimeWindowClaimedByMultipleTiles
                    )
                )
            }
        }

        return WindowMatchResult(
            matched: safeMatches.sorted { $0.tile.relativeOrder < $1.tile.relativeOrder },
            missing: missing.sorted { $0.relativeOrder < $1.relativeOrder },
            ambiguous: ambiguous.sorted { $0.tile.relativeOrder < $1.tile.relativeOrder }
        )
    }

    private static func score(
        _ persisted: PersistentWindowIdentity,
        against observed: PersistentWindowIdentity
    ) -> Score? {
        guard persisted.bundleIdentifier == observed.bundleIdentifier else { return nil }

        var value = 20
        var hasStrongSignal = false

        if let expectedHint = persisted.stableAccessibilityHint,
           let observedHint = observed.stableAccessibilityHint {
            guard expectedHint == observedHint else { return nil }
            value += 60
            hasStrongSignal = true
        }

        if let expectedHint = persisted.titleOrDocumentHint,
           let observedHint = observed.titleOrDocumentHint,
           expectedHint == observedHint {
            value += 35
            hasStrongSignal = true
        }

        if let expectedRole = persisted.role, let observedRole = observed.role {
            guard expectedRole == observedRole else { return nil }
            value += 8
        }

        if let expectedSubrole = persisted.subrole, let observedSubrole = observed.subrole {
            guard expectedSubrole == observedSubrole else { return nil }
            value += 5
        }

        var hasExactOrdinal = false
        if let expectedOrdinal = persisted.ordinalHint, let observedOrdinal = observed.ordinalHint {
            let distance = abs(expectedOrdinal - observedOrdinal)
            if distance == 0 {
                value += 12
                hasExactOrdinal = true
            } else if distance == 1 {
                value += 6
            }
        }

        let frameSimilarity = frameSimilarity(persisted.frameHint, observed.frameHint)
        value += Int((20 * frameSimilarity).rounded())

        // Apps that expose neither stable AX nor title/document hints may still be
        // recovered, but only from an exact ordinal and a near-identical frame.
        let hasPreciseFallback = hasExactOrdinal && frameSimilarity >= 0.9
        return Score(value: value, isEligible: hasStrongSignal || hasPreciseFallback)
    }

    private static func frameSimilarity(
        _ persisted: NormalizedHorizontalPlacement?,
        _ observed: NormalizedHorizontalPlacement?
    ) -> Double {
        guard let persisted, let observed else { return 0 }
        let difference = (
            abs(persisted.normalizedX - observed.normalizedX) +
                abs(persisted.normalizedWidth - observed.normalizedWidth)
        ) / 2
        return max(0, 1 - difference)
    }

    private struct Score {
        let value: Int
        let isEligible: Bool
    }

    private struct ScoredCandidate {
        let token: RuntimeWindowToken
        let score: Int
    }
}
