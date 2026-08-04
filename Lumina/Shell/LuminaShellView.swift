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
        let leadID = shell.selectedAssetID ?? presentation.selectedAssetID
        let baseRecipe: DevelopRecipe = {
            guard let leadID, let photo = model.photo(with: leadID) else { return .neutral }
            return model.appliedRecipe(for: photo)
        }()
        CullWorkspaceView(
            presentation: presentation,
            projectName: model.project?.name,
            baseRecipe: baseRecipe,
            developOffsets: Binding(
                get: { shell.developOffsets },
                set: { shell.developOffsets = $0 }
            ),
            stackPreviewMix: shell.stackPreviewMix,
            revealToken: shell.workspaceRevealToken,
            onDevelopChange: { offsets in
                guard let leadID else { return }
                shell.setDevelopOffsets(offsets, for: leadID, model: model)
            },
            onSelectGroup: { groupID in
                shell.resetStackPreview()
                shell.selectLead(in: groupID, model: model, presentation: presentation)
            },
            onSelectLead: { groupID, assetID in
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
                let updated = shell.workspacePresentation(model: model)
                if let first = updated.groups.first {
                    shell.selectLead(in: first.id, model: model, presentation: updated)
                }
            },
            onDecision: { decision, assetID, groupID in
                shell.selectGroup(groupID)
                shell.selectAsset(assetID)
                shell.applyDecision(decision, for: assetID, model: model)
            },
            onApplyToRest: { groupID in
                let fresh = shell.workspacePresentation(model: model)
                shell.applyDecisionToRest(in: groupID, model: model, presentation: fresh)
            },
            onPreviewEdits: { shell.replayStackPreview() },
            onHome: { shell.openHome() },
            onFinish: { shell.openFinish() }
        )
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
        ("← / →", "Previous / next row"),
        ("↑ / ↓", "Frame within row"),
        ("⌘K", "Keep lead frame"),
        ("⌘X", "Cut lead frame"),
        ("⌘M", "Maybe — decide later"),
        ("⌘↩", "Cut duplicates behind lead"),
        ("⌘− / ⌘+", "Exposure down / up (develop pane)"),
        ("⌘E", "Replay edit preview"),
        ("⌘1 / ⌘2", "Subject / Time rows"),
        ("⌘Z", "Undo"),
        ("Esc", "Dismiss overlay"),
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
        .frame(width: 420, height: 460)
        .background(LuminaTokens.Surface.porcelain)
    }
}
