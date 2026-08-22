import SwiftUI

/// Three-band chapter table — chronology rod, one chapter of burst plates, kept rail.
struct P0ChapterTableView: View {
    @Bindable var session: P0SessionModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var travel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            chronologyRod
                .frame(width: 156)
            chapterBoard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            keptRail
                .frame(width: 168)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LuminaTokens.Surface.mist)
        .onAppear { session.prefetchChapterCovers() }
        .onChange(of: session.activeChapterID) { _, _ in
            session.prefetchChapterCovers()
        }
        .overlay {
            if session.holdingLoupe {
                loupeOverlay
            }
        }
    }

    private var chronologyRod: some View {
        let marks = ChapterRodLayout.marks(for: session.chapters)
        return ScrollView(showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                rodSpine(marks: marks)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(marks.enumerated()), id: \.element.id) { _, mark in
                        if let chapter = session.chapters.first(where: { $0.id == mark.chapterID }) {
                            rodMark(chapter: chapter, mark: mark)
                            if mark.spacingAfter > 0 {
                                elapsedGap(mark)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 36)
            .padding(.trailing, LuminaTokens.Spacing.sm)
            .padding(.leading, LuminaTokens.Spacing.md)
            .padding(.bottom, LuminaTokens.Spacing.xxl)
        }
        .background(LuminaTokens.Surface.porcelain)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(LuminaTokens.Line.hairline)
                .frame(width: LuminaTokens.Line.hairlineWidth)
        }
    }

    private func rodSpine(marks: [ChapterRodLayout.Mark]) -> some View {
        let activeID = session.activeChapter?.id
        return ZStack(alignment: .top) {
            Capsule(style: .continuous)
                .fill(LuminaTokens.Ink.primary.opacity(0.14))
                .frame(width: 2)
                .padding(.vertical, 10)
            VStack(spacing: 0) {
                ForEach(marks) { mark in
                    let active = mark.chapterID == activeID
                    Circle()
                        .fill(active ? LuminaTokens.Ink.primary : LuminaTokens.Surface.porcelain)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    LuminaTokens.Ink.primary.opacity(active ? 1 : 0.35),
                                    lineWidth: active ? 0 : 1.5
                                )
                        }
                        .frame(width: active ? 11 : 7, height: active ? 11 : 7)
                        .padding(.top, active ? 16 : 18)
                    if mark.spacingAfter > 0 {
                        Spacer()
                            .frame(height: mark.spacingAfter)
                    }
                }
            }
        }
        .frame(width: 12)
    }

    private func rodMark(chapter: ShootChapter, mark: ChapterRodLayout.Mark) -> some View {
        let active = chapter.id == session.activeChapter?.id
        return Button {
            session.walkingKeptRail = false
            session.selectChapter(chapter.id)
        } label: {
            Text(chapterLabel(chapter))
                .font(LuminaTokens.Typeface.editorial(active ? 36 : 20))
                .foregroundStyle(active ? LuminaTokens.Ink.primary : LuminaTokens.Ink.tertiary)
                .frame(maxWidth: .infinity, minHeight: LuminaTokens.HitTarget.minimum, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(LuminaQuietButtonStyle())
        .accessibilityIdentifier(P0AccessibilityID.chapterMark(chapter.id))
        .accessibilityLabel(chapterLabel(chapter))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func elapsedGap(_ mark: ChapterRodLayout.Mark) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(height: mark.spacingAfter)
            if let label = ChapterRodLayout.elapsedLabel(seconds: mark.gapAfter) {
                Text(label)
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.tertiary.opacity(0.8))
                    .padding(.top, 2)
            }
        }
    }

    private var chapterBoard: some View {
        GeometryReader { geo in
            let chapter = session.activeChapter
            let leaned = session.leanedBurst
            let plateItems = boardItems(in: chapter, leaned: leaned)
            if plateItems.isEmpty {
                Color.clear
            } else {
                let leanedColumns = session.densityLeaned ? session.densityColumns : nil
                let pack = ChapterPack.columns(
                    count: plateItems.count,
                    width: geo.size.width - 40,
                    height: geo.size.height - 40,
                    leanedColumns: leanedColumns
                )
                let grid = LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: ChapterPack.spacing),
                        count: pack.columns
                    ),
                    alignment: .leading,
                    spacing: ChapterPack.spacing
                ) {
                    ForEach(plateItems) { item in
                        boardCell(item, plateHeight: pack.plateHeight)
                    }
                }
                .padding(20)
                .animation(reduceMotion ? nil : LuminaTokens.Motion.travel, value: plateItems.map(\.id))

                Group {
                    if pack.allowScroll {
                        ScrollView { grid }
                    } else {
                        grid
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .id(session.leanedBurstID ?? session.activeChapterID)
                .transition(
                    reduceMotion
                        ? .identity
                        : .asymmetric(insertion: .offset(y: 14), removal: .offset(y: -12))
                )
                .animation(reduceMotion ? nil : LuminaTokens.Motion.travel, value: session.activeChapterID)
                .animation(reduceMotion ? nil : LuminaTokens.Motion.travel, value: session.leanedBurstID)
                .animation(reduceMotion ? nil : LuminaTokens.Motion.travel, value: session.lookGlancing)
                .gesture(leanPinch)
            }
        }
    }

    private var leanPinch: some Gesture {
        MagnificationGesture()
            .onEnded { value in
                if value > 1.12 {
                    session.activateFocusedPhotograph()
                }
            }
    }

    private func boardItems(in chapter: ShootChapter?, leaned: ShootBurst?) -> [BoardItem] {
        let byID = Dictionary(uniqueKeysWithValues: session.assets.map { ($0.id, $0) })
        if let leaned {
            return leaned.frames.compactMap { frame in
                guard let asset = byID[frame.coverID] else { return nil }
                return BoardItem(id: frame.id, kind: .frame(frame, asset))
            }
        }
        guard let chapter else { return [] }
        return session.displayedBursts(in: chapter).compactMap { burst in
            switch burst.boardRole(in: session.assets) {
            case .gone:
                return nil
            case .hole:
                return BoardItem(id: burst.id, kind: .hole(burst))
            case .plate:
                guard let asset = coverAsset(for: burst, byID: byID) else { return nil }
                return BoardItem(id: burst.id, kind: .burst(burst, asset))
            }
        }
    }

    @ViewBuilder
    private func boardCell(_ item: BoardItem, plateHeight: CGFloat) -> some View {
        switch item.kind {
        case .hole(let burst):
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(LuminaTokens.Ink.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(minHeight: plateHeight)
                .frame(maxWidth: .infinity)
                .matchedGeometryEffect(id: burst.id, in: travel)
        case .burst(let burst, let asset):
            BurstPlate(
                assetID: asset.id,
                filename: asset.filename,
                imagePath: asset.gridThumbPath ?? asset.thumbPath,
                count: burst.frameCount,
                isFocused: session.focusedAssetID.map { burst.assetIDs.contains($0) } ?? false,
                isRejected: asset.cull == .reject,
                isKept: asset.cull == .keep,
                showClipping: session.holdingClipping
            ) {
                session.walkingKeptRail = false
                session.setFocus(asset.id)
            } onOpen: {
                session.setFocus(asset.id)
                session.activateFocusedPhotograph()
            } onKeep: {
                session.setFocus(asset.id)
                session.pointerMarkKeep()
            } onReject: {
                session.setFocus(asset.id)
                session.pointerMarkReject()
            }
            .frame(minHeight: plateHeight)
            .frame(maxWidth: .infinity)
            .transition(reduceMotion ? .identity : .offset(x: -36, y: 14))
        case .frame(let frame, let asset):
            BurstPlate(
                assetID: asset.id,
                filename: asset.filename,
                imagePath: asset.gridThumbPath ?? asset.thumbPath,
                count: 1,
                isFocused: session.focusedAssetID == asset.id,
                isRejected: asset.cull == .reject,
                isKept: asset.cull == .keep,
                showClipping: session.holdingClipping
            ) {
                session.setFocus(asset.id)
            } onOpen: {
                session.setFocus(asset.id)
                session.openFocusedPhotograph()
            } onKeep: {
                session.setFocus(asset.id)
                session.pointerMarkKeep()
            } onReject: {
                session.setFocus(asset.id)
                session.pointerMarkReject()
            }
            .frame(minHeight: plateHeight)
            .frame(maxWidth: .infinity)
        }
    }

    private var keptRail: some View {
        let kept = session.keptRailAssets
        return VStack(alignment: .leading, spacing: 10) {
            Text("Kept")
                .font(LuminaTokens.Typeface.editorial(22))
                .foregroundStyle(LuminaTokens.Ink.tertiary.opacity(0.7))
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(kept, id: \.id) { asset in
                        keptPlate(asset)
                    }
                }
            }
        }
        .padding(.top, 36)
        .padding(.horizontal, LuminaTokens.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(session.walkingKeptRail ? LuminaTokens.Surface.mist : LuminaTokens.Surface.porcelain)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(LuminaTokens.Line.hairline)
                .frame(width: LuminaTokens.Line.hairlineWidth)
        }
        .accessibilityLabel("Kept")
    }

    private func keptPlate(_ asset: AssetRecord) -> some View {
        let focused = session.walkingKeptRail && session.focusedAssetID == asset.id
        return Button {
            session.focusKeptAsset(asset.id)
        } label: {
            ZStack {
                if let path = asset.gridThumbPath ?? asset.thumbPath {
                    ChapterPlateImage(path: path)
                } else {
                    Rectangle().fill(LuminaTokens.Surface.well)
                }
            }
            .frame(height: 92)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        focused ? LuminaTokens.Ink.primary : Color.clear,
                        lineWidth: focused ? 1.5 : 0
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(LuminaPlatePressStyle())
        .matchedGeometryEffect(id: travelID(for: asset), in: travel)
        .accessibilityIdentifier(P0AccessibilityID.filmstripItem(asset.id))
        .accessibilityLabel(asset.filename)
    }

    private var loupeOverlay: some View {
        let path = focusedImagePath
        return ZStack {
            LuminaTokens.Surface.mist.opacity(0.55)
            if let path {
                ChapterPlateImage(path: path)
                    .overlay {
                        if session.holdingClipping {
                            Color.red.blendMode(.difference).opacity(0.28)
                        }
                    }
                    .frame(maxWidth: 720, maxHeight: 720)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .allowsHitTesting(false)
        .transition(reduceMotion ? .identity : .offset(y: 10))
    }

    private var focusedImagePath: String? {
        guard let id = session.focusedAssetID,
              let asset = session.assets.first(where: { $0.id == id })
        else { return nil }
        return asset.thumbPath ?? asset.gridThumbPath
    }

    private func travelID(for asset: AssetRecord) -> String {
        if let burst = session.chapters.flatMap(\.bursts).first(where: { $0.assetIDs.contains(asset.id) }),
           burst.coverID == asset.id || burst.preferredCoverID(in: session.assets) == asset.id {
            return burst.id
        }
        return asset.id.uuidString
    }

    private func chapterLabel(_ chapter: ShootChapter) -> String {
        guard let startedAt = chapter.startedAt else { return "—" }
        return CopyContractBuilder.laneTimestamp(from: startedAt)
    }

    private func coverAsset(for burst: ShootBurst, byID: [UUID: AssetRecord]) -> AssetRecord? {
        burst.preferredCoverID(in: session.assets).flatMap { byID[$0] }
    }
}

private struct BoardItem: Identifiable {
    enum Kind {
        case burst(ShootBurst, AssetRecord)
        case hole(ShootBurst)
        case frame(ShootFrame, AssetRecord)
    }

    var id: String
    var kind: Kind
}

private struct BurstPlate: View {
    let assetID: UUID
    let filename: String
    let imagePath: String?
    let count: Int
    let isFocused: Bool
    let isRejected: Bool
    let isKept: Bool
    let showClipping: Bool
    let onFocus: () -> Void
    let onOpen: () -> Void
    let onKeep: () -> Void
    let onReject: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Button(action: onFocus) {
                ZStack(alignment: .bottomTrailing) {
                    plateImage
                        .opacity(isRejected ? 0.42 : 1)
                    if count > 1 {
                        Text("\(count)")
                            .font(LuminaTokens.Typeface.editorial(20))
                            .foregroundStyle(LuminaTokens.Ink.primary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(LuminaTokens.Surface.porcelain.opacity(0.94))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .padding(8)
                    }
                    if isKept {
                        Text("✓")
                            .font(LuminaTokens.Typeface.navigation(13, weight: .semibold))
                            .foregroundStyle(LuminaTokens.Ink.primary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(LuminaTokens.Surface.porcelain.opacity(0.94))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LuminaTokens.Surface.well)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            isFocused ? LuminaTokens.Ink.primary : Color.clear,
                            lineWidth: isFocused ? 1.5 : 0
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(LuminaPlatePressStyle())
            .simultaneousGesture(
                TapGesture(count: 2).onEnded { onOpen() }
            )
            .accessibilityIdentifier(P0AccessibilityID.assetCell(assetID))
            .accessibilityLabel(filename)
            .accessibilityAddTraits(isFocused ? .isSelected : [])

            if isFocused {
                HStack(spacing: 8) {
                    pointerMark(symbol: "✓", key: "P", action: onKeep)
                        .accessibilityIdentifier(P0AccessibilityID.pointerCullKeep)
                        .accessibilityLabel("Keep")
                    pointerMark(symbol: "✕", key: "X", action: onReject)
                        .accessibilityIdentifier(P0AccessibilityID.pointerCullReject)
                        .accessibilityLabel("Reject")
                }
                .padding(8)
            }
        }
    }

    @ViewBuilder
    private var plateImage: some View {
        if let imagePath {
            ChapterPlateImage(path: imagePath)
                .overlay {
                    if showClipping && isFocused {
                        Color.red.blendMode(.difference).opacity(0.3)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Rectangle()
                .fill(LuminaTokens.Surface.well)
        }
    }

    private func pointerMark(symbol: String, key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(symbol)
                    .font(LuminaTokens.Typeface.navigation(16, weight: .bold))
                Text(key)
                    .font(LuminaTokens.Typeface.meta(11, weight: .semibold))
            }
            .foregroundStyle(LuminaTokens.Ink.inspection)
            .frame(width: LuminaTokens.HitTarget.minimum, height: LuminaTokens.HitTarget.minimum)
            .background(LuminaTokens.Ink.primary.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(LuminaPlatePressStyle())
    }
}
