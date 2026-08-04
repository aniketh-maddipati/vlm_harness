import SwiftUI
import AppKit

/// Magazine-speed cull canvas. Canvas updates every advance; chrome/filmstrip are decoupled.
struct SpeedBrowseViewer: View {
    @Bindable var model: ProjectViewModel
    /// Full session order; this is the stable PreviewSpine currency.
    let photos: [PhotoRecord]
    /// Posture-specific peek strip without shrinking/rebuilding the spine.
    let filmstripPhotos: [PhotoRecord]
    @Binding var selection: UUID?

    @State private var spine = PreviewSpine.shared
    /// Chrome weather — hidden by default; condenses after stillness.
    @State private var showControls = false
    @State private var filmstripFocusID: UUID?
    @State private var filmstripTask: Task<Void, Never>?
    @State private var controlsTask: Task<Void, Never>?

    private var filmstripHeight: CGFloat { filmstripPhotos.count > 1 ? 104 : 0 }

    var body: some View {
        GeometryReader { geo in
            let chromeInset: CGFloat = showControls && filmstripPhotos.count > 1 ? filmstripHeight : 0
            let pageHeight = max(geo.size.height - chromeInset, geo.size.height * 0.92)
            ZStack {
                LuminaAtmosphere.void.ignoresSafeArea()

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
                    showControls: showControls,
                    onReject: { model.markReject() },
                    onHero: { model.markHero() },
                    onKeep: { model.markKeep() }
                )
                .opacity(showControls ? 1 : 0)
                .animation(
                    showControls ? LuminaAtmosphere.Motion.condense : LuminaAtmosphere.Motion.dissolve,
                    value: showControls
                )
                .allowsHitTesting(showControls)

                if filmstripPhotos.count > 1 {
                    BrowseFilmstripOverlay(
                        photos: filmstripPhotos,
                        focusID: filmstripFocusID,
                        filmstripHeight: filmstripHeight,
                        onSelect: { photo in
                            let t = CFAbsoluteTimeGetCurrent()
                            model.selectBrowsePhoto(photo.id, in: photos, inputTime: t)
                            selection = photo.id
                            filmstripFocusID = photo.id
                        }
                    )
                    .opacity(showControls ? 1 : 0)
                    .animation(
                        showControls ? LuminaAtmosphere.Motion.condense : LuminaAtmosphere.Motion.dissolve,
                        value: showControls
                    )
                    .allowsHitTesting(showControls)
                }
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
                        selection = model.cursor
                    }
            )
        }
        .onAppear {
            spine.warm(photos: photos, focus: selection ?? photos.first?.id)
            if selection == nil { selection = photos.first?.id }
            filmstripFocusID = selection ?? photos.first?.id
            scheduleControlsReveal(immediate: false)
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
        .onChange(of: model.cursor) { _, new in
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

    /// Debounce filmstrip during rips; snap on settle.
    private func scheduleFilmstripUpdate(to id: UUID, immediate: Bool) {
        filmstripTask?.cancel()
        if immediate {
            filmstripFocusID = id
            return
        }
        filmstripTask = Task {
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { filmstripFocusID = id }
        }
    }

    /// Chrome dissolves while ripping; condenses after stillness.
    private func scheduleControlsReveal(immediate: Bool) {
        controlsTask?.cancel()
        if spine.ripVelocity >= 4 {
            showControls = false
            return
        }
        if immediate {
            showControls = true
            return
        }
        showControls = false
        controlsTask = Task {
            try? await Task.sleep(nanoseconds: 520_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard spine.ripVelocity < 4 else { return }
                showControls = true
            }
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
            Color.black
            MetalBrowseCanvas(
                photoID: spine.paintedPhotoID,
                jpegPath: spine.paintedJPEGPath,
                photonInputTime: spine.paintedPhotoID.flatMap { spine.pendingPhotonTime(for: $0) },
                onPhotonPresent: onPhotonPresent
            )
            .frame(width: pageWidth, height: pageHeight)

            if spine.paintedTier == .silhouette, let image = spine.paintedSilhouette {
                SilhouetteFallback(image: image, width: pageWidth, height: pageHeight)
                    .transition(.opacity)
            } else if spine.paintedTier == .empty {
                Text(filename)
                    .font(LuminaAtmosphere.Typeface.caption(12))
                    .foregroundStyle(LuminaAtmosphere.breath)
            }
        }
        .animation(LuminaAtmosphere.Motion.reveal, value: spine.paintedTier)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
            .saturation(0.15)
            .contrast(1.15)
            .opacity(0.88)
            .blur(radius: 0.6)
    }
}

// MARK: - Chrome weather (filename whisper + decision bar)

private struct BrowseChromeOverlay: View {
    let filename: String
    let showControls: Bool
    var onReject: () -> Void
    var onHero: () -> Void
    var onKeep: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(filename)
                    .font(LuminaAtmosphere.Typeface.caption(12))
                    .foregroundStyle(Color.white.opacity(0.42))
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            Spacer(minLength: 0)
            if showControls {
                LuminaDecisionBar(onReject: onReject, onHero: onHero, onKeep: onKeep)
                    .padding(.bottom, 18)
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

    private let filmCellWidth: CGFloat = 88
    private let filmCellHeight: CGFloat = 96

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos) { photo in
                            Button {
                                onSelect(photo)
                            } label: {
                                SpineAwarePhotoTile(photo: photo)
                                    .frame(width: filmCellWidth, height: filmCellHeight)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .strokeBorder(
                                                focusID == photo.id
                                                    ? LuminaAtmosphere.affirm.opacity(0.85)
                                                    : Color.white.opacity(0.10),
                                                lineWidth: focusID == photo.id ? 1.5 : 0.5
                                            )
                                    }
                                    .opacity(focusID == photo.id ? 1 : 0.62)
                                    .scaleEffect(focusID == photo.id ? 1.02 : 1)
                            }
                            .buttonStyle(.plain)
                            .id(photo.id)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                }
                .onAppear {
                    PreviewSpine.shared.warm(photos: photos, focus: focusID ?? photos.first?.id)
                    ThumbCache.shared.prefetchPhotos(photos, maxPixelSize: 512)
                }
                .onChange(of: focusID) { _, id in
                    guard let id else { return }
                    withAnimation(LuminaAtmosphere.Motion.dissolve) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .frame(height: filmstripHeight)
            .background(
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}
