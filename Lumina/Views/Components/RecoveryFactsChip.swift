import SwiftUI

/// Facts-chip recovery surface — one sentence, one action; never a modal dead-end.
struct RecoveryFactsChip: View {
    let headline: String
    let detail: String
    let actionTitle: String
    var onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headline)
                .font(LuminaTokens.Typeface.navigation(14, weight: .medium))
                .foregroundStyle(LuminaTokens.Ink.primary)
            Text(detail)
                .font(LuminaTokens.Typeface.meta(12))
                .foregroundStyle(LuminaTokens.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle, action: onAction)
                .buttonStyle(LuminaPrimaryButtonStyle())
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LuminaTokens.Surface.mist)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(LuminaTokens.Line.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

extension RecoveryFactsChip {
    static func pointedFolderMoved(onAction: @escaping () -> Void) -> RecoveryFactsChip {
        RecoveryFactsChip(
            headline: CopyContract.pointedFolderMoved,
            detail: CopyContract.pointedFolderMovedBody,
            actionTitle: CopyContract.pointedFolderMovedAction,
            onAction: onAction
        )
    }

    static func fileDamagedPreviewOnly() -> some View {
        Text(CopyContract.fileDamagedPreviewOnly)
            .font(LuminaTokens.Typeface.meta(11))
            .foregroundStyle(LuminaTokens.Ink.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(LuminaTokens.Surface.mist))
            .accessibilityLabel(CopyContract.fileDamagedPreviewOnly)
    }

    static func staleRender(onAction: @escaping () -> Void) -> RecoveryFactsChip {
        RecoveryFactsChip(
            headline: CopyContract.staleRender,
            detail: CopyContract.staleRenderBody,
            actionTitle: CopyContract.staleRenderAction,
            onAction: onAction
        )
    }
}
