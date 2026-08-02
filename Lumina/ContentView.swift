import SwiftUI
import AppKit

struct ContentView: View {
    @State private var model = ProjectViewModel()
    @State private var keyMonitor: Any?
    @State private var splitVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $splitVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 52, ideal: 220, max: 260)
        } detail: {
            main
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: model.keepsBrowseLayout) { _, layout in
            withAnimation(.easeInOut(duration: 0.4)) {
                splitVisibility = layout == .focus ? .detailOnly : .all
            }
        }
        .onChange(of: model.appSpine) { _, spine in
            if spine == .browsingKeeps && model.keepsBrowseLayout == .focus {
                splitVisibility = .detailOnly
            } else if spine != .browsingKeeps {
                model.keepsBrowseLayout = .carousel
            }
        }
        .onAppear {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
                handleKey(event)
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
        .sheet(isPresented: $model.showSessionSummary) {
            if let summary = model.sessionSummary {
                SessionSummarySheet(summary: summary) {
                    model.showSessionSummary = false
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Lumina")
                .font(.title.bold())
            Text("Agentic cull · ship keeps")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Import Photos…") {
                model.pickImportSources()
            }
            .buttonStyle(LuminaPrimaryButtonStyle())
            .disabled(model.isBusy)

            if let project = model.project {
                VStack(alignment: .leading, spacing: 6) {
                    Text(project.name).font(.headline)
                    Text(model.agentPlanText.isEmpty ? model.decisionBudgetText : model.agentPlanText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    Text("\(model.keepCount) keeps · \(model.sessionProgressText)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Toggle("Auto-deliver on complete", isOn: $model.jobBrief.autoDeliver)
                    .font(.caption)

                if model.appSpine == .sessionComplete || model.appSpine == .browsingKeeps {
                    DisclosureGroup("Tweak keeps") {
                        if model.selectedPhoto != nil {
                            DevelopSlidersStrip(
                                adjustments: $model.globalAdjustments,
                                compact: false,
                                showApplyButton: true,
                                onApplyToKeeps: { model.applyAdjustmentsToAllKeeps() }
                            )
                        }
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button("Export") { model.exportCarousel() }
                    .buttonStyle(LuminaPressStyle())
                    .disabled(model.project == nil || model.isBusy)
                if model.appSpine == .reviewingSet {
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

            if model.isImporting {
                ImportLoadingView(
                    progress: model.importProgress,
                    photos: model.importPreviewPhotos,
                    isFinishing: model.importFinishing
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
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
        switch model.appSpine {
        case .stackFeed:
            return "Open a stack · O keeps when done"
        case .browsingKeeps:
            switch model.keepsBrowseLayout {
            case .carousel: return "F/D browse · Return: enlarge · S keep · A reject"
            case .focus: return "F/D · S keep · A reject · Space before/after · Esc carousel"
            }
        case .sessionComplete:
            return "Return: export · O keeps · B all sets"
        case .reviewingSet:
            switch model.groupPhase {
            case .intro: return "Return: review · Esc: all sets"
            case .pick: return "Tap · Return: keep these"
            case .decide: return "F/D · S keep · A reject · H hero · C compare tie"
            case .done: return "Return: export"
            }
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        if event.modifierFlags.contains(.command) { return event }
        let chars = event.charactersIgnoringModifiers?.lowercased()
        switch chars {
        case "f":
            if event.type == .keyDown { model.advanceFrame() }
            return nil
        case "d":
            if event.type == .keyDown { model.retreatFrame() }
            return nil
        case "s":
            if event.type == .keyDown { model.toggleKeep() }
            return nil
        case "a":
            if event.type == .keyDown { model.toggleReject() }
            return nil
        case "p":
            if event.type == .keyDown, model.groupPhase == .decide { model.markKeep() }
            return nil
        case "x":
            if event.type == .keyDown, model.groupPhase == .decide { model.markReject() }
            return nil
        case "h":
            if event.type == .keyDown, model.groupPhase == .decide { model.markHero() }
            return nil
        case "b":
            if event.type == .keyDown { model.backToStackFeed() }
            return nil
        case "o":
            if event.type == .keyDown {
                if model.appSpine == .browsingKeeps {
                    model.unfocusKeep()
                    model.appSpine = .stackFeed
                } else if model.appSpine == .sessionComplete {
                    model.enterKeepsBrowser()
                }
            }
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
                if model.appSpine == .browsingKeeps, model.keepsBrowseLayout == .carousel {
                    model.focusKeep()
                } else if model.appSpine == .sessionComplete {
                    model.exportCarousel()
                } else if model.groupPhase == .intro, model.currentCluster != nil {
                    model.groupPhase = .pick
                    if let c = model.currentCluster { model.seedPickFromHero(cluster: c) }
                } else if model.groupPhase == .pick, let c = model.currentCluster {
                    model.confirmPicksAndAdvance(cluster: c)
                }
            }
            return nil
        default:
            if event.keyCode == 53, event.type == .keyDown {
                if model.appSpine == .browsingKeeps, model.keepsBrowseLayout == .focus {
                    model.unfocusKeep()
                    return nil
                }
                if model.appSpine == .reviewingSet {
                    model.backToStackFeed()
                    return nil
                }
            }
            if event.keyCode == 123, event.type == .keyDown {
                model.retreatFrame()
                return nil
            }
            if event.keyCode == 124, event.type == .keyDown {
                model.advanceFrame()
                return nil
            }
            if event.keyCode == 49 {
                model.showBefore = event.type == .keyDown
                if event.type == .keyDown { model.softRender.snapBefore() }
                else { model.softRender.snapAfter() }
                return nil
            }
            return event
        }
    }
}

#Preview {
    ContentView()
}
