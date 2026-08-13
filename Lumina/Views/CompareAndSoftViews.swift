import SwiftUI

/// Sort/filter lens — only shown inside grid overview.
struct DynamicSortBar: View {
    @Binding var sortMode: SortMode
    @Binding var filter: GridFilter

    var body: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SortMode.gridLensModes) { mode in
                        lensButton(mode.rawValue, active: sortMode == mode) {
                            withAnimation(LuminaTokens.Motion.photo) {
                                sortMode = mode
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GridFilter.allCases) { f in
                        lensButton(f.rawValue, active: filter == f) {
                            withAnimation(LuminaTokens.Motion.photo) {
                                filter = f
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 6)
    }

    private func lensButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(active ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(active ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct CompareOverlayView: View {
    let before: NSImage?
    let after: NSImage?
    @Binding var mix: Double
    var onDragMix: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geo in
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

/// Unified graded compare — single before/after or pair wipe, always taste-applied.
struct GradedCompareView: View {
    enum Mode: Equatable {
        case single(PhotoRecord)
        case pair(left: PhotoRecord, right: PhotoRecord)
    }

    let mode: Mode
    let projectName: String
    let recipeFor: (PhotoRecord) -> DevelopRecipe
    @Binding var mix: Double
    var showBefore: Bool = false
    var selectedID: UUID?
    var onSelect: ((UUID) -> Void)?

    @State private var beforeImage: NSImage?
    @State private var afterImage: NSImage?
    @State private var pairLeftAfter: NSImage?
    @State private var pairRightAfter: NSImage?
    @State private var developTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 8) {
            Group {
                switch mode {
                case .single(let photo):
                    singleBody
                case .pair(let left, let right):
                    VStack(spacing: 8) {
                        CompareOverlayView(
                            before: pairLeftAfter,
                            after: pairRightAfter,
                            mix: $mix
                        )
                        pairChrome(left: left, right: right)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: taskID) {
            developTask?.cancel()
            await loadGraded()
        }
        .onChange(of: recipeFingerprint) { _, _ in
            developTask?.cancel()
            developTask = Task { await loadGraded(debounce: true) }
        }
        .onDisappear { developTask?.cancel() }
    }

    private var taskID: String {
        switch mode {
        case .single(let p): return "s-\(p.id)-\(recipeFingerprint)"
        case .pair(let l, let r): return "p-\(l.id)-\(r.id)-\(recipeFingerprint)"
        }
    }

    private var recipeFingerprint: String {
        switch mode {
        case .single(let p):
            let r = recipeFor(p)
            return "\(r.exposure)-\(r.temperature)-\(r.shadows)"
        case .pair(let l, let r):
            return "\(recipeFor(l).exposure)-\(recipeFor(r).exposure)"
        }
    }

    @ViewBuilder
    private var singleBody: some View {
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
    }

    @ViewBuilder
    private func pairChrome(left: PhotoRecord, right: PhotoRecord) -> some View {
        HStack {
            Button { onSelect?(left.id) } label: {
                Text("← \(left.filename)")
                    .font(.caption.weight(selectedID == left.id ? .bold : .regular))
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Graded wipe · Space holds before")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button { onSelect?(right.id) } label: {
                Text("\(right.filename) →")
                    .font(.caption.weight(selectedID == right.id ? .bold : .regular))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func imageView(_ image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
        } else {
            ProgressView()
        }
    }

    private func loadGraded(debounce: Bool = false) async {
        if debounce { try? await Task.sleep(nanoseconds: 90_000_000) }
        if Task.isCancelled { return }

        let name = projectName
        switch mode {
        case .single(let photo):
            let recipe = recipeFor(photo)
            let loaded = await Task.detached(priority: .userInitiated) { () -> (NSImage?, NSImage?) in
                guard let proxy = DevelopEngine.ensureProxy(for: photo, projectName: name) else {
                    return (nil, nil)
                }
                let before = NSImage(contentsOf: proxy)
                let after = DevelopEngine.render(url: proxy, recipe: recipe, offsets: .zero, mix: 1)
                return (before, after)
            }.value
            if Task.isCancelled { return }
            withAnimation(LuminaSpringAnimation.animation(durationMs: 200, curve: .easeOut)) {
                beforeImage = loaded.0
                afterImage = loaded.1
            }
        case .pair(let left, let right):
            let leftRecipe = recipeFor(left)
            let rightRecipe = recipeFor(right)
            let loaded = await Task.detached(priority: .userInitiated) { () -> (NSImage?, NSImage?) in
                func graded(_ photo: PhotoRecord, recipe: DevelopRecipe) -> NSImage? {
                    guard let proxy = DevelopEngine.ensureProxy(for: photo, projectName: name) else { return nil }
                    return DevelopEngine.render(url: proxy, recipe: recipe, offsets: .zero, mix: 1)
                }
                return (graded(left, recipe: leftRecipe), graded(right, recipe: rightRecipe))
            }.value
            if Task.isCancelled { return }
            pairLeftAfter = loaded.0
            pairRightAfter = loaded.1
            if mix == 0 || mix == 1 { mix = 0.5 }
        }
    }
}
