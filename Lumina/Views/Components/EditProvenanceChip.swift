import SwiftUI

/// Post-commit edit-family chip — reference wears `Edited`, recipients wear `← frame · count`.
struct EditProvenanceChip: View {
    let provenance: AdaptProvenance

    var body: some View {
        Text(label)
            .font(.system(size: 10.5, weight: .regular, design: .monospaced))
            .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.42))
            )
            .accessibilityLabel(label)
    }

    private var label: String {
        if provenance.isReference {
            return CopyContract.editedChip
        }
        return CopyContract.provenanceChip(
            referenceFrame: provenance.referenceFrame,
            scopeCount: provenance.scopeCount
        )
    }
}
