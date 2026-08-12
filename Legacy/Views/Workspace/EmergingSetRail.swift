// QUARANTINED(D40) — legacy quarantine, retired checkpoint-by-checkpoint.
// Contract: design/contract-v6.md D40 · schedule: design/checkpoint-sequence-v6.md
// No new references from outside Legacy/. Enforced by Scripts/lint/quarantine_d40.sh.
// Do not extend, restyle, or re-enter these types under new names.
import SwiftUI

/// Living editorial preview of the emerging set — large aspect-correct photographs.
struct EmergingSetRail: View {
    let assets: [AssetPresentation]
    let selectedID: AssetID?
    var isCompact: Bool = false
    var routingNamespace: Namespace.ID?
    var routingFlightID: AssetID?
    var receivingCount: Int = 0
    var highlightFirstSlot: Bool = false
    var onSelect: (AssetID) -> Void
    var onOpenCanvas: () -> Void
    var onDropAddToSet: ((AssetID) -> Void)?

    @State private var isDropTargeted = false

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
                    editorialPreview
                        .padding(.trailing, 2)
                }
            }
            openCanvasButton
        }
        .padding(LuminaTokens.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LuminaTokens.Surface.rail)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(LuminaTokens.Ink.primary.opacity(0.28), lineWidth: 1.5)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
            onDropAddToSet?(id)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    private var compactTab: some View {
        Button(action: onOpenCanvas) {
            VStack(spacing: 8) {
                Text("Set")
                    .font(LuminaTokens.Typeface.navigation(13, weight: .medium))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                Text("\(assets.count)")
                    .font(LuminaTokens.Typeface.count(16))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
            }
            .padding(.vertical, LuminaTokens.Spacing.lg)
            .frame(width: 48)
            .frame(maxHeight: .infinity)
            .background(LuminaTokens.Surface.rail)
            .overlay(alignment: .leading) {
                Rectangle().fill(LuminaTokens.Line.hairline).frame(width: LuminaTokens.Line.hairlineWidth)
            }
        }
        .buttonStyle(LuminaQuietButtonStyle())
        .accessibilityLabel("Set, \(assets.count) photographs. Open story.")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if receivingCount > 0 {
                Text("The story so far — \(assets.count) · receiving \(receivingCount)")
                    .font(LuminaTokens.Typeface.navigation(15))
                    .foregroundStyle(LuminaTokens.Ink.primary)
            } else {
                Text("The story so far")
                    .font(LuminaTokens.Typeface.navigation(16))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                Text("\(assets.count) photograph\(assets.count == 1 ? "" : "s")")
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 24)
            if receivingCount > 0 {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.75), lineWidth: 2)
                    .frame(height: 120)
                    .overlay {
                        Text("Receiving \(receivingCount)")
                            .font(LuminaTokens.Typeface.meta(12))
                            .foregroundStyle(LuminaTokens.Ink.tertiary)
                    }
            } else {
                Text("Photographs you advance will gather here.")
                    .font(LuminaTokens.Typeface.meta(13))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var editorialPreview: some View {
        let count = assets.count
        if count == 1, let asset = assets.first {
            largePhoto(asset, maxHeight: 420, isFirst: true)
        } else if count == 2 {
            VStack(spacing: LuminaTokens.Spacing.lg) {
                ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                    largePhoto(asset, maxHeight: 280, isFirst: index == 0)
                }
            }
        } else {
            LazyVStack(spacing: LuminaTokens.Spacing.lg) {
                ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                    largePhoto(asset, maxHeight: index == 0 ? 320 : 220, isFirst: index == 0)
                }
            }
        }
    }

    private func largePhoto(_ asset: AssetPresentation, maxHeight: CGFloat, isFirst: Bool) -> some View {
        Button { onSelect(asset.id) } label: {
            photoView(asset, maxHeight: maxHeight, isFirst: isFirst)
        }
        .buttonStyle(LuminaQuietButtonStyle())
    }

    @ViewBuilder
    private func photoView(_ asset: AssetPresentation, maxHeight: CGFloat, isFirst: Bool) -> some View {
        let view = StablePhotoView(
            asset: asset,
            contentMode: .fit,
            cornerRadius: LuminaTokens.Radius.photographLarge,
            isSelected: asset.id == selectedID,
            maxPixelSize: 1400
        )
        .frame(maxWidth: .infinity)
        .frame(maxHeight: maxHeight)
        .aspectRatio(asset.aspectRatio, contentMode: .fit)
        .overlay {
            if highlightFirstSlot && isFirst {
                RoundedRectangle(cornerRadius: LuminaTokens.Radius.photographLarge, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.75), lineWidth: 2)
            }
        }

        if let ns = routingNamespace, routingFlightID == asset.id {
            view.matchedGeometryEffect(id: "routing-stack", in: ns, isSource: false)
        } else {
            view
        }
    }

    private var openCanvasButton: some View {
        Button(action: onOpenCanvas) {
            Text("Open Story")
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
