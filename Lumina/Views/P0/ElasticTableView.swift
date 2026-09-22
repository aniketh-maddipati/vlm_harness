import SwiftUI

/// The time route — moments as rows, separated by how long the shooting stopped.
///
/// Bursts stack with their leader on top and a count badge on the stack edge; the
/// badge opens the stack in place. Nothing here decides anything: marks render what
/// the photographer already said, and every mutation goes through the session.
struct ElasticTableView: View {
    @Bindable var session: P0SessionModel

    var body: some View {
        Group {
            if session.route == .focus {
                // Same table, compressed. Focus is a latch on this surface, not a
                // different screen — the mount survives so scroll and cursor do too.
                ElasticFilmstrip(session: session)
            } else {
                VStack(spacing: 0) {
                    // The flags peek: what the shoot's own structure suggests, above
                    // the table it was read from. The table stays put beneath it.
                    if session.peek == .flags, !session.inferredGroups.isEmpty {
                        ElasticGroupsBand(session: session)
                            .elasticBorn(ElasticLayout.bornGroupsMs)
                    }
                    momentScroll
                }
            }
        }
        .background(LuminaTokens.Elastic.matte)
    }

    // MARK: - Moments

    private var momentScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(session.chapters.enumerated()), id: \.element.id) { index, chapter in
                        let interval = index > 0 ? session.gapInterval(after: index - 1) : nil
                        VStack(alignment: .leading, spacing: 0) {
                            if index > 0 {
                                gap(interval)
                            }
                            ElasticMomentRow(session: session, chapter: chapter)
                        }
                        .id(chapter.id)
                    }
                }
                .padding(.horizontal, ElasticLayout.tableGutter)
                .padding(.vertical, ElasticLayout.tablePaddingTop)
            }
            .onChange(of: session.focusedAssetID) { _, id in
                guard let id,
                      let chapter = ShootChapterArrangement.chapter(containing: id, in: session.chapters)
                else { return }
                proxy.scrollTo(chapter.id, anchor: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // `position: absolute; bottom: 0` — the peek sits over the foot of the table
        // while ⇥ is held, and the table under it does not move.
        .overlay(alignment: .bottom) {
            if session.tablePeekVisible {
                ElasticPeekBar(session: session)
                    .elasticBorn(ElasticLayout.bornPeekMs)
            }
        }
    }

    /// `margin-top` above a moment, with its `+ 2 h 11 min` label centred in the gap.
    private func gap(_ interval: TimeInterval?) -> some View {
        let height = interval.map { ElasticLayout.gapHeight(after: $0) } ?? ElasticLayout.Gap.short
        return Color.clear
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                if let interval, let label = ElasticLayout.gapLabel(for: interval) {
                    Text(label)
                        .font(ElasticType.mono(ElasticLayout.gapLabelSize))
                        .foregroundStyle(LuminaTokens.Elastic.paper.opacity(ElasticLayout.gapLabelOpacity))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.leading, ElasticLayout.gapLabelLeading)
                }
            }
    }
}

/// One moment: a card with when it started, what the light was doing, and its frames.
struct ElasticMomentRow: View {
    @Bindable var session: P0SessionModel
    let chapter: ShootChapter

    var body: some View {
        HStack(alignment: .top, spacing: ElasticLayout.momentGap) {
            column
            ElasticWrapLayout(
                horizontalSpacing: ElasticLayout.groupGap,
                verticalSpacing: ElasticLayout.groupRowGap
            ) {
                ForEach(chapter.bursts) { burst in
                    ElasticFrameGroup(session: session, burst: burst)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, ElasticLayout.momentPaddingV)
        .padding(.horizontal, ElasticLayout.momentPaddingH)
        .background(
            HiFiTokens.SwimLane.fill,
            in: RoundedRectangle(cornerRadius: ElasticLayout.momentRadius, style: .continuous)
        )
    }

    private var column: some View {
        let size = ElasticLayout.momentTextSize
        let secondary = LuminaTokens.Elastic.shellAlt.opacity(ElasticLayout.momentSecondaryOpacity)
        let mix = session.momentMixLine(chapter)
        return VStack(alignment: .leading, spacing: ElasticType.lineSpacing(
            size: size, lineHeight: ElasticLayout.momentLineHeight
        )) {
            Text(session.momentTimeLabel(chapter))
                .font(ElasticType.mono(ElasticLayout.momentTimeSize, weight: .medium))
            Text(session.momentLightWord(chapter)).foregroundStyle(secondary)
            Text(session.momentCountLine(chapter)).foregroundStyle(secondary)
            if !mix.isEmpty {
                Text(mix).foregroundStyle(secondary)
            }
        }
        .font(ElasticType.mono(size))
        .foregroundStyle(LuminaTokens.Elastic.shellAlt)
        .lineLimit(1)
        .padding(.top, ElasticLayout.momentColumnTop)
        .frame(width: ElasticLayout.momentColumnWidth, alignment: .leading)
    }
}

/// One burst (or a single frame). Collapsed: the leader with two cards behind it and
/// a `×N` badge hanging off the stack edge. Open: every frame at 128, `fold` badge.
struct ElasticFrameGroup: View {
    @Bindable var session: P0SessionModel
    let burst: ShootBurst

    private var isBurst: Bool { burst.frameCount > 1 }
    /// The flags peek (`shiftTable`) opens every burst at once; otherwise a stack opens by its badge.
    private var isOpen: Bool { isBurst && (session.leanedBurstID == burst.id || session.peek == .flags) }

    var body: some View {
        if isOpen {
            HStack(spacing: ElasticLayout.frameGap) {
                ForEach(burst.frames) { frame in
                    ElasticFrameTile(session: session, assetID: frame.coverID, width: ElasticLayout.tileInOpenBurst)
                }
            }
            .overlay(alignment: .topTrailing) {
                badge("fold", fill: LuminaTokens.Elastic.ink, ink: LuminaTokens.Elastic.shell)
                    .padding(.top, ElasticLayout.badgeTop)
                    .padding(.trailing, ElasticLayout.badgeInsideOpen)
            }
        } else if isBurst {
            stacked
        } else if let id = leaderID {
            ElasticFrameTile(session: session, assetID: id, width: ElasticLayout.tile)
        }
    }

    private var leaderID: UUID? {
        burst.preferredCoverID(in: session.assets) ?? burst.coverID
    }

    private var stacked: some View {
        let width = ElasticLayout.tile
        let height = width / ElasticLayout.tileAspect
        return ZStack(alignment: .topLeading) {
            card(width: width, height: height, offset: ElasticLayout.stackBack,
                 opacity: ElasticLayout.stackBackOpacity)
            card(width: width, height: height, offset: ElasticLayout.stackMiddle,
                 opacity: ElasticLayout.stackMiddleOpacity)
            if let id = leaderID {
                ElasticFrameTile(session: session, assetID: id, width: width)
            }
        }
        .padding(.trailing, ElasticLayout.stackPadding)
        .overlay(alignment: .topTrailing) {
            badge("×\(burst.frameCount)", fill: LuminaTokens.Elastic.shell, ink: LuminaTokens.Elastic.ink)
                .padding(.top, ElasticLayout.badgeTop)
                .padding(.trailing, ElasticLayout.badgeOutsideStack)
        }
    }

    /// A card behind the leader: `left: dx; top: dy; right: 0 (of the leader)`.
    private func card(width: CGFloat, height: CGFloat, offset: CGSize, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: ElasticLayout.tileRadius, style: .continuous)
            .fill(LuminaTokens.Elastic.shellAlt.opacity(opacity))
            .frame(width: width - offset.width, height: height)
            .offset(x: offset.width, y: offset.height)
    }

    private func badge(_ text: String, fill: Color, ink: Color) -> some View {
        Button {
            session.toggleBurstOpen(burst.id)
        } label: {
            Text(text)
                .font(ElasticType.mono(ElasticLayout.badgeTextSize, weight: .semibold))
                .foregroundStyle(ink)
                .padding(.horizontal, ElasticLayout.badgePaddingH)
                .frame(minWidth: ElasticLayout.badgeMinWidth, minHeight: ElasticLayout.badgeHeight,
                       maxHeight: ElasticLayout.badgeHeight)
                .background(fill, in: RoundedRectangle(cornerRadius: ElasticLayout.badgeRadius, style: .continuous))
        }
        .buttonStyle(LuminaElasticButtonStyle())
    }
}

/// One frame on the table, carrying only marks the photographer made (§3.4, §4).
struct ElasticFrameTile: View {
    @Bindable var session: P0SessionModel
    let assetID: UUID
    let width: CGFloat

    private var asset: AssetRecord? {
        session.asset(assetID)
    }

    var body: some View {
        let asset = asset
        let ringed = session.focusedAssetID == assetID || session.selectedAssetIDs.contains(assetID)
        let inSet = session.isInFinalSet(assetID)
        let cull = asset?.cull ?? .undecided
        let height = width / ElasticLayout.tileAspect

        return ZStack {
            LuminaTokens.Elastic.deep
            if let path = asset?.gridThumbPath ?? asset?.thumbPath {
                ChapterPlateImage(path: path)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: ElasticLayout.tileRadius, style: .continuous))
        .overlay(alignment: .topLeading) {
            if let mark = inSet ? "✓" : cull == .reject ? "✕" : nil {
                Text(mark)
                    .font(.system(size: ElasticLayout.markTextSize, weight: .bold))
                    .foregroundStyle(LuminaTokens.Elastic.shell)
                    .frame(width: ElasticLayout.markSize, height: ElasticLayout.markSize)
                    .background(LuminaTokens.Elastic.ink, in: Circle())
                    .padding(ElasticLayout.markInset)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if session.isPhoneFrame(assetID) {
                ElasticPhoneGlyph().padding(ElasticLayout.markInset)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let flags = session.flagLine(for: assetID) {
                ElasticFlagChip(text: flags).padding(ElasticLayout.markInset)
            }
        }
        .elasticMarked(radius: ElasticLayout.tileRadius, ringed: ringed, inSet: inSet)
        .opacity(cull == .reject ? ElasticLayout.outOpacity : 1)
        .contentShape(Rectangle())
        .draggable(ElasticDragPayload.encode(
            ElasticDragPayload.ids(forDragging: assetID, selection: session.selectedAssetIDs)
        ))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(P0AccessibilityID.elasticTile(assetID))
        .onTapGesture(count: 2) {
            session.setFocus(assetID)
            session.openFocusedPhotograph()
        }
        .onTapGesture {
            session.setFocus(assetID)
        }
    }
}

/// `10×16; border 1.5px solid #F6F4F0; radius 2` — content box, border outside it.
struct ElasticPhoneGlyph: View {
    var body: some View {
        RoundedRectangle(cornerRadius: ElasticLayout.phoneGlyphRadius, style: .continuous)
            .strokeBorder(LuminaTokens.Elastic.shell, lineWidth: ElasticLayout.phoneGlyphStroke)
            .frame(
                width: ElasticLayout.phoneGlyph.width + 2 * ElasticLayout.phoneGlyphStroke,
                height: ElasticLayout.phoneGlyph.height + 2 * ElasticLayout.phoneGlyphStroke
            )
            .allowsHitTesting(false)
    }
}

/// The set, across the top (§3.2). A drop target in a later checkpoint.
