import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let focusLuminaSearch = Notification.Name("lumina.focusSearch")
    static let dismissLuminaTitle = Notification.Name("lumina.dismissTitle")
    static let toggleLuminaAuditRescue = Notification.Name("lumina.toggleAuditRescue")
    static let acceptLuminaAuditPile = Notification.Name("lumina.acceptAuditPile")
    static let luminaOpenPreferences = Notification.Name("lumina.openPreferences")
    static let luminaShowShortcuts = Notification.Name("lumina.showShortcuts")
    static let luminaGoHome = Notification.Name("lumina.goHome")
}

struct ContentView: View {
    @State private var model = ProjectViewModel()
    @State private var shell = LuminaShellModel()
    @State private var keyMonitor: Any?
    @State private var isDropTargeted = false

    var body: some View {
        rootStack
            .modifier(dropAndLifecycle)
            .modifier(notificationHandlers)
            .modifier(importAndAlert)
    }

    private var rootStack: some View {
        ZStack {
            LuminaShellView(model: model, shell: shell)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(model.isImporting ? 0.25 : 1)
                .allowsHitTesting(!model.isImporting)

            if model.isImporting {
                ImportLoadingView(
                    progress: model.importProgress,
                    photos: model.importPreviewPhotos,
                    isFinishing: model.importFinishing
                )
            }

            if model.showSpeedHUD {
                SpeedContractHUD(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if isDropTargeted {
                ZStack {
                    LuminaTokens.Status.selection.opacity(0.06)
                    RoundedRectangle(cornerRadius: LuminaTokens.Radius.panel, style: .continuous)
                        .strokeBorder(LuminaTokens.Status.selection.opacity(0.55), lineWidth: 1.5)
                        .padding(18)
                    Text("Release to open")
                        .font(LuminaTokens.Typeface.title(28))
                        .foregroundStyle(LuminaTokens.Ink.primary)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
    }

    private var dropAndLifecycle: some ViewModifier {
        DropAndLifecycleModifier(
            isDropTargeted: $isDropTargeted,
            handleDrop: handleDrop,
            onAppear: {
                guard keyMonitor == nil else { return }
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .swipe]) { event in
                    if event.type == .swipe, shell.route == .workspace {
                        return handleSwipe(event) ?? event
                    }
                    return handleKey(event)
                }
                model.refreshResumeAvailability()
                model.restoreCatalogQueueIfNeeded()
                shell.syncSelectionFromModel(model)
                shell.refreshSnapshotsIfNeeded(model: model)
            },
            onDisappear: {
                if let keyMonitor {
                    NSEvent.removeMonitor(keyMonitor)
                    self.keyMonitor = nil
                }
            }
        )
    }

    private var notificationHandlers: some ViewModifier {
        NotificationHandlersModifier(model: model, shell: shell)
    }

    private var importAndAlert: some ViewModifier {
        ImportAndAlertModifier(model: model, shell: shell)
    }

    private func handleSwipe(_ event: NSEvent) -> NSEvent? {
        event
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        if NSApp.keyWindow?.firstResponder is NSTextView { return event }

        // Command-layer owns workspace ⌘ chords when the workbench selection is active.
        // ContentView keeps legacy single-key routing for an empty selection.
        let selection = shell.workbenchSelection
        let commandLayerActive = shell.route == .workspace
            && (selection.isHandling || selection.staged != nil || !selection.isEmpty || shell.isTreatmentStageOpen)

        if event.modifierFlags.contains(.command), event.type == .keyDown {
            let chars = event.charactersIgnoringModifiers?.lowercased()
            let option = event.modifierFlags.contains(.option)
            let shift = event.modifierFlags.contains(.shift)

            if shell.route == .workspace {
                switch chars {
                case "1" where !option && !shift:
                    shell.openShootSelection()
                    return nil
                case "2" where !option && !shift:
                    shell.setWorkspaceStage(.workbench)
                    shell.isReadMode = false
                    return nil
                case "3" where !option && !shift:
                    shell.setWorkspaceStage(.canvas)
                    shell.isReadMode = false
                    return nil
                case "r" where !option && !shift:
                    shell.enterReadMode()
                    return nil
                case "z" where !option && !shift:
                    if shell.lastRoundReceipt != nil || shell.decisionUndo != nil {
                        shell.undoLastDecision(model: model)
                        return nil
                    }
                case "c" where option && !shift:
                    shell.showDetailedEdits = true
                    return nil
                default:
                    break
                }

                // Let CommandHandlingModifier own Return / Delete staging when gathering.
                if commandLayerActive {
                    let isReturn = event.keyCode == 36 || event.keyCode == 76
                    let isDelete = event.keyCode == 51 || event.keyCode == 117
                    if isReturn || isDelete {
                        return event
                    }
                }
            } else if chars == "k" {
                NotificationCenter.default.post(name: .focusLuminaSearch, object: nil)
                return nil
            }

            if event.keyCode == 36, shell.route != .workspace {
                model.exportCarousel()
                return nil
            }
            return event
        }

        if event.type == .keyDown, event.keyCode == 50, event.modifierFlags.contains(.option) {
            model.toggleSpeedHUD()
            return nil
        }

        if event.type == .keyDown {
            if event.keyCode == 53 {
                if shell.handleEscape() { return nil }
                return event
            }

            if shell.route == .workspace, !event.modifierFlags.contains(.command) {
                // When the command layer is gathering / staged / editing, defer arrows & Return.
                if commandLayerActive {
                    return event
                }

                let presentation = shell.workspacePresentation(model: model)
                let photoID = shell.selectedAssetID ?? model.cursor

                if event.keyCode == 126 {
                    shell.moveAttempt(delta: -1, presentation: presentation, model: model)
                    return nil
                }
                if event.keyCode == 125 {
                    shell.moveAttempt(delta: 1, presentation: presentation, model: model)
                    return nil
                }
                if event.keyCode == 123 {
                    shell.moveAlternative(delta: -1, presentation: presentation, model: model)
                    return nil
                }
                if event.keyCode == 124 {
                    shell.moveAlternative(delta: 1, presentation: presentation, model: model)
                    return nil
                }
                if event.keyCode == 36 {
                    shell.toggleRowExpanded()
                    return nil
                }
                if event.keyCode == 49 {
                    shell.isFocusMode.toggle()
                    return nil
                }

                switch event.charactersIgnoringModifiers?.lowercased() {
                case "a":
                    shell.previewAutoTreatment(model: model)
                    return nil
                case "e":
                    shell.toggleDetailedEdits()
                    return nil
                case "t":
                    shell.openTreatmentStage()
                    return nil
                case "s":
                    LuminaHaptics.decision()
                    if let photoID {
                        shell.applyDecision(.keep, for: photoID, model: model)
                    }
                    return nil
                case "m":
                    LuminaHaptics.decision()
                    if let photoID {
                        shell.applyDecision(.needsMe, for: photoID, model: model)
                    }
                    return nil
                case "x":
                    LuminaHaptics.decision()
                    if let photoID {
                        shell.applyDecision(.cut, for: photoID, model: model)
                    }
                    return nil
                default:
                    break
                }
            }

            if event.charactersIgnoringModifiers?.lowercased() == "g", !commandLayerActive {
                shell.openFinish()
                return nil
            }
        }

        return event
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let lock = NSLock()
        var collected: [URL] = []
        let group = DispatchGroup()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                let url: URL?
                if let value = item as? URL {
                    url = value
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = nil
                }
                if let url {
                    lock.lock()
                    collected.append(url)
                    lock.unlock()
                }
            }
        }
        group.notify(queue: .main) {
            model.ingestFromDroppedURLs(collected)
        }
        return true
    }
}

// MARK: - Body decomposition (keeps the type-checker fast)

private struct DropAndLifecycleModifier: ViewModifier {
    @Binding var isDropTargeted: Bool
    let handleDrop: ([NSItemProvider]) -> Bool
    let onAppear: () -> Void
    let onDisappear: () -> Void

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
            .onAppear(perform: onAppear)
            .onDisappear(perform: onDisappear)
    }
}

private struct NotificationHandlersModifier: ViewModifier {
    @Bindable var model: ProjectViewModel
    @Bindable var shell: LuminaShellModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .luminaImportRAW)) { _ in
                model.pickRAWFolder()
            }
            .onReceive(NotificationCenter.default.publisher(for: .luminaShowShortcuts)) { _ in
                shell.showShortcuts = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .luminaGoHome)) { _ in
                shell.openHome()
            }
            .onReceive(NotificationCenter.default.publisher(for: .luminaSetLensAttempts)) { _ in
                shell.setLens(.attempts)
                if shell.route != .workspace { shell.openWorkspace(lens: .attempts) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .luminaSetLensLight)) { _ in
                shell.setLens(.light)
                if shell.route != .workspace { shell.openWorkspace(lens: .light) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .luminaScanBacklog)) { _ in
                model.pickCatalogRoot()
            }
            .onReceive(NotificationCenter.default.publisher(for: .luminaOpenSources)) { _ in
                shell.openShootSelection()
            }
            .onReceive(NotificationCenter.default.publisher(for: .luminaOpenWorkbench)) { _ in
                if shell.route != .workspace { shell.openWorkspace(lens: shell.lens) }
                shell.setWorkspaceStage(.workbench)
                shell.isReadMode = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .luminaOpenStory)) { _ in
                if shell.route != .workspace { shell.openWorkspace(lens: shell.lens) }
                shell.setWorkspaceStage(.canvas)
                shell.isReadMode = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .luminaEnterRead)) { _ in
                if shell.route != .workspace { shell.openWorkspace(lens: shell.lens) }
                shell.enterReadMode()
            }
            .onReceive(NotificationCenter.default.publisher(for: .luminaMoreTreatment)) { _ in
                shell.showDetailedEdits = true
            }
    }
}

private struct ImportAndAlertModifier: ViewModifier {
    @Bindable var model: ProjectViewModel
    @Bindable var shell: LuminaShellModel

    func body(content: Content) -> some View {
        content
            .onChange(of: model.isImporting) { _, importing in
                if !importing, model.project != nil {
                    shell.invalidateCache()
                    shell.openWorkspace(lens: .attempts)
                    shell.syncSelectionFromModel(model)
                    shell.refreshSnapshotsIfNeeded(model: model)
                }
            }
            .alert(
                "Lumina",
                isPresented: Binding(
                    get: { model.project == nil && model.userFacingError != nil },
                    set: { if !$0 { model.userFacingError = nil } }
                )
            ) {
                Button("Dismiss") { model.userFacingError = nil }
            } message: {
                Text(model.userFacingError ?? "Something went wrong.")
            }
    }
}

#Preview {
    ContentView()
}
