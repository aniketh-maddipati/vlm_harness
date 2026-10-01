import Foundation
import CoreGraphics

// WP-4. Where the Edit photo sits in its canvas, and how Edit divides the window
// (README §3, LAYOUT_SIZING §5; R-41, R-43, R-46, R-50, R-55). Pure maths: the views and the
// headless tests use the same functions.

public enum EditLayout {
    /// The photo at its true aspect ratio, centred, touching the canvas (minus `padding`) on one
    /// axis. It is shown whole, except a strip so thin that fitting it would leave less than 1pt
    /// (2 × 3000): that one fills the canvas across its short side instead, still at its true
    /// proportions, and the canvas clips the rest (R-41, R-1C).
    public static func photoRect(aspect: CGFloat, canvas: CGSize, padding: CGFloat) -> CGRect {
        let w = max(1, canvas.width - 2 * padding), h = max(1, canvas.height - 2 * padding)
        let a = aspect.isFinite && aspect > 0 ? aspect : 1.5
        var size = a >= w / h ? CGSize(width: w, height: w / a) : CGSize(width: h * a, height: h)
        if size.height < 1 { size = CGSize(width: h * a, height: h) }
        else if size.width < 1 { size = CGSize(width: w, height: w / a) }
        return CGRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2, width: size.width, height: size.height)
    }

    /// Zoom is clamped to ¼× of Fit … 2× of 1:1 (R-46). `oneToOne` is the factor that shows 1:1.
    public static func clampZoom(_ z: Double, oneToOne: Double) -> Double { clamp(0.25, z.isFinite ? z : 1, max(1, 2 * oneToOne)) }

    /// Padding around the photo: 12pt, less only when the canvas is too small to leave 40pt of photo.
    public static func padding(canvas: CGSize) -> CGFloat {
        min(12, max(0, (min(canvas.width, canvas.height) - 40) / 2).rounded(.down))
    }

    // MARK: Edit's frames

    public struct Frames: Equatable, Sendable {
        public enum Controls: Equatable, Sendable {
            case hidden
            /// Beside the photo column, this wide.
            case side(width: CGFloat)
            /// Under the photo column (window under 860 wide), at most this high; 0 when collapsed.
            case below(maxHeight: CGFloat)
        }
        public var controls: Controls
        /// The canvas when the controls take all they may (the views report the real one).
        public var canvas: CGSize
        public var columnWidth: CGFloat
        /// Thumbnail height; 0 = no filmstrip.
        public var stripHeight: CGFloat
        /// Height of the filmstrip row with its padding.
        public var stripRow: CGFloat
        /// The facts line shares the filmstrip's row (wide columns) instead of its own.
        public var factsInline: Bool
        /// Height of the facts row when it has its own; 0 otherwise.
        public var factsRow: CGFloat
        /// Height of the "Hide ▾ / Show ▴" row; 0 when the controls are beside the photo.
        public var toggleRow: CGFloat
    }

    /// How Edit divides `area` (the window under the top bar). Chrome is × `s`; the filmstrip
    /// height is content and follows the window height. The facts line moves into the filmstrip's
    /// row once the column is 1000pt × S wide: a row of its own there would take the canvas under
    /// 70 % of a 1920 × 1080 window (R-55).
    public static func frames(area: CGSize, window: CGSize, scale s: CGFloat, focus: Bool, controlsHidden: Bool, controlsCollapsed: Bool) -> Frames {
        if focus {
            return Frames(controls: .hidden, canvas: area, columnWidth: area.width, stripHeight: 0, stripRow: 0, factsInline: false, factsRow: 0, toggleRow: 0)
        }
        let bp = Breakpoints(window), below = bp.editControlsBelow && !controlsHidden
        let side = !bp.editControlsBelow && !controlsHidden
        let ctlW = side ? min(bp.editControlsWidth(s), max(0, area.width - 160)) : 0
        let colW = max(1, area.width - ctlW)
        let strip = window.width >= 560 && window.height >= 560
        let stripH = strip ? bp.filmstripHeight.rounded() : 0
        let stripRow = strip ? stripH + 2 * LayoutScale.px(4, s) : 0
        let inline = strip && colW >= 1000 * s
        let factsRow = inline ? 0 : LayoutScale.px(20, s)
        let toggle = below ? LayoutScale.px(30, s) : 0
        var ctlH: CGFloat = 0
        if below && !controlsCollapsed {
            let want = window.height < 760 ? 0.46 * window.height : max(300, 0.58 * window.height)
            ctlH = max(0, min(want, area.height - toggle - stripRow - factsRow - 64)).rounded(.down)
        }
        let canvas = CGSize(width: colW, height: max(1, area.height - stripRow - factsRow - toggle - ctlH))
        return Frames(controls: side ? .side(width: ctlW) : below ? .below(maxHeight: ctlH) : .hidden, canvas: canvas, columnWidth: colW,
                      stripHeight: stripH, stripRow: stripRow, factsInline: inline, factsRow: factsRow, toggleRow: toggle)
    }

    /// The same, from the window alone (headless: no view has measured anything yet).
    public static func frames(window: CGSize, focus: Bool, controlsHidden: Bool, controlsCollapsed: Bool) -> Frames {
        let s = LayoutScale.scale(for: window), top = focus ? 0 : LayoutScale.px(Breakpoints(window).topBarHeight, s)
        return frames(area: CGSize(width: window.width, height: max(1, window.height - top)), window: window, scale: s,
                      focus: focus, controlsHidden: controlsHidden, controlsCollapsed: controlsCollapsed)
    }

    // MARK: sizes and zoom

    /// The size to decode at: the canvas's longest side × backing scale, rounded up to 400, at most 3600.
    public static func requestPixel(canvas: CGSize, backingScale: CGFloat) -> Int {
        let px = max(canvas.width, canvas.height) * max(1, backingScale)
        return Int(min(3600, max(400, (px / 400).rounded(.up) * 400)))
    }

    /// The zoom factor (× Fit) at which one photo pixel is one screen pixel.
    public static func oneToOne(pixels: CGSize, fit: CGSize, backingScale: CGFloat) -> Double {
        guard fit.width > 0, fit.height > 0, pixels.width > 0, pixels.height > 0 else { return 1 }
        let z = max(pixels.width / fit.width, pixels.height / fit.height) / max(1, backingScale)
        return z.isFinite ? Double(max(0.05, z)) : 1
    }

    public struct ZoomLevel: Equatable, Sendable {
        public var id: String, label: String, zoom: Double
    }

    /// The picker: Small / Fit / {percent} / 1:1 / 2:1. The middle one is half of 1:1; while the
    /// zoom is somewhere else (a pinch) it reads the current percentage of 1:1.
    public static func zoomLevels(oneToOne o: Double, zoom: Double) -> [ZoomLevel] {
        let half = clampZoom(o / 2, oneToOne: o), presets = [0.5, 1, half, clampZoom(o, oneToOne: o), clampZoom(2 * o, oneToOne: o)]
        let onPreset = presets.contains { abs($0 - zoom) < 0.02 }
        let pct = Int(((onPreset ? half : zoom) / max(o, 0.0001) * 100).rounded())
        return [ZoomLevel(id: "small", label: "Small", zoom: 0.5), ZoomLevel(id: "fit", label: "Fit", zoom: 1),
                ZoomLevel(id: "percent", label: "\(pct)%", zoom: half),
                ZoomLevel(id: "1to1", label: "1:1", zoom: presets[3]), ZoomLevel(id: "2to1", label: "2:1", zoom: presets[4])]
    }

    /// ⌘+ / ⌘−: the next stop above or below `zoom`.
    public static func zoomStop(from zoom: Double, direction d: Int, oneToOne o: Double) -> Double {
        let stops = Set([0.25, 0.5, 1, o / 2, o, 2 * o].map { clampZoom($0, oneToOne: o) }).sorted()
        let next = d > 0 ? stops.first { $0 > zoom + 0.01 } : stops.last { $0 < zoom - 0.01 }
        return next ?? zoom
    }

    /// The photo's frame at `zoom` (× Fit), moved by `pan` from the canvas centre.
    public static func zoomedRect(fit: CGRect, zoom: Double, pan: CGSize) -> CGRect {
        let w = fit.width * zoom, h = fit.height * zoom
        return CGRect(x: fit.midX + pan.width - w / 2, y: fit.midY + pan.height - h / 2, width: w, height: h)
    }

    /// Pan limits: an axis that fits stays centred; one that overflows can't be dragged past its
    /// edge (plus the canvas padding), so the photo never leaves the canvas (R-43).
    public static func clampPan(_ pan: CGSize, fit: CGSize, zoom: Double, canvas: CGSize, padding: CGFloat) -> CGSize {
        func axis(_ p: CGFloat, _ size: CGFloat, _ room: CGFloat) -> CGFloat {
            let over = size * zoom - room
            guard over > 0, p.isFinite else { return 0 }
            let limit = over / 2 + padding
            return min(limit, max(-limit, p))
        }
        return CGSize(width: axis(pan.width, fit.width, canvas.width), height: axis(pan.height, fit.height, canvas.height))
    }

    /// The pan that keeps the point `anchor` (from the canvas centre) on the same spot of the
    /// photo when the zoom goes from `z0` to `z1`.
    public static func pan(_ pan: CGSize, anchor: CGPoint, from z0: Double, to z1: Double) -> CGSize {
        guard z0 > 0 else { return pan }
        let k = z1 / z0
        return CGSize(width: anchor.x - (anchor.x - pan.width) * k, height: anchor.y - (anchor.y - pan.height) * k)
    }

    // MARK: facts

    /// "{lens} · {shutter} · f/{ap} · ISO {iso} · {fl} mm · {time}", missing fields left out (R-16).
    public static func facts(_ p: Photo) -> String {
        func num(_ v: Double) -> String { String(format: "%g", (v * 10).rounded() / 10) }
        var parts: [String] = []
        if let l = p.lens, !l.isEmpty { parts.append(l) }
        if let s = p.shutter, !s.isEmpty { parts.append(s) }
        if let a = p.aperture, a > 0 { parts.append("f/" + num(a)) }
        if let i = p.iso, i > 0 { parts.append("ISO \(i)") }
        if let f = p.focal, f > 0 { parts.append(num(f) + " mm") }
        if let t = p.time, !t.isEmpty { parts.append(t) }
        return parts.joined(separator: " · ")
    }
}

// MARK: Crop

/// The crop inside a `Look` (`CropKey`): quarter turns first, then the straighten angle (the
/// picture turns under the frame, scaled up just enough to keep the frame covered), then the
/// box as fractions of the turned frame, from its top-left.
public struct CropBox: Equatable, Sendable {
    public var x = 0.0, y = 0.0, w = 1.0, h = 1.0
    /// Quarter turns to the right, 0…3.
    public var turns = 0
    /// Degrees, clockwise, −45…45.
    public var angle = 0.0

    public static let ratios = ["Original", "1:1", "4:5", "3:2", "16:9", "Free"]
    static let named: [String: Double] = ["1:1": 1, "4:5": 0.8, "3:2": 1.5, "16:9": 16.0 / 9]

    public init() {}
    public init(_ look: Look?) {
        guard let l = look else { return }
        w = clamp(0.02, l[CropKey.w] ?? 1, 1); h = clamp(0.02, l[CropKey.h] ?? 1, 1)
        x = clamp(0, l[CropKey.x] ?? 0, 1 - w); y = clamp(0, l[CropKey.y] ?? 0, 1 - h)
        turns = ((Int((l[CropKey.turns] ?? 0).rounded()) % 4) + 4) % 4
        angle = clamp(-45, l[CropKey.angle] ?? 0, 45)
    }

    public var isFullFrame: Bool { x <= 0.001 && y <= 0.001 && w >= 0.999 && h >= 0.999 }
    public var isDefault: Bool { isFullFrame && turns == 0 && abs(angle) < 0.05 }

    /// All six keys (the draft while cropping).
    public var draft: Look {
        [CropKey.x: x, CropKey.y: y, CropKey.w: w, CropKey.h: h, CropKey.turns: Double(turns), CropKey.angle: angle]
    }
    /// Only what differs from an untouched photo (what is kept in the look).
    public var keys: Look {
        var l: Look = [:]
        if !isFullFrame { l[CropKey.x] = x; l[CropKey.y] = y; l[CropKey.w] = w; l[CropKey.h] = h }
        if turns != 0 { l[CropKey.turns] = Double(turns) }
        if abs(angle) >= 0.05 { l[CropKey.angle] = angle }
        return l
    }

    /// Aspect of the turned frame, and of what is shown after the crop.
    public func frameAspect(_ a: Double) -> Double { turns % 2 == 1 ? 1 / max(a, 1e-9) : a }
    public func aspect(_ a: Double) -> Double { frameAspect(a) * w / max(h, 1e-9) }

    /// How much the picture grows so a frame of `aspect` stays covered at `angle` degrees.
    public static func coverScale(angle: Double, aspect: Double) -> Double {
        let r = abs(angle) * .pi / 180, a = max(aspect, 1e-6)
        return max(cos(r) + a * sin(r), cos(r) + sin(r) / a)
    }

    /// Turn the frame a quarter right (d > 0) or left; the box turns with the picture.
    public mutating func turn(_ d: Int) {
        if d > 0 { (x, y, w, h) = (1 - y - h, x, h, w) } else { (x, y, w, h) = (y, 1 - x - w, h, w) }
        turns = ((turns + (d > 0 ? 1 : -1)) % 4 + 4) % 4
        clampIntoFrame()
    }

    public mutating func clampIntoFrame() {
        w = clamp(0.02, w, 1); h = clamp(0.02, h, 1); x = clamp(0, x, 1 - w); y = clamp(0, y, 1 - h)
    }

    /// Grow or shrink about the centre by `factor`, keeping the proportions and staying in the frame.
    public mutating func scale(by factor: Double) {
        var k = factor
        k = min(k, 1 / w, 1 / h)
        k = max(k, 0.05 / max(w, h))
        let cx = x + w / 2, cy = y + h / 2
        w *= k; h *= k; x = cx - w / 2; y = cy - h / 2
        clampIntoFrame()
    }

    /// The width / height a named ratio asks for on a frame of `frameAspect`; nil for Free.
    /// Named ratios lie the way the frame does; `swapped` turns them the other way.
    public static func target(_ name: String, frameAspect: Double, swapped: Bool) -> Double? {
        if name == "Original" { return frameAspect }
        guard let r = named[name] else { return nil }
        let portrait = (frameAspect < 1) != swapped
        return portrait ? min(r, 1 / r) : max(r, 1 / r)
    }

    /// Reshape to `ratio` (width / height in real proportions) around the centre: the width is
    /// kept and the height follows, unless that would leave the frame.
    public mutating func reshape(to ratio: Double, frameAspect a: Double) {
        let cx = x + w / 2, cy = y + h / 2
        var nw = w, nh = nw * a / ratio
        if nh > 1 { nh = 1; nw = nh * ratio / a }
        if nw > 1 { nw = 1; nh = nw * a / ratio }
        w = nw; h = nh; x = cx - w / 2; y = cy - h / 2
        clampIntoFrame()
    }

    /// The ratio menu entry that describes this box.
    public func ratioName(aspect a: Double) -> String {
        if isFullFrame { return "Original" }
        let fa = frameAspect(a), r = fa * w / h
        if abs(r / fa - 1) < 0.01 { return "Original" }
        for name in ["1:1", "4:5", "3:2", "16:9"] {
            let n = Self.named[name]!
            if abs(r / n - 1) < 0.01 || abs(r * n - 1) < 0.01 { return name }
        }
        return "Free"
    }
}

public extension Look {
    /// The look without its crop keys (tone and colour only).
    var withoutCrop: Look { filter { !CropKey.all.contains($0.key) } }
    /// Only the crop keys.
    var cropOnly: Look { filter { CropKey.all.contains($0.key) } }
}
