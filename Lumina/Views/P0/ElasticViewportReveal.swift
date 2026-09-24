import AppKit
import CoreGraphics
import SwiftUI

/// View geometry only. Focus, selection and recipes remain owned by the session.
nonisolated enum ElasticViewportReveal {
    struct Anchor: Equatable {
        var id: UUID
        var position: CGFloat
    }

    /// One-shot layout request, not a second focus model. Once resolved or exhausted,
    /// subsequent geometry changes (including manual scrolling) cannot trigger a reveal.
    struct Request: Equatable {
        var id: UUID
        var position: CGFloat? = nil
        var expectedSize: CGSize? = nil
        var containerID: String? = nil

        enum Resolution: Equatable {
            case wait
            case finished
            case reveal(UUID, CGFloat?)
        }

        mutating func resolve(frames: [UUID: CGRect], viewport: CGRect, realizedContainers: Set<String> = []) -> Resolution {
            guard let frame = frames[id] else {
                // Only the requested container's layout can finish a missing-target request.
                // An unrelated or empty preference update is not a realization signal.
                return containerID.map { realizedContainers.contains($0) } == true ? .finished : .wait
            }
            if let expectedSize, frame.size != expectedSize { return .wait }
            if let position { return .reveal(id, position) }
            return needsReveal(frame, in: viewport) ? .reveal(id, nil) : .finished
        }
    }

    static func needsReveal(_ target: CGRect, in viewport: CGRect) -> Bool {
        guard !target.isEmpty, !viewport.isEmpty else { return false }
        // A target larger than the viewport is already revealed when it spans it.
        let horizontal = target.minX >= viewport.minX && target.maxX <= viewport.maxX
            || target.minX <= viewport.minX && target.maxX >= viewport.maxX
        let vertical = target.minY >= viewport.minY && target.maxY <= viewport.maxY
            || target.minY <= viewport.minY && target.maxY >= viewport.maxY
        return !horizontal || !vertical
    }

    static func anchor(frames: [UUID: CGRect], viewport: CGRect) -> Anchor? {
        guard !viewport.isEmpty else { return nil }
        let visible = frames.filter { $0.value.intersects(viewport) }
        guard let first = visible.min(by: { lhs, rhs in
            if lhs.value.minY != rhs.value.minY { return lhs.value.minY < rhs.value.minY }
            if lhs.value.minX != rhs.value.minX { return lhs.value.minX < rhs.value.minX }
            return lhs.key.uuidString < rhs.key.uuidString
        }) else { return nil }
        let travel = viewport.height - first.value.height
        // scrollTo's unit anchor aligns the same fractional point of both rectangles.
        let position = travel > 0 ? (first.value.minY - viewport.minY) / travel : 0
        return Anchor(id: first.key, position: min(max(position, 0), 1))
    }
}

struct ElasticViewportSnapshot: Equatable {
    var tiles: [UUID: CGRect] = [:]
    var containers: Set<String> = []
}

struct ElasticViewportFrames: PreferenceKey {
    static let defaultValue = ElasticViewportSnapshot()
    static func reduce(value: inout ElasticViewportSnapshot, nextValue: () -> ElasticViewportSnapshot) {
        let next = nextValue()
        value.tiles.merge(next.tiles, uniquingKeysWith: { _, latest in latest })
        value.containers.formUnion(next.containers)
    }
}

private struct ElasticViewportSpaceKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var elasticViewportSpace: UUID? {
        get { self[ElasticViewportSpaceKey.self] }
        set { self[ElasticViewportSpaceKey.self] = newValue }
    }
}

/// Only tiles under the active table/strip contribute; shelf/peek thumbnails do not.
struct ElasticViewportTile: ViewModifier {
    let id: UUID
    @Environment(\.elasticViewportSpace) private var space

    func body(content: Content) -> some View {
        content.background {
            if let space {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ElasticViewportFrames.self,
                        value: ElasticViewportSnapshot(tiles: [id: geometry.frame(in: .named(space))])
                    )
                }
            }
        }
        .id(id)
    }
}

/// Observe native live-scroll commencement solely to cancel a pending programmatic
/// reveal. The scroll view still owns events, momentum, offsets and physics.
struct ElasticScrollInterruption: NSViewRepresentable {
    var onBegin: () -> Void

    func makeNSView(context: Context) -> ObserverView { ObserverView() }
    func updateNSView(_ view: ObserverView, context: Context) {
        view.onBegin = onBegin
        view.attach()
    }
    static func dismantleNSView(_ view: ObserverView, coordinator: ()) { view.detach() }

    final class ObserverView: NSView {
        var onBegin: (() -> Void)?
        private weak var observedScroll: NSScrollView?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { detach() } else { attach() }
        }
        override func layout() { super.layout(); attach() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func attach() {
            guard let scroll = enclosingScrollView, scroll !== observedScroll else { return }
            detach()
            observedScroll = scroll
            observer = NotificationCenter.default.addObserver(
                forName: NSScrollView.willStartLiveScrollNotification, object: scroll, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onBegin?() }
            }
        }
        func detach() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            observedScroll = nil
        }
    }
}
