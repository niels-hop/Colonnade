//
//  SettingsScreenPreview.swift
//  Colonnade
//
//  Created by Niels Hop on 2026-09-23.
//

import Luminare
import SwiftUI

/// The inspector for the preview and shortcut tabs: a wide screen with the real placement
/// preview, stepping through full-height columns or showing the selected shortcut.
struct SettingsScreenPreview: View {
    @ObservedObject var model: SettingsWindowManager

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.black.opacity(0.35))

                PreviewView(viewModel: model.previewViewModel)
                    .onGeometryChange(for: CGSize.self, of: \.size) {
                        model.setPreviewBounds(CGRect(origin: .zero, size: $0))
                    }
                    .clipShape(.rect(cornerRadius: 14))

                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 1)
            }
            .aspectRatio(32 / 9, contentMode: .fit)
            .padding(.horizontal, 12)

            Text(model.previewedAction.getName())
                .font(.title3)
                .fontWeight(.medium)
                .contentTransition(.opacity)
                .id(model.previewedAction.id)
                .transition(.opacity)

            Text("Windows always fill the full height.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}
