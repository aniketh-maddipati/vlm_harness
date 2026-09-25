import AppKit
import SwiftUI

/// The time route — moments as rows, separated by how long the shooting stopped.
///
/// Bursts stack with their leader on top and a count badge on the stack edge; the
/// badge opens the stack in place. Pointer on a plate travels. A second press on
/// the focused plate is P. Lead and trail of that burst are facts.
/// `set`, `phone`, and `out` sit on the burst — operations larger than one frame.
struct ElasticTableView: View {
    @Bindable var session: P0SessionModel
    @State private var viewportSpace = UUID()
    @State private var viewportSnapshot = ElasticViewportSnapshot()
    @State private var returnAnchor: ElasticViewportReveal.Anchor?
    @State private var revealRequest: ElasticViewportReveal.Request?

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
                burstOperations(
                    fold: ("fold", LuminaTokens.Elastic.ink, LuminaTokens.Elastic.shell)
                )
                .padding(.top, ElasticLayout.badgeTop)
                .padding(.trailing, ElasticLayout.badgeInsideOpen)
            }
        } else if isBurst {
            stacked
        } else if let id = leaderID {
            ElasticFrameTile(session: session, assetID: id, width: ElasticLayout.tile)
                .overlay(alignment: .topTrailing) {
                    outButton
                        .padding(.top, ElasticLayout.badgeTop)
                        .padding(.trailing, ElasticLayout.badgeOutsideStack)
                }
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
            burstOperations(
                fold: ("×\(burst.frameCount)", LuminaTokens.Elastic.shell, LuminaTokens.Elastic.ink)
            )
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

    /// `set`, `phone`, and `out` act on the whole run. Fold / ×N only opens or closes it.
    private func burstOperations(fold: (String, Color, Color)) -> some View {
        HStack(spacing: ElasticLayout.badgePaddingH) {
            ElasticOperationButton(
                title: "set",
                on: session.setToggleIsOn(burst.assetIDs)
            ) {
                session.classifySet(burst.assetIDs)
            }
            ElasticOperationButton(
                title: "phone",
                on: !burst.assetIDs.isEmpty && burst.assetIDs.allSatisfy(session.isPhoneFrame)
            ) {
                session.classifyPhone(burst.assetIDs)
            }
            outButton
            badge(fold.0, fill: fold.1, ink: fold.2)
        }
    }

    /// Pointer reject — a settled word, never a chip on the photograph. A travel
    /// click cannot land here. Keyboard X still rejects the focused frame.
    private var outButton: some View {
        let holdsCursor = session.focusedAssetID.map { burst.assetIDs.contains($0) } ?? false
        return ElasticOperationButton(
            title: "out",
            on: session.outToggleIsOn(burst.assetIDs)
        ) {
            session.classifyOut(burst.assetIDs)
        }
        .accessibilityIdentifier(holdsCursor ? P0AccessibilityID.pointerCullReject : P0AccessibilityID.elasticOut)
    }
}

/// One frame on the table. The plate travels; the focused plate keeps.
struct ElasticFrameTile: View {
    @Bindable var session: P0SessionModel
    let assetID: UUID
    let width: CGFloat

    private var asset: AssetRecord? {
        session.asset(assetID)
    }

    private var focused: Bool { session.focusedAssetID == assetID }
    private var ringed: Bool { focused || session.selectedAssetIDs.contains(assetID) }
    private var inSet: Bool { session.isInFinalSet(assetID) }
    private var sequence: ElasticSequenceMark? { session.sequenceMark(for: assetID) }
    private var isPhone: Bool { session.isPhoneFrame(assetID) }
    private var cull: CullDecision { asset?.cull ?? .undecided }
    private var height: CGFloat { width / ElasticLayout.tileAspect }

    var body: some View {
        plate
        .frame(width: width, height: height)
        .elasticMarked(
            radius: ElasticLayout.tileRadius,
            ringed: ringed,
            inSet: inSet,
            sequence: sequence
        )
        .opacity(cull == .reject && asset?.isUnsupportedVideo != true ? ElasticLayout.outOpacity : 1)
        .draggable(ElasticDragPayload.encode(
            ElasticDragPayload.ids(forDragging: assetID, selection: session.selectedAssetIDs)
        ))
    }

    private var plate: some View {
        ElasticPlateButton {
            let flags = NSEvent.modifierFlags
            session.clickTablePlate(assetID, shift: flags.contains(.shift), command: flags.contains(.command))
        } onDoubleTap: {
            session.setFocus(assetID)
            session.openFocusedPhotograph()
        } label: {
            ZStack {
                LuminaTokens.Elastic.deep
                if asset?.isUnsupportedVideo == true {
                    LuminaTokens.Elastic.shelfThumbFill
                } else if let path = asset?.gridThumbPath ?? asset?.thumbPath {
                    ChapterPlateImage(path: path)
                }
            }
            .frame(width: width, height: height)
            .modifier(ElasticViewportTile(id: assetID))
            .clipShape(RoundedRectangle(cornerRadius: ElasticLayout.tileRadius, style: .continuous))
            .overlay(alignment: .topLeading) {
                if let sequence {
                    ElasticSequenceChip(mark: sequence)
                        .padding(ElasticLayout.markInset)
                }
            }
            .overlay(alignment: .topTrailing) {
                if !focused, cull == .reject {
                    Text("✕")
                        .font(.system(size: ElasticLayout.markTextSize, weight: .bold))
                        .foregroundStyle(LuminaTokens.Elastic.shell)
                        .frame(width: ElasticLayout.markSize, height: ElasticLayout.markSize)
                        .background(LuminaTokens.Elastic.ink, in: Circle())
                        .padding(ElasticLayout.markInset)
                        .allowsHitTesting(false)
                } else if isPhone {
                    ElasticPhoneGlyph(isOn: true)
                        .padding(ElasticLayout.markInset)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if asset?.isUnsupportedVideo == true {
                    ElasticFlagChip(text: CopyContract.videoNotOpenedYet)
                        .padding(ElasticLayout.markInset)
                } else if let flags = session.flagLine(for: assetID) {
                    ElasticFlagChip(text: flags).padding(ElasticLayout.markInset)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(P0AccessibilityID.elasticTile(assetID))
        .accessibilityLabel(asset?.isUnsupportedVideo == true ? CopyContract.videoNotOpenedYet : "photograph")
    }
}

/// Warm phone mark. A fact. The burst `phone` operation is what writes the run.
struct ElasticPhoneGlyph: View {
    var isOn: Bool = true

    var body: some View {
        RoundedRectangle(cornerRadius: ElasticLayout.phoneGlyphRadius, style: .continuous)
            .fill(isOn ? LuminaTokens.Elastic.warmAccent : LuminaTokens.Elastic.shell)
            .overlay {
                RoundedRectangle(cornerRadius: ElasticLayout.phoneGlyphRadius, style: .continuous)
                    .strokeBorder(LuminaTokens.Elastic.ink, lineWidth: ElasticLayout.phoneGlyphStroke)
            }
            .frame(
                width: ElasticLayout.phoneGlyph.width + 2 * ElasticLayout.phoneGlyphStroke,
                height: ElasticLayout.phoneGlyph.height + 2 * ElasticLayout.phoneGlyphStroke
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
