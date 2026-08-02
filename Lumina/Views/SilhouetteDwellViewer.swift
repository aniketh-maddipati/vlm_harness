import SwiftUI
import AppKit

/// Full-bleed cull viewer: instant silhouette while scrolling, graded render + controls after dwell.
struct SilhouetteDwellViewer: View {
    @Bindable var model: ProjectViewModel
    let photos: [PhotoRecord]
    let projectName: String
    @Binding var selection: UUID?

    @State private var dwellStage: DwellStage = .silhouette
    @State private var silhouetteImage: NSImage?
    @State private var beforeImage: NSImage?
    @State private var afterImage: NSImage?
    @State private var dwellTask: Task<Void, Never>?
    @State private var renderTask: Task<Void, Never>?

    private enum DwellStage: Int, Comparable {
        case silhouette = 0
        case rendering = 1
        case graded = 2
        case manual = 3
        case auto = 4

        static func < (lhs: DwellStage, rhs: DwellStage) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private var selectedPhoto: PhotoRecord? {
        guard let selection else { return nil }
        return photos.first { $0.id == selection }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if let photo = selectedPhoto {
                    silhouetteLayer(photo: photo, size: geo.size)
                    gradedLayer(size: geo.size)
                }

                VStack(spacing: 0) {
                    topChrome
                        .opacity(dwellStage >= .manual ? 1 : 0.55)
                        .animation(.easeOut(duration: 0.25), value: dwellStage)

                    Spacer()

                    if dwellStage >= .manual, selectedPhoto != nil {
                        VStack(spacing: 10) {
                            if dwellStage >= .auto {
                                Text("Taste applied")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.72))
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }

                            LuminaDecisionBar(
                                onReject: { model.markReject() },
                                onHero: { model.markHero() },
                                onKeep: { model.markKeep() }
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        .padding(.bottom, 8)
                    }

                    bottomFilmstrip
                        .frame(height: 92)
                        .background(.black.opacity(0.55))
                }
            }
        }
        .onAppear {
            if selection == nil { selection = photos.first?.id }
            if let id = selection { beginDwell(for: id) }
        }
        .onChange(of: selection) { _, new in
            guard let new else { return }
            beginDwell(for: new)
        }
        .onChange(of: model.tasteStrength) { _, _ in
            guard let id = selection, dwellStage >= .rendering else { return }
            scheduleGradedRender(for: id)
        }
        .onDisappear {
            dwellTask?.cancel()
            renderTask?.cancel()
        }
    }

    private var topChrome: some View {
        HStack {
            if let photo = selectedPhoto {
                VStack(alignment: .leading, spacing: 2) {
                    Text(photo.filename)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(photo.whySummary)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer()
            stageHint
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var stageHint: some View {
        switch dwellStage {
        case .silhouette:
            Text("Scrolling…")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
        case .rendering:
            ProgressView()
                .controlSize(.small)
                .tint(.white)
        case .graded:
            Text("Preview ready")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
        case .manual:
            Text("P keep · X reject · M flag")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
        case .auto:
            Text("Auto look")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    @ViewBuilder
    private func silhouetteLayer(photo: PhotoRecord, size: CGSize) -> some View {
        Group {
            if let silhouetteImage {
                Image(nsImage: silhouetteImage)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: size.width, maxHeight: size.height - 120)
                    .saturation(dwellStage >= .graded ? 0 : 0.12)
                    .contrast(dwellStage >= .graded ? 1 : 1.45)
                    .brightness(dwellStage >= .graded ? 0 : -0.12)
                    .blur(radius: dwellStage >= .graded ? 0 : 0.6)
                    .opacity(dwellStage >= .graded ? 0 : 1)
            } else {
                ProgressView()
                    .tint(.white.opacity(0.5))
            }
        }
        .animation(.easeOut(duration: 0.22), value: dwellStage >= .graded)
    }

    @ViewBuilder
    private func gradedLayer(size: CGSize) -> some View {
        Group {
            if dwellStage >= .graded, let before = beforeImage, let after = afterImage {
                if model.showBefore {
                    Image(nsImage: before)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else if model.softRender.mix < 0.999 {
                    ZStack {
                        Image(nsImage: before).resizable().aspectRatio(contentMode: .fit)
                        Image(nsImage: after).resizable().aspectRatio(contentMode: .fit)
                            .opacity(model.softRender.mix)
                    }
                } else {
                    Image(nsImage: after)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                }
            }
        }
        .frame(maxWidth: size.width, maxHeight: size.height - 120)
        .opacity(dwellStage >= .graded ? 1 : 0)
        .animation(.easeIn(duration: 0.28), value: dwellStage >= .graded)
    }

    private var bottomFilmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(photos) { photo in
                        FilmstripCell(
                            photo: photo,
                            isSelected: selection == photo.id,
                            onSelect: { selection = photo.id }
                        )
                        .id(photo.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .onChange(of: selection) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onAppear {
                if let id = selection {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func beginDwell(for photoID: UUID) {
        dwellTask?.cancel()
        renderTask?.cancel()
        dwellStage = .silhouette
        model.selectPhoto(photoID)
        model.softRender.snapBefore()
        model.showBefore = false

        if let photo = photos.first(where: { $0.id == photoID }) {
            model.prefetchPhotoDisplay(photo)
            loadSilhouette(for: photo)
        }

        dwellTask = Task {
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                dwellStage = .rendering
                scheduleGradedRender(for: photoID)
            }
        }
    }

    private func loadSilhouette(for photo: PhotoRecord) {
        Task {
            let path = photo.gridThumbPath ?? photo.previewPath ?? photo.thumbPath
            var image: NSImage?
            if let path {
                image = await PhotoImageCache.shared.load(path: path)
            }
            await MainActor.run {
                silhouetteImage = image
            }
        }
    }

    private func scheduleGradedRender(for photoID: UUID) {
        renderTask?.cancel()
        renderTask = Task {
            guard let photo = photos.first(where: { $0.id == photoID }) else { return }
            let recipe = model.appliedRecipe(for: photo)
            let name = projectName

            let loaded = await Task.detached(priority: .userInitiated) { () -> (NSImage?, NSImage?) in
                guard let proxy = DevelopEngine.ensureProxy(for: photo, projectName: name) else {
                    return (nil, nil)
                }
                let before = NSImage(contentsOf: proxy)
                let after = DevelopEngine.render(url: proxy, recipe: recipe, offsets: .zero, mix: 1)
                return (before, after)
            }.value

            if Task.isCancelled { return }

            await MainActor.run {
                beforeImage = loaded.0
                afterImage = loaded.1
                withAnimation(.easeIn(duration: 0.28)) {
                    dwellStage = .graded
                }
            }

            try? await Task.sleep(nanoseconds: 140_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                withAnimation(.spring(duration: 0.38, bounce: 0.08)) {
                    dwellStage = .manual
                }
            }

            try? await Task.sleep(nanoseconds: 220_000_000)
            if Task.isCancelled { return }

            await MainActor.run {
                dwellStage = .auto
                model.playSoftRender(for: photoID)
            }
        }
    }
}

private struct FilmstripCell: View {
    let photo: PhotoRecord
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            PhotoImageView(photo: photo, tier: .grid, contentMode: .fill)
                .frame(width: 58, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.white.opacity(0.15),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                }
        }
        .buttonStyle(.plain)
    }
}
