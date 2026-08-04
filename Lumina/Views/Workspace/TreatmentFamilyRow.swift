import SwiftUI

/// One comparison family — capture-order thumbnails; equal-size when expanded.
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
    let onSelect: () -> Void
    let onSelectPhoto: (AssetID) -> Void
    let onDoubleTapPhoto: (AssetID) -> Void

    private var photos: [AssetPresentation] {
        group.captureOrderedAssets
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.sm) {
            rowHeader

            if isExpanded && isActive {
                expandedGrid
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
        .padding(.vertical, LuminaTokens.Spacing.sm)
        .contentShape(Rectangle())
        .onTapGesture(count: 1) { onSelect() }
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
                .font(LuminaTokens.Typeface.groupHeading(isActive ? 19 : 17))
                .foregroundStyle(isActive ? LuminaTokens.Ink.primary : LuminaTokens.Ink.strongSecondary)
                .lineLimit(2)

            if let subtitle = group.subtitle {
                Text("·")
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                Text(subtitle)
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if group.keepCount > 0 {
                Text("\(group.keepCount) in set")
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
            }
            if group.foldCount > 0 {
                Text("\(group.foldCount) folded")
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
            }
        }
    }

    private var compactStrip: some View {
        ScrollView(.horizontal, showsIndicators: photos.count > 5) {
            HStack(spacing: LuminaTokens.Spacing.sm) {
                ForEach(photos.prefix(8)) { asset in
                    photoTile(asset: asset, size: CGSize(width: 88, height: 66), showBadge: true)
                }
            }
        }
    }

    private var expandedGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: LuminaTokens.Spacing.sm), count: min(4, max(photos.count, 1)))
        return LazyVGrid(columns: columns, spacing: LuminaTokens.Spacing.sm) {
            ForEach(photos.prefix(8)) { asset in
                photoTile(
                    asset: asset,
                    size: nil,
                    showBadge: asset.id != selectedID,
                    equalHeight: 160
                )
            }
        }
    }

    @ViewBuilder
    private func photoTile(
        asset: AssetPresentation,
        size: CGSize?,
        showBadge: Bool,
        equalHeight: CGFloat? = nil
    ) -> some View {
        let isSelected = asset.id == selectedID
        let isSuggested = asset.id == suggestedStartID && asset.decision == .undecided
        let usePreview = isActive && rowPreviewActive

        Button {
            onSelect()
            onSelectPhoto(asset.id)
        } label: {
            VStack(spacing: 4) {
                GradedPhotoView(
                    asset: asset,
                    projectName: usePreview ? projectName : nil,
                    baseRecipe: usePreview ? baseRecipe : .neutral,
                    developOffsets: usePreview ? developOffsets : .zero,
                    previewMix: usePreview ? previewMix : 1,
                    contentMode: .fit,
                    showDecisionBadge: showBadge && asset.decision != .undecided,
                    isSelected: isSelected,
                    maxPixelSize: isExpanded ? 1200 : 640
                )
                .frame(width: size?.width, height: size?.height ?? equalHeight)
                .aspectRatio(size == nil ? asset.aspectRatio : nil, contentMode: .fit)
                .overlay {
                    RoundedRectangle(cornerRadius: LuminaTokens.Radius.photographThumb, style: .continuous)
                        .strokeBorder(
                            isSelected ? LuminaTokens.Line.emphasis : (isSuggested ? LuminaTokens.Ink.primary.opacity(0.35) : Color.clear),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                }

                if isSuggested, isExpanded {
                    Text("Suggested start")
                        .font(LuminaTokens.Typeface.meta(10))
                        .foregroundStyle(LuminaTokens.Ink.tertiary)
                }
            }
        }
        .buttonStyle(LuminaQuietButtonStyle())
        .simultaneousGesture(TapGesture(count: 2).onEnded { onDoubleTapPhoto(asset.id) })
    }
}
