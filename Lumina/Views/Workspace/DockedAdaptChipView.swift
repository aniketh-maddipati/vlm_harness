import SwiftUI

/// Post-commit grabbable adapt chip — grab / carry / place to another lane (hi-fi H6).
struct DockedAdaptChipView: View {
    let chip: LuminaShellModel.DockedAdaptChip

    private var label: String {
        CopyContract.provenanceChip(referenceFrame: chip.referenceFrame, scopeCount: chip.scopeCount)
    }

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(LuminaTokens.Ink.onTable)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.52))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(HiFiTokens.Ring.halo.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
            .draggable("adapt-chip") {
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(LuminaTokens.Ink.onTable)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.72)))
            }
            .accessibilityLabel("Adapt treatment \(label), drag to another lane")
            .accessibilityHint("Drop on a lane to stage the same treatment on kept frames there")
    }
}

extension View {
    /// Lane drop target for the docked adapt chip carry.
    func dockedChipLaneDrop(
        laneGroupID: String,
        onDrop: @escaping (String) -> Void
    ) -> some View {
        dropDestination(for: String.self) { items, _ in
            guard items.contains("adapt-chip") else { return false }
            onDrop(laneGroupID)
            return true
        } isTargeted: { _ in }
    }
}
