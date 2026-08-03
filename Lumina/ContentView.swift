import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let focusLuminaSearch = Notification.Name("lumina.focusSearch")
    static let dismissLuminaTitle = Notification.Name("lumina.dismissTitle")
    static let toggleLuminaAuditRescue = Notification.Name("lumina.toggleAuditRescue")
    static let acceptLuminaAuditPile = Notification.Name("lumina.acceptAuditPile")
}

struct ContentView: View {
    @State private var model = ProjectViewModel()
    @State private var keyMonitor: Any?
    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            UnifiedCanvasView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(model.isImporting ? 0.25 : 1)
                .allowsHitTesting(!model.isImporting)

            if model.project == nil, !model.isImporting {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        if model.canResumeLastProject {
                            Button("Resume") { model.resumeLastProject() }
                                .buttonStyle(LuminaPressStyle())
                        }
                        Button("Import RAW Folder…") { model.pickRAWFolder() }
                            .buttonStyle(LuminaPrimaryButtonStyle())
                        Button("Scan backlog…") { model.pickCatalogRoot() }
                            .buttonStyle(LuminaPressStyle())
                    }
                    .padding(.bottom, 80)
                }
            }

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
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.06))
                    .padding(12)
                    .allowsHitTesting(false)
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
        if event.type == .keyDown {
            NotificationCenter.default.post(name: .dismissLuminaTitle, object: nil)
        }

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
            return event
        }

        let chars = event.charactersIgnoringModifiers?.lowercased()
        let held = event.isARepeat
        if event.type == .keyDown, event.keyCode == 50, event.modifierFlags.contains(.option) {
            model.toggleSpeedHUD()
            return nil
        }

        switch chars {
        case "f":
            if event.type == .keyDown { model.advanceFrame(held: held) }
            return nil
        case "d":
            if event.type == .keyDown { model.retreatFrame(held: held) }
            return nil
        case "p":
            if event.type == .keyDown {
                if case .audit(_) = model.lens {
                    NotificationCenter.default.post(name: .toggleLuminaAuditRescue, object: nil)
                } else {
                    model.markKeep()
                }
            }
            return nil
        case "x":
            if event.type == .keyDown, model.lens == nil { model.markReject() }
            return nil
        case "m":
            if event.type == .keyDown { model.openAuditForCursor() }
            return nil
        case "g":
            if event.type == .keyDown { model.openGridOverview() }
            return nil
        case "\r", "\n":
            if event.type == .keyDown, case .audit(_) = model.lens {
                NotificationCenter.default.post(name: .acceptLuminaAuditPile, object: nil)
                return nil
            }
            return event
        default:
            if event.keyCode == 53, event.type == .keyDown, model.lens != nil {
                model.lens = nil
                return nil
            }
            if event.keyCode == 123, event.type == .keyDown {
                model.retreatFrame(held: held)
                return nil
            }
            if event.keyCode == 124, event.type == .keyDown {
                model.advanceFrame(held: held)
                return nil
            }
            return event
        }
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
