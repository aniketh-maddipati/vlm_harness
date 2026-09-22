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

/// The inferred groups above the table while flags are held (`data-screen-label="Groups"`):
/// a head line, then one row per group — why these frames belong together on the left,
/// the frames on the right, the ones `G` would take at full strength.
struct ElasticGroupsBand: View {
    @Bindable var session: P0SessionModel

    var body: some View {
        let groups = session.inferredGroups
        VStack(alignment: .leading, spacing: ElasticLayout.groupsGap) {
            HStack(alignment: .firstTextBaseline, spacing: ElasticLayout.peekTitleGap) {
                Text(session.groupsHeadline)
                    .font(ElasticType.mono(ElasticLayout.peekTitleSize, weight: .medium))
                Text(session.groupsSubtitle)
                    .font(ElasticType.mono(ElasticLayout.peekSubSize))
                    .opacity(ElasticLayout.peekSubOpacity)
                Spacer(minLength: 0)
                Text(P0SessionModel.groupsKeyLine)
                    .font(ElasticType.mono(ElasticLayout.peekSubSize))
                    .opacity(ElasticLayout.peekSubOpacity)
            }
            .foregroundStyle(LuminaTokens.Elastic.shellAlt)
            .lineLimit(1)

            ScrollView {
                VStack(alignment: .leading, spacing: ElasticLayout.groupsGap) {
                    ForEach(groups) { group in
                        ElasticGroupRow(session: session, group: group)
                    }
                }
            }
        }
        .padding(.top, ElasticLayout.groupsPaddingTop)
        .padding(.horizontal, ElasticLayout.tableGutter)
        .padding(.bottom, ElasticLayout.groupsPaddingBottom)
        .frame(maxWidth: .infinity, maxHeight: ElasticLayout.groupsMaxHeight, alignment: .topLeading)
        .background(LuminaTokens.Elastic.groupsBar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LuminaTokens.Elastic.ink.opacity(ElasticLayout.groupsRuleOpacity))
                .frame(height: ElasticLayout.hairline)
        }
    }
}

private struct ElasticGroupRow: View {
    @Bindable var session: P0SessionModel
    let group: ElasticInferredGroup

    var body: some View {
        let holdsCursor = session.focusedAssetID.map { group.frameIDs.contains($0) } ?? false
        HStack(alignment: .center, spacing: ElasticLayout.groupsRowGap) {
            VStack(alignment: .leading, spacing: ElasticType.lineSpacing(
                size: ElasticLayout.groupsTextSize, lineHeight: ElasticLayout.groupsLineHeight
            )) {
                Text(group.kind.rawValue)
                    .font(ElasticType.mono(ElasticLayout.groupsKindSize, weight: .semibold))
                    .foregroundStyle(LuminaTokens.Elastic.warmAccent)
                Text(group.reason)
                    .opacity(ElasticLayout.groupsReasonOpacity)
                Text(group.takeLine)
                    .opacity(ElasticLayout.groupsTakeOpacity)
            }
            .font(ElasticType.mono(ElasticLayout.groupsTextSize))
            .foregroundStyle(LuminaTokens.Elastic.shellAlt)
            .frame(width: ElasticLayout.groupsColumnWidth, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ElasticLayout.groupsFrameGap) {
                    ForEach(group.frameIDs, id: \.self) { id in
                        frame(id)
                    }
                }
                .padding(ElasticLayout.ringOuter)
            }
        }
        .padding(.vertical, ElasticLayout.groupsRowPaddingV)
        .padding(.horizontal, ElasticLayout.groupsRowPaddingH)
        .background(
            holdsCursor
                ? LuminaTokens.Elastic.warmAccent.opacity(ElasticLayout.groupsFocusRowOpacity)
                : LuminaTokens.Elastic.ink.opacity(ElasticLayout.groupsRowOpacity),
            in: RoundedRectangle(cornerRadius: ElasticLayout.groupsRowRadius, style: .continuous)
        )
    }

    private func frame(_ id: UUID) -> some View {
        let asset = session.asset(id)
        let taken = group.takeIDs.contains(id)
        let ringed = session.focusedAssetID == id || session.selectedAssetIDs.contains(id)
        return Button {
            session.setFocus(id)
        } label: {
            ZStack {
                LuminaTokens.Elastic.deep
                if let path = asset?.gridThumbPath ?? asset?.thumbPath {
                    ChapterPlateImage(path: path)
                }
            }
            .frame(width: ElasticLayout.groupsFrame.width, height: ElasticLayout.groupsFrame.height)
            .clipShape(RoundedRectangle(cornerRadius: ElasticLayout.groupsFrameRadius, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if let tag = group.tags[id] {
                    Text(tag)
                        .font(ElasticType.mono(ElasticLayout.groupsTagSize))
                        .foregroundStyle(LuminaTokens.Elastic.shell)
                        .padding(.horizontal, ElasticLayout.groupsTagPaddingH)
                        .padding(.vertical, ElasticLayout.groupsTagPaddingV)
                        .background(
                            LuminaTokens.Elastic.ink.opacity(ElasticLayout.groupsTagOpacity),
                            in: RoundedRectangle(cornerRadius: ElasticLayout.groupsTagRadius, style: .continuous)
                        )
                        .padding(ElasticLayout.groupsTagInset)
                }
            }
            .elasticMarked(radius: ElasticLayout.groupsFrameRadius, ringed: ringed, inSet: session.isInFinalSet(id))
            .opacity(taken || group.takeIDs.isEmpty ? 1 : ElasticLayout.groupsUntakenOpacity)
        }
        .buttonStyle(LuminaElasticButtonStyle())
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            session.setFocus(id)
            session.openFocusedPhotograph()
        })
    }
}

/// `soft · clips · drift` — the salmon chip at a tile's foot while flags are held.
struct ElasticFlagChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(ElasticType.mono(ElasticLayout.flagChipSize, weight: .semibold))
            .foregroundStyle(LuminaTokens.Elastic.ink)
            .lineLimit(1)
            .padding(.horizontal, ElasticLayout.flagChipPaddingH)
            .padding(.vertical, ElasticLayout.flagChipPaddingV)
            .background(
                LuminaTokens.Elastic.warn,
                in: RoundedRectangle(cornerRadius: ElasticLayout.flagChipRadius, style: .continuous)
            )
            .allowsHitTesting(false)
    }
}
