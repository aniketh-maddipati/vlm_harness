import Foundation

/// Removing a followed shape from a still-camera clip (Skim ▸ Viewer ▸ Remove), the parts that are plain maths: the
/// **clean plate**. For each pixel, the median of the clip's own frames where the shape does not cover it, so what
/// fills the hole is the scene as the camera saw it, with its own grain, and nothing is invented. It holds only when
/// the camera did not move (the pixels outside the shape agree from frame to frame: `shake`) and the scene behind the
/// shape shows in some frame (`unseen`); otherwise the removal says so and is not made. The patch file is `SkimPatch`
/// (Mac). Foundation only: it runs in the Linux Swift sandbox too.
nonisolated enum SkimPlate {
    typealias Box = LookMasks.Box
    typealias Point = LookMasks.Point

    /// Frames the plate is made from at most (evenly across the clip), and the most pixels a crop may hold (a 4K
    /// frame's worth), which bounds the memory: frames × pixels × 3 bytes.
    static let maxFrames = 48
    static let maxPixels = 3840 * 2160
    /// The area around the shape's union box that goes into the plate, as a fraction of the frame's long edge.
    static let pad = 0.03
    /// The most the frames may differ outside the shape (mean of |difference| on 0 … 255) for the camera to count as
    /// still, and the most of the hole that may show in no frame.
    static let steadyMax = 6.0
    static let unseenMax = 0.02
    /// Pixels the hole is grown by before the plate is taken, so the shape's own edge is never in it.
    static let margin = 3

    /// A crop of the frame, in pixels.
    struct Crop: Equatable, Sendable { var x: Int, y: Int, w: Int, h: Int }

    /// The crop that holds every box (fractions from the top left) and `pad` around them, in a frame `width × height`;
    /// nil when there is no box.
    static func crop(_ boxes: [Box], width: Int, height: Int, pad: Double = pad) -> Crop? {
        guard width > 0, height > 0, let f = boxes.first else { return nil }
        var x0 = f.x, y0 = f.y, x1 = f.x + f.w, y1 = f.y + f.h
        for b in boxes.dropFirst() { x0 = min(x0, b.x); y0 = min(y0, b.y); x1 = max(x1, b.x + b.w); y1 = max(y1, b.y + b.h) }
        let long = Double(max(width, height)), px = pad * long
        let l = max(0, Int((x0 * Double(width) - px).rounded(.down))), t = max(0, Int((y0 * Double(height) - px).rounded(.down)))
        let r = min(width, Int((x1 * Double(width) + px).rounded(.up))), b = min(height, Int((y1 * Double(height) + px).rounded(.up)))
        guard r > l, b > t else { return nil }
        return Crop(x: l, y: t, w: r - l, h: b - t)
    }

    /// `n` frame numbers spread evenly over `frames` (all of them when there are fewer).
    static func picks(frames: Int, n: Int = maxFrames) -> [Int] {
        guard frames > 0, n > 0 else { return [] }
        if frames <= n { return Array(0..<frames) }
        return (0..<n).map { Int((Double($0) + 0.5) * Double(frames) / Double(n)) }
    }

    /// An outline in fractions of the whole frame, as fractions of `crop`.
    static func inCrop(_ outline: [[Point]], crop c: Crop, width: Int, height: Int) -> [[Point]] {
        outline.map { l in l.map { Point(x: ($0.x * Double(width) - Double(c.x)) / Double(c.w), y: ($0.y * Double(height) - Double(c.y)) / Double(c.h)) } }
    }

    /// The plate of a crop: RGB, 3 bytes a pixel; for each pixel how many frames showed it; and the share of the hole
    /// (pixels some frame's mask covers) that no frame showed.
    struct Plate: Equatable, Sendable {
        var rgb: [UInt8]
        var seen: [UInt16]
        var unseen: Double
    }

    /// The clean plate from frames of one crop (`width × height`, RGB, 3 bytes a pixel) and the shape's mask in each
    /// (0 … 1, the crop's size): per pixel and channel, the median of the frames where the mask is under 0.5. A pixel
    /// no frame shows takes the median of all of them (and counts in `unseen`). Nil when the sizes do not agree.
    static func plate(frames: [[UInt8]], masks: [LookMasks.Plane], width: Int, height: Int) -> Plate? {
        let n = width * height
        guard n > 0, !frames.isEmpty, frames.count == masks.count, frames.allSatisfy({ $0.count == n * 3 }),
              masks.allSatisfy({ $0.width == width && $0.height == height }) else { return nil }
        var rgb = [UInt8](repeating: 0, count: n * 3), seen = [UInt16](repeating: 0, count: n)
        var hole = 0, never = 0
        var showing: [Int] = [], v: [UInt8] = []
        showing.reserveCapacity(frames.count); v.reserveCapacity(frames.count)
        for i in 0..<n {
            showing.removeAll(keepingCapacity: true)
            for k in frames.indices where masks[k].values[i] < 0.5 { showing.append(k) }
            if showing.count < frames.count { hole += 1; if showing.isEmpty { never += 1 } }
            seen[i] = UInt16(min(Int(UInt16.max), showing.count))
            if showing.isEmpty { showing.append(contentsOf: frames.indices) }
            for ch in 0..<3 {
                v.removeAll(keepingCapacity: true)
                for k in showing { v.append(frames[k][i * 3 + ch]) }
                v.sort()
                rgb[i * 3 + ch] = v[v.count / 2]
            }
        }
        return Plate(rgb: rgb, seen: seen, unseen: hole > 0 ? Double(never) / Double(hole) : 0)
    }

    /// How much the camera moved: for each frame, the mean |difference| (0 … 255) from the plate over the pixels no
    /// mask ever covers (every `step`-th one), and the median of those. 0 for a still camera on a still scene.
    static func shake(frames: [[UInt8]], masks: [LookMasks.Plane], plate: Plate, width: Int, height: Int, step: Int = 3) -> Double {
        let n = width * height
        guard n > 0, !frames.isEmpty, frames.count == masks.count, plate.rgb.count == n * 3 else { return 0 }
        // the pixels no mask ever covers
        var clear = [Bool](repeating: true, count: n)
        for m in masks { for i in 0..<n where m.values[i] >= 0.5 { clear[i] = false } }
        var per: [Double] = []
        for k in frames.indices where frames[k].count == n * 3 {
            var sum = 0, count = 0
            for i in stride(from: 0, to: n, by: max(1, step)) where clear[i] {
                for ch in 0..<3 { sum += abs(Int(frames[k][i * 3 + ch]) - Int(plate.rgb[i * 3 + ch])) }
                count += 3
            }
            if count > 0 { per.append(Double(sum) / Double(count)) }
        }
        guard !per.isEmpty else { return 0 }
        per.sort()
        return per[per.count / 2]
    }

    /// Why a removal is not made, in the user's words; nil when it can be.
    static func refusal(shake: Double, unseen: Double) -> String? {
        if shake > steadyMax { return "The camera moves in this clip. Removing from the clip's own frames needs a still camera." }
        if unseen > unseenMax { return "Not enough of the scene shows behind it: \(Int((unseen * 100).rounded()))% of it is never seen. Save the matte instead." }
        return nil
    }

    /// The patch's file name for a clip: the clip's name (without its extension) and " patch.mov".
    static func patchName(clip: String) -> String? {
        let stem = ((clip.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? "") as NSString).deletingPathExtension
        return SkimExport.safeName(stem + " patch.mov", allowed: ["mov"])
    }
}
