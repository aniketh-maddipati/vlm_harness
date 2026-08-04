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
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .onAppear {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) {
                handleKey($0)
            }
            model.refreshResumeAvailability()
            model.restoreCatalogQueueIfNeeded()
            shell.syncSelectionFromModel(model)
            shell.refreshSnapshotsIfNeeded(model: model)
        }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }
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

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        if NSApp.keyWindow?.firstResponder is NSTextView { return event }

        if event.modifierFlags.contains(.command) {
            if event.type == .keyDown,
               event.charactersIgnoringModifiers?.lowercased() == "k" {
                NotificationCenter.default.post(name: .focusLuminaSearch, object: nil)
                return nil
            }
            if event.type == .keyDown, event.keyCode == 36 {
                model.exportCarousel()
                return nil
            }
            if event.type == .keyDown,
               event.charactersIgnoringModifiers?.lowercased() == "z" {
                return nil
            }
            return event
        }

        let chars = event.charactersIgnoringModifiers?.lowercased()
        let held = event.isARepeat

        if event.type == .keyDown, event.keyCode == 50, event.modifierFlags.contains(.option) {
            model.toggleSpeedHUD()
            return nil
        }

        if event.type == .keyDown {
            switch chars {
            case "1":
                shell.setLens(.attempts)
                if shell.route != .workspace { shell.openWorkspace(lens: .attempts) }
                return nil
            case "2":
                shell.setLens(.light)
                if shell.route != .workspace { shell.openWorkspace(lens: .light) }
                return nil
            case "k", "p":
                if shell.route == .workspace {
                    shell.applyDecision(.keep, model: model)
                    return nil
                }
            case "x":
                if shell.route == .workspace {
                    shell.applyDecision(.cut, model: model)
                    return nil
                }
            case "m":
                if shell.route == .workspace {
                    shell.applyDecision(.needsMe, model: model)
                    return nil
                }
            case "a":
                if shell.route == .workspace {
                    shell.applyDecision(.anchor, model: model)
                    return nil
                }
            case " ":
                if shell.route == .workspace {
                    shell.toggleFocus()
                    return nil
                }
            case "g":
                shell.openFinish()
                return nil
            case "f":
                if shell.route == .workspace {
                    shell.moveAttempt(
                        delta: 1,
                        presentation: shell.workspacePresentation(model: model),
                        model: model
                    )
                    return nil
                }
            case "d":
                if shell.route == .workspace {
                    shell.moveAttempt(
                        delta: -1,
                        presentation: shell.workspacePresentation(model: model),
                        model: model
                    )
                    return nil
                }
            default:
                break
            }

            // Escape — Focus / inspector / shortcuts only. Never jump workspace → Home.
            if event.keyCode == 53 {
                if shell.handleEscape() { return nil }
                return event
            }

            if event.keyCode == 123, shell.route == .workspace {
                shell.moveAttempt(delta: -1, presentation: shell.workspacePresentation(model: model), model: model)
                return nil
            }
            if event.keyCode == 124, shell.route == .workspace {
                shell.moveAttempt(delta: 1, presentation: shell.workspacePresentation(model: model), model: model)
                return nil
            }
            if event.keyCode == 125, shell.route == .workspace {
                shell.moveAlternative(delta: 1, presentation: shell.workspacePresentation(model: model), model: model)
                return nil
            }
            if event.keyCode == 126, shell.route == .workspace {
                shell.moveAlternative(delta: -1, presentation: shell.workspacePresentation(model: model), model: model)
                return nil
            }
        }

        _ = held
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

#Preview {
    ContentView()
}
