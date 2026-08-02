import SwiftUI
import AppKit
import ImageIO

/// Full-bleed magazine cull: large page flip, big filmstrip, graded render after dwell.
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

    /// Tall filmstrip — magazine page feel, not a postage stamp.
    private let filmstripHeight: CGFloat = 168
    private let filmCellWidth: CGFloat = 118
    private let filmCellHeight: CGFloat = 148

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

                    Spacer(minLength: 0)

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
                        .padding(.bottom, 10)
                    }

                    bottomFilmstrip
                        .frame(height: filmstripHeight)
                        .background(.ultraThinMaterial.opacity(0.55))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        if value.translation.width < -40 {
                            advanceSelection()
                        } else if value.translation.width > 40 {
                            retreatSelection()
                        }
                    }
            )
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
            Text("Flip…")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
        case .rendering:
            Text("Rendering…")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
        case .graded:
            Text("Hold for controls")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
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
        let pageHeight = max(size.height - filmstripHeight - 8, size.height * 0.72)
        Group {
            if let silhouetteImage {
                Image(nsImage: silhouetteImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: size.width, maxHeight: pageHeight)
                    .frame(width: size.width, height: pageHeight, alignment: .center)
                    .saturation(dwellStage >= .graded ? 0 : 0.18)
                    .contrast(dwellStage >= .graded ? 1 : 1.35)
                    .brightness(dwellStage >= .graded ? 0 : -0.08)
                    .opacity(dwellStage >= .graded ? 0 : 1)
            } else {
                ProgressView()
                    .tint(.white.opacity(0.5))
                    .frame(width: size.width, height: pageHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.18), value: dwellStage >= .graded)
    }

    @ViewBuilder
    private func gradedLayer(size: CGSize) -> some View {
        let pageHeight = max(size.height - filmstripHeight - 8, size.height * 0.72)
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
        .frame(maxWidth: size.width, maxHeight: pageHeight)
        .frame(width: size.width, height: pageHeight, alignment: .center)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(dwellStage >= .graded ? 1 : 0)
        .animation(.easeIn(duration: 0.22), value: dwellStage >= .graded)
    }

    private var bottomFilmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(photos) { photo in
                        FilmstripCell(
                            photo: photo,
                            isSelected: selection == photo.id,
                            width: filmCellWidth,
                            height: filmCellHeight,
                            onSelect: {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    selection = photo.id
                                }
                            }
                        )
                        .id(photo.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .onChange(of: selection) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.22)) {
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

    private func advanceSelection() {
        guard let current = selection,
              let idx = photos.firstIndex(where: { $0.id == current }),
              idx + 1 < photos.count else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            selection = photos[idx + 1].id
        }
    }

    private func retreatSelection() {
        guard let current = selection,
              let idx = photos.firstIndex(where: { $0.id == current }),
              idx > 0 else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            selection = photos[idx - 1].id
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
            loadSilhouette(for: photo)
            model.prefetchPhotoDisplay(photo)
        }

        dwellTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                dwellStage = .rendering
                scheduleGradedRender(for: photoID)
            }
        }
    }

    private func loadSilhouette(for photo: PhotoRecord) {
        Task {
            let path = photo.gridThumbPath ?? photo.thumbPath ?? photo.previewPath
            guard let path else { return }
            let outcome = await PhotoImageCache.shared.load(path: path, maxPixelSize: 2200, allowRAW: false)
            await MainActor.run {
                if case .image(let img) = outcome {
                    silhouetteImage = img
                }
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
                let source = DevelopEngine.ensureProxy(for: photo, projectName: name)
                    ?? photo.displayThumbPath.map { URL(fileURLWithPath: $0) }
                    ?? URL(fileURLWithPath: photo.rawPath)
                let before = Self.decodeDisplay(url: source, maxPixel: 2200)
                let after = DevelopEngine.render(url: source, recipe: recipe, offsets: .zero, mix: 1)
                    ?? before
                return (before, after)
            }.value

            if Task.isCancelled { return }

            await MainActor.run {
                beforeImage = loaded.0
                afterImage = loaded.1
                withAnimation(.easeIn(duration: 0.22)) {
                    dwellStage = .graded
                }
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
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

    nonisolated private static func decodeDisplay(url: URL, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return NSImage(contentsOf: url)
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else {
            return NSImage(contentsOf: url)
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        return NSImage(
            cgImage: cg,
            size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale)
        )
    }
}

private struct FilmstripCell: View {
    let photo: PhotoRecord
    let isSelected: Bool
    var width: CGFloat = 118
    var height: CGFloat = 148
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            PhotoImageView(photo: photo, tier: .grid, contentMode: .fill)
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.white.opacity(0.18),
                            lineWidth: isSelected ? 3 : 1
                        )
                }
                .scaleEffect(isSelected ? 1.04 : 1)
                .shadow(color: isSelected ? Color.accentColor.opacity(0.35) : .clear, radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}
