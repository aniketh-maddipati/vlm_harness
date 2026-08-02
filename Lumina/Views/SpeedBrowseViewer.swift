import SwiftUI
import AppKit

/// Magazine-speed cull canvas. Paints only from PreviewSpine — no CI/taste on advance.
struct SpeedBrowseViewer: View {
    @Bindable var model: ProjectViewModel
    let photos: [PhotoRecord]
    @Binding var selection: UUID?

    @State private var spine = PreviewSpine.shared
    @State private var showControls = true
    @State private var restTask: Task<Void, Never>?

    private let filmstripHeight: CGFloat = 168
    private let filmCellWidth: CGFloat = 118
    private let filmCellHeight: CGFloat = 148

    var body: some View {
        GeometryReader { geo in
            let pageHeight = max(geo.size.height - filmstripHeight - 8, geo.size.height * 0.72)
            ZStack {
                Color.black.ignoresSafeArea()

                // Metal canvas for preview fidelity; silhouette NSImage underneath while warming.
                Group {
                    if spine.paintedTier == .silhouette, let image = spine.paintedImage {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.medium)
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: geo.size.width, maxHeight: pageHeight)
                            .frame(width: geo.size.width, height: pageHeight, alignment: .center)
                            .saturation(0.2)
                            .contrast(1.25)
                    } else if let id = spine.paintedPhotoID, let path = spine.paintedJPEGPath {
                        MetalBrowseCanvas(photoID: id, jpegPath: path)
                            .frame(width: geo.size.width, height: pageHeight)
                    } else if let image = spine.paintedImage {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: geo.size.width, maxHeight: pageHeight)
                            .frame(width: geo.size.width, height: pageHeight, alignment: .center)
                    } else {
                        Color.black
                            .overlay {
                                Text(selectedFilename)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                            .frame(width: geo.size.width, height: pageHeight)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                VStack(spacing: 0) {
                    topChrome
                    Spacer(minLength: 0)
                    if showControls {
                        LuminaDecisionBar(
                            onReject: { model.markReject() },
                            onHero: { model.markHero() },
                            onKeep: { model.markKeep() }
                        )
                        .padding(.bottom, 10)
                        .transition(.opacity)
                    }
                    filmstrip
                        .frame(height: filmstripHeight)
                        .background(.ultraThinMaterial.opacity(0.5))
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
                        selection = model.selectedPhotoID
                    }
            )
        }
        .onAppear {
            spine.warm(photos: photos, focus: selection ?? photos.first?.id)
            if selection == nil { selection = photos.first?.id }
            showControls = true
        }
        .onChange(of: photos.map(\.id)) { _, _ in
            spine.warm(photos: photos, focus: selection)
        }
        .onChange(of: selection) { _, new in
            guard let new, new != spine.paintedPhotoID else { return }
            spine.paint(id: new, inputTime: CFAbsoluteTimeGetCurrent(), held: false)
            scheduleControlsReveal()
        }
        .onChange(of: model.selectedPhotoID) { _, new in
            if let new { selection = new }
            scheduleControlsReveal()
        }
    }

    private var selectedFilename: String {
        guard let id = selection ?? spine.paintedPhotoID,
              let photo = photos.first(where: { $0.id == id }) else { return "" }
        return photo.filename
    }

    private var topChrome: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedFilename)
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
    }

    private var tierLabel: String {
        switch spine.paintedTier {
        case .preview: "preview · \(String(format: "%.0f", spine.lastInputToPhotonMs))ms"
        case .silhouette: "silhouette · resolving…"
        case .empty: "warming…"
        }
    }

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(photos) { photo in
                        Button {
                            let t = CFAbsoluteTimeGetCurrent()
                            model.selectBrowsePhoto(photo.id, in: photos, inputTime: t)
                            selection = photo.id
                        } label: {
                            PhotoImageView(photo: photo, tier: .grid, contentMode: .fill)
                                .frame(width: filmCellWidth, height: filmCellHeight)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(
                                            (selection ?? spine.paintedPhotoID) == photo.id
                                                ? Color.accentColor
                                                : Color.white.opacity(0.18),
                                            lineWidth: (selection ?? spine.paintedPhotoID) == photo.id ? 3 : 1
                                        )
                                }
                                .scaleEffect((selection ?? spine.paintedPhotoID) == photo.id ? 1.04 : 1)
                        }
                        .buttonStyle(.plain)
                        .id(photo.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .onChange(of: spine.paintedPhotoID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private func scheduleControlsReveal() {
        showControls = false
        restTask?.cancel()
        restTask = Task {
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.12)) {
                    showControls = true
                }
            }
        }
    }
}
