import Foundation
import CoreGraphics

// WP-0 contract: what `debug.state` and `debug.metrics` report (ACCESSIBILITY_CONTRACT.md).
// Keys are stable; the XCTests decode them.

/// What the views actually used, for the sizing tests (R-54…R-59). Not observable: views write
/// to it while laying out, and the debug hook reads it on a timer.
public final class Metrics: @unchecked Sendable {
    public struct Row: Equatable, Sendable {
        public var scene: Int, width: Double, gridWidth: Double, last: Bool
        public init(scene: Int, width: Double, gridWidth: Double, last: Bool) { self.scene = scene; self.width = width; self.gridWidth = gridWidth; self.last = last }
    }
    public static let shared = Metrics()
    private let lock = NSLock()
    private var _scale = 1.0, tokens: Set<Double> = [], fonts: [String: Double] = [:]
    private var _canvas: CGRect?, _photo: CGRect?, _tileH: Double?, _rows: [Row] = []

    public var scale: Double { get { lock.withLock { _scale } } set { lock.withLock { _scale = newValue } } }
    /// Edit canvas and photo frames in window coordinates.
    public var canvas: CGRect? { get { lock.withLock { _canvas } } set { lock.withLock { _canvas = newValue } } }
    public var photo: CGRect? { get { lock.withLock { _photo } } set { lock.withLock { _photo = newValue } } }
    public var tileH: Double? { get { lock.withLock { _tileH } } set { lock.withLock { _tileH = newValue } } }
    public var rows: [Row] { get { lock.withLock { _rows } } set { lock.withLock { _rows = newValue } } }

    /// Called by `LuminaFont`: the unscaled token size, and the view that used it when known.
    public func record(font token: Double, id: String? = nil) {
        lock.withLock { tokens.insert(token); if let id { fonts[id] = token } }
    }

    public var json: String {
        lock.lock(); defer { lock.unlock() }
        func f(_ pt: Double) -> Double { (pt * _scale * 2).rounded() / 2 }
        var d: [String: Any] = ["scale": _scale, "minFontPt": f(tokens.min() ?? 13), "bodyFontPt": f(13), "fonts": fonts.mapValues(f)]
        func rect(_ r: CGRect) -> [Double] { [r.minX, r.minY, r.width, r.height].map { Double($0) } }
        if let c = _canvas { d["canvas"] = rect(c) }
        if let p = _photo { d["photo"] = rect(p) }
        if let t = _tileH { d["tileH"] = t }
        d["rows"] = _rows.map { ["scene": $0.scene, "width": $0.width, "gridWidth": $0.gridWidth, "last": $0.last] as [String: Any] }
        return (try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

public extension AppModel {
    /// `debug.state`: compact JSON, rebuilt on every state change.
    var debugStateJSON: String {
        let keep = decisions.keep
        let kept = decisions.keptCount, out = decisions.outCount
        var d: [String: Any] = [
            "step": step.rawValue, "copied": shoot.local ? total : copied, "total": total,
            "kept": kept, "out": out, "undecided": total - kept - out,
            "keep": keep, "look": currentLook, "looksCount": edits.looks.count, "lookBytes": edits.lookBytes,
            "zoom": edit.zoom, "errors": ErrorFunnel.count,
            "import": ["busy": imports.busy, "n": imports.added, "msg": imports.message as Any? ?? NSNull(), "local": shoot.local] as [String: Any],
        ]
        d["cur"] = cur ?? NSNull()
        d["overlay"] = step == .edit ? (edit.overlay?.rawValue ?? (edit.focus ? "focus" : nil)) as Any? ?? NSNull() : NSNull()
        d["spec"] = edit.variationKey ?? NSNull()
        if let s = save.saved {
            d["saved"] = ["sig": s.sig, "n": s.n, "ne": s.ne, "fmt": s.fmt.rawValue, "again": s.again] as [String: Any]
        } else { d["saved"] = NSNull() }
        return (try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
