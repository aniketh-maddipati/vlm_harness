import AppKit
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
    var routingFlightID: AssetID?
    var decisionReceiptMessage: String?
    var onDevelopChange: (DevelopAdjustments) -> Void = { _ in }
    var onSelectGroup: (String) -> Void
    var onSelectPhoto: (String, AssetID) -> Void
    var onLensChange: (WorkspaceLens) -> Void
    var onSendToSet: (AssetID, String) -> Void
    var onFold: (AssetID, String) -> Void
    var onHold: (AssetID, String) -> Void
    var onRestore: (AssetID) -> Void = { _ in }
    var onUndo: () -> Void = {}
    var onFocusPhoto: (AssetID) -> Void
    var onPreviewEdits: () -> Void
    var onHome: () -> Void
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var routingNamespace
    @State private var setFraction: Double = IngestPreferences.workbenchSetFraction
    @State private var isDraggingDivider = false
    @State private var dragOriginFraction: Double?

    private var selectedID: AssetID? {
        presentation.selectedAssetID
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
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

                if let message = decisionReceiptMessage, workspaceStage == .workbench {
                    DecisionReceiptBanner(
                        message: message,
                        onUndo: decisionReceiptMessage == "Undone" ? nil : onUndo
                    )
                        .padding(.bottom, 20)
                        .transition(.opacity)
                        .zIndex(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LuminaTokens.Surface.rail)
        .animation(reduceMotion ? nil : LuminaTokens.Motion.control, value: decisionReceiptMessage)
        .onAppear {
            setFraction = IngestPreferences.workbenchSetFraction
        }
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
        }
        .padding(.top, LuminaTokens.Spacing.xs)
    }

    private func stageShortcutHelp(_ stage: WorkspaceStage) -> String {
        switch stage {
        case .workbench: "⌘1"
        case .canvas: "⌘2"
        case .proof: "⌘3"
        }
    }

    // MARK: - Workbench

    @ViewBuilder
    private func workbenchBody(availableWidth: CGFloat) -> some View {
        let compactRail = availableWidth < 1100
            || availableWidth < (IngestPreferences.workbenchLeftMin + IngestPreferences.workbenchRightMin)

        if compactRail {
            HStack(spacing: 0) {
                workbenchLedger
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                EmergingSetRail(
                    assets: emergingSet,
                    selectedID: selectedID,
                    isCompact: true,
                    routingNamespace: routingNamespace,
                    routingFlightID: routingFlightID,
                    onSelect: { id in
                        if let gid = presentation.selectedGroupID {
                            onSelectPhoto(gid, id)
                        }
                    },
                    onOpenCanvas: { workspaceStage = .canvas },
                    onDropAddToSet: { id in
                        onSendToSet(id, presentation.selectedGroupID ?? "")
                    }
                )
            }
        } else {
            let rightWidth = clampedRightWidth(availableWidth: availableWidth, fraction: setFraction)
            HStack(spacing: 0) {
                workbenchLedger
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                WorkbenchSplitDivider(
                    isDragging: $isDraggingDivider,
                    onDragBegan: {
                        if dragOriginFraction == nil {
                            dragOriginFraction = setFraction
                        }
                    },
                    onDrag: { translation in
                        let origin = dragOriginFraction ?? setFraction
                        let next = origin - Double(translation / max(availableWidth, 1))
                        applyFraction(next, availableWidth: availableWidth)
                    },
                    onDragEnded: {
                        dragOriginFraction = nil
                    },
                    onReset: {
                        applyFraction(IngestPreferences.workbenchSetFractionDefault, availableWidth: availableWidth)
                    }
                )

                EmergingSetRail(
                    assets: emergingSet,
                    selectedID: selectedID,
                    isCompact: false,
                    routingNamespace: routingNamespace,
                    routingFlightID: routingFlightID,
                    onSelect: { id in
                        if let gid = presentation.selectedGroupID {
                            onSelectPhoto(gid, id)
                        }
                    },
                    onOpenCanvas: { workspaceStage = .canvas },
                    onDropAddToSet: { id in
                        onSendToSet(id, presentation.selectedGroupID ?? "")
                    }
                )
                .frame(width: rightWidth)
                .frame(maxHeight: .infinity)
            }
        }
    }

    private var workbenchLedger: some View {
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
            routingNamespace: routingNamespace,
            routingFlightID: routingFlightID,
            showDecisionShelf: workspaceStage == .workbench,
            onDevelopChange: onDevelopChange,
            onPreviewEdits: onPreviewEdits,
            onSelectGroup: onSelectGroup,
            onSelectPhoto: onSelectPhoto,
            onFocusPhoto: onFocusPhoto,
            onAddToSet: { id, gid in onSendToSet(id, gid) },
            onSetAside: { id, gid in onFold(id, gid) },
            onHold: { id, gid in onHold(id, gid) },
            onRestore: onRestore
        )
    }

    private func clampedRightWidth(availableWidth: CGFloat, fraction: Double) -> CGFloat {
        let maxRight = availableWidth * IngestPreferences.workbenchRightMaxFraction
        let minRight = IngestPreferences.workbenchRightMin
        let maxByLeft = availableWidth - IngestPreferences.workbenchLeftMin
        let ideal = availableWidth * fraction
        return min(max(ideal, minRight), min(maxRight, maxByLeft))
    }

    private func applyFraction(_ fraction: Double, availableWidth: CGFloat) {
        let width = clampedRightWidth(availableWidth: availableWidth, fraction: fraction)
        let stored = Double(width / max(availableWidth, 1))
        setFraction = stored
        IngestPreferences.workbenchSetFraction = stored
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

// MARK: - Quiet splitter

private struct WorkbenchSplitDivider: View {
    @Binding var isDragging: Bool
    var onDragBegan: () -> Void
    var onDrag: (CGFloat) -> Void
    var onDragEnded: () -> Void
    var onReset: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 10)
                .contentShape(Rectangle())
            Rectangle()
                .fill(isDragging ? LuminaTokens.Ink.primary.opacity(0.28) : LuminaTokens.Line.hairline)
                .frame(width: LuminaTokens.Line.hairlineWidth)
        }
        .frame(maxHeight: .infinity)
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    isDragging = true
                    onDragBegan()
                    onDrag(value.translation.width)
                }
                .onEnded { _ in
                    isDragging = false
                    onDragEnded()
                }
        )
        .onTapGesture(count: 2) { onReset() }
        .accessibilityLabel("Resize emerging set")
        .accessibilityHint("Drag to resize. Double-click to restore default.")
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
    var routingNamespace: Namespace.ID?
    var routingFlightID: AssetID?
    var showDecisionShelf: Bool
    var onDevelopChange: (DevelopAdjustments) -> Void
    var onPreviewEdits: () -> Void
    let onSelectGroup: (String) -> Void
    let onSelectPhoto: (String, AssetID) -> Void
    let onFocusPhoto: (AssetID) -> Void
    var onAddToSet: (AssetID, String) -> Void
    var onSetAside: (AssetID, String) -> Void
    var onHold: (AssetID, String) -> Void
    var onRestore: (AssetID) -> Void

    private var effectiveOffsets: DevelopAdjustments {
        treatmentPreviewMode == .current ? developOffsets : .zero
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: LuminaTokens.Spacing.md) {
                    ForEach(presentation.groups) { group in
                        let isActive = group.id == presentation.selectedGroupID
                        let selected = presentation.selectedAssetID
                        let suggested = group.captureOrderedAssets.first(where: { $0.decision == .undecided })?.id
                        let expanded = isActive && isRowExpanded

                        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.sm) {
                            TreatmentFamilyRow(
                                group: group,
                                isActive: isActive,
                                isExpanded: expanded,
                                selectedID: isActive ? selected : nil,
                                suggestedStartID: suggested,
                                projectName: projectName,
                                baseRecipe: baseRecipe,
                                developOffsets: effectiveOffsets,
                                previewMix: stackPreviewMix,
                                rowPreviewActive: rowPreviewActive && isActive,
                                routingNamespace: routingNamespace,
                                routingFlightID: routingFlightID,
                                showDecisionShelf: showDecisionShelf && expanded,
                                onSelect: { onSelectGroup(group.id) },
                                onSelectPhoto: { onSelectPhoto(group.id, $0) },
                                onDoubleTapPhoto: onFocusPhoto,
                                onAddToSet: { onAddToSet($0, group.id) },
                                onSetAside: { onSetAside($0, group.id) },
                                onHold: { onHold($0, group.id) },
                                onRestore: onRestore
                            )
                            .frame(minHeight: expanded ? 360 : nil)
                            .frame(maxHeight: expanded ? .infinity : nil)

                            if expanded {
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
                .padding(.vertical, LuminaTokens.Spacing.md)
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
