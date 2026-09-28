import AppKit
import SwiftUI

/// The time route — moments as rows, separated by how long the shooting stopped.
///
/// Capture headings scroll above the photographs. Burst controls live in captions,
/// outside the image, and actions appear only for bursts containing a selection.
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
        !session.chapters.isEmpty
    }

    private var momentScroll: some View {
        GeometryReader { viewport in
          ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: 0) {
                if showsChronologyBar {
                    // The elastic time axis stays beside the clean, full-width moment rows.
                    ElasticChronologyBar(
                        chapters: session.chapters,
                        activeID: session.chronologyViewportChapterID,
                        orientation: .vertical,
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
                .onChange(of: session.momentPageRequest) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id, anchor: .top)
                    session.momentPageRequest = nil
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
        VStack(alignment: .leading, spacing: ElasticLayout.momentGap) {
            if session.peek != .set {
                HStack(spacing: ElasticLayout.chipGap) {
                    Text("•")
                        .accessibilityHidden(true)
                    Text(ElasticChronology.label(for: chapter))
                }
                .font(ElasticType.mono(ElasticLayout.momentTimeSize))
                .foregroundStyle(LuminaTokens.Elastic.paper)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("p0.chronology.\(chapter.id)")
            }
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
    }
}

/// One burst (or a single frame). The count/fold caption remains available;
/// selecting a photo reveals actions for its burst below the photographs.
struct ElasticFrameGroup: View {
    @Bindable var session: P0SessionModel
    let burst: ShootBurst

    private var isBurst: Bool { burst.frameCount > 1 }
    /// The flags peek (`shiftTable`) opens every burst at once; otherwise a stack opens by its badge.
    private var isOpen: Bool { isBurst && (session.leanedBurstID == burst.id || session.peek == .flags) }

    private var hasSelection: Bool {
        burst.assetIDs.contains { session.selectedAssetIDs.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ElasticLayout.frameGap) {
            if isOpen {
                ElasticWrapLayout(
                    horizontalSpacing: ElasticLayout.frameGap,
                    verticalSpacing: ElasticLayout.groupRowGap
                ) {
                    ForEach(burst.frames) { frame in
                        ElasticFrameTile(session: session, assetID: frame.coverID, width: ElasticLayout.tileInOpenBurst)
                    }
                }
            } else if isBurst {
                stacked
            } else if let id = leaderID {
                ElasticFrameTile(session: session, assetID: id, width: ElasticLayout.tile)
            }
            if hasSelection || isBurst {
                caption
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
    }

    /// A card behind the leader: `left: dx; top: dy; right: 0 (of the leader)`.
    private func card(width: CGFloat, height: CGFloat, offset: CGSize, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: ElasticLayout.tileRadius, style: .continuous)
            .fill(LuminaTokens.Elastic.shellAlt.opacity(opacity))
            .frame(width: width - offset.width, height: height)
            .offset(x: offset.width, y: offset.height)
    }

    /// Actions retain whole-burst scope, including when a single member is selected.
    private var caption: some View {
        ElasticWrapLayout(
            horizontalSpacing: ElasticLayout.badgePaddingH,
            verticalSpacing: ElasticLayout.frameGap
        ) {
            if hasSelection {
                ElasticOperationButton(
                    title: "Keep",
                    on: session.setToggleIsOn(burst.assetIDs)
                ) {
                    session.classifySet(burst.assetIDs)
                }
                ElasticOperationButton(
                    title: "Phone",
                    on: !burst.assetIDs.isEmpty && burst.assetIDs.allSatisfy(session.isPhoneFrame)
                ) {
                    session.classifyPhone(burst.assetIDs)
                }
                ElasticOperationButton(
                    title: "Reject",
                    on: session.outToggleIsOn(burst.assetIDs)
                ) {
                    session.classifyOut(burst.assetIDs)
                }
                .accessibilityIdentifier(
                    session.focusedAssetID.map { burst.assetIDs.contains($0) } == true
                        ? P0AccessibilityID.pointerCullReject
                        : "p0.burst.reject.\(burst.id)"
                )
            }
            if isBurst {
                ElasticOperationButton(
                    title: isOpen ? "fold" : "×\(burst.frameCount)",
                    on: isOpen
                ) {
                    session.toggleBurstOpen(burst.id)
                }
            }
        }
        .frame(maxWidth: isOpen ? nil : ElasticLayout.tile + ElasticLayout.stackPadding, alignment: .leading)
    }
}

/// One frame on the table. Selection and kept-set membership have distinct marks.
struct ElasticFrameTile: View {
    @Bindable var session: P0SessionModel
    let assetID: UUID
    let width: CGFloat

    private var asset: AssetRecord? {
        session.asset(assetID)
    }

    private var focused: Bool { session.focusedAssetID == assetID }
    private var selected: Bool { session.selectedAssetIDs.contains(assetID) }
    private var inSet: Bool { session.isInFinalSet(assetID) }
    private var cull: CullDecision { asset?.cull ?? .undecided }
    private var height: CGFloat { width / ElasticLayout.tileAspect }

    var body: some View {
        VStack(alignment: .leading, spacing: ElasticLayout.frameGap) {
            plate
                .frame(width: width, height: height)
                .elasticMarked(radius: ElasticLayout.tileRadius, ringed: selected, inSet: inSet)
            Text("Focused")
                .font(ElasticType.mono(ElasticLayout.badgeTextSize))
                .foregroundStyle(LuminaTokens.Elastic.paper)
                .opacity(focused ? 1 : 0)
                .accessibilityHidden(true)
        }
        .opacity(cull == .reject && asset?.isUnsupportedVideo != true ? ElasticLayout.outOpacity : 1)
        .draggable(ElasticDragPayload.encode(
            ElasticDragPayload.ids(forDragging: assetID, selection: session.selectedAssetIDs)
        ))
    }

    private var plate: some View {
        ElasticPlateButton { flags in
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
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(focused ? "Focused" : "")
    }
}
