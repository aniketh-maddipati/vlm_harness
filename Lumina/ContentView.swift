import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model = ProjectViewModel()
    @State private var keyMonitor: Any?
    @State private var isDropTargeted = false
    @State private var splitVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $splitVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 52, ideal: 220, max: 260)
        } detail: {
            main
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
                handleKey(event)
            }
            model.refreshResumeAvailability()
            model.restoreCatalogQueueIfNeeded()
        }
        .onChange(of: model.sessionPhase) { _, phase in
            withAnimation(.easeInOut(duration: 0.35)) {
                splitVisibility = phase == .decide ? .detailOnly : .all
            }
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
        .sheet(isPresented: $model.showExportPayoff) {
            if let payoff = model.exportPayoff {
                ExportPayoffSheet(payoff: payoff) {
                    model.showExportPayoff = false
                    if model.isCatalogMode {
                        model.advanceCatalogQueueAfterExport()
                    }
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Lumina")
                .font(.title.bold())
            Text("Turn a shoot into something posted")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.canResumeLastProject {
                Button("Resume last project") {
                    model.resumeLastProject()
                }
                .buttonStyle(LuminaPressStyle())
            }

            Button("Import RAW Folder…") {
                model.pickRAWFolder()
            }
            .buttonStyle(LuminaPrimaryButtonStyle())
            .disabled(model.isBusy)

            Button("Scan backlog…") {
                model.pickCatalogRoot()
            }
            .buttonStyle(LuminaPressStyle())
            .disabled(model.isBusy)

            if model.isCatalogMode {
                CatalogQueueView(model: model)
            }

            if let project = model.project {
                VStack(alignment: .leading, spacing: 6) {
                    Text(project.name).font(.headline)
                    Text(model.sessionPhaseLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(model.sessionProgressText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if model.showsDevelopControls {
                    TasteStrengthPanel(
                        strength: Binding(
                            get: { model.tasteStrength },
                            set: { model.tasteStrength = $0 }
                        ),
                        profile: model.extractedProfile,
                        sourceCount: model.tasteSourceCount
                    )
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button("Export") { model.exportCarousel() }
                    .buttonStyle(LuminaPressStyle())
                    .disabled(model.project == nil || model.isBusy || model.keepCount == 0)
                if model.isCatalogMode, model.sessionPhase == .export {
                    Button("Next folder") { model.advanceCatalogQueueAfterExport() }
                        .buttonStyle(LuminaPressStyle())
                }
                if model.sessionPhase == .pick || model.sessionPhase == .decide {
                    Button("Undo set") { model.undoLastStack() }
                        .buttonStyle(LuminaPressStyle())
                }
            }
        }
        .padding(16)
        .frame(minWidth: 200)
    }

    private var main: some View {
        ZStack {
            VStack(spacing: 0) {
                UnifiedCanvasView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(model.isImporting ? 0.3 : 1)
                    .allowsHitTesting(!model.isImporting)

                AdaptivePanelHost(model: model)
                statusBar
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .background(Color.accentColor.opacity(0.06))
                        .padding(12)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
            }

            if model.isImporting {
                ImportLoadingView(
                    progress: model.importProgress,
                    photos: model.importPreviewPhotos,
                    isFinishing: model.importFinishing
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if model.showSpeedHUD {
                VStack {
                    HStack {
                        Spacer()
                        SpeedContractHUD(model: model)
                            .padding(16)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: model.isImporting)
    }

    private var statusBar: some View {
        HStack {
            if model.isBusy { ProgressView().controlSize(.small) }
            if model.isImporting {
                Text(model.importProgress.phase.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(model.statusMessage)
                .lineLimit(1)
            Spacer()
            if !model.isImporting {
                Text(keymapHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var keymapHint: String {
        if model.showGridOverview {
            return "F/D browse grid · Esc back"
        }
        switch model.sessionPhase {
        case .meet:
            return "Return: pick · ]/[ sets"
        case .pick:
            return "Tap · Return: keep these · ]/[ sets"
        case .decide:
            return "F/D · P/X · M flag · H hero · Space before/after · ]/[ sets"
        case .export:
            return "Return: export · G grid overview"
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        if event.modifierFlags.contains(.command) { return event }
        let chars = event.charactersIgnoringModifiers?.lowercased()
        let held = event.isARepeat
        // ⌥` — Speed Contract HUD
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
        case "s":
            if event.type == .keyDown { model.toggleKeep() }
            return nil
        case "p":
            if event.type == .keyDown { model.toggleKeep() }
            return nil
        case "a":
            if event.type == .keyDown { model.toggleReject() }
            return nil
        case "x":
            if event.type == .keyDown { model.toggleReject() }
            return nil
        case "m":
            if event.type == .keyDown { model.toggleFlag() }
            return nil
        case "h":
            if event.type == .keyDown, model.sessionPhase == .decide { model.markHero() }
            return nil
        case "g":
            if event.type == .keyDown { model.openGridOverview() }
            return nil
        case "z":
            if event.modifierFlags.contains(.command), event.type == .keyDown {
                model.undoLastStack()
                return nil
            }
            return event
        case "]":
            if event.type == .keyDown { model.advanceCluster() }
            return nil
        case "[":
            if event.type == .keyDown { model.previousCluster() }
            return nil
        case "\r", "\n":
            if event.type == .keyDown {
                if model.showGridOverview {
                    return event
                }
                switch model.sessionPhase {
                case .meet:
                    model.advanceFromMeet()
                case .pick:
                    if let c = model.currentCluster {
                        model.confirmPicksAndAdvance(cluster: c)
                    }
                case .export:
                    model.exportCarousel()
                default:
                    break
                }
            }
            return nil
        default:
            if event.keyCode == 53, event.type == .keyDown {
                if model.showGridOverview {
                    model.closeGridOverview()
                    return nil
                }
            }
            if event.keyCode == 123, event.type == .keyDown {
                model.retreatFrame(held: held)
                return nil
            }
            if event.keyCode == 124, event.type == .keyDown {
                model.advanceFrame(held: held)
                return nil
            }
            if event.keyCode == 49, model.sessionPhase == .decide {
                // Space — reserved; no before/after taste on browse spine.
                return nil
            }
            return event
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var collected: [URL] = []
        let group = DispatchGroup()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let url = item as? URL {
                    collected.append(url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    collected.append(url)
                }
            }
        }
        group.notify(queue: .main) {
            guard !collected.isEmpty else { return }
            model.ingestFromDroppedURLs(collected)
        }
        return true
    }
}

#Preview {
    ContentView()
}
