// QUARANTINED(D40) — legacy quarantine, retired checkpoint-by-checkpoint.
// Contract: design/contract-v6.md D40 · schedule: design/checkpoint-sequence-v6.md
// No new references from outside Legacy/. Enforced by Scripts/lint/quarantine_d40.sh.
// Do not extend, restyle, or re-enter these types under new names.
import AppKit
import SwiftUI

/// Screen-fit photo grid — all paths render immediately; tiles self-load async.
/// Used by ImportLoadingView (streaming ingest) and Meet when paths are available.
struct ProgressivePhotoWall: View {
    var paths: [String]
    var maxSlots: Int?
    var revealIntervalMs: UInt64 = 380
    var prefetchAhead: Int = 4

    var body: some View {
        GeometryReader { geo in
            let layout = FitGridLayout.compute(in: geo.size, spacing: 10, aspect: 4 / 3)
            let columns = layout.columns
            let visible = Array(paths.filter { !$0.isEmpty }.prefix(maxSlots ?? paths.count))

            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: max(columns, 1)),
                    spacing: 10
                ) {
                    ForEach(visible, id: \.self) { path in
                        ProgressiveWallTile(path: path)
                            .aspectRatio(4 / 3, contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                ThumbCache.shared.prefetchPaths(visible, maxPixelSize: PhotoImageTier.gridMaxPixelSize, allowRAW: false)
            }
            .onChange(of: paths) { _, new in
                let next = Array(new.filter { !$0.isEmpty }.prefix(maxSlots ?? new.count))
                ThumbCache.shared.prefetchPaths(next, maxPixelSize: PhotoImageTier.gridMaxPixelSize, allowRAW: false)
            }
        }
    }
}

// MARK: - Session grid (Meet + Pick) — one cell per photo immediately

/// Even photo wall for a finite known set. Shows every member in one frame.
struct SessionPhotoGrid: View {
    let photos: [PhotoRecord]
    var selected: Set<UUID> = []
    var onToggle: ((UUID) -> Void)? = nil
    var columnsHint: Int? = nil

    var body: some View {
        GeometryReader { geo in
            let layout = FitGridLayout.compute(in: geo.size, spacing: 8, aspect: 4 / 3)
            let columns = columnsHint ?? min(max(layout.columns, 2), photos.count > 1 ? 5 : 1)

            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: max(columns, 1)),
                    spacing: 8
                ) {
                    ForEach(photos) { photo in
                        if let onToggle {
                            PickWallCard(
                                photo: photo,
                                selected: selected.contains(photo.id),
                                onToggle: { onToggle(photo.id) }
                            )
                        } else {
                            SessionWallTile(photo: photo)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .onAppear { warmSessionCache() }
            .onChange(of: photos.map(\.id)) { _, _ in warmSessionCache() }
        }
    }

    private func warmSessionCache() {
        guard !photos.isEmpty else { return }
        PreviewSpine.shared.warm(photos: photos, focus: photos.first?.id)
        ThumbCache.shared.prefetchPhotos(photos, maxPixelSize: PhotoImageTier.gridMaxPixelSize)
    }
}

private struct SessionWallTile: View {
    let photo: PhotoRecord

    var body: some View {
        SpineAwarePhotoTile(photo: photo)
            .aspectRatio(4 / 3, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
    }
}

/// Silhouette from PreviewSpine instantly, then session-cache fidelity — never an empty cell.
struct SpineAwarePhotoTile: View {
    let photo: PhotoRecord
    var contentMode: ContentMode = .fill

    @State private var image: NSImage?
    @State private var failed = false
    @State private var showingSilhouette = false

    private var resolveKey: String {
        [
            photo.id.uuidString,
            photo.gridThumbPath ?? "",
            photo.thumbPath ?? "",
            photo.proxyPath ?? "",
        ].joined(separator: "|")
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(showingSilhouette ? .low : .high)
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                Color.secondary.opacity(0.1)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    }
            } else {
                Color.secondary.opacity(0.08)
            }
        }
        .task(id: resolveKey) {
            await resolveFidelity()
        }
    }

    private func resolveFidelity() async {
        await MainActor.run { failed = false }

        if let sil = PreviewSpine.shared.silhouetteImage(for: photo.id) {
            await MainActor.run {
                if image == nil || showingSilhouette {
                    image = sil
                    showingSilhouette = true
                }
            }
        }

        guard photo.gridThumbPath != nil
                || photo.thumbPath != nil
                || photo.proxyPath != nil
                || PreviewSpine.shared.previewJPEGPath(for: photo.id) != nil else {
            if image == nil { await MainActor.run { failed = true } }
            return
        }

        if let img = await PreviewSpine.shared.fidelityImage(for: photo) {
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    image = img
                    showingSilhouette = false
                    failed = false
                }
            }
            return
        }

        if image == nil {
            await MainActor.run { failed = true }
        }
    }
}

private struct ProgressiveWallTile: View {
    let path: String
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else if failed {
                Color.secondary.opacity(0.08)
            } else {
                Color.secondary.opacity(0.06)
            }
        }
        .task(id: path) {
            let outcome = await PhotoImageCache.shared.load(path: path, maxPixelSize: PhotoImageTier.gridMaxPixelSize, allowRAW: false)
            switch outcome {
            case .image(let img):
                withAnimation(.easeOut(duration: 0.25)) { image = img }
            case .missing, .failed:
                failed = true
            }
        }
    }
}

struct PickWallCard: View {
    let photo: PhotoRecord
    let selected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            ZStack(alignment: .topTrailing) {
                SpineAwarePhotoTile(photo: photo)
                    .aspectRatio(4 / 3, contentMode: .fill)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, selected ? Color.accentColor : .white.opacity(0.5))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .padding(8)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: selected ? 3 : 1)
            )
        }
        .buttonStyle(LuminaPressStyle(pressedScale: 0.96))
        .accessibilityLabel(photo.filename)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

enum FitGridLayout {
    struct Result {
        let columns: Int
        let rows: Int
        let slots: Int
        let cellSize: CGSize
    }

    static func compute(in size: CGSize, spacing: CGFloat, aspect: CGFloat) -> Result {
        let pad: CGFloat = 28
        let availW = max(size.width - pad, 200)
        let availH = max(size.height - pad, 160)
        let minCellW: CGFloat = 110
        let maxCellW: CGFloat = 220

        var best = Result(columns: 2, rows: 2, slots: 4, cellSize: CGSize(width: 160, height: 120))
        var bestScore = -1.0

        for cols in 2...6 {
            let cellW = (availW - spacing * CGFloat(cols - 1)) / CGFloat(cols)
            guard cellW >= minCellW else { continue }
            let w = min(cellW, maxCellW)
            let h = w / aspect
            let rows = max(2, Int(floor((availH + spacing) / (h + spacing))))
            let slots = cols * rows
            let score = Double(slots) * Double(w)
            if score > bestScore {
                bestScore = score
                best = Result(columns: cols, rows: rows, slots: slots, cellSize: CGSize(width: w, height: h))
            }
        }
        return best
    }
}
