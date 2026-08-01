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
    @State private var loadedKey = ""

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
        .task(id: loadKey) { await load() }
    }

    private var loadKey: String {
        let base = path ?? photo.flatMap { tier.path(for: $0) } ?? ""
        return "\(base)-\(tier)-\(projectName ?? "")"
    }

    private func load() async {
        image = nil

        if let fast = path ?? photo.flatMap({ PhotoImageTier.preview.path(for: $0) }),
           let img = await PhotoImageCache.shared.load(path: fast) {
            image = img
        }

        guard tier == .proxy, let photo, let projectName else { return }
        if let proxy = await PhotoImageLoader.ensureProxyPath(photo: photo, projectName: projectName),
           let sharp = await PhotoImageCache.shared.load(path: proxy) {
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
            image = await PhotoImageCache.shared.load(path: path)
        }
    }
}
