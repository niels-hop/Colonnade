import AppKit
import Scribe

@MainActor
private final class WindowHorizontalLayoutTarget: HorizontalLayoutFrameTarget {
    let window: Window
    let resolvedProperties: Window.ResolvedProperties

    init(window: Window) {
        self.window = window
        self.resolvedProperties = Window.ResolvedProperties(from: window)
    }

    var horizontalLayoutFrame: CGRect { window.frame }

    func applyHorizontalLayoutFrame(_ frame: CGRect) async throws {
        await window.setFrame(frame, resolvedProperties: resolvedProperties)
    }
}

/// Runtime wrapper around the testable batch core. It resolves padding once, avoids focus/cursor APIs,
/// and records the actual settled frames only after the complete transaction succeeds.
@MainActor
@Loggable
final class HorizontalLayoutExecutor {
    static let shared = HorizontalLayoutExecutor()

    private init() {}

    @discardableResult
    func execute(_ execution: HorizontalLayoutPendingExecution) async throws -> HorizontalLayoutBatchResult {
        let normalizedFrames = execution.normalizedFrames
        let orderedIDs = execution.changedIDs.sorted {
            let lhsX = normalizedFrames[$0]?.minX ?? 0
            let rhsX = normalizedFrames[$1]?.minX ?? 0
            return lhsX == rhsX ? $0.rawValue < $1.rawValue : lhsX < rhsX
        }

        var targets: [HorizontalLayoutTileID: any HorizontalLayoutFrameTarget] = [:]
        var concreteTargets: [HorizontalLayoutTileID: WindowHorizontalLayoutTarget] = [:]
        var requests: [HorizontalLayoutBatchRequest] = []

        for id in orderedIDs {
            guard let window = execution.windowsByID[id], let normalized = normalizedFrames[id] else {
                throw HorizontalLayoutExecutionError.missingTarget(id)
            }
            let target = WindowHorizontalLayoutTarget(window: window)
            let action = HorizontalLayoutRuntimeAdapter.action(for: normalized)
            let logicalFrame = HorizontalLayoutRuntimeAdapter.logicalFrame(normalized, in: execution.usableBounds)
            let actualTarget = execution.padding.applyToWindow(
                frame: logicalFrame,
                paddedBounds: execution.usableBounds,
                action: action,
                resolvedWindowProperties: target.resolvedProperties
            )
            targets[id] = target
            concreteTargets[id] = target
            requests.append(HorizontalLayoutBatchRequest(id: id, targetFrame: actualTarget))
        }

        let result = try await HorizontalLayoutBatchExecutor().execute(
            requests,
            targets: targets,
            within: execution.usableBounds
        )

        let records = orderedIDs.compactMap { id -> WindowRecords.HorizontalLayoutBatchEntry? in
            guard let target = concreteTargets[id],
                  let original = result.originalFrames[id],
                  let actual = result.actualFrames[id]
            else { return nil }
            let normalizedActual = CGRect(
                x: (actual.minX - execution.usableBounds.minX) / execution.usableBounds.width,
                y: 0,
                width: actual.width / execution.usableBounds.width,
                height: 1
            )
            return WindowRecords.HorizontalLayoutBatchEntry(
                window: target.window,
                originalProperties: Window.ResolvedProperties(updating: original, from: target.resolvedProperties),
                actualProperties: Window.ResolvedProperties(updating: actual, from: target.resolvedProperties),
                action: HorizontalLayoutRuntimeAdapter.action(
                    for: normalizedActual,
                    name: "horizontal_layout_batch"
                )
            )
        }
        await WindowRecords.shared.recordHorizontalLayoutBatch(records)
        log.success("Applied horizontal layout batch to \(records.count) windows")
        return result
    }
}
