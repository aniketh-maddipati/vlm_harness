import SwiftUI
import AppKit

struct ContentView: View {
    @State private var model = ProjectViewModel()
    @FocusState private var focused: Bool

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            main
        }
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
                handleKey(event)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .luminaImportRAW)) { _ in
            model.pickRAWFolder()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Lumina")
                .font(.title2.bold())
            Text("Beyond Lightroom")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Import Photos…") {
                model.pickImportSources()
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy)

            if let project = model.project {
                Group {
                    Text(project.name).font(.headline)
                    Text("\(model.keepCount)/\(model.totalCount) kept")
                        .foregroundStyle(.secondary)
                    if project.profile.hasSettings {
                        Text("Taste library loaded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("View", selection: $model.viewMode) {
                    ForEach(ProjectViewModel.ViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Divider()
                Text("Filter").font(.caption.bold()).foregroundStyle(.secondary)
                Picker("Filter", selection: $model.filter) {
                    ForEach(GridFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Spacer()

            if let photo = model.selectedPhoto {
                developPanel(photo: photo)
            }

            Button("Export Collections") {
                model.exportCarousel()
            }
            .disabled(model.project == nil || model.isBusy)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding()
        .frame(minWidth: 240)
    }

    private func developPanel(photo: PhotoRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Edit").font(.headline)
            if let neighbors = photo.recipe?.sourceNeighbors, !neighbors.isEmpty {
                Text("Matched \(neighbors.prefix(2).joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            slider("Exposure", value: $model.globalAdjustments.exposure, range: -2...2)
            slider("Temp Δ", value: $model.globalAdjustments.temperature, range: -800...800)
            slider("Contrast", value: $model.globalAdjustments.contrast, range: -50...50)
            slider("Highlights", value: $model.globalAdjustments.highlights, range: -100...100)
            slider("Shadows", value: $model.globalAdjustments.shadows, range: -100...100)
            slider("Vibrance", value: $model.globalAdjustments.vibrance, range: -50...50)

            DisclosureGroup("Pro") {
                slider("Clarity", value: $model.globalAdjustments.clarity, range: -50...50)
                slider("Dehaze", value: $model.globalAdjustments.dehaze, range: -50...50)
                slider("Saturation", value: $model.globalAdjustments.saturation, range: -50...50)
                slider("Tint Δ", value: $model.globalAdjustments.tint, range: -50...50)
            }

            Button("Apply offsets to keeps") {
                model.applyAdjustmentsToAllKeeps()
            }
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
        VStack(spacing: 0) {
            DynamicSortBar(sortMode: $model.sortMode, uncertainCount: model.uncertainCount)
                .onChange(of: model.sortMode) { _, newValue in
                    withAnimation(.spring(duration: 0.28)) {
                        switch newValue {
                        case .uncertain: model.viewMode = .uncertain
                        case .similar: model.viewMode = .cluster
                        default: model.viewMode = .grid
                        }
                        model.selectedPhotoID = model.displayedPhotos.first?.id
                        if let id = model.selectedPhotoID {
                            model.playSoftRender(for: id)
                        }
                    }
                }

            Group {
                switch model.viewMode {
                case .uncertain:
                    UncertainQueueView(model: model)
                case .cluster:
                    ClusterCullView(model: model)
                case .grid:
                    PhotoGridView(
                        photos: model.displayedPhotos,
                        selectedID: model.selectedPhotoID,
                        onSelect: { model.selectPhoto($0) }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.viewMode == .grid, let photo = model.selectedPhoto, let project = model.project {
                SoftPreviewView(
                    photo: photo,
                    projectName: project.name,
                    baseline: project.profile,
                    offsets: model.globalAdjustments.merged(with: photo.perPhotoAdjustments ?? .zero),
                    mix: model.showBefore ? 0 : model.softRender.mix,
                    showBefore: model.showBefore
                )
                .frame(height: 220)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            statusBar
        }
        .focusable()
        .focused($focused)
        .onAppear { focused = true }
    }

    private var statusBar: some View {
        HStack {
            if model.isBusy { ProgressView().controlSize(.small) }
            Text(model.statusMessage)
                .lineLimit(1)
            Spacer()
            Text("P keep · X reject · H hero · ] next · Space compare · G grid")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        if event.modifierFlags.contains(.command) { return event }
        let chars = event.charactersIgnoringModifiers?.lowercased()
        switch chars {
        case "p":
            if event.type == .keyDown { model.markKeep() }
            return nil
        case "x":
            if event.type == .keyDown { model.markReject() }
            return nil
        case "h":
            if event.type == .keyDown { model.markHero() }
            return nil
        case "g":
            if event.type == .keyDown {
                model.viewMode = model.viewMode == .grid ? .uncertain : .grid
            }
            return nil
        case "]":
            if event.type == .keyDown { model.advanceUncertain() }
            return nil
        case "[":
            if event.type == .keyDown { model.previousUncertain() }
            return nil
        default:
            if event.keyCode == 49 {
                model.showBefore = event.type == .keyDown
                if event.type == .keyDown {
                    model.softRender.snapBefore()
                } else {
                    model.softRender.snapAfter()
                }
                return nil
            }
            return event
        }
    }
}

#Preview {
    ContentView()
}
