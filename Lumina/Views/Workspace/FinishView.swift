import SwiftUI

struct FinishView: View {
    let presentation: FinishPresentation
    var onFinish: () -> Void
    var onReview: () -> Void
    var onUndo: () -> Void
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            finishHeader

            ScrollView {
                VStack(alignment: .leading, spacing: LuminaTokens.Spacing.section) {
                    editorialSequence
                    statusSummary
                    actionRow
                }
                .padding(.horizontal, LuminaTokens.Spacing.xl)
                .padding(.vertical, LuminaTokens.Spacing.lg)
                .frame(maxWidth: 1080, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LuminaTokens.Surface.porcelain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Finish review")
    }

    private var finishHeader: some View {
        HStack(spacing: LuminaTokens.Spacing.md) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(LuminaTokens.Typeface.navigation(13, weight: .medium))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                    .frame(width: LuminaTokens.HitTarget.minimum, height: LuminaTokens.HitTarget.minimum)
                    .contentShape(Rectangle())
            }
            .buttonStyle(LuminaQuietButtonStyle())
            .accessibilityLabel("Back to workspace")

            VStack(alignment: .leading, spacing: 4) {
                Text("Finished set")
                    .font(LuminaTokens.Typeface.editorial(28))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(presentation.shootTitle)
                    .font(LuminaTokens.Typeface.meta(13))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
            }

            Spacer(minLength: 12)

            LuminaGhostActionButton(title: "Undo", action: onUndo)
        }
        .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
        .frame(height: LuminaTokens.HitTarget.header)
        .background(LuminaTokens.Surface.porcelain)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LuminaTokens.Line.hairline.opacity(0.65))
                .frame(height: LuminaTokens.Line.hairlineWidth)
        }
    }

    private var editorialSequence: some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.md) {
            SectionHeader(title: "Sequence")

            Text(presentation.sequenceLabel)
                .font(LuminaTokens.Typeface.control(15))
                .foregroundStyle(LuminaTokens.Ink.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LuminaTokens.Spacing.md) {
                    ForEach(Array(presentation.assets.enumerated()), id: \.element.id) { index, asset in
                        FinishSequenceTile(asset: asset, index: index + 1)
                    }
                }
            }
            .accessibilityLabel("Finished photograph sequence, \(presentation.assets.count) photographs")
        }
    }

    private var statusSummary: some View {
        HStack(spacing: LuminaTokens.Spacing.lg) {
            if presentation.unresolvedCount > 0 {
                statusChip(
                    count: presentation.unresolvedCount,
                    label: "Unresolved",
                    color: LuminaTokens.Status.needsAttention
                )
            }

            if presentation.protectedCount > 0 {
                statusChip(
                    count: presentation.protectedCount,
                    label: "Protected",
                    color: LuminaTokens.Ink.secondary
                )
            }

            if presentation.unresolvedCount == 0 && presentation.protectedCount == 0 {
                Text("All photographs resolved")
                    .font(LuminaTokens.Typeface.control(14))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func statusChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Text("\(count)")
                .font(LuminaTokens.Typeface.count(15))
                .foregroundStyle(color)
            Text(label)
                .font(LuminaTokens.Typeface.meta(12, weight: .medium))
                .foregroundStyle(LuminaTokens.Ink.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: LuminaTokens.Radius.button, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: LuminaTokens.Radius.button, style: .continuous)
                .strokeBorder(LuminaTokens.Line.hairline, lineWidth: LuminaTokens.Line.hairlineWidth)
        }
        .accessibilityLabel("\(count) \(label)")
    }

    private var actionRow: some View {
        HStack(spacing: LuminaTokens.Spacing.md) {
            if presentation.unresolvedCount > 0 {
                LuminaGhostActionButton(title: presentation.secondaryReviewTitle, action: onReview)
            }

            LuminaTextActionButton(
                title: presentation.primaryActionTitle,
                prominent: true,
                action: onFinish
            )
        }
        .padding(.top, LuminaTokens.Spacing.sm)
    }
}

private struct FinishSequenceTile: View {
    let asset: AssetPresentation
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.sm) {
            StablePhotoView(
                asset: asset,
                cornerRadius: LuminaTokens.Radius.photographLarge,
                showDecisionBadge: true,
                maxPixelSize: 1600
            )
            .frame(width: 280)

            HStack(spacing: 6) {
                Text(String(format: "%02d", index))
                    .font(LuminaTokens.Typeface.count(12))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                Text(asset.filename)
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                    .lineLimit(1)
            }
            .frame(width: 280, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sequence \(index), \(asset.filename), \(asset.decision.title)")
    }
}

#Preview("Finished set") {
    FinishView(
        presentation: PresentationFixtures.finishedSet(),
        onFinish: {},
        onReview: {},
        onUndo: {},
        onBack: {}
    )
    .frame(width: 1100, height: 800)
}

#Preview("Missing source") {
    FinishView(
        presentation: PresentationFixtures.missingSourceFinish(),
        onFinish: {},
        onReview: {},
        onUndo: {},
        onBack: {}
    )
    .frame(width: 1100, height: 700)
}
