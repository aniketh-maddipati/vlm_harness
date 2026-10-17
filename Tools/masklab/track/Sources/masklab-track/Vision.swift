#if canImport(Vision) && canImport(AVFoundation)
import CoreVideo
import Foundation
import MaskLabCore
import Vision

/// A tracker sees the frames in order: `first` on the start frame with the prompt, `next` on each
/// frame after it. Each returns the frame's mask (empty = lost); the caller resizes it to the proxy.
protocol FrameTracker: AnyObject {
    func first(_ frame: CVPixelBuffer, prompt: Prompt) throws -> Mask
    func next(_ frame: CVPixelBuffer) throws -> Mask
    /// The last frame's tracker confidence, where the tracker has one.
    var confidence: Double? { get }
}

/// Vision's foreground instances for one frame: the low-resolution instance map to pick from, and
/// the observation + handler to ask for the full-size mask of the one picked.
struct Foreground {
    let observation: VNInstanceMaskObservation
    let handler: VNImageRequestHandler
    let map: LabelMap

    /// nil when Vision finds no foreground in the frame.
    static func of(_ frame: CVPixelBuffer) throws -> Foreground? {
        let handler = VNImageRequestHandler(cvPixelBuffer: frame, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first else { return nil }
        return Foreground(observation: observation, handler: handler, map: labelMap(observation.instanceMask))
    }

    /// The picked instance at the frame's size (generateScaledMaskForImage: a soft mask, 32-bit
    /// float, thresholded at 0.5).
    func mask(_ id: Int, width: Int, height: Int) throws -> Mask {
        guard observation.allInstances.contains(id) else { return Mask(width: width, height: height) }
        let buffer = try observation.generateScaledMaskForImage(forInstances: IndexSet(integer: id), from: handler)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        let rowFloats = CVPixelBufferGetBytesPerRow(buffer) / MemoryLayout<Float>.size
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: Float.self) else {
            throw UsageError("empty scaled mask")
        }
        return Mask.threshold(width: w, height: h, outWidth: width, outHeight: height, above: 0.5) { x, y in base[y * rowFloats + x] }
    }
}

/// The instance map (OneComponent8: 0 = background, k = instance k) copied row by row, since rows
/// may be padded.
func labelMap(_ buffer: CVPixelBuffer) -> LabelMap {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer), row = CVPixelBufferGetBytesPerRow(buffer)
    var labels = [UInt8](repeating: 0, count: w * h)
    if let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) {
        for y in 0..<h { for x in 0..<w { labels[y * w + x] = base[y * row + x] } }
    }
    return LabelMap(width: w, height: h, labels: labels)
}

func frameSize(_ frame: CVPixelBuffer) -> (width: Int, height: Int) {
    (CVPixelBufferGetWidth(frame), CVPixelBufferGetHeight(frame))
}

/// vision-box: VNTrackObjectRequest follows a box; on each frame the foreground instance with the
/// highest IoU with the tracked box is the mask. A point prompt starts the box from the instance
/// under the point.
final class VisionBoxTracker: FrameTracker {
    private let sequence = VNSequenceRequestHandler()
    private var request: VNTrackObjectRequest?
    private var box = Box(x: 0, y: 0, w: 1, h: 1)
    private(set) var confidence: Double?

    func first(_ frame: CVPixelBuffer, prompt: Prompt) throws -> Mask {
        let (w, h) = frameSize(frame)
        let fg = try Foreground.of(frame)
        switch prompt {
        case .box(let b): box = b.clamped()
        case .point(let p):
            guard let fg, let id = Pick.byPoint(fg.map, point: p), let b = fg.map.instance(id).boundingBox else {
                throw UsageError("the point prompt is on no foreground instance in the start frame; give a box")
            }
            box = b.clamped()
        }
        let r = VNTrackObjectRequest(detectedObjectObservation: VNDetectedObjectObservation(boundingBox: rect(box.flippedY)))
        r.trackingLevel = .accurate
        request = r
        confidence = 1
        return try mask(fg, w, h)
    }

    func next(_ frame: CVPixelBuffer) throws -> Mask {
        let (w, h) = frameSize(frame)
        guard let request else { return Mask(width: w, height: h) }
        try sequence.perform([request], on: frame)
        if let obs = request.results?.first as? VNDetectedObjectObservation {
            // The next frame starts from this one's observation (Apple's tracking sample does the same).
            request.inputObservation = obs
            confidence = Double(obs.confidence)
            let b = obs.boundingBox
            box = Box(x: Double(b.minX), y: Double(b.minY), w: Double(b.width), h: Double(b.height)).flippedY.clamped()
        } else {
            confidence = 0
        }
        return try mask(try Foreground.of(frame), w, h)
    }

    private func mask(_ fg: Foreground?, _ w: Int, _ h: Int) throws -> Mask {
        guard let fg, let id = Pick.byBox(fg.map, box: box) else { return Mask(width: w, height: h) }
        return try fg.mask(id, width: w, height: h)
    }

    private func rect(_ b: Box) -> CGRect { CGRect(x: b.x, y: b.y, width: b.w, height: b.h) }
}

/// vision-instance: no tracker. Each frame takes the foreground instance with the highest IoU with
/// the last mask held (the start frame: the instance the prompt picks). A frame where nothing
/// overlaps is written empty and the last mask is kept as the reference, so the object can be found
/// again when it comes back.
final class VisionInstanceTracker: FrameTracker {
    private var reference: Mask?
    var confidence: Double? { nil }

    func first(_ frame: CVPixelBuffer, prompt: Prompt) throws -> Mask {
        let (w, h) = frameSize(frame)
        guard let fg = try Foreground.of(frame), let id = Pick.byPrompt(fg.map, prompt: prompt) else {
            throw UsageError("the prompt picks no foreground instance in the start frame")
        }
        let m = try fg.mask(id, width: w, height: h)
        reference = m
        return m
    }

    func next(_ frame: CVPixelBuffer) throws -> Mask {
        let (w, h) = frameSize(frame)
        guard let reference, let fg = try Foreground.of(frame), let id = Pick.byPrevious(fg.map, previous: reference) else {
            return Mask(width: w, height: h)
        }
        let m = try fg.mask(id, width: w, height: h)
        if !m.isEmpty { self.reference = m }
        return m
    }
}
#endif
