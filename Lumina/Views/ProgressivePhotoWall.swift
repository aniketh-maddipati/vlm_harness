import AppKit
import SwiftUI

/// Screen-fit photo grid that reveals loaded previews slowly — no horizontal scroll, no thundering herd.
struct ProgressivePhotoWall: View {
    var paths: [String]
    var maxSlots: Int?
    var revealIntervalMs: UInt64 = 380
    var prefetchAhead: Int = 4

    @State private var displayed: [String] = []
    @State private var pending: [String] = []
    @State private var revealTask: Task<Void, Never>?
    @State private var slotCount = 6

    var body: some View {
        GeometryReader { geo in
            let layout = FitGridLayout.compute(in: geo.size, spacing: 10, aspect: 4 / 3)
            let slots = maxSlots ?? layout.slots
            let columns = layout.columns

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns),
                spacing: 10
            ) {
                ForEach(displayed, id: \.self) { path in
                    ProgressiveWallTile(path: path)
                        .aspectRatio(4 / 3, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                ForEach(0..<max(0, slots - displayed.count), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                        .aspectRatio(4 / 3, contentMode: .fill)
                        .overlay {
                            ProgressView()
                                .controlSize(.small)
                                .opacity(0.35)
                        }
                }
            }
            .padding(.horizontal, 20)
            .animation(.easeOut(duration: 0.42), value: displayed)
            .onAppear {
                slotCount = slots
                syncPaths(paths, slotLimit: slots)
            }
            .onChange(of: paths) { _, new in
                syncPaths(new, slotLimit: slots)
            }
            .onChange(of: geo.size) { _, new in
                let updated = FitGridLayout.compute(in: new, spacing: 10, aspect: 4 / 3).slots
                slotCount = maxSlots ?? updated
            }
        }
    }

    private func syncPaths(_ incoming: [String], slotLimit: Int) {
        let unique = incoming.filter { !$0.isEmpty }
        let known = Set(displayed + pending)
        let fresh = unique.filter { !known.contains($0) }
        guard !fresh.isEmpty else { return }

        pending.append(contentsOf: fresh)
        prefetchWindow(from: unique, slotLimit: slotLimit)
        startReveal(slotLimit: slotLimit)
    }

    private func prefetchWindow(from all: [String], slotLimit: Int) {
        let tail = Array(all.suffix(slotLimit + prefetchAhead))
        ThumbCache.shared.prefetchPaths(tail, maxPixelSize: 512, allowRAW: false)
    }

    private func startReveal(slotLimit: Int) {
        revealTask?.cancel()
        revealTask = Task {
            while !Task.isCancelled {
                let next: String? = await MainActor.run {
                    guard !pending.isEmpty else { return nil }
                    return pending.removeFirst()
                }
                guard let next else { break }

                _ = await PhotoImageCache.shared.load(path: next, maxPixelSize: 512, allowRAW: false)
                guard !Task.isCancelled else { break }

                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.45)) {
                        if displayed.count >= slotLimit {
                            displayed.removeFirst()
                        }
                        displayed.append(next)
                    }
                }
                try? await Task.sleep(nanoseconds: revealIntervalMs * 1_000_000)
            }
        }
    }
}

/// Pick / Meet wall — same progressive reveal for `PhotoRecord` sets.
struct ProgressivePickWall: View {
    let photos: [PhotoRecord]
    let selected: Set<UUID>
    var onToggle: (UUID) -> Void
    var revealIntervalMs: UInt64 = 320
    var batchSize: Int = 2

    @State private var visibleIDs: [UUID] = []
    @State private var revealTask: Task<Void, Never>?

    private var visiblePhotos: [PhotoRecord] {
        let order = Dictionary(uniqueKeysWithValues: visibleIDs.enumerated().map { ($0.element, $0.offset) })
        return photos
            .filter { order[$0.id] != nil }
            .sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
    }

    var body: some View {
        GeometryReader { geo in
            let layout = FitGridLayout.compute(in: geo.size, spacing: 12, aspect: 4 / 3)
            let columns = layout.columns

            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns),
                    spacing: 12
                ) {
                    ForEach(visiblePhotos) { photo in
                        PickWallCard(
                            photo: photo,
                            selected: selected.contains(photo.id),
                            onToggle: { onToggle(photo.id) }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .animation(.easeOut(duration: 0.35), value: visibleIDs)
            }
            .onAppear {
                startReveal(total: photos.count)
                prefetchNext(from: 0)
            }
            .onChange(of: photos.map(\.id)) { _, _ in
                visibleIDs.removeAll()
                startReveal(total: photos.count)
            }
        }
    }

    private func startReveal(total: Int) {
        revealTask?.cancel()
        guard total > 0 else { return }
        revealTask = Task {
            var index = 0
            while index < total, !Task.isCancelled {
                let batch = photos[index..<min(index + batchSize, total)]
                for photo in batch {
                    if let path = photo.gridThumbPath ?? photo.thumbPath {
                        _ = await PhotoImageCache.shared.load(path: path, maxPixelSize: 512, allowRAW: false)
                    }
                }
                let ids = batch.map(\.id)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.4)) {
                        visibleIDs.append(contentsOf: ids)
                    }
                }
                prefetchNext(from: index + batchSize)
                index += batchSize
                try? await Task.sleep(nanoseconds: revealIntervalMs * 1_000_000)
            }
        }
    }

    private func prefetchNext(from index: Int) {
        let slice = photos[index..<min(index + 8, photos.count)]
        ThumbCache.shared.prefetchPhotos(Array(slice), maxPixelSize: 512)
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
                    .overlay { ProgressView().controlSize(.small).opacity(0.4) }
            }
        }
        .task(id: path) {
            let outcome = await PhotoImageCache.shared.load(path: path, maxPixelSize: 512, allowRAW: false)
            switch outcome {
            case .image(let img):
                withAnimation(.easeOut(duration: 0.35)) { image = img }
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
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    PhotoImageView(photo: photo, tier: .grid, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(4 / 3, contentMode: .fill)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, selected ? Color.accentColor : .white.opacity(0.45))
                        .padding(8)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: selected ? 3 : 1)
                )

                Text(photo.filename)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .buttonStyle(LuminaPressStyle(pressedScale: 0.97))
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
        let pad: CGFloat = 40
        let availW = max(size.width - pad, 200)
        let availH = max(size.height - pad, 160)
        let minCellW: CGFloat = 120
        let maxCellW: CGFloat = 240

        var best = Result(columns: 2, rows: 2, slots: 4, cellSize: CGSize(width: 160, height: 120))
        var bestScore = -1.0

        for cols in 2...5 {
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
