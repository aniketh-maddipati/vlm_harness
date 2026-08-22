import SwiftUI

/// Three-band chapter table — time rail, one chapter of burst plates, empty kept rail.
struct P0ChapterTableView: View {
    @Bindable var session: P0SessionModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            chapterRail
                .frame(width: 168)
            chapterBoard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            keptRail
                .frame(width: 160)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LuminaTokens.Surface.mist)
        .onAppear { session.prefetchChapterCovers() }
        .onChange(of: session.activeChapterID) { _, _ in
            session.prefetchChapterCovers()
        }
    }

    private var chapterRail: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(session.chapters) { chapter in
                    let active = chapter.id == session.activeChapter?.id
                    Button {
                        session.selectChapter(chapter.id)
                    } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .fill(active ? LuminaTokens.Ink.primary : Color.clear)
                                .frame(width: 2, height: 28)
                            Text(chapterLabel(chapter))
                                .font(LuminaTokens.Typeface.editorial(active ? 34 : 26))
                                .foregroundStyle(active ? LuminaTokens.Ink.primary : LuminaTokens.Ink.tertiary)
                                .frame(maxWidth: .infinity, minHeight: LuminaTokens.HitTarget.minimum, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(LuminaQuietButtonStyle())
                    .accessibilityIdentifier(P0AccessibilityID.chapterMark(chapter.id))
                    .accessibilityLabel(chapterLabel(chapter))
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
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

    private var chapterBoard: some View {
        GeometryReader { geo in
            let bursts = session.activeChapter?.bursts ?? []
            let byID = Dictionary(uniqueKeysWithValues: session.assets.map { ($0.id, $0) })
            if bursts.isEmpty {
                Color.clear
            } else {
                let columns = max(1, min(session.densityColumns, bursts.count))
                let spacing: CGFloat = 22
                let rows = max(1, Int(ceil(Double(bursts.count) / Double(columns))))
                let availableHeight = geo.size.height - 40
                let fitted = (availableHeight - spacing * CGFloat(rows - 1)) / CGFloat(rows)
                let plateHeight = min(240, max(96, fitted))
                let allowScroll = fitted < 96

                let grid = LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: spacing),
                        count: columns
                    ),
                    alignment: .leading,
                    spacing: spacing
                ) {
                    ForEach(bursts) { burst in
                        if let asset = coverAsset(for: burst, byID: byID) {
                            BurstPlate(
                                assetID: asset.id,
                                filename: asset.filename,
                                imagePath: asset.gridThumbPath ?? asset.thumbPath,
                                count: burst.frameCount,
                                isFocused: session.focusedAssetID.map { burst.assetIDs.contains($0) } ?? false,
                                isRejected: asset.cull == .reject,
                                isKept: asset.cull == .keep
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
                }
                .padding(20)

                Group {
                    if allowScroll {
                        ScrollView { grid }
                    } else {
                        grid
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .id(session.activeChapterID)
                .transition(
                    reduceMotion
                        ? .identity
                        : .asymmetric(insertion: .offset(y: 14), removal: .offset(y: -10))
                )
                .animation(reduceMotion ? nil : LuminaTokens.Motion.travel, value: session.activeChapterID)
            }
        }
    }

    private var keptRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kept")
                .font(LuminaTokens.Typeface.editorial(22))
                .foregroundStyle(LuminaTokens.Ink.tertiary.opacity(0.7))
            Spacer(minLength: 0)
        }
        .padding(.top, 36)
        .padding(.horizontal, LuminaTokens.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LuminaTokens.Surface.porcelain)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(LuminaTokens.Line.hairline)
                .frame(width: LuminaTokens.Line.hairlineWidth)
        }
        .accessibilityLabel("Kept")
    }

    private func chapterLabel(_ chapter: ShootChapter) -> String {
        guard let startedAt = chapter.startedAt else { return "—" }
        return CopyContractBuilder.laneTimestamp(from: startedAt)
    }

    private func coverAsset(for burst: ShootBurst, byID: [UUID: AssetRecord]) -> AssetRecord? {
        burst.preferredCoverID(in: session.assets).flatMap { byID[$0] }
    }
}

private struct BurstPlate: View {
    let assetID: UUID
    let filename: String
    let imagePath: String?
    let count: Int
    let isFocused: Bool
    let isRejected: Bool
    let isKept: Bool
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
