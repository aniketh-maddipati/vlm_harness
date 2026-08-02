import SwiftUI
import AppKit

/// Progressive photo display — fast tier first, upgrades to proxy when centered.
struct PhotoImageView: View {
    var photo: PhotoRecord?
    var path: String?
    var tier: PhotoImageTier = .preview
    var projectName: String?
    var contentMode: ContentMode = .fit

    @State private var image: NSImage?
    @State private var activeKey = ""

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: contentMode)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary)
                    .overlay { ProgressView().controlSize(.small) }
            }
        }
        .task(id: resolveKey) {
            await load(for: resolveKey)
        }
    }

    /// Stable key from the best available on-disk / RAW path.
    private var resolveKey: String {
        let base = path ?? resolvedPath(for: tier) ?? ""
        return "\(base)|\(tier)|\(projectName ?? "")"
    }

    private func resolvedPath(for tier: PhotoImageTier) -> String? {
        guard let photo else { return path }
        if let direct = tier.path(for: photo), !direct.isEmpty { return direct }
        // Fallbacks when a tier file hasn't been written yet (early ingest).
        return photo.gridThumbPath ?? photo.thumbPath ?? photo.rawPath
    }

    private func load(for key: String) async {
        guard !key.hasPrefix("|") else { return }
        let displaySize = tier.displayMaxPixelSize
        let candidates: [String] = {
            if let path, !path.isEmpty { return [path] }
            guard let photo else { return [] }
            var list: [String] = []
            if let p = tier.path(for: photo) { list.append(p) }
            if let p = photo.gridThumbPath { list.append(p) }
            if let p = photo.thumbPath { list.append(p) }
            list.append(photo.rawPath)
            // Unique preserve order
            var seen = Set<String>()
            return list.filter { seen.insert($0).inserted }
        }()

        // Keep prior frame while swapping keys to avoid blank flash.
        if activeKey != key {
            activeKey = key
        }

        for candidate in candidates {
            if let img = await PhotoImageCache.shared.load(path: candidate, maxPixelSize: displaySize) {
                image = img
                break
            }
        }

        guard tier == .proxy, let photo, let projectName else { return }
        if let proxy = await PhotoImageLoader.ensureProxyPath(photo: photo, projectName: projectName),
           let sharp = await PhotoImageCache.shared.load(path: proxy, maxPixelSize: nil) {
            withAnimation(.easeOut(duration: 0.22)) {
                image = sharp
            }
        }
    }
}

/// Path-only variant for import loading strip.
struct PhotoPathImageView: View {
    let path: String
    var contentMode: ContentMode = .fill

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: contentMode)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary)
            }
        }
        .task(id: path) {
            image = await PhotoImageCache.shared.load(path: path, maxPixelSize: 512)
        }
    }
}
