import SwiftUI

struct ElasticFilmstrip: View {
    @Bindable var session: P0SessionModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ElasticLayout.filmstripGap) {
                    Text("time")
                        .font(ElasticType.mono(ElasticLayout.stripLabelSize))
                        .lineSpacing(ElasticType.lineSpacing(
                            size: ElasticLayout.stripLabelSize,
                            lineHeight: ElasticLayout.stripLabelLineHeight
                        ))
                        .foregroundStyle(
                            LuminaTokens.Elastic.shellAlt
                                .opacity(ElasticLayout.stripLabelOpacity)
                        )
                        .frame(width: ElasticLayout.stripLabelWidth, alignment: .leading)

                    ForEach(session.assets) { asset in
                        tile(asset)
                            .id(asset.id)
                            .padding(
                                .trailing,
                                session.startsNewMoment(after: asset.id)
                                    ? ElasticLayout.filmstripMomentGap
                                    : 0
                            )
                    }
                }
                .padding(.horizontal, ElasticLayout.tableGutter)
                .frame(height: ElasticLayout.filmstripHeight)
            }
            .onChange(of: session.focusedAssetID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
        .frame(height: ElasticLayout.filmstripHeight)
        .background(
            LuminaTokens.Elastic.shadowInk.opacity(ElasticLayout.filmstripFillOpacity)
        )
    }

    private func tile(_ asset: AssetRecord) -> some View {
        let focused = session.focusedAssetID == asset.id
        let ringed = focused || session.selectedAssetIDs.contains(asset.id)
        let inSet = session.isInFinalSet(asset.id)
        let size = focused ? ElasticLayout.filmstripFocusedTile : ElasticLayout.filmstripTile

        return ZStack {
            LuminaTokens.Elastic.deep
            if let path = asset.gridThumbPath ?? asset.thumbPath {
                ChapterPlateImage(path: path)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: ElasticLayout.tileRadius, style: .continuous))
        .elasticMarked(radius: ElasticLayout.tileRadius, ringed: ringed, inSet: inSet)
        .opacity(asset.cull == .reject ? ElasticLayout.outOpacity : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(P0AccessibilityID.elasticTile(asset.id))
        .onTapGesture { session.setFocus(asset.id) }
    }
}
