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
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
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

    /// Non-workspace / global chords only.
    /// Workspace keyboard is owned exclusively by `CommandHandlingModifier`
    /// (installed while `shell.route == .workspace`).
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        if NSApp.keyWindow?.firstResponder is NSTextView { return event }

        // Global: Option+` speed HUD (works on every route).
        if event.type == .keyDown, event.keyCode == 50, event.modifierFlags.contains(.option) {
            model.toggleSpeedHUD()
            return nil
        }

        // Defer the entire workspace board to CommandHandlingModifier.
        if shell.route == .workspace {
            return event
        }

        if event.modifierFlags.contains(.command), event.type == .keyDown {
            let chars = event.charactersIgnoringModifiers?.lowercased()

            if chars == "k" {
                NotificationCenter.default.post(name: .focusLuminaSearch, object: nil)
                return nil
            }

            if event.keyCode == 36 {
                model.exportCarousel()
                return nil
            }
            return event
        }

        if event.type == .keyDown {
            if event.keyCode == 53 {
                if shell.handleEscape() { return nil }
                return event
            }

            if event.charactersIgnoringModifiers?.lowercased() == "g" {
                shell.openFinish()
                return nil
            }
        }

        return event
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        FileDropResolver.collectURLs(from: providers, requireFileURLType: true) { urls in
            model.ingestFromDroppedURLs(urls)
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
