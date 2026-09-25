import CoreGraphics
import Foundation

/// Placement of the open photograph under a pinch.
///
/// `zoom` 1 is aspect-fit. Pan is in points, top-left, and matches
/// `PhotoPresentProof`: positive x moves the picture right, positive y moves it
/// down. The gesture only changes these two numbers. It does not render.
nonisolated struct FocusZoom: Equatable, Sendable {
    var zoom: CGFloat = 1
    var pan: CGSize = .zero

    static let fit: CGFloat = 1
    /// How far past fit or 1:1 a live pinch may stretch before it stops growing.
    static let rubberSlack: CGFloat = 48
    /// Horizontal travel at fit that pages to the next photograph.
    static let pageThreshold: CGFloat = 72
    /// Used until the sensor size is known, so a pinch still has somewhere to go.
    static let fallbackMaxZoom: CGFloat = 6
    /// Two-finger double-tap lands here when the picture is at fit.
    static let smartZoom: CGFloat = 2
    /// Used only when the window has not reported a backing scale yet.
    static let assumedBackingScale: CGFloat = 2

    /// Sensor pixels per screen pixel at fit. At least 1, so fit is always legal.
    static func maximum(sensor: CGSize, box: CGSize, backingScale: CGFloat) -> CGFloat {
        let backing = max(backingScale, 1)
        guard sensor.width > 1, sensor.height > 1, box.width > 1, box.height > 1 else {
            return fallbackMaxZoom
        }
        let across = sensor.width / (box.width * backing)
        let down = sensor.height / (box.height * backing)
        return max(fit, min(across, down))
    }

    /// Where `viewPoint` sits in the picture, 0...1, origin top-left.
    func contentFraction(at viewPoint: CGPoint, in box: CGSize) -> CGPoint {
        let displayed = CGSize(width: box.width * zoom, height: box.height * zoom)
        let origin = pictureOrigin(in: box)
        guard displayed.width > 0, displayed.height > 0 else {
            return CGPoint(x: 0.5, y: 0.5)
        }
        return CGPoint(
            x: (viewPoint.x - origin.x) / displayed.width,
            y: (viewPoint.y - origin.y) / displayed.height
        )
    }

    /// `delta` is the trackpad magnification for this event (0 means unchanged).
    /// The content point under `viewPoint` stays under `viewPoint`.
    mutating func magnify(
        by delta: CGFloat,
        at viewPoint: CGPoint,
        in box: CGSize,
        maxZoom: CGFloat,
        rubber: Bool
    ) {
        guard box.width > 1, box.height > 1 else { return }
        let factor = 1 + delta
        guard factor > 0 else { return }
        let anchor = contentFraction(at: viewPoint, in: box)
        let limit = Swift.max(maxZoom, Self.fit)
        var next = zoom * factor
        if rubber {
            next = resist(next, min: Self.fit, max: limit)
        } else {
            next = min(Swift.max(next, Self.fit), limit)
        }
        zoom = next
        let displayed = CGSize(width: box.width * zoom, height: box.height * zoom)
        let originX = viewPoint.x - anchor.x * displayed.width
        let originY = viewPoint.y - anchor.y * displayed.height
        pan.width = originX - (box.width - displayed.width) / 2
        pan.height = originY - (box.height - displayed.height) / 2
        if rubber {
            resistPan(in: box)
        } else {
            clampPan(in: box)
        }
    }

    mutating func pan(by delta: CGSize, in box: CGSize, rubber: Bool) {
        guard zoom > Self.fit else {
            pan = .zero
            return
        }
        pan.width += delta.width
        pan.height += delta.height
        if rubber {
            resistPan(in: box)
        } else {
            clampPan(in: box)
        }
    }

    /// Drop the rubber-band. Fit is the floor, `maxZoom` is the ceiling.
    mutating func settle(in box: CGSize, maxZoom: CGFloat) {
        let limit = Swift.max(maxZoom, Self.fit)
        zoom = min(Swift.max(zoom, Self.fit), limit)
        if zoom <= Self.fit + 0.001 {
            zoom = Self.fit
            pan = .zero
        } else {
            clampPan(in: box)
        }
    }

    /// A sharper bitmap of the same photograph arrived. Keep the same on-screen
    /// scale: `PhotoPresentProof` fits by `drawable / extent`, so a larger extent
    /// needs a proportionally larger zoom.
    mutating func rebase(from oldExtent: CGSize, to newExtent: CGSize) {
        guard oldExtent.width > 1, newExtent.width > 1, zoom > Self.fit else { return }
        let ratio = newExtent.width / oldExtent.width
        guard ratio > 0, abs(ratio - 1) > 0.01 else { return }
        zoom *= ratio
    }

    /// Two-finger double-tap. Zoomed returns to fit. Fit jumps to `smartZoom`,
    /// still under `maxZoom`, with `viewPoint` held still.
    mutating func toggleSmart(at viewPoint: CGPoint, in box: CGSize, maxZoom: CGFloat) {
        if zoom > Self.fit + 0.05 {
            zoom = Self.fit
            pan = .zero
            return
        }
        let limit = Swift.max(maxZoom, Self.fit)
        let target = min(Swift.max(Self.smartZoom, Self.fit), limit)
        let delta = (target / Swift.max(zoom, Self.fit)) - 1
        magnify(by: delta, at: viewPoint, in: box, maxZoom: limit, rubber: false)
    }

    /// +1 / −1 to page, or nil when the drag should pan or be ignored.
    static func page(dx: CGFloat, dy: CGFloat, zoom: CGFloat) -> Int? {
        guard zoom <= fit + 0.001 else { return nil }
        guard abs(dx) >= pageThreshold, abs(dx) > abs(dy) else { return nil }
        return dx < 0 ? 1 : -1
    }

    private func pictureOrigin(in box: CGSize) -> CGPoint {
        let displayed = CGSize(width: box.width * zoom, height: box.height * zoom)
        return CGPoint(
            x: (box.width - displayed.width) / 2 + pan.width,
            y: (box.height - displayed.height) / 2 + pan.height
        )
    }

    private mutating func clampPan(in box: CGSize) {
        let excess = excess(in: box)
        pan.width = min(Swift.max(pan.width, -excess.width), excess.width)
        pan.height = min(Swift.max(pan.height, -excess.height), excess.height)
    }

    private mutating func resistPan(in box: CGSize) {
        let excess = excess(in: box)
        pan.width = resistEdge(pan.width, limit: excess.width)
        pan.height = resistEdge(pan.height, limit: excess.height)
    }

    private func excess(in box: CGSize) -> CGSize {
        CGSize(
            width: Swift.max(0, (box.width * zoom - box.width) / 2),
            height: Swift.max(0, (box.height * zoom - box.height) / 2)
        )
    }

    private func resist(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        if value < minValue {
            return minValue - rubber(minValue - value)
        }
        if value > maxValue {
            return maxValue + rubber(value - maxValue)
        }
        return value
    }

    private func resistEdge(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        if value > limit { return limit + rubber(value - limit) }
        if value < -limit { return -limit - rubber(-limit - value) }
        return value
    }

    /// Approaches `rubberSlack` and never reaches it, so a hard pinch cannot fling the picture away.
    private func rubber(_ over: CGFloat) -> CGFloat {
        Self.rubberSlack * (1 - exp(-over / Self.rubberSlack))
    }
}
