import SwiftUI

/// Secondary focused culling surface — compact controls, aspect-correct stage.
struct FocusOverlayView: View {
    let presentation: WorkspacePresentation
    let onSelectAsset: (AssetID) -> Void
    let onDecision: (AssetDecision) -> Void
    let onClose: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var asset: AssetPresentation? { presentation.selectedAsset }
    private var group: GroupPresentation? { presentation.selectedGroup }

    var body: some View {
        ZStack {
            LuminaTokens.Surface.focusScrim
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: LuminaTokens.Spacing.md) {
                focusHeader
                    .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
                    .padding(.top, LuminaTokens.Spacing.lg)

                if let asset {
                    SpineActiveStage(
                        assetID: asset.id,
                        filename: asset.filename,
                        imageAspect: asset.aspectRatio,
                        isFocusMode: true,
                        onDoubleTap: onClose
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, LuminaTokens.Spacing.xl)
                    .accessibilityLabel("\(asset.filename), focus")
                }

                if let group, group.assets.count > 1 {
                    nearbyAlternatives(group: group)
                }

                HStack(spacing: LuminaTokens.Spacing.md) {
                    LuminaGhostActionButton(title: "Previous") { onPrevious() }
                    DecisionDock(
                        current: asset?.decision ?? .undecided,
                        isCompact: true,
                        onDecision: onDecision
                    )
                    LuminaGhostActionButton(title: "Next") { onNext() }
                }
                .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
                .padding(.bottom, LuminaTokens.Spacing.lg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LuminaTokens.Surface.porcelain
                    .shadow(
                        color: LuminaTokens.Depth.focusShadow,
                        radius: LuminaTokens.Depth.focusShadowRadius,
                        y: LuminaTokens.Depth.focusShadowY
                    )
                    .ignoresSafeArea()
            )
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("Focus")
    }

    private var focusHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(asset?.filename ?? "Photograph")
                    .font(LuminaTokens.Typeface.navigation(14))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                    .lineLimit(1)
                if let group {
                    Text(group.title)
                        .font(LuminaTokens.Typeface.meta(13))
                        .foregroundStyle(LuminaTokens.Ink.secondary)
                }
            }
            Spacer(minLength: 12)
            LuminaGhostActionButton(title: "Close") { onClose() }
                .help("Escape")
        }
    }

    private func nearbyAlternatives(group: GroupPresentation) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LuminaTokens.Spacing.sm) {
                ForEach(group.assets) { item in
                    Button {
                        onSelectAsset(item.id)
                    } label: {
                        StablePhotoView(
                            asset: item,
                            contentMode: .fit,
                            cornerRadius: LuminaTokens.Radius.photographThumb,
                            isSelected: item.id == asset?.id,
                            maxPixelSize: 640
                        )
                        .frame(width: 88, height: 66)
                    }
                    .buttonStyle(LuminaQuietButtonStyle())
                }
            }
            .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
        }
        .frame(height: 78)
        .accessibilityLabel("Nearby alternatives")
    }
}

#Preview("Focus landscape") {
    FocusOverlayView(
        presentation: PresentationFixtures.attemptWorkspace(),
        onSelectAsset: { _ in },
        onDecision: { _ in },
        onClose: {},
        onPrevious: {},
        onNext: {}
    )
    .frame(width: 1200, height: 820)
}

#Preview("Focus portrait") {
    FocusOverlayView(
        presentation: PresentationFixtures.focusPortrait(),
        onSelectAsset: { _ in },
        onDecision: { _ in },
        onClose: {},
        onPrevious: {},
        onNext: {}
    )
    .frame(width: 1200, height: 820)
}
