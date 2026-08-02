import SwiftUI
import AppKit

/// Magazine-speed cull canvas. Canvas updates every advance; chrome/filmstrip are decoupled.
struct SpeedBrowseViewer: View {
    @Bindable var model: ProjectViewModel
    let photos: [PhotoRecord]
    @Binding var selection: UUID?

    @State private var spine = PreviewSpine.shared
    @State private var showControls = true
    @State private var filmstripFocusID: UUID?
    @State private var filmstripTask: Task<Void, Never>?
    @State private var controlsTask: Task<Void, Never>?

    private let filmstripHeight: CGFloat = 168

    var body: some View {
        GeometryReader { geo in
            let pageHeight = max(geo.size.height - filmstripHeight - 8, geo.size.height * 0.72)
            ZStack {
                Color.black.ignoresSafeArea()

                BrowseCanvasStage(
                    spine: spine,
                    pageWidth: geo.size.width,
                    pageHeight: pageHeight,
                    filename: canvasFilename,
                    onPhotonPresent: { inputTime in
                        spine.recordPhotonPresent(inputTime: inputTime)
                    }
                )

                BrowseChromeOverlay(
                    filename: chromeFilename,
                    tierLabel: tierLabel,
                    showControls: showControls,
                    onReject: { model.markReject() },
                    onHero: { model.markHero() },
                    onKeep: { model.markKeep() }
                )

                BrowseFilmstripOverlay(
                    photos: photos,
                    focusID: filmstripFocusID,
                    filmstripHeight: filmstripHeight,
                    onSelect: { photo in
                        let t = CFAbsoluteTimeGetCurrent()
                        model.selectBrowsePhoto(photo.id, in: photos, inputTime: t)
                        selection = photo.id
                        filmstripFocusID = photo.id
                    }
                )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 36)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        let t = CFAbsoluteTimeGetCurrent()
                        if value.translation.width < -36 {
                            model.advanceBrowse(delta: 1, in: photos, inputTime: t)
                        } else if value.translation.width > 36 {
                            model.advanceBrowse(delta: -1, in: photos, inputTime: t)
                        }
                        selection = model.selectedPhotoID
                    }
            )
        }
        .onAppear {
            spine.warm(photos: photos, focus: selection ?? photos.first?.id)
            if selection == nil { selection = photos.first?.id }
            filmstripFocusID = selection ?? photos.first?.id
            showControls = true
        }
        .onChange(of: photos.map(\.id)) { _, _ in
            spine.warm(photos: photos, focus: selection)
        }
        .onChange(of: selection) { _, new in
            guard let new, new != spine.paintedPhotoID else { return }
            spine.paint(id: new, inputTime: CFAbsoluteTimeGetCurrent(), held: false)
            scheduleFilmstripUpdate(to: new, immediate: true)
            scheduleControlsReveal(immediate: true)
        }
        .onChange(of: model.selectedPhotoID) { _, new in
            if let new {
                selection = new
                scheduleFilmstripUpdate(to: new, immediate: spine.ripVelocity < 4)
            }
            if spine.ripVelocity < 4 {
                scheduleControlsReveal(immediate: false)
            }
        }
        .onChange(of: spine.paintedPhotoID) { _, new in
            guard let new else { return }
            scheduleFilmstripUpdate(to: new, immediate: spine.ripVelocity < 4)
        }
    }

    private var canvasFilename: String {
        guard let id = spine.paintedPhotoID,
              let photo = photos.first(where: { $0.id == id }) else { return "" }
        return photo.filename
    }

    private var chromeFilename: String {
        guard let id = filmstripFocusID ?? spine.paintedPhotoID,
              let photo = photos.first(where: { $0.id == id }) else { return "" }
        return photo.filename
    }

    private var tierLabel: String {
        switch spine.paintedTier {
        case .preview: "preview · commit \(String(format: "%.0f", spine.lastPaintCommitMs))ms"
        case .silhouette: "silhouette · GPU warming…"
        case .empty: "warming…"
        }
    }

    /// Debounce filmstrip during rips; snap on settle.
    private func scheduleFilmstripUpdate(to id: UUID, immediate: Bool) {
        filmstripTask?.cancel()
        if immediate {
            filmstripFocusID = id
            return
        }
        filmstripTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { filmstripFocusID = id }
        }
    }

    /// Skip chrome animation churn during fast rips.
    private func scheduleControlsReveal(immediate: Bool) {
        guard spine.ripVelocity < 8 else { return }
        controlsTask?.cancel()
        if immediate {
            showControls = true
            return
        }
        showControls = false
        controlsTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { showControls = true }
        }
    }
}

// MARK: - Isolated canvas (only these spine fields invalidate Metal stage)

private struct BrowseCanvasStage: View {
    let spine: PreviewSpine
    let pageWidth: CGFloat
    let pageHeight: CGFloat
    let filename: String
    var onPhotonPresent: (CFAbsoluteTime) -> Void

    var body: some View {
        ZStack {
            if spine.paintedTier == .silhouette, let image = spine.paintedSilhouette {
                SilhouetteFallback(image: image, width: pageWidth, height: pageHeight)
            } else if let id = spine.paintedPhotoID, let path = spine.paintedJPEGPath {
                MetalBrowseCanvas(
                    photoID: id,
                    jpegPath: path,
                    photonInputTime: spine.pendingPhotonTime(for: id),
                    onPhotonPresent: onPhotonPresent
                )
                .frame(width: pageWidth, height: pageHeight)
            } else {
                Color.black
                    .overlay {
                        Text(filename)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .frame(width: pageWidth, height: pageHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct SilhouetteFallback: View {
    let image: NSImage
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.medium)
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: width, maxHeight: height)
            .frame(width: width, height: height, alignment: .center)
            .saturation(0.2)
            .contrast(1.25)
    }
}

// MARK: - Chrome (filename bar + decision bar — not tied to every paint)

private struct BrowseChromeOverlay: View {
    let filename: String
    let tierLabel: String
    let showControls: Bool
    var onReject: () -> Void
    var onHero: () -> Void
    var onKeep: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(filename)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(tierLabel)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                Text("F/D flip · P/X · M · ⌥` HUD")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            Spacer(minLength: 0)
            if showControls {
                LuminaDecisionBar(onReject: onReject, onHero: onHero, onKeep: onKeep)
                    .padding(.bottom, 10)
            }
        }
    }
}

// MARK: - Filmstrip (debounced focus, no scroll on every intermediate frame)

private struct BrowseFilmstripOverlay: View {
    let photos: [PhotoRecord]
    let focusID: UUID?
    let filmstripHeight: CGFloat
    var onSelect: (PhotoRecord) -> Void

    private let filmCellWidth: CGFloat = 118
    private let filmCellHeight: CGFloat = 148

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(photos) { photo in
                            Button {
                                onSelect(photo)
                            } label: {
                                PhotoImageView(photo: photo, tier: .grid, contentMode: .fill)
                                    .frame(width: filmCellWidth, height: filmCellHeight)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(
                                                focusID == photo.id ? Color.accentColor : Color.white.opacity(0.18),
                                                lineWidth: focusID == photo.id ? 3 : 1
                                            )
                                    }
                                    .scaleEffect(focusID == photo.id ? 1.04 : 1)
                            }
                            .buttonStyle(.plain)
                            .id(photo.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .onChange(of: focusID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .frame(height: filmstripHeight)
            .background(.ultraThinMaterial.opacity(0.5))
        }
    }
}
