// QUARANTINED(D40) — legacy quarantine, retired checkpoint-by-checkpoint.
// Contract: design/contract-v6.md D40 · schedule: design/checkpoint-sequence-v6.md
// No new references from outside Legacy/. Enforced by Scripts/lint/quarantine_d40.sh.
// Do not extend, restyle, or re-enter these types under new names.
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
                        .font(LuminaTokens.Typeface.navigation(13, weight: .medium))
                        .foregroundStyle(LuminaTokens.Ink.secondary)
                        .frame(width: LuminaTokens.HitTarget.minimum, height: LuminaTokens.HitTarget.minimum)
                        .contentShape(Rectangle())
                }
                .buttonStyle(LuminaQuietButtonStyle())
                .accessibilityLabel("Back to home")
            }

            Text(title)
                .font(LuminaTokens.Typeface.editorial(30))
                .foregroundStyle(LuminaTokens.Ink.primary)
                .lineLimit(1)

            Spacer(minLength: 12)

            LensSwitcher(lens: lens, onChange: onLensChange)

            Text(progressLabel)
                .font(LuminaTokens.Typeface.count(13))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
                .frame(minWidth: 64, alignment: .trailing)
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
                    .font(LuminaTokens.Typeface.navigation(14, weight: .medium))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                    .frame(width: LuminaTokens.HitTarget.minimum, height: LuminaTokens.HitTarget.minimum)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(width: LuminaTokens.HitTarget.minimum, height: LuminaTokens.HitTarget.minimum)
            .accessibilityLabel("More")
        }
        .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
        .frame(height: LuminaTokens.HitTarget.header)
        .background(LuminaTokens.Surface.porcelain)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LuminaTokens.Line.hairline.opacity(0.65))
                .frame(height: LuminaTokens.Line.hairlineWidth)
        }
    }
}

struct LensSwitcher: View {
    let lens: WorkspaceLens
    let onChange: (WorkspaceLens) -> Void

    var body: some View {
        HStack(spacing: LuminaTokens.Spacing.lg) {
            ForEach(WorkspaceLens.allCases) { item in
                Button {
                    onChange(item)
                } label: {
                    Text(item.title)
                        .font(LuminaTokens.Typeface.navigation(15))
                        .foregroundStyle(lens == item ? LuminaTokens.Ink.primary : LuminaTokens.Ink.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(alignment: .bottom) {
                            if lens == item {
                                Capsule(style: .continuous)
                                    .fill(LuminaTokens.Surface.mist)
                                    .padding(.horizontal, -4)
                                    .padding(.vertical, -2)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if lens == item {
                                Rectangle()
                                    .fill(LuminaTokens.Ink.primary.opacity(0.35))
                                    .frame(height: 1)
                                    .offset(y: 8)
                            }
                        }
                }
                .buttonStyle(LuminaQuietButtonStyle())
                .accessibilityLabel("\(item.title) lens")
                .accessibilityAddTraits(lens == item ? .isSelected : [])
                .help("\(item.title) (\(item.shortcut))")
            }
        }
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
                .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
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
                    .font(LuminaTokens.Typeface.meta(13))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
            }
            if let note = group.relationshipNote {
                Text("·").foregroundStyle(LuminaTokens.Ink.tertiary)
                Text(note)
                    .font(LuminaTokens.Typeface.meta(13))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
        .accessibilityElement(children: .combine)
    }
}

/// Flat content container — whitespace grouping, no dashboard card chrome.
struct LuminaCard<Content: View>: View {
    var bodyContent: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.bodyContent = content
    }

    var body: some View {
        bodyContent()
            .padding(.vertical, LuminaTokens.Spacing.md)
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(LuminaTokens.Typeface.navigation(13))
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
