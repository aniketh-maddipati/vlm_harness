import SwiftUI
import AppKit

struct ContentView: View {
    @State private var model = ProjectViewModel()
    @State private var keyMonitor: Any?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            main
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        overview
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

    private var overview: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Overview")
                    .font(.headline)
                Spacer()
                Picker("Sort", selection: $model.sortMode) {
                    Text("Similar").tag(SortMode.similar)
                    Text("Quality").tag(SortMode.quality)
                    Text("Sharpest").tag(SortMode.sharpest)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                Button("Back to session") {
                    model.viewMode = .session
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            PhotoGridView(
                photos: model.displayedPhotos,
                selectedID: model.selectedPhotoID,
                onSelect: { model.selectPhoto($0) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)

            if let photo = model.selectedPhoto, let project = model.project {
                SoftPreviewView(
                    photo: photo,
                    projectName: project.name,
                    baseline: project.profile,
                    offsets: model.globalAdjustments.merged(with: photo.perPhotoAdjustments ?? .zero),
                    mix: model.showBefore ? 0 : model.softRender.mix,
                    showBefore: model.showBefore
                )
                .frame(height: 240)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.filter = .keeps }
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
        switch model.groupPhase {
        case .intro: "Return: review set · scroll sideways · ] next set"
        case .pick: "Tap cards · Return: keep these"
        case .decide: "← → browse · P keep · X reject · ] next set"
        case .done: "Return: export · O overview"
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
                model.viewMode = model.viewMode == .overview ? .session : .overview
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
                if model.groupPhase == .intro, let c = model.currentCluster {
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
            if event.keyCode == 123, event.type == .keyDown { // ←
                if model.groupPhase == .decide { model.previousUncertain() }
                return nil
            }
            if event.keyCode == 124, event.type == .keyDown { // →
                if model.groupPhase == .decide { model.nextUncertainInCluster() }
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
