import SwiftUI

/// Single continuous photographic workspace — Workbench, Canvas, and Proof share selection state.
struct ContinuousWorkspaceView: View {
    let presentation: WorkspacePresentation
    let emergingSet: [AssetPresentation]
    var projectName: String?
    var baseRecipe: DevelopRecipe = .neutral
    @Binding var workspaceStage: WorkspaceStage
    @Binding var isRowExpanded: Bool
    @Binding var treatmentPreviewMode: TreatmentPreviewMode
    @Binding var developOffsets: DevelopAdjustments
    @Binding var showDetailedEdits: Bool
    @Binding var rowPreviewActive: Bool
    var stackPreviewMix: Double = 1
    var workbenchScrollAnchor: String?
    var canvasScrollAnchor: String?
    var proofScrollAnchor: String?
    var onDevelopChange: (DevelopAdjustments) -> Void = { _ in }
    var onSelectGroup: (String) -> Void
    var onSelectPhoto: (String, AssetID) -> Void
    var onLensChange: (WorkspaceLens) -> Void
    var onSendToSet: (AssetID, String) -> Void
    var onFold: (AssetID, String) -> Void
    var onHold: (AssetID, String) -> Void
    var onFocusPhoto: (AssetID) -> Void
    var onPreviewEdits: () -> Void
    var onHome: () -> Void
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activeGroup: GroupPresentation? {
        presentation.groups.first { $0.id == presentation.selectedGroupID }
    }

    private var selectedID: AssetID? {
        presentation.selectedAssetID
    }

    private var selectedPhotoID: AssetID? {
        selectedID
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if workspaceStage != .proof {
                    workspaceHeader
                }

                switch workspaceStage {
                case .workbench:
                    workbenchBody(availableWidth: geo.size.width)
                case .canvas:
                    canvasBody
                case .proof:
                    StoryProofView(
                        assets: emergingSet,
                        scrollAnchor: proofScrollAnchor,
                        onSelect: { id in onSelectPhoto(presentation.selectedGroupID ?? "", id) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LuminaTokens.Surface.rail)
    }

    // MARK: - Header

    private var workspaceHeader: some View {
        VStack(spacing: 0) {
            WorkspaceToolbar(
                title: presentation.shootTitle,
                lens: presentation.lens,
                progressLabel: presentation.progressLabel,
                onLensChange: onLensChange,
                onHome: onHome,
                onFinish: onFinish
            )

            stageSwitcher
                .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
                .padding(.bottom, LuminaTokens.Spacing.sm)
                .background(LuminaTokens.Surface.porcelain)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(LuminaTokens.Line.hairline).frame(height: LuminaTokens.Line.hairlineWidth)
                }
        }
    }

    private var stageSwitcher: some View {
        HStack(spacing: LuminaTokens.Spacing.lg) {
            ForEach(WorkspaceStage.allCases, id: \.self) { stage in
                Button {
                    workspaceStage = stage
                } label: {
                    Text(stage.title)
                        .font(LuminaTokens.Typeface.navigation(14))
                        .foregroundStyle(workspaceStage == stage ? LuminaTokens.Ink.primary : LuminaTokens.Ink.tertiary)
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) {
                            if workspaceStage == stage {
                                Rectangle()
                                    .fill(LuminaTokens.Ink.primary.opacity(0.55))
                                    .frame(height: 1)
                                    .offset(y: 4)
                            }
                        }
                }
                .buttonStyle(LuminaQuietButtonStyle())
                .help(stageShortcutHelp(stage))
            }
            Spacer(minLength: 0)
            Text(workbenchHint)
                .font(LuminaTokens.Typeface.meta(12))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
                .lineLimit(1)
        }
        .padding(.top, LuminaTokens.Spacing.xs)
    }

    private var workbenchHint: String {
        switch workspaceStage {
        case .workbench: "S send to set · X fold · M hold · Return expand row"
        case .canvas: "Draft capture-time order"
        case .proof: ""
        }
    }

    private func stageShortcutHelp(_ stage: WorkspaceStage) -> String {
        switch stage {
        case .workbench: "⌘1"
        case .canvas: "⌘2"
        case .proof: "⌘3"
        }
    }

    // MARK: - Workbench

    private func workbenchBody(availableWidth: CGFloat) -> some View {
        let compactRail = availableWidth < 1100
        return HStack(spacing: 0) {
            WorkbenchLedgerView(
                presentation: presentation,
                isRowExpanded: isRowExpanded,
                projectName: projectName,
                baseRecipe: baseRecipe,
                developOffsets: $developOffsets,
                treatmentPreviewMode: $treatmentPreviewMode,
                showDetailedEdits: $showDetailedEdits,
                rowPreviewActive: $rowPreviewActive,
                stackPreviewMix: stackPreviewMix,
                scrollAnchor: workbenchScrollAnchor,
                onDevelopChange: onDevelopChange,
                onPreviewEdits: onPreviewEdits,
                onSelectGroup: onSelectGroup,
                onSelectPhoto: onSelectPhoto,
                onFocusPhoto: onFocusPhoto
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            EmergingSetRail(
                assets: emergingSet,
                selectedID: selectedID,
                isCompact: compactRail,
                onSelect: { id in
                    if let gid = presentation.selectedGroupID {
                        onSelectPhoto(gid, id)
                    }
                },
                onOpenCanvas: { workspaceStage = .canvas }
            )
        }
    }

    // MARK: - Canvas

    private var canvasBody: some View {
        HStack(spacing: 0) {
            WorkbenchSourceRail(
                groups: presentation.groups,
                selectedGroupID: presentation.selectedGroupID,
                onSelectGroup: onSelectGroup
            )

            StoryCanvasView(
                assets: emergingSet,
                selectedID: selectedID,
                scrollAnchor: canvasScrollAnchor,
                projectName: projectName,
                onSelect: { id in
                    if let gid = presentation.selectedGroupID {
                        onSelectPhoto(gid, id)
                    }
                },
                onEnterProof: { workspaceStage = .proof }
            )
        }
    }
}

// MARK: - Workbench ledger

struct WorkbenchLedgerView: View {
    let presentation: WorkspacePresentation
    let isRowExpanded: Bool
    var projectName: String?
    var baseRecipe: DevelopRecipe
    @Binding var developOffsets: DevelopAdjustments
    @Binding var treatmentPreviewMode: TreatmentPreviewMode
    @Binding var showDetailedEdits: Bool
    @Binding var rowPreviewActive: Bool
    var stackPreviewMix: Double
    var scrollAnchor: String?
    var onDevelopChange: (DevelopAdjustments) -> Void
    var onPreviewEdits: () -> Void
    let onSelectGroup: (String) -> Void
    let onSelectPhoto: (String, AssetID) -> Void
    let onFocusPhoto: (AssetID) -> Void

    private var effectiveOffsets: DevelopAdjustments {
        treatmentPreviewMode == .current ? developOffsets : .zero
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: LuminaTokens.Spacing.lg) {
                    ForEach(presentation.groups) { group in
                        let isActive = group.id == presentation.selectedGroupID
                        let selected = presentation.selectedAssetID
                        let suggested = group.captureOrderedAssets.first(where: { $0.decision == .undecided })?.id

                        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.sm) {
                            TreatmentFamilyRow(
                                group: group,
                                isActive: isActive,
                                isExpanded: isActive && isRowExpanded,
                                selectedID: isActive ? selected : nil,
                                suggestedStartID: suggested,
                                projectName: projectName,
                                baseRecipe: baseRecipe,
                                developOffsets: effectiveOffsets,
                                previewMix: stackPreviewMix,
                                rowPreviewActive: rowPreviewActive && isActive,
                                onSelect: { onSelectGroup(group.id) },
                                onSelectPhoto: { onSelectPhoto(group.id, $0) },
                                onDoubleTapPhoto: onFocusPhoto
                            )

                            if isActive && isRowExpanded {
                                ContextualTreatmentStrip(
                                    previewMode: $treatmentPreviewMode,
                                    offsets: Binding(
                                        get: { developOffsets },
                                        set: { newValue in
                                            developOffsets = newValue
                                            onDevelopChange(newValue)
                                        }
                                    ),
                                    showDetailed: $showDetailedEdits,
                                    rowPreviewActive: rowPreviewActive,
                                    onPreviewRow: onPreviewEdits,
                                    onReset: {
                                        developOffsets = .zero
                                        onDevelopChange(.zero)
                                        treatmentPreviewMode = .current
                                    }
                                )
                            }
                        }
                        .id(group.id)
                    }
                }
                .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
                .padding(.vertical, LuminaTokens.Spacing.lg)
            }
            .background(LuminaTokens.Surface.porcelain)
            .onChange(of: presentation.selectedGroupID) { _, new in
                guard let new else { return }
                withAnimation(LuminaTokens.Motion.selection) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
            .onAppear {
                if let scrollAnchor { proxy.scrollTo(scrollAnchor, anchor: .center) }
            }
        }
    }
}

// MARK: - Canvas source rail

struct WorkbenchSourceRail: View {
    let groups: [GroupPresentation]
    let selectedGroupID: String?
    let onSelectGroup: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: LuminaTokens.Spacing.sm) {
                ForEach(groups) { group in
                    Button { onSelectGroup(group.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.title)
                                .font(LuminaTokens.Typeface.meta(12))
                                .foregroundStyle(group.id == selectedGroupID ? LuminaTokens.Ink.primary : LuminaTokens.Ink.secondary)
                                .lineLimit(2)
                            if let thumb = group.captureOrderedAssets.first {
                                StablePhotoView(
                                    asset: thumb,
                                    contentMode: .fit,
                                    cornerRadius: LuminaTokens.Radius.photographThumb,
                                    maxPixelSize: 400
                                )
                                .frame(height: 48)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(group.id == selectedGroupID ? LuminaTokens.Surface.highlight : Color.clear)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    group.id == selectedGroupID ? LuminaTokens.Line.emphasis : LuminaTokens.Line.hairline,
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(LuminaQuietButtonStyle())
                }
            }
            .padding(LuminaTokens.Spacing.sm)
        }
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .background(LuminaTokens.Surface.rail)
        .overlay(alignment: .trailing) {
            Rectangle().fill(LuminaTokens.Line.hairline).frame(width: LuminaTokens.Line.hairlineWidth)
        }
    }
}

#Preview("Continuous workspace") {
    ContinuousWorkspaceView(
        presentation: PresentationFixtures.attemptWorkspace(),
        emergingSet: [],
        workspaceStage: .constant(.workbench),
        isRowExpanded: .constant(true),
        treatmentPreviewMode: .constant(.current),
        developOffsets: .constant(.zero),
        showDetailedEdits: .constant(false),
        rowPreviewActive: .constant(false),
        onSelectGroup: { _ in },
        onSelectPhoto: { _, _ in },
        onLensChange: { _ in },
        onSendToSet: { _, _ in },
        onFold: { _, _ in },
        onHold: { _, _ in },
        onFocusPhoto: { _ in },
        onPreviewEdits: {},
        onHome: {},
        onFinish: {}
    )
    .frame(width: 1440, height: 900)
}
