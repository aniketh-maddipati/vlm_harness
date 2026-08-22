import SwiftUI

/// Three-band chapter table — time rail, one chapter of burst plates, empty kept rail.
struct P0ChapterTableView: View {
    @Bindable var session: P0SessionModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            chapterRail
                .frame(width: 176)
            chapterBoard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            keptRail
                .frame(width: 176)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LuminaTokens.Surface.mist)
    }

    private var chapterRail: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(session.chapters) { chapter in
                    let active = chapter.id == session.activeChapter?.id
                    Button {
                        session.selectChapter(chapter.id)
                    } label: {
                        Text(chapterLabel(chapter))
                            .font(LuminaTokens.Typeface.editorial(32))
                            .foregroundStyle(active ? LuminaTokens.Ink.primary : LuminaTokens.Ink.tertiary)
                            .frame(maxWidth: .infinity, minHeight: LuminaTokens.HitTarget.minimum, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(LuminaQuietButtonStyle())
                    .accessibilityIdentifier(P0AccessibilityID.chapterMark(chapter.id))
                    .accessibilityLabel(chapterLabel(chapter))
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
            .padding(.top, LuminaTokens.Spacing.xl)
            .padding(.horizontal, LuminaTokens.Spacing.md)
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
            if bursts.isEmpty {
                Color.clear
            } else {
                let columns = max(1, min(session.densityColumns, bursts.count))
                let spacing: CGFloat = 28
                let rows = max(1, Int(ceil(Double(bursts.count) / Double(columns))))
                let availableHeight = geo.size.height - 48
                let fitted = (availableHeight - spacing * CGFloat(rows - 1)) / CGFloat(rows)
                let plateHeight = min(220, max(88, fitted))
                let allowScroll = fitted < 88

                let grid = LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: spacing),
                        count: columns
                    ),
                    alignment: .leading,
                    spacing: spacing
                ) {
                    ForEach(bursts) { burst in
                        if let asset = coverAsset(for: burst) {
                            BurstPlate(
                                asset: asset,
                                count: burst.assetIDs.count,
                                isFocused: session.focusedAssetID.map { burst.assetIDs.contains($0) } ?? false,
                                marks: marks(for: asset)
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
                .padding(24)

                if allowScroll {
                    ScrollView {
                        grid
                    }
                } else {
                    grid
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    private var keptRail: some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.md) {
            Text("Kept")
                .font(LuminaTokens.Typeface.editorial(28))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.top, LuminaTokens.Spacing.xl)
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

    private func coverAsset(for burst: ShootBurst) -> AssetRecord? {
        let undecided = burst.assetIDs.first { id in
            session.assets.first(where: { $0.id == id })?.cull == .undecided
        }
        let coverID = undecided ?? burst.assetIDs.first
        return coverID.flatMap { id in session.assets.first(where: { $0.id == id }) }
    }

    private func marks(for asset: AssetRecord) -> ContactSheetMarks {
        .derive(
            asset: asset,
            selectedIDs: session.selectedAssetIDs,
            orderedIDs: session.orderedIDList,
            keptOrderMode: session.keptOrderMode
        )
    }
}

private struct BurstPlate: View {
    let asset: AssetRecord
    let count: Int
    let isFocused: Bool
    let marks: ContactSheetMarks
    let onFocus: () -> Void
    let onOpen: () -> Void
    let onKeep: () -> Void
    let onReject: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Button(action: onFocus) {
                ZStack(alignment: .bottomTrailing) {
                    plateImage
                        .opacity(marks.rejected ? 0.45 : 1)
                    if count > 1 {
                        Text("\(count)")
                            .font(LuminaTokens.Typeface.editorial(22))
                            .foregroundStyle(LuminaTokens.Ink.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(LuminaTokens.Surface.porcelain.opacity(0.92))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .padding(10)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LuminaTokens.Surface.well)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isFocused ? LuminaTokens.Ink.primary.opacity(0.85) : Color.clear,
                            lineWidth: 1.5
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(LuminaQuietButtonStyle())
            .simultaneousGesture(
                TapGesture(count: 2).onEnded { onOpen() }
            )
            .accessibilityIdentifier(P0AccessibilityID.assetCell(asset.id))
            .accessibilityLabel(asset.filename)
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
                .padding(10)
            }
        }
    }

    @ViewBuilder
    private var plateImage: some View {
        if let path = asset.thumbPath ?? asset.gridThumbPath {
            ContactSheetInspectImage(path: path)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
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
        .buttonStyle(LuminaQuietButtonStyle())
    }
}
