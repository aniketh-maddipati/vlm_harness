import SwiftUI

/// The three fixed versions beside the photograph: 1 shot · 2 auto · 3 yours.
///
/// Its own file because two things want it at once — how the tiles get their
/// pixels, and whether the column is on screen at all while the develop drawer
/// is open. Keeping it here lets those land independently.
struct ElasticVersionColumn: View {
    @Bindable var session: P0SessionModel
    let asset: AssetRecord

    /// Three fixed versions, stacked beside the photograph: 1 shot · 2 auto · 3 yours.
    var body: some View {
        VStack(spacing: ElasticLayout.versionGap) {
            versionTile(1, word: "shot")
            versionTile(2, word: "auto")
            versionTile(3, word: "yours")
        }
        .frame(width: ElasticLayout.versionColumnWidth)
    }

    private func versionTile(_ index: Int, word: String) -> some View {
        let active = session.versionIndex(for: asset) == index
        // `yours` stays legible but unfinished until there is a hand recipe to go back to.
        let unauthored = index == 3 && asset.handRecipe == nil

        return Button {
            session.pickVersion(index, for: asset.id)
        } label: {
            ZStack {
                LuminaTokens.Elastic.deep
                if let path = asset.gridThumbPath ?? asset.thumbPath {
                    ChapterPlateImage(path: path)
                }
            }
            .opacity(unauthored ? ElasticLayout.versionUnauthoredOpacity : 1)
            .aspectRatio(ElasticLayout.tileAspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: ElasticLayout.tileRadius, style: .continuous))
            .overlay(alignment: .topLeading) {
                versionBadge(index, word: word)
                    .padding(ElasticLayout.versionBadgeInset)
            }
            .elasticMarked(radius: ElasticLayout.tileRadius, ringed: active, inSet: false)
        }
        .buttonStyle(LuminaElasticButtonStyle())
        .accessibilityIdentifier(P0AccessibilityID.elasticVersion(index))
    }

    /// `1 shot` — the number in ink, the word in the softer ink beside it.
    private func versionBadge(_ index: Int, word: String) -> some View {
        HStack(spacing: ElasticLayout.versionBadgeGap) {
            Text("\(index)")
                .font(ElasticType.mono(ElasticLayout.versionBadgeTextSize, weight: .semibold))
                .foregroundStyle(LuminaTokens.Elastic.ink)
            Text(word)
                .font(ElasticType.mono(ElasticLayout.versionBadgeTextSize))
                .foregroundStyle(LuminaTokens.Elastic.inkSoft)
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, ElasticLayout.versionBadgePaddingH)
        .frame(height: ElasticLayout.versionBadgeHeight)
        .background(
            LuminaTokens.Elastic.shell,
            in: RoundedRectangle(cornerRadius: ElasticLayout.chipRadius, style: .continuous)
        )
    }
}
