import SwiftUI

/// Vertically scrolling palette board — several photographic groups visible at once.
struct PaletteBoardView: View {
    let groups: [GroupPresentation]
    let lens: WorkspaceLens
    let selectedAssetID: AssetID?
    var scrollTargetGroupID: String?
    let onSelectAsset: (AssetID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let rowHeight: CGFloat = 148

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: LuminaTokens.Spacing.section) {
                    ForEach(groups) { group in
                        PaletteGroupRow(
                            group: group,
                            selectedAssetID: selectedAssetID,
                            rowHeight: rowHeight,
                            onSelectAsset: onSelectAsset
                        )
                        .id(group.id)
                    }
                }
                .padding(.horizontal, LuminaTokens.Spacing.lg)
                .padding(.vertical, LuminaTokens.Spacing.lg)
            }
            .onAppear {
                scrollToSelection(proxy: proxy, animated: false)
            }
            .onChange(of: selectedAssetID) { _, _ in
                scrollToSelection(proxy: proxy, animated: !reduceMotion)
            }
            .onChange(of: scrollTargetGroupID) { _, _ in
                scrollToSelection(proxy: proxy, animated: !reduceMotion)
            }
            .onChange(of: lens) { _, _ in
                scrollToSelection(proxy: proxy, animated: !reduceMotion)
            }
        }
        .background(LuminaTokens.Surface.porcelain)
        .accessibilityLabel("\(lens.title) palette board")
    }

    private func scrollToSelection(proxy: ScrollViewProxy, animated: Bool) {
        guard let target = scrollTargetGroupID
            ?? groups.first(where: { $0.assets.contains(where: { $0.id == selectedAssetID }) })?.id
            ?? groups.first?.id else { return }
        if animated {
            withAnimation(LuminaTokens.Motion.photo) {
                proxy.scrollTo(target, anchor: .center)
            }
        } else {
            proxy.scrollTo(target, anchor: .center)
        }
    }
}

private struct PaletteGroupRow: View {
    let group: GroupPresentation
    let selectedAssetID: AssetID?
    let rowHeight: CGFloat
    let onSelectAsset: (AssetID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.title)
                    .font(LuminaTokens.Typeface.title(18))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                    .accessibilityAddTraits(.isHeader)

                if let subtitle = group.subtitle {
                    Text("·")
                        .foregroundStyle(LuminaTokens.Ink.tertiary)
                    Text(subtitle)
                        .font(LuminaTokens.Typeface.meta(13))
                        .foregroundStyle(LuminaTokens.Ink.secondary)
                }

                Spacer(minLength: 0)
            }

            PalettePhotoStripView(
                assets: group.assets,
                selectedID: selectedAssetID,
                rowHeight: rowHeight,
                onSelect: onSelectAsset
            )
            .frame(height: rowHeight)

            if group.assets.count > 4 {
                Rectangle()
                    .fill(LuminaTokens.Line.hairline)
                    .frame(height: LuminaTokens.Line.hairlineWidth)
                    .padding(.top, LuminaTokens.Spacing.xs)
            }
        }
    }
}

#Preview("Attempts board") {
    PaletteBoardView(
        groups: PresentationFixtures.attemptWorkspace().groups,
        lens: .attempts,
        selectedAssetID: PresentationFixtures.attemptWorkspace().selectedAssetID,
        onSelectAsset: { _ in }
    )
    .frame(width: 1100, height: 760)
}

#Preview("Light board") {
    PaletteBoardView(
        groups: PresentationFixtures.lightWorkspace().groups,
        lens: .light,
        selectedAssetID: PresentationFixtures.lightWorkspace().selectedAssetID,
        onSelectAsset: { _ in }
    )
    .frame(width: 1100, height: 760)
}

#Preview("Mixed aspects") {
    PaletteBoardView(
        groups: PresentationFixtures.mixedAspectBoard().groups,
        lens: .attempts,
        selectedAssetID: PresentationFixtures.mixedAspectBoard().selectedAssetID,
        onSelectAsset: { _ in }
    )
    .frame(width: 900, height: 700)
}

#Preview("Empty shoot") {
    PaletteBoardView(
        groups: [],
        lens: .attempts,
        selectedAssetID: nil,
        onSelectAsset: { _ in }
    )
    .frame(width: 900, height: 500)
}
