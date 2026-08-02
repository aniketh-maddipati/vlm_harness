import Foundation
import Metal
import CoreVideo
import ImageIO
import CoreGraphics

/// Zero-copy GPU texture pool for browse previews.
/// Tier-3 JPEG bytes are memory-mapped; pixels land in IOSurface-backed CVPixelBuffers;
/// MTLTexture is a CVMetalTextureCache wrap (no GPU memcpy on Apple Silicon).
nonisolated final class MetalPreviewPool: @unchecked Sendable {
    static let shared = MetalPreviewPool()

    let device: MTLDevice?
    private var textureCache: CVMetalTextureCache?
    private let slotCount = 32
    private var slots: [Slot]
    private var ringIndex = 0
    private let lock = NSLock()

    /// Wall time for last full miss path (decode + IOSurface fill). Wrap-only is tracked separately.
    private(set) var lastUploadMs: Double = 0
    /// CVMetalTextureCache wrap cost — should be ~0 on unified memory.
    private(set) var lastWrapMs: Double = 0
    private(set) var uploadSamples: [Double] = []
    private(set) var wrapSamples: [Double] = []

    struct Slot {
        var photoID: UUID?
        var texture: MTLTexture?
        var pixelBuffer: CVPixelBuffer?
        var distanceBias: Int = .max
    }

    private init() {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        if let device {
            CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        }
        slots = (0..<slotCount).map { _ in Slot() }
    }

    func texture(for id: UUID) -> MTLTexture? {
        lock.lock()
        defer { lock.unlock() }
        return slots.first(where: { $0.photoID == id })?.texture
    }

    @discardableResult
    func upload(id: UUID, jpegPath: String, distanceBias: Int = 0) -> Double {
        lock.lock()
        if let existing = slots.firstIndex(where: { $0.photoID == id }), slots[existing].texture != nil {
            slots[existing].distanceBias = distanceBias
            lock.unlock()
            lastUploadMs = 0
            lastWrapMs = 0
            return 0
        }
        lock.unlock()

        let start = CFAbsoluteTimeGetCurrent()
        guard let cg = Self.decodeMappedJPEG(path: jpegPath, maxPixel: 2400) else { return -1 }
        guard let pb = Self.makeIOSurfacePixelBuffer(from: cg) else { return -1 }
        guard let cache = textureCache else { return -1 }

        let wrapStart = CFAbsoluteTimeGetCurrent()
        var cvTexture: CVMetalTexture?
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pb, nil, .bgra8Unorm, w, h, 0, &cvTexture
        )
        let wrapMs = (CFAbsoluteTimeGetCurrent() - wrapStart) * 1000
        guard status == kCVReturnSuccess, let cvTexture,
              let texture = CVMetalTextureGetTexture(cvTexture) else {
            return -1
        }

        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        lock.lock()
        let idx = pickSlotLocked()
        slots[idx] = Slot(photoID: id, texture: texture, pixelBuffer: pb, distanceBias: distanceBias)
        ringIndex = (idx + 1) % slotCount
        lastUploadMs = ms
        lastWrapMs = wrapMs
        uploadSamples.append(ms)
        wrapSamples.append(wrapMs)
        if uploadSamples.count > 256 { uploadSamples.removeFirst(uploadSamples.count - 256) }
        if wrapSamples.count > 256 { wrapSamples.removeFirst(wrapSamples.count - 256) }
        lock.unlock()

        LatencyMetrics.record("spine.gpu_upload", milliseconds: ms)
        LatencyMetrics.record("spine.gpu_wrap", milliseconds: wrapMs)
        return wrapMs
    }

    func evictFar(from centerIndex: Int, order: [UUID], keepRadius: Int) {
        lock.lock()
        defer { lock.unlock() }
        let indexByID = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        for i in slots.indices {
            guard let pid = slots[i].photoID, let idx = indexByID[pid] else { continue }
            let dist = abs(idx - centerIndex)
            slots[i].distanceBias = dist
            if dist > keepRadius {
                slots[i] = Slot()
            }
        }
    }

    private func pickSlotLocked() -> Int {
        if let empty = slots.firstIndex(where: { $0.photoID == nil }) { return empty }
        var best = ringIndex
        var bestDist = -1
        for (i, slot) in slots.enumerated() where slot.distanceBias >= bestDist {
            bestDist = slot.distanceBias
            best = i
        }
        return best
    }

    /// Tier 3: mmap JPEG bytes, then ImageIO decode (map-and-decode, not read-and-copy).
    private static func decodeMappedJPEG(path: String, maxPixel: Int) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return decodeCGImage(path: path, maxPixel: maxPixel)
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary)
    }

    private static func decodeCGImage(path: String, maxPixel: Int) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary)
    }

    private static func makeIOSurfacePixelBuffer(from image: CGImage) -> CVPixelBuffer? {
        let width = image.width
        let height = image.height
        let attrs: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pb
        )
        guard status == kCVReturnSuccess, let pb else { return nil }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pb),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pb
    }

    var uploadP50: Double? {
        lock.lock()
        defer { lock.unlock() }
        guard !uploadSamples.isEmpty else { return nil }
        let s = uploadSamples.sorted()
        return s[min(Int(Double(s.count - 1) * 0.50), s.count - 1)]
    }

    var wrapP50: Double? {
        lock.lock()
        defer { lock.unlock() }
        guard !wrapSamples.isEmpty else { return nil }
        let s = wrapSamples.sorted()
        return s[min(Int(Double(s.count - 1) * 0.50), s.count - 1)]
    }
}
