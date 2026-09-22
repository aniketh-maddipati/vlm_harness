import SwiftUI

/// The time route — moments as rows, separated by how long the shooting stopped.
///
/// Bursts stack with their leader on top and a count badge on the stack edge; a
/// click opens the stack in place. Nothing here decides anything: marks render
/// what the photographer already said, and every mutation goes through the session.
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
                    header
                    momentScroll
                    ElasticSetShelf(session: session)
                }
            }
        }
        .background(LuminaTokens.Elastic.shell)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: LuminaTokens.Spacing.md) {
            Text(session.elasticHeaderLine)
                .font(LuminaTokens.Typeface.meta(12))
                .foregroundStyle(LuminaTokens.Elastic.inkSoft)
                .accessibilityIdentifier(P0AccessibilityID.elasticHeader)

            Spacer(minLength: LuminaTokens.Spacing.sm)

            Button {
                session.applyAutoToTable()
            } label: {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Auto")
                        .font(LuminaTokens.Typeface.meta(12, weight: .medium))
                    Text(session.autoButtonSubLabel)
                        .font(LuminaTokens.Typeface.meta(11))
                        .foregroundStyle(LuminaTokens.Elastic.muted)
                }
                .foregroundStyle(LuminaTokens.Elastic.ink)
                .padding(.horizontal, LuminaTokens.Spacing.sm)
                .padding(.vertical, LuminaTokens.Spacing.xs)
                .background(LuminaTokens.Elastic.shellAlt)
                .clipShape(RoundedRectangle(cornerRadius: ElasticLayout.chipRadius, style: .continuous))
            }
            .buttonStyle(LuminaQuietButtonStyle())
            .accessibilityIdentifier(P0AccessibilityID.elasticAutoButton)

            if session.exportCount > 0 {
                Button {
                    session.chooseAndExportKept()
                } label: {
                    Text(session.exportStatusLine ?? "Export \(session.exportCount) · ⌘E")
                        .font(LuminaTokens.Typeface.meta(12))
                        .foregroundStyle(LuminaTokens.Elastic.ink)
                        .padding(.horizontal, LuminaTokens.Spacing.sm)
                        .padding(.vertical, LuminaTokens.Spacing.xs)
                        .background(LuminaTokens.Elastic.warmAccent)
                        .clipShape(RoundedRectangle(cornerRadius: ElasticLayout.chipRadius, style: .continuous))
                }
                .buttonStyle(LuminaQuietButtonStyle())
                .disabled(session.isExporting)
            }
        }
        .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
        .frame(height: LuminaTokens.HitTarget.header)
        .background(LuminaTokens.Elastic.shell)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LuminaTokens.Elastic.muted.opacity(0.25))
                .frame(height: LuminaTokens.Line.hairlineWidth)
        }
    }

    // MARK: - Moments

    private var momentScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(session.chapters.enumerated()), id: \.element.id) { index, chapter in
                        ElasticMomentRow(session: session, chapter: chapter)
                            .id(chapter.id)

                        if let interval = session.gapInterval(after: index) {
                            gap(interval)
                        }
                    }
                }
                .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
                .padding(.vertical, LuminaTokens.Spacing.lg)
            }
            .onChange(of: session.focusedAssetID) { _, id in
                guard let id,
                      let chapter = ShootChapterArrangement.chapter(containing: id, in: session.chapters)
                else { return }
                proxy.scrollTo(chapter.id, anchor: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func gap(_ interval: TimeInterval) -> some View {
        let height = ElasticLayout.gapHeight(after: interval)
        return Group {
            if let label = ElasticLayout.gapLabel(for: interval) {
                HStack {
                    Text(label)
                        .font(LuminaTokens.Typeface.meta(11))
                        .foregroundStyle(LuminaTokens.Elastic.muted)
                    Spacer()
                }
                .frame(height: max(height, LuminaTokens.Spacing.md))
            } else {
                Spacer().frame(height: height)
            }
        }
    }
}

/// One moment: when it started, what the light was doing, and its frames.
struct ElasticMomentRow: View {
    @Bindable var session: P0SessionModel
    let chapter: ShootChapter

    var body: some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.sm) {
            header
            frames
        }
        .padding(.vertical, LuminaTokens.Spacing.sm)
    }

    private var header: some View {
        HStack(spacing: LuminaTokens.Spacing.sm) {
            Text(session.momentTimeLabel(chapter))
                .font(LuminaTokens.Typeface.meta(12, weight: .medium))
                .foregroundStyle(LuminaTokens.Elastic.ink)
            Text(session.momentLightWord(chapter))
                .font(LuminaTokens.Typeface.meta(11))
                .foregroundStyle(LuminaTokens.Elastic.muted)
            Text(session.momentCountLine(chapter))
                .font(LuminaTokens.Typeface.meta(11))
                .foregroundStyle(LuminaTokens.Elastic.muted)
            Spacer()
        }
    }

    private var frames: some View {
        let tile = session.leanedBurstID == nil
            ? ElasticLayout.tile
            : ElasticLayout.tileInOpenBurst
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: tile), spacing: LuminaTokens.Spacing.sm)],
            alignment: .leading,
            spacing: LuminaTokens.Spacing.sm
        ) {
            ForEach(chapter.bursts) { burst in
                if session.leanedBurstID == burst.id {
                    ForEach(burst.frames) { frame in
                        ElasticFrameTile(session: session, assetID: frame.coverID, side: tile)
                    }
                } else {
                    ElasticBurstStack(session: session, burst: burst, side: tile)
                }
            }
        }
    }
}

/// A burst at rest: leader on top, count badge on the stack edge.
struct ElasticBurstStack: View {
    @Bindable var session: P0SessionModel
    let burst: ShootBurst
    let side: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if burst.frameCount > 1 {
                // The stack edge — two slivers behind the leader, nothing more.
                RoundedRectangle(cornerRadius: ElasticLayout.tileRadius, style: .continuous)
                    .fill(LuminaTokens.Elastic.shellAlt)
                    .frame(width: side, height: side * 0.72)
                    .offset(x: 6, y: 6)
                RoundedRectangle(cornerRadius: ElasticLayout.tileRadius, style: .continuous)
                    .fill(LuminaTokens.Elastic.matte.opacity(0.35))
                    .frame(width: side, height: side * 0.72)
                    .offset(x: 3, y: 3)
            }

            if let coverID = burst.preferredCoverID(in: session.assets) ?? burst.coverID {
                ElasticFrameTile(session: session, assetID: coverID, side: side)
            }

            if burst.frameCount > 1 {
                Text("\(burst.frameCount)")
                    .font(LuminaTokens.Typeface.meta(11, weight: .medium))
                    .foregroundStyle(LuminaTokens.Elastic.ink)
                    .padding(.horizontal, LuminaTokens.Spacing.xs)
                    .padding(.vertical, 2)
                    .background(LuminaTokens.Elastic.shell)
                    .clipShape(Capsule())
                    .padding(LuminaTokens.Spacing.xs)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            session.toggleBurstOpen(burst.id)
        }
    }
}

/// One frame on the table, carrying only marks the photographer made.
struct ElasticFrameTile: View {
    @Bindable var session: P0SessionModel
    let assetID: UUID
    let side: CGFloat

    private var asset: AssetRecord? {
        session.assets.first(where: { $0.id == assetID })
    }

    var body: some View {
        let asset = asset
        let isFocused = session.focusedAssetID == assetID
        let isSelected = session.selectedAssetIDs.contains(assetID)
        let inSet = session.isInFinalSet(assetID)
        let cull = asset?.cull ?? .undecided

        return ZStack(alignment: .topLeading) {
            Group {
                if let path = asset?.gridThumbPath ?? asset?.thumbPath {
                    ChapterPlateImage(path: path)
                } else {
                    LuminaTokens.Elastic.shellAlt
                }
            }
            .frame(width: side, height: side * 0.72)
            .clipShape(RoundedRectangle(cornerRadius: ElasticLayout.tileRadius, style: .continuous))
            .opacity(cull == .reject ? ElasticLayout.outOpacity : 1)

            marks(cull: cull, asset: asset)
        }
        .overlay {
            RoundedRectangle(cornerRadius: ElasticLayout.tileRadius, style: .continuous)
                .strokeBorder(
                    inSet ? LuminaTokens.Elastic.warmAccent : .clear,
                    lineWidth: ElasticLayout.setOutlineWidth
                )
        }
        .overlay {
            if isFocused || isSelected {
                RoundedRectangle(cornerRadius: ElasticLayout.tileRadius, style: .continuous)
                    .strokeBorder(LuminaTokens.Elastic.ink, lineWidth: ElasticLayout.focusRingWidth)
                    .overlay {
                        RoundedRectangle(cornerRadius: ElasticLayout.tileRadius, style: .continuous)
                            .strokeBorder(
                                LuminaTokens.Elastic.shellAlt,
                                lineWidth: ElasticLayout.focusRingHaloWidth
                            )
                            .padding(-ElasticLayout.focusRingWidth)
                    }
            }
        }
        .contentShape(Rectangle())
        .accessibilityIdentifier(P0AccessibilityID.elasticTile(assetID))
        .onTapGesture(count: 2) {
            session.setFocus(assetID)
            session.openFocusedPhotograph()
        }
        .onTapGesture {
            session.setFocus(assetID)
        }
    }

    @ViewBuilder
    private func marks(cull: CullDecision, asset: AssetRecord?) -> some View {
        HStack(spacing: LuminaTokens.Spacing.xs) {
            switch cull {
            case .keep:
                chip("✓", tint: LuminaTokens.Elastic.ok)
            case .reject:
                chip("✕", tint: LuminaTokens.Elastic.warn)
            case .undecided, .hold:
                EmptyView()
            }
            if asset?.recipeSource == .auto || asset?.recipeSource == .autoHand {
                chip("auto", tint: LuminaTokens.Elastic.shellAlt)
            }
        }
        .padding(LuminaTokens.Spacing.xs)
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(LuminaTokens.Typeface.meta(11))
            .foregroundStyle(LuminaTokens.Elastic.ink)
            .padding(.horizontal, LuminaTokens.Spacing.xs)
            .padding(.vertical, 1)
            .background(tint)
            .clipShape(Capsule())
    }
}

/// The kept set, along the bottom. A drop target in a later checkpoint.
struct ElasticSetShelf: View {
    @Bindable var session: P0SessionModel

    var body: some View {
        HStack(spacing: LuminaTokens.Spacing.sm) {
            Text(session.setShelfLabel)
                .font(LuminaTokens.Typeface.meta(11))
                .foregroundStyle(LuminaTokens.Elastic.muted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LuminaTokens.Spacing.xs) {
                    ForEach(session.finalSetAssetIDs, id: \.self) { id in
                        ElasticFrameTile(
                            session: session,
                            assetID: id,
                            side: ElasticLayout.filmstripTile.width
                        )
                    }
                }
            }
        }
        .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
        .frame(height: ElasticLayout.setShelfHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LuminaTokens.Elastic.shellAlt)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LuminaTokens.Elastic.muted.opacity(0.25))
                .frame(height: LuminaTokens.Line.hairlineWidth)
        }
    }
}
