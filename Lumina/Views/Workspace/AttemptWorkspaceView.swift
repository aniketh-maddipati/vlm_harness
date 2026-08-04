import SwiftUI

struct AttemptWorkspaceView: View {
    let presentation: WorkspacePresentation
    var isFocusMode: Bool = false
    var showInspector: Bool = false
    var onSelectAsset: (AssetID) -> Void
    var onLensChange: (WorkspaceLens) -> Void
    var onDecision: (AssetDecision) -> Void
    var onToggleFocus: () -> Void
    var onToggleInspector: () -> Void
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

            if let group = presentation.selectedGroup, !isFocusMode {
                GroupRelationshipCaption(group: group)
                    .padding(.top, LuminaTokens.Spacing.xs)
            }

            workspaceStage
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !isFocusMode {
                if let group = presentation.selectedGroup {
                    AttemptFilmstrip(
                        assets: group.assets,
                        selectedID: presentation.selectedAssetID,
                        onSelect: onSelectAsset
                    )
                }

                HStack {
                    Spacer(minLength: 0)
                    DecisionDock(
                        current: presentation.selectedAsset?.decision ?? .undecided,
                        onDecision: onDecision
                    )
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, LuminaTokens.Spacing.lg)
                .padding(.bottom, LuminaTokens.Spacing.md)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(stageBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Attempts workspace")
    }

    private var stageBackground: Color {
        isFocusMode ? LuminaTokens.Surface.focusMatte : LuminaTokens.Surface.porcelain
    }

    @ViewBuilder
    private var workspaceStage: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                activeStage
                    .padding(isFocusMode ? LuminaTokens.Spacing.md : LuminaTokens.Spacing.lg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !isFocusMode && presentation.inspectorAvailable {
                    inspectorToggle
                        .padding(LuminaTokens.Spacing.md)
                }
            }

            if showInspector && !isFocusMode, let asset = presentation.selectedAsset {
                AssetInspectorPanel(asset: asset, onClose: onToggleInspector)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(LuminaTokens.Motion.route, value: showInspector)
        .animation(LuminaTokens.Motion.route, value: isFocusMode)
    }

    @ViewBuilder
    private var activeStage: some View {
        if let asset = presentation.selectedAsset {
            SpineActiveStage(
                assetID: asset.id,
                filename: asset.filename,
                isFocusMode: isFocusMode,
                onDoubleTap: onToggleFocus
            )
            .accessibilityLabel(
                isFocusMode
                    ? "\(asset.filename), focus mode. Double-tap to leave focus."
                    : "\(asset.filename), active photograph. Double-tap for focus mode."
            )
        } else {
            emptyStage
        }
    }

    private var emptyStage: some View {
        VStack(spacing: LuminaTokens.Spacing.md) {
            Text("No photograph selected")
                .font(LuminaTokens.Typeface.title(18))
                .foregroundStyle(LuminaTokens.Ink.secondary)
            Text("Choose an alternative below")
                .font(LuminaTokens.Typeface.meta(13))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("No photograph selected")
    }

    private var inspectorToggle: some View {
        Button(action: onToggleInspector) {
            Image(systemName: showInspector ? "sidebar.right" : "sidebar.right")
                .symbolVariant(showInspector ? .fill : .none)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(LuminaTokens.Ink.secondary)
                .frame(width: LuminaTokens.HitTarget.minimum, height: LuminaTokens.HitTarget.minimum)
                .background(
                    RoundedRectangle(cornerRadius: LuminaTokens.Radius.button, style: .continuous)
                        .fill(LuminaTokens.Surface.elevated.opacity(0.92))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: LuminaTokens.Radius.button, style: .continuous)
                        .strokeBorder(LuminaTokens.Line.hairline, lineWidth: LuminaTokens.Line.hairlineWidth)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(LuminaQuietButtonStyle())
        .accessibilityLabel(showInspector ? "Hide inspector" : "Show inspector")
        .help("Inspect at high fidelity (Space)")
    }
}

// MARK: - Inspector

struct AssetInspectorPanel: View {
    let asset: AssetPresentation
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.md) {
            HStack {
                Text("Inspector")
                    .font(LuminaTokens.Typeface.title(16))
                    .foregroundStyle(LuminaTokens.Ink.inspection)
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(LuminaTokens.Ink.inspection.opacity(0.7))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(LuminaQuietButtonStyle())
                .accessibilityLabel("Close inspector")
            }

            StablePhotoView(
                asset: asset,
                cornerRadius: LuminaTokens.Radius.photographThumb,
                maxPixelSize: 2400
            )
            .frame(maxHeight: 320)

            VStack(alignment: .leading, spacing: 8) {
                inspectorRow("Filename", asset.filename)
                inspectorRow("Decision", asset.decision.title)
                if asset.isProtected {
                    inspectorRow("Status", "Protected anchor")
                }
                if let caption = asset.caption {
                    inspectorRow("Note", caption)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(LuminaTokens.Spacing.lg)
        .frame(width: 300)
        .frame(maxHeight: .infinity)
        .background(LuminaTokens.Surface.inspectionMatte)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector, \(asset.filename)")
    }

    private func inspectorRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(LuminaTokens.Typeface.meta(10, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(LuminaTokens.Ink.inspection.opacity(0.5))
            Text(value)
                .font(LuminaTokens.Typeface.control(13))
                .foregroundStyle(LuminaTokens.Ink.inspection)
                .lineLimit(3)
        }
    }
}

#Preview("Attempts") {
    AttemptWorkspaceView(
        presentation: PresentationFixtures.attemptWorkspace(),
        onSelectAsset: { _ in },
        onLensChange: { _ in },
        onDecision: { _ in },
        onToggleFocus: {},
        onToggleInspector: {},
        onHome: {},
        onFinish: {}
    )
    .frame(width: 1200, height: 820)
}

#Preview("Focus mode") {
    AttemptWorkspaceView(
        presentation: PresentationFixtures.attemptWorkspace(),
        isFocusMode: true,
        onSelectAsset: { _ in },
        onLensChange: { _ in },
        onDecision: { _ in },
        onToggleFocus: {},
        onToggleInspector: {},
        onHome: {},
        onFinish: {}
    )
    .frame(width: 1200, height: 820)
}

#Preview("Inspector") {
    AttemptWorkspaceView(
        presentation: PresentationFixtures.attemptWorkspace(),
        showInspector: true,
        onSelectAsset: { _ in },
        onLensChange: { _ in },
        onDecision: { _ in },
        onToggleFocus: {},
        onToggleInspector: {},
        onHome: {},
        onFinish: {}
    )
    .frame(width: 1200, height: 820)
}
