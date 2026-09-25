import AppKit
import SwiftUI

/// The time route — moments as rows, separated by how long the shooting stopped.
///
/// Bursts stack with their leader on top and a count badge on the stack edge; the
/// badge opens the stack in place. Nothing here decides anything: marks render what
/// the photographer already said, and every mutation goes through the session.
struct ElasticTableView: View {
    @Bindable var session: P0SessionModel
    @State private var viewportSpace = UUID()
    @State private var viewportSnapshot = ElasticViewportSnapshot()
    @State private var returnAnchor: ElasticViewportReveal.Anchor?
    @State private var revealRequest: ElasticViewportReveal.Request?
    @State private var marqueeRect: CGRect?

    var body: some View {
        Group {
            if session.route == .focus {
                // The scroll content is replaced by a strip; returnAnchor lives
                // here so the table can restore a visible photo when it returns.
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
        #if DEBUG
        .workbenchHot()
        #endif
    }

    // MARK: - Moments

    private var showsChronologyBar: Bool {
        session.peek != .set && !session.chapters.isEmpty
    }

    private var momentScroll: some View {
        GeometryReader { viewport in
          ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if showsChronologyBar {
                    // CHRON-02 — pinned markers; click reveals chapter without moving focus.
                    ElasticChronologyBar(
                        chapters: session.chapters,
                        activeID: session.chronologyViewportChapterID,
                        navigate: { id in proxy.scrollTo(id, anchor: .top) }
                    )
                }
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
                            .background {
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: ElasticViewportFrames.self,
                                        value: ElasticViewportSnapshot(
                                            containers: [chapter.id],
                                            chapters: [chapter.id: geo.frame(in: .named(viewportSpace))]
                                        )
                                    )
                                }
                            }
                        }
                    }
                    .background(ElasticScrollInterruption { revealRequest = nil })
                    .padding(.horizontal, ElasticLayout.tableGutter)
                    .padding(.vertical, ElasticLayout.tablePaddingTop)
                    .background {
                        ElasticMarqueeGesture(
                            session: session,
                            space: viewportSpace,
                            frames: viewportSnapshot.tiles,
                            rect: $marqueeRect
                        )
                    }
                }
                .overlay {
                    if let marqueeRect {
                        Rectangle()
                            .strokeBorder(
                                LuminaTokens.Elastic.ink,
                                style: StrokeStyle(
                                    lineWidth: ElasticLayout.shelfDropRingWidth,
                                    dash: ElasticLayout.shelfDropRingDash
                                )
                            )
                            .frame(width: marqueeRect.width, height: marqueeRect.height)
                            .position(x: marqueeRect.midX, y: marqueeRect.midY)
                            .allowsHitTesting(false)
                    }
                }
                .coordinateSpace(name: viewportSpace)
                .environment(\.elasticViewportSpace, viewportSpace)
                .onPreferenceChange(ElasticViewportFrames.self) { snapshot in
                    viewportSnapshot = snapshot
                    let wasRevealing = revealRequest != nil
                    resolveReveal(snapshot: snapshot, viewport: viewport.size, proxy: proxy)
                    if !wasRevealing, session.route == .time,
                       let anchor = ElasticViewportReveal.anchor(
                        frames: snapshot.tiles, viewport: CGRect(origin: .zero, size: viewport.size)
                       ) {
                        // Keep the last valid viewport before the table is dismantled.
                        returnAnchor = anchor
                    }
                    // Marker tracks the leading chapter; never writes focus or selection.
                    let next = ElasticChronology.activeChapter(frames: snapshot.chapters)
                    if session.chronologyViewportChapterID != next {
                        session.chronologyViewportChapterID = next
                    }
                }
                .onChange(of: session.focusedAssetID) { _, id in
                    requestReveal(id: id, position: nil, viewport: viewport.size, proxy: proxy)
                }
                .onAppear {
                    requestReveal(
                        id: returnAnchor?.id ?? session.focusedAssetID,
                        position: returnAnchor?.position, viewport: viewport.size, proxy: proxy
                    )
                }
                .onDisappear {
                    revealRequest = nil
                    viewportSnapshot = ElasticViewportSnapshot()
                }
            }
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

    /// Resolve to the exact representative this table renders, including collapsed bursts.
    private func renderedTarget(for id: UUID) -> (photo: UUID, chapter: String)? {
        for chapter in session.chapters {
            guard let burst = chapter.bursts.first(where: { $0.assetIDs.contains(id) }) else { continue }
            let open = burst.frameCount > 1
                && (session.leanedBurstID == burst.id || session.peek == .flags)
            if open, let frame = burst.frames.first(where: { $0.assetIDs.contains(id) }) {
                return (frame.coverID, chapter.id)
            }
            if let cover = burst.preferredCoverID(in: session.assets) ?? burst.coverID {
                return (cover, chapter.id)
            }
        }
        return nil
    }

    private func requestReveal(id: UUID?, position: CGFloat?, viewport: CGSize, proxy: ScrollViewProxy) {
        guard let id, let target = renderedTarget(for: id) else {
            revealRequest = nil
            return
        }
        revealRequest = ElasticViewportReveal.Request(id: target.photo, position: position)
        if viewportSnapshot.tiles[target.photo] != nil {
            resolveReveal(snapshot: viewportSnapshot, viewport: viewport, proxy: proxy)
        } else {
            // The lazy chapter is a known scroll target even before its tiles exist.
            // Resolve only when that chapter contributes its layout; native scrolling cancels.
            revealRequest?.containerID = target.chapter
            proxy.scrollTo(target.chapter)
        }
    }

    private func resolveReveal(snapshot: ElasticViewportSnapshot, viewport: CGSize, proxy: ScrollViewProxy) {
        guard var request = revealRequest else { return }
        switch request.resolve(frames: snapshot.tiles, viewport: CGRect(origin: .zero, size: viewport), realizedContainers: snapshot.containers) {
        case .wait: break
        case .finished: revealRequest = nil
        case .reveal(let id, let position):
            revealRequest = nil
            if let position {
                proxy.scrollTo(id, anchor: UnitPoint(x: UnitPoint.center.x, y: position))
            } else {
                proxy.scrollTo(id)
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

/// Chronology follows vertical scrolling; every moment gives its width to photographs.
struct ElasticMomentRow: View {
    @Bindable var session: P0SessionModel
    let chapter: ShootChapter

    var body: some View {
        // CHRON-02 — date/time lives in the pinned bar, not on each photograph band.
        ElasticWrapLayout(
            horizontalSpacing: ElasticLayout.groupGap,
            verticalSpacing: ElasticLayout.groupRowGap
        ) {
            ForEach(chapter.bursts) { burst in
                ElasticFrameGroup(session: session, burst: burst)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, ElasticLayout.momentPaddingV)
        .padding(.horizontal, ElasticLayout.momentPaddingH)
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
            ElasticWrapLayout(
                horizontalSpacing: ElasticLayout.frameGap,
                verticalSpacing: ElasticLayout.groupRowGap
            ) {
                ForEach(burst.frames) { frame in
                    ElasticFrameTile(session: session, assetID: frame.coverID, width: ElasticLayout.tileInOpenBurst)
                }
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: ElasticLayout.badgePaddingH) {
                    setButton
                    badge("fold", fill: LuminaTokens.Elastic.ink, ink: LuminaTokens.Elastic.shell)
                }
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
                ElasticFrameTile(session: session, assetID: id, width: width, showsSetButton: false)
            }
        }
        .padding(.trailing, ElasticLayout.stackPadding)
        .overlay(alignment: .topLeading) {
            setButton
                .padding(.top, ElasticLayout.badgeTop)
                .padding(.leading, ElasticLayout.markInset)
        }
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

    /// One control for the whole burst. On only when every frame is already in.
    private var setButton: some View {
        ElasticSetButton(on: session.setToggleIsOn(burst.assetIDs)) {
            session.classifySet(burst.assetIDs)
        }
    }
}

/// One frame on the table, carrying only marks the photographer made (§3.4, §4).
struct ElasticFrameTile: View {
    @Bindable var session: P0SessionModel
    let assetID: UUID
    let width: CGFloat
    var showsSetButton = true

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
        .modifier(ElasticViewportTile(id: assetID))
        .clipShape(RoundedRectangle(cornerRadius: ElasticLayout.tileRadius, style: .continuous))
        .overlay(alignment: .topLeading) {
            if showsSetButton {
                ElasticSetButton(on: inSet) {
                    session.classifySet([assetID])
                }
                .padding(ElasticLayout.markInset)
            }
        }
        .overlay(alignment: showsSetButton ? .topTrailing : .topLeading) {
            if cull == .reject {
                Text("✕")
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
            // ⇧-click range · ⌘-click toggle · click moves the cursor. The modifier
            // is read off the event, so one tap owns all three.
            let flags = NSEvent.modifierFlags
            session.clickFrame(assetID, shift: flags.contains(.shift), command: flags.contains(.command))
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
