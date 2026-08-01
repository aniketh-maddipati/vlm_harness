import SwiftUI

struct DynamicSortBar: View {
    @Binding var sortMode: SortMode
    var uncertainCount: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SortMode.allCases) { mode in
                    Button {
                        withAnimation(.spring(duration: 0.28, bounce: 0.12)) {
                            sortMode = mode
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(mode.rawValue)
                            if mode == .uncertain, uncertainCount > 0 {
                                Text("\(uncertainCount)")
                                    .font(.caption2.monospacedDigit())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.orange.opacity(0.85), in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                        .font(.subheadline.weight(sortMode == mode ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(sortMode == mode ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}

struct CompareOverlayView: View {
    let before: NSImage?
    let after: NSImage?
    @Binding var mix: Double
    var onDragMix: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geo in
            // Letterbox both images in the same frame so wipe never stretches mismatched aspects.
            ZStack {
                Color.black.opacity(0.12)
                if let before {
                    Image(nsImage: before)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                if let after {
                    Image(nsImage: after)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .mask(
                            HStack(spacing: 0) {
                                Rectangle().frame(width: geo.size.width * mix)
                                Spacer(minLength: 0)
                            }
                        )
                }
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 2)
                    .offset(x: geo.size.width * (mix - 0.5))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let t = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
                        mix = t
                        onDragMix?(t)
                    }
            )
        }
    }
}

/// Side-by-side wipe compare for uncertain burst/cluster pairs.
struct ComparePairView: View {
    let left: PhotoRecord
    let right: PhotoRecord
    let projectName: String
    @Binding var mix: Double
    var selectedID: UUID?
    var onSelect: (UUID) -> Void

    @State private var leftImage: NSImage?
    @State private var rightImage: NSImage?

    var body: some View {
        VStack(spacing: 8) {
            CompareOverlayView(before: leftImage, after: rightImage, mix: $mix) { _ in }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Button {
                    onSelect(left.id)
                } label: {
                    Text("← \(left.filename)")
                        .font(.caption.weight(selectedID == left.id ? .bold : .regular))
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Drag wipe · Space holds before")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onSelect(right.id)
                } label: {
                    Text("\(right.filename) →")
                        .font(.caption.weight(selectedID == right.id ? .bold : .regular))
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: "\(left.id)-\(right.id)") {
            let name = projectName
            let leftPath = left.proxyPath ?? left.displayThumbPath
            let rightPath = right.proxyPath ?? right.displayThumbPath
            let loaded = await Task.detached(priority: .userInitiated) {
                (
                    leftPath.flatMap { NSImage(contentsOf: URL(fileURLWithPath: $0)) },
                    rightPath.flatMap { NSImage(contentsOf: URL(fileURLWithPath: $0)) }
                )
            }.value
            leftImage = loaded.0
            rightImage = loaded.1
            if mix == 0 || mix == 1 { mix = 0.5 }
            _ = name
        }
    }
}

struct SoftPreviewView: View {
    let photo: PhotoRecord
    let projectName: String
    let baseline: DevelopRecipe
    let offsets: DevelopAdjustments
    let mix: Double
    let showBefore: Bool

    @State private var beforeImage: NSImage?
    @State private var afterImage: NSImage?

    var body: some View {
        Group {
            if showBefore {
                imageView(beforeImage)
            } else if let before = beforeImage, let after = afterImage, mix < 0.999 {
                ZStack {
                    Image(nsImage: before).resizable().aspectRatio(contentMode: .fit)
                    Image(nsImage: after).resizable().aspectRatio(contentMode: .fit).opacity(mix)
                }
            } else {
                imageView(afterImage ?? beforeImage)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: taskID) { await load() }
    }

    private var taskID: String {
        "\(photo.id)-\(photo.recipe?.exposure ?? 0)-\(photo.recipe?.temperature ?? 0)-\(offsets.exposure)-\(offsets.temperature)-\(offsets.highlights)"
    }

    @ViewBuilder
    private func imageView(_ image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            ProgressView()
        }
    }

    private func load() async {
        let name = projectName
        let photo = photo
        let recipe = photo.effectiveRecipe
        let offsets = offsets

        let loaded = await Task.detached(priority: .userInitiated) { () -> (NSImage?, NSImage?) in
            guard let proxy = DevelopEngine.ensureProxy(for: photo, projectName: name) else {
                return (nil, nil)
            }
            let before = NSImage(contentsOf: proxy)
            let after = DevelopEngine.render(url: proxy, recipe: recipe, offsets: offsets, mix: 1)
            return (before, after)
        }.value

        beforeImage = loaded.0
        afterImage = loaded.1
    }
}
