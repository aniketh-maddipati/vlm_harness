import SwiftUI

struct ShootSelectionView: View {
    let presentation: ShootSelectionPresentation
    var onOpen: (String) -> Void
    var onBack: () -> Void

    private let gridColumns = [
        GridItem(.adaptive(minimum: 320, maximum: 420), spacing: LuminaTokens.Spacing.lg, alignment: .top)
    ]

    var body: some View {
        VStack(spacing: 0) {
            selectionHeader

            ScrollView {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: LuminaTokens.Spacing.lg) {
                    ForEach(presentation.shoots) { shoot in
                        ShootSelectionCard(shoot: shoot) {
                            onOpen(shoot.id)
                        }
                    }
                }
                .padding(.horizontal, LuminaTokens.Spacing.xl)
                .padding(.vertical, LuminaTokens.Spacing.lg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LuminaTokens.Surface.porcelain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shoot selection")
    }

    private var selectionHeader: some View {
        HStack(spacing: LuminaTokens.Spacing.md) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(LuminaTokens.Typeface.navigation(13, weight: .medium))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                    .frame(width: LuminaTokens.HitTarget.minimum, height: LuminaTokens.HitTarget.minimum)
                    .contentShape(Rectangle())
            }
            .buttonStyle(LuminaQuietButtonStyle())
            .accessibilityLabel("Back to home")

            VStack(alignment: .leading, spacing: 4) {
                Text("Shoots")
                    .font(LuminaTokens.Typeface.editorial(28))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(presentation.readinessSummary)
                    .font(LuminaTokens.Typeface.meta(13))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
            }

            Spacer(minLength: 12)
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
}

private struct ShootSelectionCard: View {
    let shoot: ShootCardPresentation
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: LuminaTokens.Spacing.md) {
                ShootCardHeader(card: shoot)

                PhotoStripPreview(assets: shoot.previewAssets, maxCount: 5, height: 140)

                HStack {
                    Spacer(minLength: 0)
                    Text(shoot.primaryActionTitle)
                        .font(LuminaTokens.Typeface.navigation(15))
                        .foregroundStyle(LuminaTokens.Ink.primary)
                    Image(systemName: "arrow.right")
                        .font(LuminaTokens.Typeface.navigation(12, weight: .medium))
                        .foregroundStyle(LuminaTokens.Ink.tertiary)
                }
            }
            .padding(.vertical, LuminaTokens.Spacing.md)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(LuminaTokens.Line.hairline)
                    .frame(height: LuminaTokens.Line.hairlineWidth)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(LuminaQuietButtonStyle())
        .accessibilityLabel("\(shoot.title), \(shoot.photographCount) photographs, open shoot")
    }
}

#Preview("Selection") {
    ShootSelectionView(
        presentation: PresentationFixtures.shootSelection(),
        onOpen: { _ in },
        onBack: {}
    )
    .frame(width: 1100, height: 800)
}

#Preview("Uncertain boundary") {
    ShootSelectionView(
        presentation: PresentationFixtures.shootUncertainBoundary(),
        onOpen: { _ in },
        onBack: {}
    )
    .frame(width: 1100, height: 800)
}
