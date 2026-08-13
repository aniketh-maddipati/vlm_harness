import SwiftUI
import AppKit

/// Progressive photo display — session cache first, no eternal spinners.
struct PhotoImageView: View {
    var photo: PhotoRecord?
    var path: String?
    var tier: PhotoImageTier = .preview
    var projectName: String?
    var contentMode: ContentMode = .fit

    @State private var image: NSImage?
    @State private var loadState: LoadState = .loading
    @State private var activeKey = ""

    private enum LoadState {
        case loading
        case ready
        case missing
        case failed
    }

    var body: some View {
        Group {
            switch loadState {
            case .ready:
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .aspectRatio(contentMode: contentMode)
                }
            case .loading:
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary)
                    .overlay { ProgressView().controlSize(.small) }
            case .missing, .failed:
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary)
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "photo")
                                .foregroundStyle(.tertiary)
                            if let photo {
                                Text(photo.filename)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(6)
                    }
            }
        }
        .task(id: resolveKey) {
            await load(for: resolveKey)
        }
    }

    private var resolveKey: String {
        let base = path ?? resolvedPath(for: tier) ?? ""
        return "\(base)|\(tier)|\(projectName ?? "")"
    }

    private func resolvedPath(for tier: PhotoImageTier) -> String? {
        guard let photo else { return path }
        if let direct = tier.path(for: photo), !direct.isEmpty { return direct }
        if tier.allowsRAWFallback {
            return photo.gridThumbPath ?? photo.thumbPath ?? photo.rawPath
        }
        return photo.gridThumbPath ?? photo.thumbPath
    }

    private func load(for key: String) async {
        guard !key.hasPrefix("|") else {
            loadState = .missing
            return
        }
        let displaySize = tier.displayMaxPixelSize
        let allowRAW = tier.allowsRAWFallback
        let candidates: [String] = {
            if let path, !path.isEmpty { return [path] }
            guard let photo else { return [] }
            var list: [String] = []
            if let p = tier.path(for: photo) { list.append(p) }
            if let p = photo.gridThumbPath { list.append(p) }
            if let p = photo.thumbPath { list.append(p) }
            if allowRAW { list.append(photo.rawPath) }
            var seen = Set<String>()
            return list.filter { seen.insert($0).inserted }
        }()

        if activeKey != key {
            activeKey = key
            loadState = .loading
        }

        for candidate in candidates {
            let outcome = await PhotoImageCache.shared.load(
                path: candidate,
                maxPixelSize: displaySize,
                allowRAW: allowRAW
            )
            switch outcome {
            case .image(let img):
                image = img
                loadState = .ready
                break
            case .missing:
                continue
            case .failed:
                continue
            }
            if loadState == .ready { break }
        }

        if loadState != .ready {
            loadState = candidates.isEmpty ? .missing : .failed
        }

        guard tier == .proxy, loadState == .ready, let photo, let projectName else { return }
        if let proxy = await PhotoImageLoader.ensureProxyPath(photo: photo, projectName: projectName) {
            let outcome = await PhotoImageCache.shared.load(path: proxy, maxPixelSize: nil, allowRAW: true)
            if case .image(let img) = outcome {
                withAnimation(LuminaTokens.Motion.fidelity) {
                    image = img
                }
            }
        }
    }
}

/// Path-only variant for import loading strip.
struct PhotoPathImageView: View {
    let path: String
    var contentMode: ContentMode = .fill

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary)
            }
        }
        .task(id: path) {
            let outcome = await PhotoImageCache.shared.load(path: path, maxPixelSize: PhotoImageTier.gridMaxPixelSize, allowRAW: false)
            switch outcome {
            case .image(let img): image = img
            case .missing, .failed: failed = true
            }
        }
    }
}
