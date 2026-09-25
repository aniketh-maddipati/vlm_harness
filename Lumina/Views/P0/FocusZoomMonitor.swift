import AppKit
import SwiftUI

/// Watches pinch and scroll over the photograph without becoming the hit target,
/// so double-click and hold-before on the picture keep working.
struct FocusZoomMonitor: NSViewRepresentable {
    var enabled: Bool
    var well: CGSize
    var photo: CGSize
    var onMagnify: (CGFloat, CGPoint, Bool, CGFloat) -> Void
    var onScroll: (CGFloat, CGFloat, Bool, Bool, CGFloat) -> Void
    var onSmartZoom: (CGPoint, CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> Bridge {
        let view = Bridge()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ view: Bridge, context: Context) {
        context.coordinator.enabled = enabled
        context.coordinator.well = well
        context.coordinator.photo = photo
        context.coordinator.onMagnify = onMagnify
        context.coordinator.onScroll = onScroll
        context.coordinator.onSmartZoom = onSmartZoom
        context.coordinator.attach(to: view)
    }

    static func dismantleNSView(_ nsView: Bridge, coordinator: Coordinator) {
        coordinator.detach()
        _ = nsView
    }

    final class Bridge: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    final class Coordinator {
        var enabled = false
        var well: CGSize = .zero
        var photo: CGSize = .zero
        var onMagnify: (CGFloat, CGPoint, Bool, CGFloat) -> Void = { _, _, _, _ in }
        var onScroll: (CGFloat, CGFloat, Bool, Bool, CGFloat) -> Void = { _, _, _, _, _ in }
        var onSmartZoom: (CGPoint, CGFloat) -> Void = { _, _ in }
        private weak var view: Bridge?
        private var monitor: Any?
        private var gesturePoint: CGPoint?
        private var scrolling = false

        func attach(to view: Bridge) {
            self.view = view
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .scrollWheel, .smartMagnify]) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            view = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard enabled, let view, event.window === view.window else { return event }
            let point = photoPoint(of: event, in: view)
            switch event.type {
            case .magnify:
                return magnify(event, point: point)
            case .smartMagnify:
                guard let point else { return event }
                onSmartZoom(point, backingScale)
                return nil
            case .scrollWheel:
                return scroll(event, point: point)
            default:
                return event
            }
        }

        private var backingScale: CGFloat {
            view?.window?.backingScaleFactor ?? FocusZoom.assumedBackingScale
        }

        private func magnify(_ event: NSEvent, point: CGPoint?) -> NSEvent? {
            let ended = event.phase == .ended || event.phase == .cancelled
            if event.phase == .began || gesturePoint == nil {
                gesturePoint = point
            }
            let anchor = point ?? gesturePoint
            guard let anchor else { return event }
            if ended { gesturePoint = nil }
            onMagnify(event.magnification, anchor, ended, backingScale)
            return nil
        }

        private func scroll(_ event: NSEvent, point: CGPoint?) -> NSEvent? {
            let began = event.phase == .began || event.phase == .mayBegin
            let ended = event.momentumPhase == .ended
                || ((event.phase == .ended || event.phase == .cancelled) && event.momentumPhase.isEmpty)
            if began {
                scrolling = point != nil
                gesturePoint = point
            }
            guard point != nil || scrolling else { return event }
            scrolling = true
            onScroll(event.scrollingDeltaX, event.scrollingDeltaY, began, ended, backingScale)
            if ended {
                scrolling = false
                gesturePoint = nil
            }
            return nil
        }

        /// Top-left point inside the photograph, or nil when the event is on the matte.
        private func photoPoint(of event: NSEvent, in view: NSView) -> CGPoint? {
            let local = view.convert(event.locationInWindow, from: nil)
            let topLeft = CGPoint(x: local.x, y: view.bounds.height - local.y)
            let origin = CGPoint(
                x: (well.width - photo.width) / 2,
                y: (well.height - photo.height) / 2
            )
            let point = CGPoint(x: topLeft.x - origin.x, y: topLeft.y - origin.y)
            guard point.x >= 0, point.y >= 0, point.x <= photo.width, point.y <= photo.height else {
                return nil
            }
            return point
        }
    }
}
