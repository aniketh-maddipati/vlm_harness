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
        VStack(alignment: .leading, spacing: 16) {
            Text("Lumina")
                .font(.title2.bold())

            Button("Import RAW Folder…") {
                model.pickRAWFolder()
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy)

            if let project = model.project {
                Group {
                    Text(project.name)
                        .font(.headline)
                    Text("\(model.keepCount)/\(model.totalCount) kept")
                        .foregroundStyle(.secondary)
                    if project.profile.sourceCount > 0 {
                        Text("Taste from \(project.profile.sourceCount) JPGs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            Text("Filter")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Picker("Filter", selection: $model.filter) {
                ForEach(GridFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.radioGroup)

            Spacer()

            Button("Export Carousel") {
                model.exportCarousel()
            }
            .buttonStyle(.bordered)
            .disabled(model.project == nil || model.isBusy)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding()
        .frame(minWidth: 220)
    }

    private var main: some View {
        HSplitView {
            VStack(spacing: 0) {
                gridHeader
                photoGrid
                statusBar
            }
            inspector
                .frame(minWidth: 280, idealWidth: 300, maxWidth: 340)
        }
    }

    private var gridHeader: some View {
        HStack {
            Text(model.filter.rawValue)
                .font(.headline)
            Spacer()
            if model.isBusy {
                ProgressView().controlSize(.small)
            }
            Text("\(model.filteredPhotos.count) shown")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var photoGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 10)], spacing: 10) {
                ForEach(model.filteredPhotos) { photo in
                    PhotoCell(
                        photo: photo,
                        isSelected: photo.id == model.selectedPhotoID
                    )
                    .onTapGesture {
                        model.selectedPhotoID = photo.id
                    }
                }
            }
            .padding()
        }
        .focusable()
        .focused($focused)
        .onAppear { focused = true }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let photo = model.selectedPhoto {
                previewPane(photo: photo)

                Text("Why")
                    .font(.headline)
                Text(photo.whySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                tierPicker(for: photo)

                Divider()

                Text("Edit")
                    .font(.headline)

                sliderRow("Exposure", value: $model.globalAdjustments.exposure, range: -2...2)
                sliderRow("Temp offset", value: $model.globalAdjustments.temperature, range: -800...800)
                sliderRow("Contrast", value: $model.globalAdjustments.contrast, range: -50...50)
                sliderRow("Highlights", value: $model.globalAdjustments.highlights, range: -100...100)
                sliderRow("Shadows", value: $model.globalAdjustments.shadows, range: -100...100)
                sliderRow("Vibrance", value: $model.globalAdjustments.vibrance, range: -50...50)

                Button("Apply to all keeps") {
                    model.applyAdjustmentsToAllKeeps()
                }
                .buttonStyle(.bordered)
            } else {
                ContentUnavailableView(
                    "No photo selected",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Import a folder or select a thumbnail.")
                )
            }
            Spacer()
        }
        .padding()
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func previewPane(photo: PhotoRecord) -> some View {
        if let path = photo.thumbPath {
            let url = URL(fileURLWithPath: path)
            if model.showBefore {
                AsyncThumb(url: url)
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else if let project = model.project {
                AsyncThumb(
                    url: url,
                    profile: project.profile,
                    offsets: developOffsets(for: photo)
                )
                .frame(maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func tierPicker(for photo: PhotoRecord) -> some View {
        HStack {
            ForEach([PhotoTier.keep, .maybe, .reject], id: \.rawValue) { tier in
                Button(tier.label) {
                    model.setTier(tier, for: photo.id)
                }
                .buttonStyle(.bordered)
                .tint(tierColor(tier))
                .disabled(photo.tier == tier)
            }
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(String(format: "%.1f", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            Text(model.statusMessage)
                .lineLimit(1)
            Spacer()
            Text("P keep · X reject · ] next · Space compare")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func developOffsets(for photo: PhotoRecord) -> DevelopAdjustments {
        let per = photo.perPhotoAdjustments ?? .zero
        return model.globalAdjustments.merged(with: per)
    }

    private func tierColor(_ tier: PhotoTier) -> Color {
        switch tier {
        case .keep: .green
        case .maybe: .orange
        case .reject: .gray
        case .unranked: .secondary
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard !event.modifierFlags.contains(.command) else { return event }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "p":
            model.markKeep()
            return nil
        case "x":
            model.markReject()
            return nil
        case "m":
            model.markMaybe()
            return nil
        case "]":
            model.advanceFlag()
            return nil
        case "[":
            model.previousFlag()
            return nil
        default:
            if event.keyCode == 49 {
                model.showBefore = event.type == .keyDown
                return nil
            }
            return event
        }
    }
}

struct PhotoCell: View {
    let photo: PhotoRecord
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                if let path = photo.thumbPath {
                    AsyncThumb(url: URL(fileURLWithPath: path))
                        .aspectRatio(3 / 2, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .background(Color.black.opacity(0.04))
                } else {
                    Rectangle().fill(.quaternary).frame(height: 120)
                }

                Text(photo.tier.label)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tierColor.opacity(0.85))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(6)

                if photo.isFlagged {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
            )

            Text(photo.filename)
                .font(.caption2)
                .lineLimit(1)
        }
    }

    private var tierColor: Color {
        switch photo.tier {
        case .keep: .green
        case .maybe: .orange
        case .reject: .gray
        case .unranked: .secondary
        }
    }
}

struct AsyncThumb: View {
    let url: URL
    var profile: DevelopProfile = DevelopProfile()
    var offsets: DevelopAdjustments = .zero
    @State private var image: NSImage?

    private var needsDevelop: Bool {
        profile.hasDevelopSettings || !offsets.isZero
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Rectangle().fill(.quaternary)
                    .task(id: taskID) { await load() }
            }
        }
    }

    private var taskID: String {
        "\(url.path)-\(profile.temperature)-\(offsets.exposure)-\(offsets.contrast)-\(offsets.temperature)"
    }

    @MainActor
    private func load() async {
        let url = url
        let profile = profile
        let offsets = offsets
        let needsDevelop = needsDevelop

        let loaded: NSImage? = if needsDevelop {
            await Task.detached(priority: .userInitiated) {
                PreviewRenderer.render(url: url, profile: profile, offsets: offsets)
            }.value
        } else {
            NSImage(contentsOf: url)
        }
        image = loaded
    }
}

#Preview {
    ContentView()
}
