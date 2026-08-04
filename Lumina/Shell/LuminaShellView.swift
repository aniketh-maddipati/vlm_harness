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
        PaletteWorkspaceView(
            presentation: presentation,
            isFocusMode: shell.isFocusMode,
            scrollTargetGroupID: shell.scrollTargetGroupID,
            onSelectAsset: { id in
                shell.selectAsset(id)
                shell.scrollTargetGroupID = presentation.groups
                    .first(where: { $0.assets.contains(where: { $0.id == id }) })?.id
                if model.project != nil { model.setCursor(id) }
                _ = PreviewSpine.shared.paint(id: id, inputTime: CFAbsoluteTimeGetCurrent(), held: false)
                shell.isFocusMode = true
            },
            onLensChange: { newLens in
                let selected = presentation.selectedAssetID
                shell.setLens(newLens)
                let updated = shell.workspacePresentation(model: model)
                if let selected {
                    shell.scrollTargetGroupID = updated.groups
                        .first(where: { $0.assets.contains(where: { $0.id == selected }) })?.id
                }
            },
            onDecision: { shell.applyDecision($0, model: model) },
            onToggleFocus: { shell.toggleFocus() },
            onHome: { shell.openHome() },
            onFinish: { shell.openFinish() },
            onPrevious: {
                shell.moveAlternative(delta: -1, presentation: presentation, model: model)
            },
            onNext: {
                shell.moveAlternative(delta: 1, presentation: presentation, model: model)
            }
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
        ("← / →", "Previous / next attempt"),
        ("↑ / ↓", "Alternative within attempt"),
        ("Space", "Focus photograph"),
        ("K", "Keep"),
        ("X", "Cut"),
        ("M", "Review"),
        ("A", "Anchor"),
        ("1", "Attempts lens"),
        ("2", "Light lens"),
        ("⌘Z", "Undo"),
        ("Esc", "Leave Focus / inspector"),
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
