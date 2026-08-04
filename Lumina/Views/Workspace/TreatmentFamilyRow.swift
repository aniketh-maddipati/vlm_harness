import SwiftUI

/// One comparison family — spacious 2×2 / side-by-side spread when expanded; compact when idle.
struct TreatmentFamilyRow: View {
    let group: GroupPresentation
    let isActive: Bool
    let isExpanded: Bool
    let selectedID: AssetID?
    let suggestedStartID: AssetID?
    var projectName: String?
    var baseRecipe: DevelopRecipe = .neutral
    var developOffsets: DevelopAdjustments = .zero
    var previewMix: Double = 1
    var rowPreviewActive: Bool = false
    var routingNamespace: Namespace.ID?
    var routingFlightID: AssetID?
    var showDecisionShelf: Bool = true
    let onSelect: () -> Void
    let onSelectPhoto: (AssetID) -> Void
    let onDoubleTapPhoto: (AssetID) -> Void
    var onAddToSet: ((AssetID) -> Void)?
    var onSetAside: ((AssetID) -> Void)?
    var onHold: ((AssetID) -> Void)?
    var onRestore: ((AssetID) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var comparisonPage = 0
    @State private var foldExpanded = false

    private let pageSize = 4

    /// Photographs still in the comparison spread (not set aside).
    private var activePhotos: [AssetPresentation] {
        group.captureOrderedAssets.filter { $0.decision != .cut }
    }

    private var foldedPhotos: [AssetPresentation] {
        group.captureOrderedAssets.filter { $0.decision == .cut }
    }

    private var pageCount: Int {
        max(1, Int(ceil(Double(activePhotos.count) / Double(pageSize))))
    }

    private var pagePhotos: [AssetPresentation] {
        let start = comparisonPage * pageSize
        guard start < activePhotos.count else { return Array(activePhotos.prefix(pageSize)) }
        return Array(activePhotos[start..<min(start + pageSize, activePhotos.count)])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded && isActive ? LuminaTokens.Spacing.md : LuminaTokens.Spacing.xs) {
            rowHeader

            if isExpanded && isActive {
                comparisonSpread
                if !foldedPhotos.isEmpty {
                    setAsideFold
                }
            } else {
                compactStrip
            }
        }
        .padding(.leading, group.isSiblingContinuation ? LuminaTokens.Spacing.lg : 0)
        .overlay(alignment: .leading) {
            if group.isSiblingContinuation {
                Rectangle()
                    .fill(LuminaTokens.Line.emphasis)
                    .frame(width: 2)
                    .padding(.vertical, LuminaTokens.Spacing.xs)
            }
        }
        .padding(.vertical, isExpanded && isActive ? LuminaTokens.Spacing.md : LuminaTokens.Spacing.xs)
        .contentShape(Rectangle())
        .onTapGesture(count: 1) { onSelect() }
        .onChange(of: selectedID) { _, newID in
            syncPage(to: newID)
            if let newID, foldedPhotos.contains(where: { $0.id == newID }) {
                foldExpanded = true
            }
        }
        .onChange(of: activePhotos.map(\.id)) { _, _ in
            if comparisonPage >= pageCount {
                comparisonPage = max(0, pageCount - 1)
            }
            syncPage(to: selectedID)
        }
        .onAppear { syncPage(to: selectedID) }
        .accessibilityElement(children: .contain)
    }

    private var rowHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if group.isSiblingContinuation, let part = group.siblingPartIndex, let total = group.siblingPartCount {
                Text("continued · \(part) of \(total)")
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
            }

            Text(group.title)
                .font(LuminaTokens.Typeface.groupHeading(isActive && isExpanded ? 20 : (isActive ? 17 : 15)))
                .foregroundStyle(isActive ? LuminaTokens.Ink.primary : LuminaTokens.Ink.secondary)
                .lineLimit(1)

            if isActive, let subtitle = group.subtitle, isExpanded {
                Text("·")
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                Text(subtitle)
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isExpanded && isActive && pageCount > 1 {
                pageIndicator
            }

            if group.keepCount > 0 {
                Text("\(group.keepCount) in set")
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
            }
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            Button {
                comparisonPage = max(0, comparisonPage - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(comparisonPage > 0 ? LuminaTokens.Ink.secondary : LuminaTokens.Ink.tertiary.opacity(0.4))
            }
            .buttonStyle(LuminaQuietButtonStyle())
            .disabled(comparisonPage == 0)

            Text("\(comparisonPage + 1) / \(pageCount)")
                .font(LuminaTokens.Typeface.meta(11))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
                .monospacedDigit()

            Button {
                comparisonPage = min(pageCount - 1, comparisonPage + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(comparisonPage < pageCount - 1 ? LuminaTokens.Ink.secondary : LuminaTokens.Ink.tertiary.opacity(0.4))
            }
            .buttonStyle(LuminaQuietButtonStyle())
            .disabled(comparisonPage >= pageCount - 1)
        }
    }

    private var compactStrip: some View {
        HStack(spacing: LuminaTokens.Spacing.xs) {
            ForEach(activePhotos.prefix(6)) { asset in
                photoTile(asset: asset, maxHeight: isActive ? 56 : 44, showShelf: false)
                    .frame(maxWidth: 72)
            }
            if activePhotos.count > 6 {
                Text("+\(activePhotos.count - 6)")
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(height: isActive ? 60 : 48)
    }

    private var comparisonSpread: some View {
        GeometryReader { geo in
            let photos = pagePhotos
            let count = photos.count
            let spacing = LuminaTokens.Spacing.md
            let availableHeight = max(geo.size.height, 220)

            Group {
                if count <= 1 {
                    singleSpread(photos: photos, height: availableHeight)
                } else if count == 2 {
                    twoUpSpread(photos: photos, width: geo.size.width, height: availableHeight, spacing: spacing)
                } else {
                    gridSpread(photos: photos, width: geo.size.width, height: availableHeight, spacing: spacing)
                }
            }
            .frame(width: geo.size.width, height: availableHeight, alignment: .top)
        }
        .frame(minHeight: 280)
        .frame(maxHeight: .infinity)
    }

    private func singleSpread(photos: [AssetPresentation], height: CGFloat) -> some View {
        HStack {
            Spacer(minLength: 0)
            if let asset = photos.first {
                photoTile(asset: asset, maxHeight: height - 36, showShelf: showDecisionShelf)
                    .frame(maxWidth: min(height * asset.aspectRatio, 720))
            }
            Spacer(minLength: 0)
        }
    }

    private func twoUpSpread(photos: [AssetPresentation], width: CGFloat, height: CGFloat, spacing: CGFloat) -> some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(photos) { asset in
                photoTile(asset: asset, maxHeight: height - 36, showShelf: showDecisionShelf && asset.id == selectedID)
                    .frame(maxWidth: (width - spacing) / 2)
            }
        }
    }

    private func gridSpread(photos: [AssetPresentation], width: CGFloat, height: CGFloat, spacing: CGFloat) -> some View {
        let rows: [[AssetPresentation]] = {
            if photos.count <= 2 { return [photos] }
            let mid = (photos.count + 1) / 2
            return [Array(photos.prefix(mid)), Array(photos.suffix(photos.count - mid))]
        }()
        let rowHeight = (height - spacing) / CGFloat(max(rows.count, 1))

        return VStack(spacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .center, spacing: spacing) {
                    ForEach(row) { asset in
                        photoTile(
                            asset: asset,
                            maxHeight: rowHeight - 28,
                            showShelf: showDecisionShelf && asset.id == selectedID
                        )
                        .frame(maxWidth: (width - spacing) / CGFloat(max(row.count, 1)))
                    }
                }
                .frame(height: rowHeight)
            }
        }
    }

    private var setAsideFold: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(LuminaTokens.Motion.control) { foldExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: foldExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(LuminaTokens.Ink.tertiary)
                    Text("Set aside · \(foldedPhotos.count)")
                        .font(LuminaTokens.Typeface.meta(12))
                        .foregroundStyle(LuminaTokens.Ink.secondary)
                    Spacer(minLength: 0)
                    // Tiny stacked peeks
                    HStack(spacing: -8) {
                        ForEach(foldedPhotos.prefix(3)) { asset in
                            StablePhotoView(
                                asset: asset,
                                contentMode: .fit,
                                cornerRadius: 2,
                                maxPixelSize: 200
                            )
                            .frame(width: 28, height: 22)
                            .opacity(0.75)
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(LuminaTokens.Surface.well.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(LuminaTokens.Line.hairline, lineWidth: 1)
                }
            }
            .buttonStyle(LuminaQuietButtonStyle())

            if foldExpanded {
                HStack(spacing: LuminaTokens.Spacing.sm) {
                    ForEach(foldedPhotos) { asset in
                        VStack(spacing: 4) {
                            Button {
                                onSelect()
                                onSelectPhoto(asset.id)
                            } label: {
                                StablePhotoView(
                                    asset: asset,
                                    contentMode: .fit,
                                    cornerRadius: LuminaTokens.Radius.photographThumb,
                                    isSelected: asset.id == selectedID,
                                    maxPixelSize: 480
                                )
                                .frame(width: 96, height: 72)
                                .opacity(0.88)
                            }
                            .buttonStyle(LuminaQuietButtonStyle())

                            Button("Restore") {
                                onRestore?(asset.id)
                            }
                            .font(LuminaTokens.Typeface.meta(11))
                            .foregroundStyle(LuminaTokens.Ink.secondary)
                            .buttonStyle(LuminaQuietButtonStyle())
                        }
                    }
                }
                .padding(.leading, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func photoTile(asset: AssetPresentation, maxHeight: CGFloat, showShelf: Bool) -> some View {
        let isSelected = asset.id == selectedID
        let isSuggested = asset.id == suggestedStartID && asset.decision == .undecided
        let usePreview = isActive && rowPreviewActive
        let inSet = asset.decision == .keep || asset.decision == .anchor
        let onHoldMark = asset.decision == .needsMe

        VStack(spacing: 0) {
            Button {
                onSelect()
                onSelectPhoto(asset.id)
            } label: {
                ZStack(alignment: .topLeading) {
                    photoImage(
                        asset: asset,
                        usePreview: usePreview,
                        isSelected: isSelected,
                        isSuggested: isSuggested,
                        inSet: inSet,
                        maxHeight: maxHeight
                    )

                    if inSet || onHoldMark {
                        Text(asset.decision.quietMarker)
                            .font(LuminaTokens.Typeface.meta(10))
                            .foregroundStyle(LuminaTokens.Ink.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(LuminaTokens.Surface.porcelain.opacity(0.9))
                            )
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                }
            }
            .buttonStyle(LuminaQuietButtonStyle())
            .simultaneousGesture(TapGesture(count: 2).onEnded { onDoubleTapPhoto(asset.id) })
            .draggable(asset.id.uuidString) {
                StablePhotoView(
                    asset: asset,
                    contentMode: .fit,
                    cornerRadius: LuminaTokens.Radius.photographThumb,
                    maxPixelSize: 320
                )
                .frame(width: 120, height: 90)
                .opacity(0.9)
            }

            if showShelf, isSelected, isExpanded, isActive {
                FloatingDecisionShelf(
                    current: asset.decision,
                    onSetAside: { onSetAside?(asset.id) },
                    onHold: { onHold?(asset.id) },
                    onAddToSet: { onAddToSet?(asset.id) }
                )
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(reduceMotion ? nil : LuminaTokens.Motion.control, value: isSelected)
    }

    @ViewBuilder
    private func photoImage(
        asset: AssetPresentation,
        usePreview: Bool,
        isSelected: Bool,
        isSuggested: Bool,
        inSet: Bool,
        maxHeight: CGFloat
    ) -> some View {
        let image = GradedPhotoView(
            asset: asset,
            projectName: usePreview ? projectName : nil,
            baseRecipe: usePreview ? baseRecipe : .neutral,
            developOffsets: usePreview ? developOffsets : .zero,
            previewMix: usePreview ? previewMix : 1,
            contentMode: .fit,
            showDecisionBadge: false,
            isSelected: false,
            maxPixelSize: isExpanded ? 1600 : 480
        )
        .frame(maxHeight: maxHeight)
        .aspectRatio(asset.aspectRatio, contentMode: .fit)
        .opacity(inSet ? 0.92 : 1)
        .overlay {
            RoundedRectangle(cornerRadius: LuminaTokens.Radius.photographThumb, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? LuminaTokens.Ink.primary.opacity(0.50)
                        : (isSuggested ? LuminaTokens.Ink.primary.opacity(0.28) : Color.clear),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }

        if let ns = routingNamespace, routingFlightID == asset.id {
            image.matchedGeometryEffect(id: asset.id, in: ns, isSource: true)
        } else {
            image
        }
    }

    private func syncPage(to selected: AssetID?) {
        guard let selected,
              let index = activePhotos.firstIndex(where: { $0.id == selected }) else { return }
        let page = index / pageSize
        if page != comparisonPage {
            comparisonPage = page
        }
    }
}
