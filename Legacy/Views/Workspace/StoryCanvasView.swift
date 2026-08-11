import SwiftUI

/// Editorial vertical sequence of kept photographs — draft capture-time order.
struct StoryCanvasView: View {
    let assets: [AssetPresentation]
    let selectedID: AssetID?
    var showChrome: Bool = true
    var scrollAnchor: String?
    var projectName: String?
    let onSelect: (AssetID) -> Void
    let onEnterProof: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: LuminaTokens.Spacing.xl) {
                    if showChrome {
                        canvasHeader
                    }

                    if assets.isEmpty {
                        emptyCanvas
                    } else {
                        storyBlocks
                    }
                }
                .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
                .padding(.vertical, LuminaTokens.Spacing.lg)
            }
            .onAppear {
                if let scrollAnchor { proxy.scrollTo(scrollAnchor, anchor: .center) }
            }
            .onChange(of: scrollAnchor) { _, anchor in
                guard let anchor else { return }
                withAnimation(LuminaTokens.Motion.selection) {
                    proxy.scrollTo(anchor, anchor: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LuminaTokens.Surface.porcelain)
    }

    private var canvasHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Emerging set")
                    .font(LuminaTokens.Typeface.editorial(28))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                Text("Draft order · capture time")
                    .font(LuminaTokens.Typeface.meta(13))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
            }
            Spacer(minLength: 12)
            Button("Read") { onEnterProof() }
                .font(LuminaTokens.Typeface.navigation(14))
                .foregroundStyle(LuminaTokens.Ink.secondary)
                .buttonStyle(LuminaQuietButtonStyle())
                .disabled(assets.isEmpty)
                .help("⌘R")
        }
        .padding(.bottom, LuminaTokens.Spacing.sm)
    }

    private var emptyCanvas: some View {
        Text("Send photographs to the set from the Workbench to build a canvas.")
            .font(LuminaTokens.Typeface.meta(14))
            .foregroundStyle(LuminaTokens.Ink.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, LuminaTokens.Spacing.xxl)
    }

    @ViewBuilder
    private var storyBlocks: some View {
        ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
            let isHero = index == 0
            storyPhoto(asset, maxHeight: isHero ? 480 : 320, isHero: isHero)
                .id(asset.id.uuidString)

            if index == 1 {
                narrativePlaceholder
            }
        }
    }

    private func storyPhoto(_ asset: AssetPresentation, maxHeight: CGFloat, isHero: Bool) -> some View {
        Button { onSelect(asset.id) } label: {
            StablePhotoView(
                asset: asset,
                contentMode: .fit,
                cornerRadius: LuminaTokens.Radius.photographLarge,
                isSelected: asset.id == selectedID,
                maxPixelSize: isHero ? 2400 : 1600
            )
            .frame(maxHeight: maxHeight)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(LuminaQuietButtonStyle())
    }

    private var narrativePlaceholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Narrative")
                .font(LuminaTokens.Typeface.meta(10, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(LuminaTokens.Ink.tertiary)
            Text("Story copy could live here — not implemented in this iteration.")
                .font(LuminaTokens.Typeface.meta(13))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
                .italic()
        }
        .padding(.vertical, LuminaTokens.Spacing.lg)
        .accessibilityLabel("Narrative placeholder")
    }
}

/// Proof — same canvas without chrome or badges.
struct StoryProofView: View {
    let assets: [AssetPresentation]
    var scrollAnchor: String?
    let onSelect: (AssetID) -> Void

    @State private var showHint = true

    var body: some View {
        ZStack(alignment: .bottom) {
            StoryCanvasView(
                assets: assets,
                selectedID: nil,
                showChrome: false,
                scrollAnchor: scrollAnchor,
                onSelect: onSelect,
                onEnterProof: {}
            )

            if showHint {
                Text("Esc to return to canvas")
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(LuminaTokens.Surface.porcelain.opacity(0.92))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(LuminaTokens.Line.hairline, lineWidth: 1)
                    }
                    .padding(.bottom, LuminaTokens.Spacing.lg)
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 4_000_000_000)
                            withAnimation(LuminaTokens.Motion.control) { showHint = false }
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LuminaTokens.Surface.porcelain)
    }
}
