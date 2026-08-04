import SwiftUI

/// Quiet receipt of kept photographs — expands into Canvas.
struct EmergingSetRail: View {
    let assets: [AssetPresentation]
    let selectedID: AssetID?
    var isCompact: Bool = false
    let onSelect: (AssetID) -> Void
    let onOpenCanvas: () -> Void

    var body: some View {
        if isCompact {
            compactTab
        } else {
            fullRail
        }
    }

    private var fullRail: some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.md) {
            header
            if assets.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: LuminaTokens.Spacing.sm) {
                        ForEach(assets) { asset in
                            Button { onSelect(asset.id) } label: {
                                StablePhotoView(
                                    asset: asset,
                                    contentMode: .fit,
                                    cornerRadius: LuminaTokens.Radius.photographThumb,
                                    isSelected: asset.id == selectedID,
                                    maxPixelSize: 800
                                )
                                .frame(maxWidth: .infinity)
                                .frame(height: 72)
                            }
                            .buttonStyle(LuminaQuietButtonStyle())
                        }
                    }
                }
            }
            openCanvasButton
        }
        .padding(LuminaTokens.Spacing.md)
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 330)
        .frame(maxHeight: .infinity)
        .background(LuminaTokens.Surface.rail)
        .overlay(alignment: .leading) {
            Rectangle().fill(LuminaTokens.Line.hairline).frame(width: LuminaTokens.Line.hairlineWidth)
        }
    }

    private var compactTab: some View {
        Button(action: onOpenCanvas) {
            VStack(spacing: 6) {
                Text("Set")
                    .font(LuminaTokens.Typeface.navigation(13, weight: .medium))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                Text("·")
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                Text("\(assets.count)")
                    .font(LuminaTokens.Typeface.count(14))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                Text("photos")
                    .font(LuminaTokens.Typeface.meta(10))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                    .rotationEffect(.degrees(-90))
                    .fixedSize()
            }
            .padding(.vertical, LuminaTokens.Spacing.lg)
            .frame(width: 44)
            .frame(maxHeight: .infinity)
            .background(LuminaTokens.Surface.rail)
            .overlay(alignment: .leading) {
                Rectangle().fill(LuminaTokens.Line.hairline).frame(width: LuminaTokens.Line.hairlineWidth)
            }
        }
        .buttonStyle(LuminaQuietButtonStyle())
        .accessibilityLabel("Set, \(assets.count) photographs. Open canvas.")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("The set so far")
                .font(LuminaTokens.Typeface.navigation(15))
                .foregroundStyle(LuminaTokens.Ink.primary)
            Text("\(assets.count) photograph\(assets.count == 1 ? "" : "s")")
                .font(LuminaTokens.Typeface.meta(12))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
        }
    }

    private var emptyState: some View {
        Text("Worthwhile photographs will appear here as you send them to the emerging set.")
            .font(LuminaTokens.Typeface.meta(12))
            .foregroundStyle(LuminaTokens.Ink.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var openCanvasButton: some View {
        Button(action: onOpenCanvas) {
            Text("Open canvas")
                .font(LuminaTokens.Typeface.navigation(14))
                .foregroundStyle(LuminaTokens.Ink.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(LuminaTokens.Line.emphasis, lineWidth: 1)
                }
        }
        .buttonStyle(LuminaQuietButtonStyle())
        .disabled(assets.isEmpty)
        .opacity(assets.isEmpty ? 0.45 : 1)
    }
}
