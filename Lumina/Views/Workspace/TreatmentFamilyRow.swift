import SwiftUI

/// One comparison family — tray pages of 3 (or 2 when story pane is wide); darkroom mats when handling.
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
    var routingFlightIDs: [AssetID] = []
    var showDecisionShelf: Bool = false
    var handSelectedIDs: Set<AssetID> = []
    var isStagingActive: Bool = false
    var leaderID: AssetID?
    var isHandling: Bool = false
    var stagedAdvance: Bool = false
    var pageSize: Int = 3
    /// Row width actually available — tiles justify to it. 0 = legacy fixed sizes.
    var availableWidth: CGFloat = 0
    var twoUp: Bool = false
    var reduceMotion: Bool = false
    var travelAnimation: Animation = LuminaTokens.Motion.travel
    let onSelect: () -> Void
    let onSelectPhoto: (AssetID) -> Void
    var onGatherPhoto: (AssetID) -> Void = { _ in }
    var onToggleHandSelection: (AssetID) -> Void = { _ in }
    var tableCoordinateSpace: CoordinateSpace = .global
    let onDoubleTapPhoto: (AssetID) -> Void
    var onCommandDoubleTap: (AssetID) -> Void = { _ in }
    var onAddToSet: ((AssetID) -> Void)?
    var onSetAside: ((AssetID) -> Void)?
    var onHold: ((AssetID) -> Void)?
    var onRestore: ((AssetID) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var envReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var comparisonPage = 0
    @State private var foldExpanded = false
    /// Frozen page assignment — computed once when the family is first shown.
    @State private var frozenPages: [[AssetID]]?

    private var effectiveReduceMotion: Bool { reduceMotion || envReduceMotion }

    /// Photographs still in the comparison spread (not set aside).
    private var activePhotos: [AssetPresentation] {
        group.captureOrderedAssets.filter { $0.decision != .cut }
    }

    private var foldedPhotos: [AssetPresentation] {
        group.captureOrderedAssets.filter { $0.decision == .cut }
    }

    private var pages: [[AssetPresentation]] {
        if let frozen = frozenPages {
            return frozen.compactMap { ids in
                ids.compactMap { id in activePhotos.first(where: { $0.id == id }) }
            }.filter { !$0.isEmpty }
        }
        return paginate(activePhotos, size: pageSize)
    }

    private var pageCount: Int { max(1, pages.count) }

    private var pagePhotos: [AssetPresentation] {
        guard comparisonPage < pages.count else { return Array(activePhotos.prefix(pageSize)) }
        return pages[comparisonPage]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded && isActive ? LuminaTokens.Spacing.md : LuminaTokens.Spacing.xs) {
            rowHeader

            if isExpanded && isActive {
                comparisonSpread
            } else {
                compactStrip
            }
        }
        .padding(.leading, group.isSiblingContinuation ? LuminaTokens.Spacing.md : 0)
        .padding(.vertical, isExpanded && isActive ? LuminaTokens.Spacing.sm : LuminaTokens.Spacing.xs)
        .contentShape(Rectangle())
        .onTapGesture(count: 1) { onSelect() }
        .onChange(of: selectedID) { _, newID in
            syncPage(to: newID)
            if let newID, foldedPhotos.contains(where: { $0.id == newID }) {
                foldExpanded = true
            }
        }
        .onAppear {
            if frozenPages == nil {
                frozenPages = paginate(activePhotos, size: pageSize).map { $0.map(\.id) }
            }
            syncPage(to: selectedID)
        }
        .onChange(of: pageSize) { _, newSize in
            // Window resized / fullscreen toggled — re-lay pages to the new width.
            frozenPages = paginate(activePhotos, size: newSize).map { $0.map(\.id) }
            comparisonPage = 0
            syncPage(to: selectedID)
        }
        .accessibilityElement(children: .contain)
    }

    private var rowHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if group.isSiblingContinuation, let part = group.siblingPartIndex, let total = group.siblingPartCount {
                Text("continued · \(part) of \(total)")
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
            }

            Text(group.title)
                .font(LuminaTokens.Typeface.groupHeading(isActive && isExpanded ? 20 : (isActive ? 17 : 15)))
                .foregroundStyle(isActive ? LuminaTokens.Ink.onTable : LuminaTokens.Ink.onTableSecondary)
                .lineLimit(1)

            if isActive, let subtitle = group.subtitle, isExpanded {
                Text("·")
                    .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
                Text(subtitle)
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isExpanded && isActive && pageCount > 1 {
                pageIndicator
            }

            if group.keepCount > 0 {
                Text("\(group.keepCount) in set")
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
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
                    .foregroundStyle(comparisonPage > 0 ? LuminaTokens.Ink.onTableSecondary : LuminaTokens.Ink.onTableSecondary.opacity(0.35))
            }
            .buttonStyle(LuminaQuietButtonStyle())
            .disabled(comparisonPage == 0)
            .accessibilityLabel("Previous page of set")

            Text("\(comparisonPage + 1) / \(pageCount)")
                .font(LuminaTokens.Typeface.meta(11))
                .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
                .monospacedDigit()

            Button {
                comparisonPage = min(pageCount - 1, comparisonPage + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(comparisonPage < pageCount - 1 ? LuminaTokens.Ink.onTableSecondary : LuminaTokens.Ink.onTableSecondary.opacity(0.35))
            }
            .buttonStyle(LuminaQuietButtonStyle())
            .disabled(comparisonPage >= pageCount - 1)
            .accessibilityLabel("Next page of set")
        }
    }

    /// How many compact tiles genuinely fit across the row.
    private var compactVisibleCount: Int {
        TableLayout.compactVisibleCount(availableWidth: availableWidth)
    }

    private var compactStrip: some View {
        let visible = compactVisibleCount
        return HStack(spacing: LuminaTokens.Spacing.xs) {
            ForEach(activePhotos.prefix(visible)) { asset in
                photoTile(asset: asset, width: 104, height: isActive ? 80 : 64)
                    .frame(maxWidth: 104)
            }
            if activePhotos.count > visible {
                Text("+\(activePhotos.count - visible)")
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
            }
            Spacer(minLength: 0)
        }
        .frame(height: isActive ? 88 : 72)
    }

    private var comparisonSpread: some View {
        let photos = pagePhotos
        let gap: CGFloat = 16
        let mat: CGFloat = 12
        let baseW = TableLayout.comparisonTileWidth(
            availableWidth: availableWidth,
            pageSize: pageSize,
            twoUp: twoUp,
            gap: gap,
            mat: mat
        )
        let compression = TableLayout.comparisonCompression(
            pageSize: pageSize,
            hasSelection: photos.contains(where: { $0.id == selectedID })
        )
        let focusH = (baseW * compression.focusScale * 2 / 3).rounded()

        return HStack(alignment: .center, spacing: gap) {
            ForEach(photos) { asset in
                let focused = asset.id == selectedID
                let tileW = (focused ? baseW * compression.focusScale : baseW * compression.neighborScale).rounded()
                let tileH = (tileW * 2 / 3).rounded()
                photoTile(asset: asset, width: tileW, height: tileH, mat: focused ? mat + 2 : mat)
                    .scaleEffect(focused ? 1.02 : 0.96)
                    .opacity(focused || selectedID == nil ? 1.0 : 0.72)
                    .animation(effectiveReduceMotion ? nil : LuminaTokens.Motion.selection, value: selectedID)
                    .zIndex(focused ? 1 : 0)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: focusH + mat * 2)
    }

    @ViewBuilder
    private func photoTile(asset: AssetPresentation, width: CGFloat, height: CGFloat, mat: CGFloat = 8) -> some View {
        let handSelected = handSelectedIDs.contains(asset.id)
        let isLeader = leaderID == asset.id
        let isSelected = asset.id == selectedID
        let isSuggested = asset.id == suggestedStartID && asset.decision == .undecided
        let usePreview = isActive && rowPreviewActive
        let inSet = asset.decision == .keep || asset.decision == .anchor
        let onHoldMark = asset.decision == .needsMe
        let matColor: Color = {
            if reduceTransparency {
                return handSelected && isHandling ? LuminaTokens.Surface.tableMatLifted : LuminaTokens.Surface.tableMat
            }
            return isHandling ? LuminaTokens.Surface.tableMatLifted : LuminaTokens.Surface.tableMat
        }()

        let lift: CGFloat = {
            guard handSelected && isHandling else { return 0 }
            return effectiveReduceMotion ? 0 : -14
        }()
        let stageOffset: CGSize = {
            guard handSelected && stagedAdvance else { return .zero }
            if effectiveReduceMotion { return .zero }
            return CGSize(width: 26, height: -16)
        }()
        let stageRotation: Double = (handSelected && stagedAdvance && !effectiveReduceMotion) ? 1.6 : 0

        VStack(spacing: 0) {
            Button {
                onSelect()
                if isStagingActive {
                    onToggleHandSelection(asset.id)
                } else if isHandling {
                    onGatherPhoto(asset.id)
                } else {
                    onSelectPhoto(asset.id)
                }
            } label: {
                ZStack(alignment: .topLeading) {
                    matColor
                        .frame(width: width + mat * 2, height: height + mat * 2)

                    GradedPhotoView(
                        asset: asset,
                        projectName: usePreview ? projectName : nil,
                        baseRecipe: usePreview ? baseRecipe : .neutral,
                        developOffsets: usePreview ? developOffsets : .zero,
                        previewMix: usePreview ? previewMix : 1,
                        contentMode: .fit,
                        showDecisionBadge: false,
                        isSelected: false,
                        maxPixelSize: isExpanded ? 2048 : 768,
                        tableBirth: true
                    )
                    .frame(width: width, height: height)
                    .aspectRatio(asset.aspectRatio, contentMode: .fit)
                    .padding(mat)

                    if let provenance = asset.adaptProvenance {
                        EditProvenanceChip(provenance: provenance)
                            .padding(mat + 4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .allowsHitTesting(false)
                    }

                    if inSet || onHoldMark {
                        Text(asset.decision.quietMarker)
                            .font(LuminaTokens.Typeface.meta(10))
                            .foregroundStyle(LuminaTokens.Ink.onTable)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                            .padding(mat + 6)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(
                            keylineColor(
                                handSelected: handSelected,
                                isLeader: isLeader,
                                isSelected: isSelected,
                                isSuggested: isSuggested
                            ),
                            lineWidth: keylineWidth(handSelected: handSelected, isSuggested: isSuggested, isSelected: isSelected)
                        )
                }
                .reportsTableTileFrame(id: asset.id, in: tableCoordinateSpace)
                .offset(x: stageOffset.width, y: lift + stageOffset.height)
                .rotationEffect(.degrees(stageRotation))
                .animation(effectiveReduceMotion ? nil : LuminaTokens.Motion.lift, value: handSelected && isHandling)
                .animation(effectiveReduceMotion ? LuminaTokens.Motion.reduceMotionKeyline : LuminaTokens.Motion.stage, value: stagedAdvance)
            }
            .buttonStyle(LuminaQuietButtonStyle())
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                // Editing opens on ⌘-double-click; plain double-tap remains focus.
                if isHandling {
                    onCommandDoubleTap(asset.id)
                } else {
                    onDoubleTapPhoto(asset.id)
                }
            })
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
            .modifier(RoutingFlightModifier(
                assetID: asset.id,
                namespace: routingNamespace,
                flightID: routingFlightID,
                flightIDs: routingFlightIDs,
                reduceMotion: effectiveReduceMotion
            ))
            .accessibilityLabel(handSelected ? "Selected photograph \(asset.filename)" : asset.filename)
            .accessibilityAddTraits(handSelected ? .isSelected : [])
        }
        .opacity(inSet && !handSelected ? 0.92 : 1)
    }

    private func keylineWidth(handSelected: Bool, isSuggested: Bool, isSelected: Bool) -> CGFloat {
        if handSelected { return HiFiTokens.Ring.haloWidth }
        if isSuggested { return HiFiTokens.Ring.haloWidth }
        return isSelected ? 2 : 1
    }

    private func keylineColor(handSelected: Bool, isLeader: Bool, isSelected: Bool, isSuggested: Bool) -> Color {
        if handSelected {
            return HiFiTokens.Ring.selection
        }
        if isSuggested {
            return HiFiTokens.Ring.halo.opacity(HiFiTokens.Ring.haloOpacity)
        }
        if isSelected || isLeader {
            return Color.white.opacity(0.55)
        }
        return Color.clear
    }

    private func syncPage(to selected: AssetID?) {
        guard let selected else { return }
        if let pageIndex = pages.firstIndex(where: { $0.contains(where: { $0.id == selected }) }) {
            comparisonPage = pageIndex
        }
    }

    /// Sort by embedding-distance proxy (quality as stand-in) inside each page, then freeze.
    private func paginate(_ photos: [AssetPresentation], size: Int) -> [[AssetPresentation]] {
        guard !photos.isEmpty else { return [] }
        // Near-twins share a page: sort by quality within capture-order windows.
        var remaining = photos
        var result: [[AssetPresentation]] = []
        while !remaining.isEmpty {
            let chunk = Array(remaining.prefix(size))
            let sortedChunk = chunk.sorted { $0.qualityScore > $1.qualityScore }
            // Preserve capture order overall but cluster near scores — keep original order for stability,
            // only nudge near-twins (close quality) adjacent within the page.
            let nudged = nearTwinSort(chunk)
            result.append(nudged.isEmpty ? sortedChunk : nudged)
            remaining = Array(remaining.dropFirst(size))
        }
        return result
    }

    private func nearTwinSort(_ chunk: [AssetPresentation]) -> [AssetPresentation] {
        guard chunk.count > 1 else { return chunk }
        return chunk.sorted { a, b in
            let da = abs(a.qualityScore - (chunk.first?.qualityScore ?? 0))
            let db = abs(b.qualityScore - (chunk.first?.qualityScore ?? 0))
            if abs(da - db) < 0.02 {
                return (a.capturedAt ?? .distantPast) < (b.capturedAt ?? .distantPast)
            }
            return da < db
        }
    }
}

private struct RoutingFlightModifier: ViewModifier {
    let assetID: AssetID
    let namespace: Namespace.ID?
    let flightID: AssetID?
    let flightIDs: [AssetID]
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(flightIDs.contains(assetID) || flightID == assetID ? 0.55 : 1)
        } else if let ns = namespace, flightID == assetID || flightIDs.contains(assetID) {
            // Grouped stack uses the last id as the matched-geometry proxy source.
            if assetID == (flightIDs.last ?? flightID) {
                content.matchedGeometryEffect(id: "routing-stack", in: ns, isSource: true)
            } else {
                content.opacity(0.01)
            }
        } else {
            content
        }
    }
}
