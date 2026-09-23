import AppKit
import SwiftUI

@MainActor
private final class HorizontalLayoutPlanPreviewModel: ObservableObject {
    @Published var frames: [CGRect] = []
}

private struct HorizontalLayoutPlanPreviewView: View {
    @ObservedObject var model: HorizontalLayoutPlanPreviewModel
    @ObservedObject private var accentColorController: AccentColorController = .shared

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(model.frames.enumerated()), id: \.offset) { _, frame in
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [accentColorController.color1, accentColorController.color2],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .opacity(0.28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.48), lineWidth: 2)
                    )
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One non-interactive overlay panel that previews every affected frame in a pending row plan.
@MainActor
final class HorizontalLayoutPlanPreviewController {
    private let model = HorizontalLayoutPlanPreviewModel()
    private var controller: NSWindowController?

    func open(_ execution: HorizontalLayoutPendingExecution) {
        let screen = execution.screen
        let displayBounds = screen.displayBounds
        let changedTileIDs = execution.changedTileIDs
        model.frames = execution.plan.snapshot.tiles.compactMap { tile in
            guard changedTileIDs.contains(tile.id) else { return nil }
            let action = HorizontalLayoutRuntimeAdapter.action(for: tile.frame)
            var frame = execution.padding.applyToWindow(
                frame: HorizontalLayoutRuntimeAdapter.logicalFrame(tile.frame, in: execution.usableBounds),
                paddedBounds: execution.usableBounds,
                action: action,
                resolvedWindowProperties: nil
            )
            frame.origin.x -= displayBounds.minX
            frame.origin.y -= displayBounds.minY
            return frame
        }

        if let panel = controller?.window {
            if panel.screen != screen {
                panel.setFrame(screen.frame, display: true)
            }
            panel.orderFrontRegardless()
            return
        }

        let panel = ActivePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = .canJoinAllSpaces
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.level = NSWindow.Level(NSWindow.Level.screenSaver.rawValue - 1)
        panel.contentView = NSHostingView(rootView: HorizontalLayoutPlanPreviewView(model: model))
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        controller = NSWindowController(window: panel)
    }

    func close() {
        controller?.close()
        controller = nil
        model.frames = []
    }
}
