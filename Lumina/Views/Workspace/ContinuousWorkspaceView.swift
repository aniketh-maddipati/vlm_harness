import AppKit
import SwiftUI

/// Single continuous photographic workspace — Workbench / Story share selection state.
/// Read is a mode inside Story (⌘R), not a destination in the stage switch.
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
    var routingFlightIDs: [AssetID] = []
    var decisionReceiptMessage: String?
    var stagingCopySnapshot: StagingCopySnapshot?
    var selection: WorkbenchSelection?
    var isTreatmentStageOpen: Bool = false
    var isReadMode: Bool = false
    var travelAnimation: Animation = LuminaTokens.Motion.travel
    var onDevelopChange: (DevelopAdjustments) -> Void = { _ in }
    var onSelectGroup: (String) -> Void
    var onSelectPhoto: (String, AssetID) -> Void
    var onGatherPhoto: (AssetID) -> Void = { _ in }
    var onLensChange: (WorkspaceLens) -> Void
    var onSendToSet: (AssetID, String) -> Void
    var onFold: (AssetID, String) -> Void
    var onHold: (AssetID, String) -> Void
    var onRestore: (AssetID) -> Void = { _ in }
    var onUndo: () -> Void = {}
    var onFocusPhoto: (AssetID) -> Void
    var onOpenTreatment: (AssetID) -> Void = { _ in }
    var onCloseTreatment: () -> Void = {}
    var onStageTreat: () -> Void = {}
    var onConfirmRound: () -> Void = {}
    var onCancelStage: () -> Void = {}
    var onApplyToSet: () -> Void = {}
    var onAddRetouch: (AssetID, RetouchSpot) -> Void = { _, _ in }
    var onUndoRetouch: (AssetID) -> Void = { _ in }
    var onClearRetouch: (AssetID) -> Void = { _ in }
    @Binding var cropSession: CropSession?
    var onEnterCrop: () -> Void = {}
    var onStageAdvance: () -> Void = {}
    var onStageSetAside: () -> Void = {}
    var onStageHold: () -> Void = {}
    var onPreviewEdits: () -> Void
    var onHome: () -> Void
    var onFinish: () -> Void
    var onOpenSources: () -> Void = {}
    var fidelity: TreatmentFidelity = .interactivePreview
    var exifLine: String = ""
    var sourceDisconnected: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var routingNamespace
    /// Story pane fraction — default 0.36; preserved across Edit.
    @State private var storyFraction: Double = 0.36
    @State private var isDraggingDivider = false
    @State private var dragOriginFraction: Double?
    @State private var forceTwoUp = false
    @State private var savedStoryFractionForEdit: Double?

    private var selectedID: AssetID? {
        selection?.leader ?? presentation.selectedAssetID
    }

    private var gatheredIDs: Set<AssetID> {
        Set(selection?.ids ?? [])
    }

    private var twoUp: Bool {
        forceTwoUp || storyFraction >= 0.48
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    if workspaceStage != .proof && !isReadMode {
                        workspaceHeader
                    }

                    if isTreatmentStageOpen {
                        treatmentBody
                    } else {
                        switch workspaceStage {
                        case .workbench:
                            workbenchBody(availableWidth: geo.size.width, availableHeight: geo.size.height)
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

                if let message = decisionReceiptMessage, workspaceStage == .workbench, !isTreatmentStageOpen {
                    let canUndo = message != "Undone" && message != "Hold cleared"
                    DecisionReceiptBanner(
                        message: message,
                        onUndo: canUndo ? onUndo : nil
                    )
                    .padding(.bottom, 120)
                    .transition(.opacity)
                    .zIndex(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(workspaceStage == .workbench ? LuminaTokens.Surface.table : LuminaTokens.Surface.rail)
        .animation(reduceMotion ? nil : LuminaTokens.Motion.control, value: decisionReceiptMessage)
        .onAppear {
            if let saved = savedStoryFractionForEdit {
                storyFraction = saved
            }
        }
        .onChange(of: isTreatmentStageOpen) { _, open in
            if open {
                savedStoryFractionForEdit = storyFraction
            } else if let saved = savedStoryFractionForEdit {
                storyFraction = saved
            }
        }
        .onChange(of: isReadMode) { _, reading in
            if reading {
                workspaceStage = .proof
            } else if workspaceStage == .proof {
                workspaceStage = .canvas
            }
        }
    }

    // MARK: - Header

    private var workspaceHeader: some View {
        VStack(spacing: 0) {
            if let snapshot = stagingCopySnapshot {
                Text(CopyContract.stagedHeader(snapshot))
                    .font(LuminaTokens.Typeface.meta(12, weight: .medium).monospaced())
                    .foregroundStyle(LuminaTokens.Ink.onTable)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
                    .padding(.vertical, 8)
                    .background(LuminaTokens.Surface.tableHead)
            }

            WorkspaceToolbar(
                title: presentation.shootTitle,
                lens: presentation.lens,
                progressLabel: presentation.tableHeaderLabel,
                onLensChange: onLensChange,
                onHome: onHome,
                onFinish: onFinish
            )

            stageSwitcher
                .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
                .padding(.bottom, LuminaTokens.Spacing.sm)
                .background(LuminaTokens.Surface.tableHead)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                }
        }
        .frame(height: 52, alignment: .bottom)
    }

    private var stageSwitcher: some View {
        HStack(spacing: LuminaTokens.Spacing.lg) {
            Button {
                onOpenSources()
            } label: {
                Text("Sources")
                    .font(LuminaTokens.Typeface.navigation(14))
                    .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
                    .padding(.vertical, 6)
            }
            .buttonStyle(LuminaQuietButtonStyle())
            .help("⌘1")
            .accessibilityLabel("Sources")
            .accessibilityHint("Open shoot selection. Command 1.")

            ForEach(WorkspaceStage.switcherCases, id: \.self) { stage in
                Button {
                    workspaceStage = stage
                } label: {
                    Text(stage.title)
                        .font(LuminaTokens.Typeface.navigation(14))
                        .foregroundStyle(workspaceStage == stage ? LuminaTokens.Ink.onTable : LuminaTokens.Ink.onTableSecondary)
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) {
                            if workspaceStage == stage {
                                Rectangle()
                                    .fill(LuminaTokens.Ink.onTable.opacity(0.55))
                                    .frame(height: 1)
                                    .offset(y: 4)
                            }
                        }
                }
                .buttonStyle(LuminaQuietButtonStyle())
                .help(stageShortcutHelp(stage))
                .accessibilityLabel("\(stage.title) stage")
                .accessibilityHint("Shortcut \(stageShortcutHelp(stage))")
                .accessibilityAddTraits(workspaceStage == stage ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.top, LuminaTokens.Spacing.xs)
    }

    private func stageShortcutHelp(_ stage: WorkspaceStage) -> String {
        switch stage {
        case .workbench: "⌘2"
        case .canvas: "⌘3"
        case .proof: "⌘R"
        }
    }

    // MARK: - Treatment

    @ViewBuilder
    private var treatmentBody: some View {
        // Focus follows the selected photograph so scrolling/tapping the
        // carousel grows that frame and hosts live develop.
        if let leaderID = presentation.selectedAssetID ?? selection?.leader,
           let leader = asset(for: leaderID) {
            let refs = (selection?.ids ?? [])
                .filter { $0 != leaderID }
                .compactMap { asset(for: $0) }
            let stagedRecipe: DevelopRecipe? = {
                switch selection?.staged {
                case .treat(let r): return r
                case .develop: return baseRecipe.applying(developOffsets)
                default: return nil
                }
            }()
            let setAssets = presentation.groups
                .first { group in group.assets.contains(where: { $0.id == leaderID }) }?
                .captureOrderedAssets.filter { $0.decision != .cut }
                ?? [leader]
            let setSize = setAssets.count
            TreatmentStageView(
                leader: leader,
                references: refs,
                setPhotos: setAssets,
                selectionCount: max(selection?.count ?? 1, 1),
                setCount: setSize,
                projectName: projectName,
                baseRecipe: baseRecipe,
                offsets: $developOffsets,
                previewMode: $treatmentPreviewMode,
                stagedRecipe: stagedRecipe,
                stagingSnapshot: stagingCopySnapshot,
                fidelity: sourceDisconnected ? .previewsOnly : fidelity,
                localOverrideNotes: localOverrideNotes(for: refs),
                storyStrip: emergingSet,
                exifLine: exifLine.isEmpty ? leader.filename : exifLine,
                onClose: onCloseTreatment,
                onOffsetsChange: onDevelopChange,
                onStageTreat: onStageTreat,
                onConfirmTreat: onConfirmRound,
                onCancelStage: onCancelStage,
                onOpenMore: { showDetailedEdits = true },
                onSelectReference: { id in
                    if let gid = presentation.selectedGroupID {
                        onSelectPhoto(gid, id)
                    }
                },
                onApplyToSet: onApplyToSet,
                onAddRetouch: { spot in onAddRetouch(leaderID, spot) },
                onUndoRetouch: { onUndoRetouch(leaderID) },
                onClearRetouch: { onClearRetouch(leaderID) },
                cropSession: $cropSession,
                onEnterCrop: onEnterCrop
            )
        }
    }

    private func localOverrideNotes(for refs: [AssetPresentation]) -> [AssetID: String] {
        var notes: [AssetID: String] = [:]
        // Surface a local-override caption when a sibling already carries its own recipe offsets.
        for asset in refs where abs(developOffsets.shadows) > 0.5 && asset.id != selectedID {
            notes[asset.id] = String(format: "staged · shadows %+.0f local override", developOffsets.shadows)
            break
        }
        return notes
    }

    private func asset(for id: AssetID) -> AssetPresentation? {
        for group in presentation.groups {
            if let found = group.assets.first(where: { $0.id == id }) { return found }
        }
        return emergingSet.first(where: { $0.id == id })
    }

    // MARK: - Workbench

    @ViewBuilder
    private func workbenchBody(availableWidth: CGFloat, availableHeight: CGFloat) -> some View {
        let compactRail = availableWidth < 1100
            || availableWidth < (IngestPreferences.workbenchLeftMin + IngestPreferences.workbenchRightMin)
        let isHandling = selection?.isHandling == true
        let stagedAdvance = selection?.staged == .advance
        let stagedTreat = {
            switch selection?.staged {
            case .treat, .develop: return true
            default: return false
            }
        }()
        let receivingCount = stagedAdvance ? (selection?.count ?? 0) : 0
        // Width actually available to the ledger tray — rows size themselves
        // from this so the bench always justifies to the screen.
        let railWidth: CGFloat = compactRail
            ? 84
            : clampedRightWidth(availableWidth: availableWidth, fraction: storyFraction) + 6
        let trayWidth = max(availableWidth - 74 - railWidth, 400)

        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                // Edge preview strip — adjacent families, not gatherable.
                edgePreviewStrip
                    .frame(width: 74)

                mainTrayColumn(
                    isHandling: isHandling,
                    stagedAdvance: stagedAdvance,
                    twoUp: twoUp,
                    trayWidth: trayWidth
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !compactRail {
                    WorkbenchSplitDivider(
                        isDragging: $isDraggingDivider,
                        onDragBegan: {
                            if dragOriginFraction == nil {
                                dragOriginFraction = storyFraction
                            }
                        },
                        onDrag: { translation in
                            let origin = dragOriginFraction ?? storyFraction
                            let next = origin - Double(translation / max(availableWidth, 1))
                            applyFraction(next, availableWidth: availableWidth)
                        },
                        onDragEnded: {
                            dragOriginFraction = nil
                        },
                        onReset: {
                            applyFraction(0.36, availableWidth: availableWidth)
                        }
                    )
                    .frame(width: 6)

                    storyPane(
                        receivingCount: receivingCount,
                        stagedAdvance: stagedAdvance,
                        width: clampedRightWidth(availableWidth: availableWidth, fraction: storyFraction)
                    )
                } else {
                    EmergingSetRail(
                        assets: emergingSet,
                        selectedID: selectedID,
                        isCompact: true,
                        routingNamespace: routingNamespace,
                        routingFlightID: routingFlightID,
                        receivingCount: receivingCount,
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
            }

            if let selection, !selection.isEmpty {
                Color.clear
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(selection.accessibilityAnnouncement)
                    .accessibilitySortPriority(1.5)
                    .frame(width: 0, height: 0)
            }

            if let selection, !selection.isEmpty, selection.hasEverHandled {
                WorkbenchShelf(
                    selectionCount: selection.count,
                    label: selection.shelfLabel,
                    staged: selection.staged,
                    reduceTransparency: reduceTransparency,
                    onSetAside: onStageSetAside,
                    onHold: onStageHold,
                    onAdvance: onStageAdvance
                )
                .padding(.horizontal, 30)
                .padding(.bottom, 8)
                .opacity(1)
                .offset(y: 0)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(reduceMotion ? nil : LuminaTokens.Motion.shelfIn, value: selection.count)
                .zIndex(15)
                .accessibilitySortPriority(2)
            } else if selection?.hasEverHandled != true, (selection?.completedRoundCount ?? 0) < 3 {
                Text("Hold ⌘ when you are ready to handle these.")
                    .font(LuminaTokens.Typeface.meta(13))
                    .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
                    .padding(.bottom, 28)
                    .transition(.opacity)
            }

            if stagedTreat, let snapshot = stagingCopySnapshot {
                StagedTreatmentBanner(snapshot: snapshot)
                    .padding(.bottom, 152)
                    .zIndex(16)
                    .transition(.opacity)
            } else if stagedAdvance, let count = selection?.count, count > 0 {
                StagedAdvanceBanner(count: count)
                    .padding(.bottom, 152)
                    .zIndex(16)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : LuminaTokens.Motion.stage, value: selection?.staged)
    }

    private var edgePreviewStrip: some View {
        let neighbors = neighboringGroups()
        return VStack(spacing: 10) {
            ForEach(neighbors.prefix(4)) { group in
                if let thumb = group.captureOrderedAssets.first {
                    StablePhotoView(
                        asset: thumb,
                        contentMode: .fit,
                        cornerRadius: 2,
                        maxPixelSize: 240
                    )
                    .frame(width: 56)
                    .aspectRatio(thumb.aspectRatio, contentMode: .fit)
                    .opacity(0.40)
                    .allowsHitTesting(false)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(LuminaTokens.Surface.tableHead)
        .accessibilitySortPriority(5)
        .accessibilityLabel("Adjacent families")
    }

    private func neighboringGroups() -> [GroupPresentation] {
        guard let selected = presentation.selectedGroupID,
              let idx = presentation.groups.firstIndex(where: { $0.id == selected }) else {
            return Array(presentation.groups.prefix(2))
        }
        var result: [GroupPresentation] = []
        if idx > 0 { result.append(presentation.groups[idx - 1]) }
        if idx + 1 < presentation.groups.count { result.append(presentation.groups[idx + 1]) }
        return result
    }

    @ViewBuilder
    private func mainTrayColumn(isHandling: Bool, stagedAdvance: Bool, twoUp: Bool, trayWidth: CGFloat) -> some View {
        ZStack {
            LuminaTokens.Surface.table
            if isHandling {
                Color.black.opacity(0.18)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                if storyFraction >= 0.48 && !forceTwoUp {
                    HStack {
                        Spacer()
                        Button("Fit three") { forceTwoUp = false; /* keep fraction; tray reads twoUp from fraction */ }
                            .font(LuminaTokens.Typeface.meta(11))
                            .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
                            .buttonStyle(LuminaQuietButtonStyle())
                            .opacity(0) // placeholder; real control below
                    }
                }
                if storyFraction >= 0.48 {
                    HStack {
                        Text(twoUp ? "Two across" : "Three across")
                            .font(LuminaTokens.Typeface.meta(11))
                            .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
                        Spacer()
                        Button("Fit three") {
                            forceTwoUp = false
                            // Never move the divider programmatically — only offer the button.
                        }
                        .font(LuminaTokens.Typeface.meta(11))
                        .foregroundStyle(LuminaTokens.Ink.onTable)
                        .buttonStyle(LuminaQuietButtonStyle())
                        .opacity(twoUp ? 1 : 0.4)
                        .disabled(!twoUp)
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 8)
                }

                workbenchLedger(twoUp: twoUp, isHandling: isHandling, stagedAdvance: stagedAdvance, trayWidth: trayWidth)
            }
        }
        .accessibilitySortPriority(1)
    }

    private func workbenchLedger(twoUp: Bool, isHandling: Bool, stagedAdvance: Bool, trayWidth: CGFloat) -> some View {
        WorkbenchLedgerView(
            presentation: presentation,
            isRowExpanded: isRowExpanded,
            availableWidth: trayWidth,
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
            routingFlightIDs: routingFlightIDs,
            showDecisionShelf: false,
            gatheredIDs: gatheredIDs,
            leaderID: selection?.leader,
            isHandling: isHandling,
            stagedAdvance: stagedAdvance,
            twoUp: twoUp,
            reduceMotion: reduceMotion,
            travelAnimation: travelAnimation,
            onDevelopChange: onDevelopChange,
            onPreviewEdits: onPreviewEdits,
            onSelectGroup: onSelectGroup,
            onSelectPhoto: onSelectPhoto,
            onGatherPhoto: onGatherPhoto,
            onFocusPhoto: onFocusPhoto,
            onOpenTreatment: onOpenTreatment,
            onAddToSet: { id, gid in onSendToSet(id, gid) },
            onSetAside: { id, gid in onFold(id, gid) },
            onHold: { id, gid in onHold(id, gid) },
            onRestore: onRestore
        )
    }

    private func storyPane(receivingCount: Int, stagedAdvance: Bool, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            EmergingSetRail(
                assets: emergingSet,
                selectedID: selectedID,
                isCompact: false,
                routingNamespace: routingNamespace,
                routingFlightID: routingFlightID,
                receivingCount: receivingCount,
                highlightFirstSlot: stagedAdvance,
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
            .frame(maxHeight: .infinity)

            setAsideFold
                .accessibilitySortPriority(4)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .accessibilitySortPriority(3)
    }

    private var setAsideFold: some View {
        let folded = presentation.groups.flatMap { $0.assets.filter { $0.decision == .cut } }
        return HStack(spacing: 8) {
            HStack(spacing: -10) {
                ForEach(folded.prefix(3)) { asset in
                    StablePhotoView(
                        asset: asset,
                        contentMode: .fit,
                        cornerRadius: 2,
                        maxPixelSize: 200
                    )
                    .frame(width: 66, height: 40)
                    .opacity(0.85)
                }
            }
            Text("\(folded.count) set aside")
                .font(LuminaTokens.Typeface.meta(11))
                .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
            Spacer(minLength: 0)
            if let first = folded.first {
                Button("Restore") { onRestore(first.id) }
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.onTable)
                    .buttonStyle(LuminaQuietButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(LuminaTokens.Surface.tableHead)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
        .accessibilityLabel("Set aside fold, \(folded.count) photographs")
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
        storyFraction = stored
    }

    // MARK: - Story (Canvas)

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
                showChrome: !isReadMode,
                scrollAnchor: canvasScrollAnchor ?? proofScrollAnchor,
                projectName: projectName,
                onSelect: { id in
                    if let gid = presentation.selectedGroupID {
                        onSelectPhoto(gid, id)
                    }
                },
                onEnterProof: {
                    workspaceStage = .proof
                }
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
                .frame(width: 6)
                .contentShape(Rectangle())
            Rectangle()
                .fill(isDragging ? LuminaTokens.Ink.onTable.opacity(0.40) : Color.white.opacity(0.12))
                .frame(width: 1)
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
        .accessibilityLabel("Resize story pane")
        .accessibilityHint("Drag to resize. Double-click to restore default.")
    }
}

// MARK: - Workbench ledger

struct WorkbenchLedgerView: View {
    let presentation: WorkspacePresentation
    let isRowExpanded: Bool
    /// Tray width — rows scale tiles and page count from this.
    var availableWidth: CGFloat = 0
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
    var routingFlightIDs: [AssetID] = []
    var showDecisionShelf: Bool
    var gatheredIDs: Set<AssetID> = []
    var leaderID: AssetID?
    var isHandling: Bool = false
    var stagedAdvance: Bool = false
    var twoUp: Bool = false
    var reduceMotion: Bool = false
    var travelAnimation: Animation = LuminaTokens.Motion.travel
    var onDevelopChange: (DevelopAdjustments) -> Void
    var onPreviewEdits: () -> Void
    let onSelectGroup: (String) -> Void
    let onSelectPhoto: (String, AssetID) -> Void
    var onGatherPhoto: (AssetID) -> Void = { _ in }
    let onFocusPhoto: (AssetID) -> Void
    var onOpenTreatment: (AssetID) -> Void = { _ in }
    var onAddToSet: (AssetID, String) -> Void
    var onSetAside: (AssetID, String) -> Void
    var onHold: (AssetID, String) -> Void
    var onRestore: (AssetID) -> Void

    private var effectiveOffsets: DevelopAdjustments {
        treatmentPreviewMode == .current ? developOffsets : .zero
    }

    /// Two across when the story pane is wide; otherwise as many 300 pt+
    /// tiles as the tray genuinely fits (3–5).
    private var responsivePageSize: Int {
        TableLayout.responsivePageSize(twoUp: twoUp, availableWidth: availableWidth)
    }

    @State private var tableHovered = false
    @State private var hoverHintOpacity: Double = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: LuminaTokens.Spacing.md) {
                        ForEach(TableLayout.swimLaneUnits(from: presentation.groups)) { unit in
                            SwimLaneContainer(
                                laneHeader: unit.laneHeader,
                                sceneBreakBefore: unit.sceneBreakBefore
                            ) {
                                VStack(alignment: .leading, spacing: LuminaTokens.Spacing.sm) {
                                    ForEach(unit.groups) { group in
                                        rowBlock(for: group)
                                            .id(group.id)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.bottom, 10)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, LuminaTokens.Spacing.md)
                }
                .background(Color.clear)
                .onHover { hovering in
                    tableHovered = hovering
                    withAnimation(hovering ? LuminaTokens.Motion.tableHoverIn : LuminaTokens.Motion.tableHoverOut) {
                        hoverHintOpacity = hovering ? 1 : 0
                    }
                }
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

            tableFooterChrome
        }
    }

    private var tableFooterChrome: some View {
        ZStack(alignment: .bottomLeading) {
            Text(CopyContract.tableFooterShortcuts)
                .font(LuminaTokens.Typeface.meta(11))
                .foregroundStyle(LuminaTokens.Ink.onTableSecondary.opacity(0.72))
            Text(CopyContract.tableFooterHover)
                .font(LuminaTokens.Typeface.meta(11))
                .foregroundStyle(LuminaTokens.Ink.onTableSecondary.opacity(0.92))
                .opacity(hoverHintOpacity)
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func rowBlock(for group: GroupPresentation) -> some View {
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
                routingFlightIDs: routingFlightIDs,
                showDecisionShelf: false,
                gatheredIDs: isActive ? gatheredIDs : [],
                leaderID: isActive ? leaderID : nil,
                isHandling: isHandling && isActive,
                stagedAdvance: stagedAdvance && isActive,
                pageSize: responsivePageSize,
                availableWidth: max(availableWidth - 60, 0),
                twoUp: twoUp,
                reduceMotion: reduceMotion,
                travelAnimation: travelAnimation,
                onSelect: { onSelectGroup(group.id) },
                onSelectPhoto: { onSelectPhoto(group.id, $0) },
                onGatherPhoto: onGatherPhoto,
                onDoubleTapPhoto: onFocusPhoto,
                onCommandDoubleTap: onOpenTreatment,
                onAddToSet: { onAddToSet($0, group.id) },
                onSetAside: { onSetAside($0, group.id) },
                onHold: { onHold($0, group.id) },
                onRestore: onRestore
            )
            .frame(minHeight: expanded ? 480 : nil)
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
        onFinish: {},
        cropSession: .constant(nil),
        onEnterCrop: {}
    )
    .frame(width: 1440, height: 900)
}
