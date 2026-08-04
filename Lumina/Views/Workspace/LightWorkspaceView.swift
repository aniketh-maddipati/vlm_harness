import SwiftUI

struct LightWorkspaceView: View {
    let presentation: WorkspacePresentation
    var onSelectAsset: (AssetID) -> Void
    var onSelectGroup: (String) -> Void
    var onLensChange: (WorkspaceLens) -> Void
    var onToggleInclusion: (AssetID) -> Void
    var onSetReference: (AssetID) -> Void
    var onHome: () -> Void
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceToolbar(
                title: presentation.shootTitle,
                lens: presentation.lens,
                progressLabel: presentation.progressLabel,
                onLensChange: onLensChange,
                onHome: onHome,
                onFinish: onFinish
            )

            HStack(spacing: 0) {
                paletteRail
                    .frame(width: 220)

                Rectangle()
                    .fill(LuminaTokens.Line.hairline)
                    .frame(width: LuminaTokens.Line.hairlineWidth)

                activePalette
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LuminaTokens.Surface.porcelain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Light workspace")
    }

    private var paletteRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LuminaTokens.Spacing.sm) {
                SectionHeader(title: "Palettes")
                    .padding(.horizontal, LuminaTokens.Spacing.md)
                    .padding(.top, LuminaTokens.Spacing.md)

                ForEach(presentation.groups) { group in
                    PaletteRailItem(
                        group: group,
                        isSelected: group.id == presentation.selectedGroupID,
                        onSelect: { onSelectGroup(group.id) }
                    )
                }
            }
            .padding(.bottom, LuminaTokens.Spacing.md)
        }
        .background(LuminaTokens.Surface.mist)
        .accessibilityLabel("Palette rail")
    }

    @ViewBuilder
    private var activePalette: some View {
        if let group = presentation.selectedGroup {
            ScrollView {
                VStack(alignment: .leading, spacing: LuminaTokens.Spacing.lg) {
                    paletteHeader(group: group)

                    if let asset = presentation.selectedAsset {
                        StablePhotoView(
                            asset: asset,
                            cornerRadius: LuminaTokens.Radius.photographLarge,
                            showDecisionBadge: true,
                            maxPixelSize: 2000
                        )
                        .frame(maxWidth: 640)
                        .padding(.horizontal, LuminaTokens.Spacing.lg)
                        .accessibilityLabel("\(asset.filename), active palette photograph")

                        inclusionActions(for: asset)
                            .padding(.horizontal, LuminaTokens.Spacing.lg)
                    }

                    paletteGrid(group: group)
                }
                .padding(.vertical, LuminaTokens.Spacing.lg)
            }
        } else {
            Text("Select a palette")
                .font(LuminaTokens.Typeface.title(18))
                .foregroundStyle(LuminaTokens.Ink.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func paletteHeader(group: GroupPresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.title)
                .font(LuminaTokens.Typeface.title(22))
                .foregroundStyle(LuminaTokens.Ink.primary)
                .accessibilityAddTraits(.isHeader)

            if let subtitle = group.subtitle {
                Text(subtitle)
                    .font(LuminaTokens.Typeface.meta(13))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
            }

            if let note = group.relationshipNote {
                Text(note)
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
            }
        }
        .padding(.horizontal, LuminaTokens.Spacing.lg)
    }

    private func inclusionActions(for asset: AssetPresentation) -> some View {
        HStack(spacing: LuminaTokens.Spacing.sm) {
            inclusionButton(
                title: asset.decision == .cut ? "Include" : "Exclude",
                isActive: asset.decision == .cut,
                accessibility: asset.decision == .cut ? "Include in palette" : "Exclude from palette",
                action: { onToggleInclusion(asset.id) }
            )

            inclusionButton(
                title: "Reference",
                isActive: asset.decision == .anchor,
                accessibility: "Set as reference photograph",
                action: { onSetReference(asset.id) }
            )

            if asset.isProtected {
                Text("Protected")
                    .font(LuminaTokens.Typeface.meta(11, weight: .medium))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(LuminaTokens.Surface.secondary)
                    )
                    .accessibilityLabel("Protected anchor")
            }

            Spacer(minLength: 0)
        }
    }

    private func inclusionButton(
        title: String,
        isActive: Bool,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(LuminaTokens.Typeface.control(14, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? LuminaTokens.Ink.primary : LuminaTokens.Ink.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: LuminaTokens.HitTarget.minimum)
                .background(
                    RoundedRectangle(cornerRadius: LuminaTokens.Radius.button, style: .continuous)
                        .fill(isActive ? LuminaTokens.Surface.secondary : LuminaTokens.Surface.mist)
                )
                .overlay {
                    if isActive {
                        RoundedRectangle(cornerRadius: LuminaTokens.Radius.button, style: .continuous)
                            .strokeBorder(LuminaTokens.Line.hairline, lineWidth: LuminaTokens.Line.hairlineWidth)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(LuminaQuietButtonStyle())
        .accessibilityLabel(accessibility)
    }

    private func paletteGrid(group: GroupPresentation) -> some View {
        let columns = [
            GridItem(.adaptive(minimum: 120, maximum: 160), spacing: LuminaTokens.Spacing.sm, alignment: .top)
        ]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: LuminaTokens.Spacing.sm) {
            ForEach(group.assets) { asset in
                Button {
                    onSelectAsset(asset.id)
                } label: {
                    StablePhotoView(
                        asset: asset,
                        contentMode: .fill,
                        cornerRadius: LuminaTokens.Radius.photographThumb,
                        showDecisionBadge: true,
                        isSelected: asset.id == presentation.selectedAssetID,
                        maxPixelSize: 640
                    )
                    .frame(height: 100)
                    .clipped()
                }
                .buttonStyle(LuminaQuietButtonStyle())
                .accessibilityLabel("\(asset.filename), \(asset.decision.title)")
                .accessibilityAddTraits(asset.id == presentation.selectedAssetID ? .isSelected : [])
            }
        }
        .padding(.horizontal, LuminaTokens.Spacing.lg)
        .accessibilityLabel("Palette photographs")
    }
}

// MARK: - Palette rail item

private struct PaletteRailItem: View {
    let group: GroupPresentation
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: LuminaTokens.Spacing.sm) {
                if let rep = group.representative {
                    StablePhotoView(
                        asset: rep,
                        contentMode: .fill,
                        cornerRadius: LuminaTokens.Radius.photographThumb,
                        maxPixelSize: 256
                    )
                    .frame(width: 52, height: 52)
                    .clipped()
                } else {
                    LuminaTokens.Surface.secondary
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: LuminaTokens.Radius.photographThumb, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title)
                        .font(LuminaTokens.Typeface.control(13, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? LuminaTokens.Ink.primary : LuminaTokens.Ink.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(group.assets.count) photographs")
                        .font(LuminaTokens.Typeface.meta(11))
                        .foregroundStyle(LuminaTokens.Ink.tertiary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, LuminaTokens.Spacing.md)
            .padding(.vertical, LuminaTokens.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: LuminaTokens.Radius.button, style: .continuous)
                    .fill(isSelected ? LuminaTokens.Surface.elevated : Color.clear)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: LuminaTokens.Radius.button, style: .continuous)
                        .strokeBorder(LuminaTokens.Status.selection.opacity(0.35), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(LuminaQuietButtonStyle())
        .accessibilityLabel("\(group.title), \(group.assets.count) photographs")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Light") {
    LightWorkspaceView(
        presentation: PresentationFixtures.lightWorkspace(),
        onSelectAsset: { _ in },
        onSelectGroup: { _ in },
        onLensChange: { _ in },
        onToggleInclusion: { _ in },
        onSetReference: { _ in },
        onHome: {},
        onFinish: {}
    )
    .frame(width: 1200, height: 820)
}
