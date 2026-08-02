import SwiftUI
import AppKit

struct ContentView: View {
    @State private var model = ProjectViewModel()
    @State private var keyMonitor: Any?
    @State private var splitVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $splitVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            main
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: model.keepsBrowseLayout) { _, layout in
            withAnimation(.easeInOut(duration: 0.4)) {
                splitVisibility = layout == .focus ? .detailOnly : .all
            }
        }
        .onChange(of: model.viewMode) { _, mode in
            if mode != .overview {
                model.keepsBrowseLayout = .carousel
                splitVisibility = .all
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
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Lumina")
                .font(.title.bold())
            Text("Pick sets · ship keeps")
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
                    Text("\(model.keepCount) keeps · \(model.sessionProgressText)")
                        .foregroundStyle(.secondary)
                    if project.profile.hasSettings {
                        Text("Taste on")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Picker("Mode", selection: $model.viewMode) {
                    Text("Session").tag(ProjectViewModel.ViewMode.session)
                    Text("Overview").tag(ProjectViewModel.ViewMode.overview)
                }
                .pickerStyle(.segmented)

                if model.viewMode == .session {
                    Text("Follow Meet → Pick → Decide for each set.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if model.viewMode == .overview || model.groupPhase == .done {
                DisclosureGroup("Tweak keeps") {
                    if model.selectedPhoto != nil {
                        developSliders
                    }
                }
            }

            Button("Export Collections") {
                model.exportCarousel()
            }
            .buttonStyle(LuminaPressStyle())
            .controlSize(.large)
            .disabled(model.project == nil || model.isBusy)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(16)
        .frame(minWidth: 220)
    }

    private var developSliders: some View {
        VStack(alignment: .leading, spacing: 8) {
            slider("Exposure", value: $model.globalAdjustments.exposure, range: -2...2)
            slider("Temp Δ", value: $model.globalAdjustments.temperature, range: -800...800)
            slider("Highlights", value: $model.globalAdjustments.highlights, range: -100...100)
            slider("Shadows", value: $model.globalAdjustments.shadows, range: -100...100)
            Button("Apply to keeps") { model.applyAdjustmentsToAllKeeps() }
                .font(.caption)
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(String(format: "%.1f", value.wrappedValue))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private var main: some View {
        ZStack {
            VStack(spacing: 0) {
                Group {
                    switch model.viewMode {
                    case .session:
                        ClusterCullView(model: model)
                    case .overview:
                        KeepsBrowserView(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(model.isImporting ? 0.3 : 1)
                .allowsHitTesting(!model.isImporting)

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
            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
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
        if model.viewMode == .overview {
            switch model.keepsBrowseLayout {
            case .carousel:
                return "Return/dbl-click: enlarge · ← → browse · O session · Esc carousel"
            case .focus:
                return "Esc: carousel · ← → · Space before/after · O session"
            }
        }
        switch model.groupPhase {
        case .intro: return "Return: review set · scroll sideways · ] next set"
        case .pick: return "Tap cards · Return: keep these"
        case .decide: return "← → browse · P keep · X reject · ] next set"
        case .done: return "Return: export · O keeps"
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        if event.modifierFlags.contains(.command) { return event }
        let chars = event.charactersIgnoringModifiers?.lowercased()
        switch chars {
        case "p":
            if event.type == .keyDown, model.groupPhase == .decide { model.markKeep() }
            return nil
        case "x":
            if event.type == .keyDown, model.groupPhase == .decide { model.markReject() }
            return nil
        case "h":
            if event.type == .keyDown, model.groupPhase == .decide { model.markHero() }
            return nil
        case "o":
            if event.type == .keyDown {
                if model.viewMode == .overview {
                    model.unfocusKeep()
                    model.viewMode = .session
                } else {
                    model.enterKeepsBrowser()
                }
            }
            return nil
        case "]":
            if event.type == .keyDown { model.advanceCluster() }
            return nil
        case "[":
            if event.type == .keyDown { model.previousCluster() }
            return nil
        case "\r", "\n":
            if event.type == .keyDown {
                if model.viewMode == .overview {
                    if model.keepsBrowseLayout == .carousel {
                        model.focusKeep()
                    }
                } else if model.groupPhase == .intro, let c = model.currentCluster {
                    model.groupPhase = .pick
                    model.seedPickFromHero(cluster: c)
                } else if model.groupPhase == .pick, let c = model.currentCluster {
                    model.confirmPicksAndAdvance(cluster: c)
                } else if model.groupPhase == .done {
                    model.exportCarousel()
                }
            }
            return nil
        default:
            if event.keyCode == 53, event.type == .keyDown { // Esc
                if model.viewMode == .overview, model.keepsBrowseLayout == .focus {
                    model.unfocusKeep()
                    return nil
                }
            }
            if event.keyCode == 123, event.type == .keyDown { // ←
                if model.viewMode == .overview { model.previousKeep() }
                else if model.groupPhase == .decide { model.previousUncertain() }
                return nil
            }
            if event.keyCode == 124, event.type == .keyDown { // →
                if model.viewMode == .overview { model.nextKeep() }
                else if model.groupPhase == .decide { model.nextUncertainInCluster() }
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
