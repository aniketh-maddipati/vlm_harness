import SwiftUI

/// Phase 1 product shell — five coherent states, one interaction model.
struct LuminaShellView: View {
    @Bindable var model: ProjectViewModel
    @Bindable var shell: LuminaShellModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LuminaTokens.Surface.porcelain.ignoresSafeArea()

            Group {
                switch shell.route {
                case .home:
                    HomeView(
                        presentation: shell.homePresentation(model: model),
                        onOpenNew: { enterWorkspaceFromHome() },
                        onContinue: { enterWorkspaceFromHome() },
                        onOpenFinished: { _ in shell.openFinish() },
                        onOpenSettings: {
                            NotificationCenter.default.post(name: .luminaOpenPreferences, object: nil)
                        },
                        onOpenShoot: {
                            if model.catalogQueue.totalFolders > 0 {
                                shell.openShootSelection()
                            } else {
                                model.pickRAWFolder()
                            }
                        },
                        onScanBacklog: { model.pickCatalogRoot() }
                    )
                case .shootSelection:
                    ShootSelectionView(
                        presentation: shell.shootPresentation(model: model),
                        onOpen: { _ in shell.openWorkspace(lens: shell.lens) },
                        onBack: { shell.openHome() }
                    )
                case .workspace:
                    workspaceBody
                case .finish:
                    FinishView(
                        presentation: shell.finishPresentation(model: model),
                        onFinish: { model.exportCarousel() },
                        onReview: { shell.openWorkspace(lens: .attempts) },
                        onUndo: {},
                        onBack: { shell.openWorkspace(lens: shell.lens) }
                    )
                }
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.995)))
        }
        .animation(reduceMotion ? nil : LuminaTokens.Motion.route, value: shell.route)
        .animation(reduceMotion ? nil : LuminaTokens.Motion.route, value: shell.lens)
        .onAppear {
            shell.syncSelectionFromModel(model)
            shell.refreshSnapshotsIfNeeded(model: model)
        }
        .onChange(of: model.project?.name) { _, _ in
            shell.invalidateCache()
            shell.syncSelectionFromModel(model)
            shell.refreshSnapshotsIfNeeded(model: model)
        }
        .onChange(of: model.cursor) { _, cursor in
            // Selection sync only — does not rebuild shell snapshots.
            if let cursor { shell.selectedAssetID = cursor }
        }
        .onChange(of: model.keepCount) { _, _ in
            shell.invalidateCache()
        }
        .onChange(of: model.totalCount) { _, _ in
            shell.invalidateCache()
            shell.refreshSnapshotsIfNeeded(model: model)
        }
        .sheet(isPresented: $shell.showShortcuts) {
            KeyboardShortcutsSheet()
        }
    }

    @ViewBuilder
    private var workspaceBody: some View {
        let presentation = shell.workspacePresentation(model: model)
        let photoID = shell.selectedAssetID ?? presentation.selectedAssetID
        let baseRecipe: DevelopRecipe = {
            guard let photoID, let photo = model.photo(with: photoID) else { return .neutral }
            switch shell.treatmentPreviewMode {
            case .original: return .neutral
            case .auto, .current: return model.appliedRecipe(for: photo)
            }
        }()

        ZStack {
            ContinuousWorkspaceView(
                presentation: presentation,
                emergingSet: model.emergingSetPresentations(),
                projectName: model.project?.name,
                baseRecipe: baseRecipe,
                workspaceStage: Binding(
                    get: { shell.workspaceStage },
                    set: { shell.setWorkspaceStage($0) }
                ),
                isRowExpanded: Binding(
                    get: { shell.isRowExpanded },
                    set: { shell.isRowExpanded = $0 }
                ),
                treatmentPreviewMode: Binding(
                    get: { shell.treatmentPreviewMode },
                    set: { shell.treatmentPreviewMode = $0 }
                ),
                developOffsets: Binding(
                    get: { shell.developOffsets },
                    set: { shell.developOffsets = $0 }
                ),
                showDetailedEdits: Binding(
                    get: { shell.showDetailedEdits },
                    set: { shell.showDetailedEdits = $0 }
                ),
                rowPreviewActive: Binding(
                    get: { shell.rowPreviewActive },
                    set: { shell.rowPreviewActive = $0 }
                ),
                stackPreviewMix: shell.stackPreviewMix,
                workbenchScrollAnchor: shell.workbenchScrollAnchor,
                canvasScrollAnchor: shell.canvasScrollAnchor,
                proofScrollAnchor: shell.proofScrollAnchor,
                routingFlightID: shell.routingFlightID,
                routingFlightIDs: shell.routingFlightIDs,
                decisionReceiptMessage: shell.decisionReceipt?.message,
                stagingCopySnapshot: shell.stagingCopySnapshot,
                selection: shell.workbenchSelection,
                isTreatmentStageOpen: shell.isTreatmentStageOpen,
                isReadMode: shell.isReadMode,
                travelAnimation: shell.fastRunTracker.travelAnimation,
                onDevelopChange: { offsets in
                    guard let photoID else { return }
                    shell.treatmentPreviewMode = .current
                    shell.setDevelopOffsets(offsets, for: photoID, model: model)
                },
                onSelectGroup: { groupID in
                    shell.selectLead(in: groupID, model: model, presentation: presentation)
                },
                onSelectPhoto: { groupID, assetID in
                    shell.selectGroup(groupID)
                    shell.selectAsset(assetID)
                    shell.scrollTargetGroupID = groupID
                    if model.project != nil { model.setCursor(assetID) }
                    shell.loadDevelop(for: assetID, model: model)
                    _ = PreviewSpine.shared.paint(id: assetID, inputTime: CFAbsoluteTimeGetCurrent(), held: false)
                },
                onGatherPhoto: { assetID in
                    shell.workbenchSelection.gather(assetID)
                    shell.selectAsset(assetID)
                    if model.project != nil { model.setCursor(assetID) }
                    shell.loadDevelop(for: assetID, model: model)
                },
                onLensChange: { newLens in
                    shell.setLens(newLens)
                    shell.resetStackPreview()
                    shell.refreshSnapshotsIfNeeded(model: model)
                },
                onSendToSet: { assetID, groupID in
                    shell.selectGroup(groupID)
                    shell.selectAsset(assetID)
                    shell.applyDecision(.keep, for: assetID, model: model)
                },
                onFold: { assetID, groupID in
                    shell.selectGroup(groupID)
                    shell.selectAsset(assetID)
                    shell.applyDecision(.cut, for: assetID, model: model)
                },
                onHold: { assetID, groupID in
                    shell.selectGroup(groupID)
                    shell.selectAsset(assetID)
                    shell.applyDecision(.needsMe, for: assetID, model: model)
                },
                onRestore: { assetID in
                    shell.restoreFromFold(assetID: assetID, model: model)
                },
                onUndo: {
                    shell.undoLastDecision(model: model)
                },
                onFocusPhoto: { assetID in
                    shell.selectAsset(assetID)
                    shell.isFocusMode = true
                },
                onOpenTreatment: { assetID in
                    shell.selectAsset(assetID)
                    shell.loadDevelop(for: assetID, model: model)
                    shell.openTreatmentStage()
                    // Prewarm the RAW session so the live pipeline's first frame is fast.
                    if let photo = model.photo(with: assetID),
                       FileManager.default.fileExists(atPath: photo.rawPath) {
                        let recipe = EditRecipe(
                            from: DevelopEngine.clampRecipe(model.appliedRecipe(for: photo)),
                            id: assetID
                        )
                        WorkbenchDevelop.scheduler.prewarm(
                            photos: [(id: assetID, rawURL: URL(fileURLWithPath: photo.rawPath))],
                            recipe: recipe
                        )
                    }
                },
                onCloseTreatment: {
                    shell.closeTreatmentStage()
                },
                onStageTreat: {
                    guard let photoID,
                          let photo = model.photo(with: photoID) else { return }
                    let recipe = model.appliedRecipe(for: photo).applying(shell.developOffsets)
                    _ = shell.workbenchSelection.stage(.treat(recipe))
                    shell.refreshStagingCopy(model: model)
                    LuminaHaptics.decision()
                },
                onConfirmRound: {
                    _ = shell.commitRound(shell.workbenchSelection, model: model)
                },
                onCancelStage: {
                    shell.workbenchSelection.cancel()
                    shell.stagingCopySnapshot = nil
                    LuminaHaptics.alignment()
                },
                onApplyToSet: {
                    let applied = shell.applyTreatmentToSet(model: model, presentation: presentation)
                    if applied > 0 { LuminaHaptics.decision() } else { LuminaHaptics.light() }
                },
                onAddRetouch: { assetID, spot in
                    model.updateRetouch(for: assetID) { $0.append(spot) }
                },
                onUndoRetouch: { assetID in
                    model.updateRetouch(for: assetID) { if !$0.isEmpty { $0.removeLast() } }
                },
                onClearRetouch: { assetID in
                    model.updateRetouch(for: assetID) { $0.removeAll() }
                },
                cropSession: Binding(
                    get: { shell.cropSession },
                    set: { shell.cropSession = $0 }
                ),
                onEnterCrop: {
                    guard let photoID else { return }
                    shell.enterCrop(for: photoID, model: model)
                },
                onStageAdvance: {
                    if shell.workbenchSelection.stage(.advance) {
                        LuminaHaptics.decision()
                    } else {
                        LuminaHaptics.light()
                    }
                },
                onStageSetAside: {
                    if shell.workbenchSelection.stage(.setAside) {
                        LuminaHaptics.decision()
                    } else {
                        LuminaHaptics.light()
                    }
                },
                onStageHold: {
                    if shell.workbenchSelection.stage(.hold) {
                        LuminaHaptics.decision()
                    } else {
                        LuminaHaptics.light()
                    }
                },
                onPreviewEdits: { shell.toggleRowPreview() },
                onHome: { shell.openHome() },
                onFinish: { shell.openFinish() },
                onOpenSources: { shell.openShootSelection() },
                fidelity: {
                    switch PreviewSpine.shared.paintedTier {
                    case .empty, .silhouette: return .interactivePreview
                    case .preview: return .fullPreview
                    }
                }(),
                exifLine: photoID.flatMap { model.photo(with: $0)?.filename } ?? "",
                sourceDisconnected: {
                    guard let path = model.project?.rawFolder else { return false }
                    return !FileManager.default.fileExists(atPath: path)
                }()
            )
            .commandHandling(shell: shell, model: model, presentation: presentation)

            if shell.isFocusMode {
                FocusOverlayView(
                    presentation: presentation,
                    onSelectAsset: { id in
                        shell.selectAsset(id)
                        if model.project != nil { model.setCursor(id) }
                        shell.loadDevelop(for: id, model: model)
                    },
                    onClose: { shell.isFocusMode = false },
                    onPrevious: {
                        shell.moveAlternative(delta: -1, presentation: presentation, model: model)
                    },
                    onNext: {
                        shell.moveAlternative(delta: 1, presentation: presentation, model: model)
                    }
                )
            }
        }
        .accessibilityHint(shell.workbenchSelection.accessibilityAnnouncement)
    }

    private func enterWorkspaceFromHome() {
        if model.project == nil, model.canResumeLastProject {
            model.resumeLastProject()
        }
        shell.invalidateCache()
        shell.syncSelectionFromModel(model)
        shell.refreshSnapshotsIfNeeded(model: model)
        shell.openWorkspace(lens: .attempts)
    }
}

struct KeyboardShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let rows: [(String, String)] = [
        ("↑ / ↓", "Previous / next family"),
        ("← / →", "Move leader / tray focus"),
        ("⌘-click", "Gather up to 3 photographs"),
        ("⌘↩", "Stage Advance — ↩ confirms"),
        ("⌘⌫", "Stage Set aside"),
        ("⌘⇧↩", "Stage Hold"),
        ("Esc", "Cancel staged action"),
        ("T", "Open treatment (Edit)"),
        ("Space", "Original hold (Edit) / 1:1 focus"),
        ("⌘⇧A", "Apply treatment to whole set (Edit)"),
        ("⌘⌥C", "More treatment controls"),
        ("⌘Z", "Undo whole round"),
        ("⌘1 / ⌘2 / ⌘3", "Sources / Workbench / Story"),
        ("⌘R", "Read inside Story"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.lg) {
            HStack {
                Text("Keyboard")
                    .font(LuminaTokens.Typeface.title(22))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                Spacer()
                LuminaGhostActionButton(title: "Close") { dismiss() }
            }
            VStack(spacing: 10) {
                ForEach(rows, id: \.0) { key, label in
                    HStack {
                        Text(key)
                            .font(LuminaTokens.Typeface.control(13, weight: .medium))
                            .foregroundStyle(LuminaTokens.Ink.primary)
                            .frame(width: 100, alignment: .leading)
                        Text(label)
                            .font(LuminaTokens.Typeface.control(13))
                            .foregroundStyle(LuminaTokens.Ink.secondary)
                        Spacer()
                    }
                }
            }
            Spacer()
        }
        .padding(LuminaTokens.Spacing.xl)
        .frame(width: 420, height: 500)
        .background(LuminaTokens.Surface.porcelain)
    }
}
