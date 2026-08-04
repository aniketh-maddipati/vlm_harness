import SwiftUI

/// Unified Attempts / Light workspace — porcelain palette board with optional Focus overlay.
struct PaletteWorkspaceView: View {
    let presentation: WorkspacePresentation
    var isFocusMode: Bool = false
    var scrollTargetGroupID: String?
    var onSelectAsset: (AssetID) -> Void
    var onLensChange: (WorkspaceLens) -> Void
    var onDecision: (AssetDecision) -> Void
    var onToggleFocus: () -> Void
    var onHome: () -> Void
    var onFinish: () -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                WorkspaceToolbar(
                    title: presentation.shootTitle,
                    lens: presentation.lens,
                    progressLabel: presentation.progressLabel,
                    onLensChange: onLensChange,
                    onHome: onHome,
                    onFinish: onFinish
                )

                if presentation.groups.isEmpty {
                    emptyBoard
                } else {
                    PaletteBoardView(
                        groups: presentation.groups,
                        lens: presentation.lens,
                        selectedAssetID: presentation.selectedAssetID,
                        scrollTargetGroupID: scrollTargetGroupID,
                        onSelectAsset: { id in
                            onSelectAsset(id)
                        }
                    )
                    .animation(reduceMotion ? nil : LuminaTokens.Motion.photo, value: presentation.lens)
                    .animation(reduceMotion ? nil : LuminaTokens.Motion.photo, value: presentation.groups.map(\.id))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LuminaTokens.Surface.porcelain)

            if isFocusMode {
                FocusOverlayView(
                    presentation: presentation,
                    onSelectAsset: onSelectAsset,
                    onDecision: onDecision,
                    onClose: onToggleFocus,
                    onPrevious: onPrevious,
                    onNext: onNext
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(presentation.lens.title) workspace")
    }

    private var emptyBoard: some View {
        VStack(spacing: LuminaTokens.Spacing.md) {
            Text("No photographs yet")
                .font(LuminaTokens.Typeface.title(20))
                .foregroundStyle(LuminaTokens.Ink.secondary)
            Text("Open a shoot to begin reviewing on the palette board.")
                .font(LuminaTokens.Typeface.meta(13))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Porcelain Attempts") {
    PaletteWorkspaceView(
        presentation: PresentationFixtures.attemptWorkspace(),
        onSelectAsset: { _ in },
        onLensChange: { _ in },
        onDecision: { _ in },
        onToggleFocus: {},
        onHome: {},
        onFinish: {},
        onPrevious: {},
        onNext: {}
    )
    .frame(width: 1200, height: 820)
}

#Preview("Porcelain Light") {
    PaletteWorkspaceView(
        presentation: PresentationFixtures.lightWorkspace(),
        onSelectAsset: { _ in },
        onLensChange: { _ in },
        onDecision: { _ in },
        onToggleFocus: {},
        onHome: {},
        onFinish: {},
        onPrevious: {},
        onNext: {}
    )
    .frame(width: 1200, height: 820)
}

#Preview("Narrow window") {
    PaletteWorkspaceView(
        presentation: PresentationFixtures.attemptWorkspace(),
        onSelectAsset: { _ in },
        onLensChange: { _ in },
        onDecision: { _ in },
        onToggleFocus: {},
        onHome: {},
        onFinish: {},
        onPrevious: {},
        onNext: {}
    )
    .frame(width: 720, height: 820)
}

#Preview("Wide window") {
    PaletteWorkspaceView(
        presentation: PresentationFixtures.lightWorkspace(),
        onSelectAsset: { _ in },
        onLensChange: { _ in },
        onDecision: { _ in },
        onToggleFocus: {},
        onHome: {},
        onFinish: {},
        onPrevious: {},
        onNext: {}
    )
    .frame(width: 1600, height: 820)
}

#Preview("Ungrouped shoot") {
    PaletteWorkspaceView(
        presentation: PresentationFixtures.ungroupedWorkspace(),
        onSelectAsset: { _ in },
        onLensChange: { _ in },
        onDecision: { _ in },
        onToggleFocus: {},
        onHome: {},
        onFinish: {},
        onPrevious: {},
        onNext: {}
    )
    .frame(width: 1100, height: 760)
}
