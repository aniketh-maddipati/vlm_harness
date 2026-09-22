import SwiftUI

/// The peek bar at the foot of the table while similar or the set is held
/// (`data-screen-label="Peek"`): a title line, then the frames in a row, each
/// under the key that jumps to it. It reads the session and decides nothing.
struct ElasticPeekBar: View {
    @Bindable var session: P0SessionModel

    var body: some View {
        let mode = session.peek
        let items = mode == .set ? session.setPeekItems : session.relatedPeekItems
        VStack(alignment: .leading, spacing: ElasticLayout.peekGap) {
            HStack(spacing: ElasticLayout.peekTitleGap) {
                Text(session.peekTitle)
                    .font(ElasticType.mono(ElasticLayout.peekTitleSize, weight: .medium))
                Text(session.peekSubtitle)
                    .font(ElasticType.mono(ElasticLayout.peekSubSize))
                    .opacity(ElasticLayout.peekSubOpacity)
            }
            .foregroundStyle(LuminaTokens.Elastic.shellAlt)
            .lineLimit(1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: ElasticLayout.peekGap) {
                    ForEach(items) { item in
                        ElasticPeekTile(
                            session: session,
                            item: item,
                            width: mode == .set
                                ? ElasticLayout.peekSetTile
                                : item.isCursor ? ElasticLayout.peekCursorTile : ElasticLayout.peekRelatedTile
                        )
                    }
                }
                // Room for the cursor ring, which sits outside the tile.
                .padding(ElasticLayout.ringOuter)
            }
        }
        .padding(.top, ElasticLayout.peekPaddingTop)
        .padding(.horizontal, ElasticLayout.tableGutter)
        .padding(.bottom, ElasticLayout.peekPaddingBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LuminaTokens.Elastic.ink.opacity(ElasticLayout.peekFillOpacity))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LuminaTokens.Elastic.shellAlt.opacity(ElasticLayout.peekRuleOpacity))
                .frame(height: ElasticLayout.hairline)
        }
    }
}

/// One frame in the peek bar: the picture, its key, and a caption that says how it
/// relates to the cursor.
private struct ElasticPeekTile: View {
    @Bindable var session: P0SessionModel
    let item: ElasticPeekItem
    let width: CGFloat

    var body: some View {
        let asset = session.asset(item.id)
        VStack(alignment: .leading, spacing: ElasticLayout.peekCaptionGap) {
            Button {
                session.pickInPeek(item.id)
            } label: {
                ZStack {
                    LuminaTokens.Elastic.deep
                    if let path = asset?.gridThumbPath ?? asset?.thumbPath {
                        ChapterPlateImage(path: path)
                    }
                }
                .frame(width: width, height: width / ElasticLayout.tileAspect)
                .clipShape(RoundedRectangle(cornerRadius: ElasticLayout.peekTileRadius, style: .continuous))
                .overlay(alignment: .topLeading) {
                    ElasticKeyBadge(
                        text: item.key,
                        height: ElasticLayout.peekKeyBadgeHeight,
                        textSize: ElasticLayout.peekKeyBadgeTextSize
                    )
                    .padding(ElasticLayout.peekKeyBadgeInset)
                }
                .elasticMarked(radius: ElasticLayout.peekTileRadius, ringed: item.ringed, inSet: item.outlined)
            }
            .buttonStyle(LuminaElasticButtonStyle())

            ElasticPeekCaption(item: item)
                .frame(width: width)
        }
    }
}

/// `rel` on the left, the warm fact on the right, one line, mono 11.
private struct ElasticPeekCaption: View {
    let item: ElasticPeekItem

    var body: some View {
        HStack(spacing: ElasticLayout.peekCaptionSpacing) {
            Text(item.relation)
            Spacer(minLength: 0)
            Text(item.facts)
                .foregroundStyle(LuminaTokens.Elastic.warmAccent)
                .truncationMode(.tail)
        }
        .font(ElasticType.mono(ElasticLayout.peekCaptionSize))
        .foregroundStyle(LuminaTokens.Elastic.shellAlt.opacity(ElasticLayout.statusTextOpacity))
        .lineLimit(1)
    }
}

/// `min-width: h; height: h; padding: 0 6px; radius 6` — shell over ink, semibold mono.
struct ElasticKeyBadge: View {
    let text: String
    let height: CGFloat
    let textSize: CGFloat

    var body: some View {
        Text(text)
            .font(ElasticType.mono(textSize, weight: .semibold))
            .foregroundStyle(LuminaTokens.Elastic.ink)
            .padding(.horizontal, ElasticLayout.peekKeyBadgePaddingH)
            .frame(minWidth: height, minHeight: height, maxHeight: height)
            .background(
                LuminaTokens.Elastic.shell,
                in: RoundedRectangle(cornerRadius: ElasticLayout.chipRadius, style: .continuous)
            )
            .allowsHitTesting(false)
    }
}

/// Similar, in the focus route: the photograph gives way to its neighbours, bottoms
/// aligned, the cursor 1.6× as wide as each of them. A click on a neighbour goes
/// there; a click on the cursor comes back.
struct ElasticRelatedRow: View {
    @Bindable var session: P0SessionModel

    var body: some View {
        let items = session.relatedPeekItems
        GeometryReader { geometry in
            let count = CGFloat(items.count)
            let gaps = max(count - 1, 0) * ElasticLayout.relatedRowGap
            let units = max(count - 1 + ElasticLayout.relatedCursorGrow, 1)
            let captionHeight = ElasticLayout.peekCaptionSize * ElasticLayout.systemLineHeight
                + ElasticLayout.relatedColumnGap
            // `max-height: 100%` — a column never grows taller than the band.
            let tallest = max(geometry.size.height - captionHeight, 0) * ElasticLayout.tileAspect
            let unit = min(max((geometry.size.width - gaps) / units, 0), tallest / ElasticLayout.relatedCursorGrow)

            HStack(alignment: .bottom, spacing: ElasticLayout.relatedRowGap) {
                ForEach(items) { item in
                    column(item, width: item.isCursor ? unit * ElasticLayout.relatedCursorGrow : unit)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
        }
    }

    private func column(_ item: ElasticPeekItem, width: CGFloat) -> some View {
        let asset = session.asset(item.id)
        return VStack(alignment: .leading, spacing: ElasticLayout.relatedColumnGap) {
            Button {
                session.pickInPeek(item.id)
            } label: {
                ZStack {
                    LuminaTokens.Elastic.deep
                    if let path = asset?.gridThumbPath ?? asset?.thumbPath {
                        ChapterPlateImage(path: path)
                    }
                }
                .frame(width: width, height: width / ElasticLayout.tileAspect)
                .clipShape(RoundedRectangle(cornerRadius: ElasticLayout.peekTileRadius, style: .continuous))
                .overlay(alignment: .topLeading) {
                    ElasticKeyBadge(
                        text: item.key,
                        height: ElasticLayout.relatedKeyBadgeHeight,
                        textSize: ElasticLayout.relatedKeyBadgeTextSize
                    )
                    .padding(ElasticLayout.peekKeyBadgeInset)
                }
                .elasticMarked(radius: ElasticLayout.peekTileRadius, ringed: item.ringed, inSet: item.outlined)
            }
            .buttonStyle(LuminaElasticButtonStyle())

            ElasticPeekCaption(item: item)
                .padding(.horizontal, ElasticLayout.relatedCaptionPaddingH)
                .frame(width: width)
        }
    }
}
