import SwiftUI

struct WorkspaceToolbar: View {
    let title: String
    let lens: WorkspaceLens
    let progressLabel: String
    var onLensChange: (WorkspaceLens) -> Void
    var onHome: (() -> Void)? = nil
    var onFinish: (() -> Void)? = nil
    var onShowShortcuts: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: LuminaTokens.Spacing.md) {
            if let onHome {
                Button(action: onHome) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(LuminaTokens.Ink.secondary)
                        .frame(width: LuminaTokens.HitTarget.minimum, height: LuminaTokens.HitTarget.minimum)
                        .contentShape(Rectangle())
                }
                .buttonStyle(LuminaQuietButtonStyle())
                .accessibilityLabel("Back to home")
            }

            Text(title)
                .font(LuminaTokens.Typeface.title(20))
                .foregroundStyle(LuminaTokens.Ink.primary)
                .lineLimit(1)

            Spacer(minLength: 12)

            LensSwitcher(lens: lens, onChange: onLensChange)

            Text(progressLabel)
                .font(LuminaTokens.Typeface.count(13))
                .foregroundStyle(LuminaTokens.Ink.secondary)
                .frame(minWidth: 72, alignment: .trailing)
                .accessibilityLabel("Progress \(progressLabel)")

            Menu {
                if let onFinish {
                    Button("Review finished set", action: onFinish)
                }
                if let onShowShortcuts {
                    Button("Keyboard Shortcuts", action: onShowShortcuts)
                }
                Divider()
                Button("Home") { onHome?() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                    .frame(width: LuminaTokens.HitTarget.minimum, height: LuminaTokens.HitTarget.minimum)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(width: LuminaTokens.HitTarget.minimum, height: LuminaTokens.HitTarget.minimum)
            .accessibilityLabel("More")
        }
        .padding(.horizontal, LuminaTokens.Spacing.lg)
        .frame(height: 56)
        .background(LuminaTokens.Surface.porcelain)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LuminaTokens.Line.hairline)
                .frame(height: LuminaTokens.Line.hairlineWidth)
        }
    }
}

struct LensSwitcher: View {
    let lens: WorkspaceLens
    let onChange: (WorkspaceLens) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(WorkspaceLens.allCases) { item in
                Button {
                    onChange(item)
                } label: {
                    Text(item.title)
                        .font(LuminaTokens.Typeface.control(13, weight: lens == item ? .medium : .regular))
                        .foregroundStyle(lens == item ? LuminaTokens.Ink.primary : LuminaTokens.Ink.tertiary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(lens == item ? LuminaTokens.Surface.secondary : Color.clear)
                        )
                }
                .buttonStyle(LuminaQuietButtonStyle())
                .accessibilityLabel("\(item.title) lens")
                .accessibilityAddTraits(lens == item ? .isSelected : [])
                .help("\(item.title) (\(item.shortcut))")
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LuminaTokens.Surface.mist)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace lens")
    }
}

struct AttemptFilmstrip: View {
    let assets: [AssetPresentation]
    let selectedID: AssetID?
    var labels: Bool = true
    let onSelect: (AssetID) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LuminaTokens.Spacing.sm) {
                    ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                        Button {
                            onSelect(asset.id)
                        } label: {
                            StableThumbView(
                                asset: asset,
                                isSelected: asset.id == selectedID,
                                label: labels ? String(format: "A%02d", index + 1) : nil
                            )
                            .frame(width: 96)
                        }
                        .buttonStyle(LuminaQuietButtonStyle())
                        .id(asset.id)
                    }
                }
                .padding(.horizontal, LuminaTokens.Spacing.lg)
                .padding(.vertical, LuminaTokens.Spacing.sm)
            }
            .onChange(of: selectedID) { _, new in
                guard let new else { return }
                withAnimation(LuminaTokens.Motion.photo) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
        .frame(height: labels ? 110 : 88)
        .accessibilityLabel("Alternatives")
    }
}

struct GroupRelationshipCaption: View {
    let group: GroupPresentation

    var body: some View {
        HStack(spacing: 8) {
            if let subtitle = group.subtitle {
                Text(subtitle)
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
            }
            if let note = group.relationshipNote {
                Text("·").foregroundStyle(LuminaTokens.Ink.tertiary)
                Text(note)
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LuminaTokens.Spacing.lg)
        .accessibilityElement(children: .combine)
    }
}

struct LuminaCard<Content: View>: View {
    var bodyContent: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.bodyContent = content
    }

    var body: some View {
        bodyContent()
            .padding(LuminaTokens.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: LuminaTokens.Radius.card, style: .continuous)
                    .fill(LuminaTokens.Surface.elevated)
                    .shadow(color: LuminaTokens.Depth.softShadow, radius: 14, y: 4)
            )
            .overlay {
                RoundedRectangle(cornerRadius: LuminaTokens.Radius.card, style: .continuous)
                    .strokeBorder(LuminaTokens.Line.hairline, lineWidth: LuminaTokens.Line.hairlineWidth)
            }
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(LuminaTokens.Typeface.meta(11, weight: .medium))
            .tracking(1.1)
            .foregroundStyle(LuminaTokens.Ink.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

struct PhotoStripPreview: View {
    let assets: [AssetPresentation]
    var maxCount: Int = 5
    var height: CGFloat = 120

    var body: some View {
        GeometryReader { geo in
            let visible = Array(assets.prefix(maxCount))
            let spacing: CGFloat = 8
            let count = max(visible.count, 1)
            let width = max((geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count), 40)
            HStack(spacing: spacing) {
                ForEach(visible) { asset in
                    StablePhotoView(
                        asset: asset,
                        contentMode: .fill,
                        cornerRadius: LuminaTokens.Radius.photographThumb,
                        maxPixelSize: 640
                    )
                    .frame(width: width, height: height)
                    .clipped()
                }
            }
        }
        .frame(height: height)
    }
}
