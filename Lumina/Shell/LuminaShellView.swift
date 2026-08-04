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
                decisionReceiptMessage: shell.decisionReceipt?.message,
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
                onPreviewEdits: { shell.toggleRowPreview() },
                onHome: { shell.openHome() },
                onFinish: { shell.openFinish() }
            )

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
        ("↑ / ↓", "Previous / next row"),
        ("← / →", "Photograph within row"),
        ("Return", "Expand / collapse active row"),
        ("Space", "High-resolution focus"),
        ("S", "Add to set"),
        ("X", "Set aside"),
        ("M", "Hold"),
        ("A", "Preview Auto treatment"),
        ("E", "Detailed edit controls"),
        ("⌘Z", "Undo last decision"),
        ("⌘1 / ⌘2 / ⌘3", "Workbench / Canvas / Proof"),
        ("Esc", "Return one level"),
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
