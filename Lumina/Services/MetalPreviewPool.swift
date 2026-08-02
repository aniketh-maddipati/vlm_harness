import Foundation
import Metal
import CoreVideo
import ImageIO
import CoreGraphics
import Accelerate

extension Notification.Name {
    static let luminaTextureReady = Notification.Name("lumina.textureReady")
}

/// GPU texture pool for browse previews — one JPEG decode per photo, no CGContext blit.
nonisolated final class MetalPreviewPool: @unchecked Sendable {
    static let shared = MetalPreviewPool()

    struct UploadTimings: Sendable {
        var decodeMs: Double = 0
        var blitMs: Double = 0
        var wrapMs: Double = 0
        var cacheHit: Bool = false
    }

    let device: MTLDevice?
    private var textureCache: CVMetalTextureCache?
    private let slotCount = 32
    private var slots: [Slot]
    private var ringIndex = 0
    private let lock = NSLock()
    private let uploadQueue = DispatchQueue(label: "lumina.metal-preview.upload", qos: .userInitiated, attributes: .concurrent)

    private(set) var lastTimings = UploadTimings()
    private(set) var decodeSamples: [Double] = []
    private(set) var blitSamples: [Double] = []
    private(set) var wrapSamples: [Double] = []

    struct Slot {
        var photoID: UUID?
        var texture: MTLTexture?
        var pixelBuffer: CVPixelBuffer?
        var distanceBias: Int = .max
    }

    private static let rawExtensions: Set<String> = [
        "ARW", "CR2", "CR3", "NEF", "RAF", "DNG", "ORF", "RW2", "PEF", "SRW", "3FR", "IIQ",
    ]

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

    /// Background-only upload. Never call from the main thread.
    @discardableResult
    func upload(id: UUID, jpegPath: String, distanceBias: Int = 0) -> UploadTimings {
        assert(!Thread.isMainThread, "MetalPreviewPool.upload must not run on the main thread")

        lock.lock()
        if let existing = slots.firstIndex(where: { $0.photoID == id }), slots[existing].texture != nil {
            slots[existing].distanceBias = distanceBias
            lock.unlock()
            let hit = UploadTimings(cacheHit: true)
            recordTimings(hit)
            return hit
        }
        lock.unlock()

        Self.assertBrowseJPEGPath(jpegPath)

        var timings = UploadTimings()
        let decodeStart = CFAbsoluteTimeGetCurrent()
        guard let cg = Self.decodeBrowseJPEG(path: jpegPath, maxPixel: 2400) else { return timings }
        timings.decodeMs = (CFAbsoluteTimeGetCurrent() - decodeStart) * 1000

        let blitStart = CFAbsoluteTimeGetCurrent()
        guard let pb = Self.makeIOSurfacePixelBuffer(width: cg.width, height: cg.height),
              Self.copyIntoPixelBuffer(cg, pb) else { return timings }
        timings.blitMs = (CFAbsoluteTimeGetCurrent() - blitStart) * 1000

        guard let cache = textureCache else { return timings }

        let wrapStart = CFAbsoluteTimeGetCurrent()
        var cvTexture: CVMetalTexture?
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pb, nil, .bgra8Unorm, w, h, 0, &cvTexture
        )
        timings.wrapMs = (CFAbsoluteTimeGetCurrent() - wrapStart) * 1000
        guard status == kCVReturnSuccess, let cvTexture,
              let texture = CVMetalTextureGetTexture(cvTexture) else { return timings }

        lock.lock()
        let idx = pickSlotLocked()
        slots[idx] = Slot(photoID: id, texture: texture, pixelBuffer: pb, distanceBias: distanceBias)
        ringIndex = (idx + 1) % slotCount
        lock.unlock()

        recordTimings(timings)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .luminaTextureReady, object: nil, userInfo: ["photoID": id])
        }
        return timings
    }

    /// Schedule upload off the main thread; no-op if texture already resident.
    func scheduleUpload(id: UUID, jpegPath: String, distanceBias: Int = 0) {
        guard texture(for: id) == nil else { return }
        uploadQueue.async {
            _ = self.upload(id: id, jpegPath: jpegPath, distanceBias: distanceBias)
        }
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

    func evictAll() {
        lock.lock()
        defer { lock.unlock() }
        slots = (0..<slotCount).map { _ in Slot() }
        ringIndex = 0
        lastTimings = UploadTimings()
        decodeSamples.removeAll()
        blitSamples.removeAll()
        wrapSamples.removeAll()
    }

    private func recordTimings(_ timings: UploadTimings) {
        lock.lock()
        lastTimings = timings
        if !timings.cacheHit {
            decodeSamples.append(timings.decodeMs)
            blitSamples.append(timings.blitMs)
            wrapSamples.append(timings.wrapMs)
            if decodeSamples.count > 256 { decodeSamples.removeFirst(decodeSamples.count - 256) }
            if blitSamples.count > 256 { blitSamples.removeFirst(blitSamples.count - 256) }
            if wrapSamples.count > 256 { wrapSamples.removeFirst(wrapSamples.count - 256) }
        }
        lock.unlock()

        if !timings.cacheHit {
            LatencyMetrics.record("spine.decode_ms", milliseconds: timings.decodeMs)
            LatencyMetrics.record("spine.blit_ms", milliseconds: timings.blitMs)
            LatencyMetrics.record("spine.wrap_ms", milliseconds: timings.wrapMs)
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

    func p50Decode() -> Double? { p50(decodeSamples) }
    func p50Blit() -> Double? { p50(blitSamples) }
    func p50Wrap() -> Double? { p50(wrapSamples) }

    private func p50(_ samples: [Double]) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard !samples.isEmpty else { return nil }
        let s = samples.sorted()
        return s[min(Int(Double(s.count - 1) * 0.50), s.count - 1)]
    }

    // MARK: - Browse-safe JPEG decode (never demosaic)

    private static func assertBrowseJPEGPath(_ path: String) {
        let ext = URL(fileURLWithPath: path).pathExtension.uppercased()
        #if DEBUG
        precondition(!rawExtensions.contains(ext), "Interactive browse path must never decode RAW: \(path)")
        #endif
        _ = ext
    }

    /// Cached preview JPEG only — IfAbsent/Always false so ImageIO never demosaics.
    private static func decodeBrowseJPEG(path: String, maxPixel: Int) -> CGImage? {
        assertBrowseJPEGPath(path)
        let url = URL(fileURLWithPath: path)
        let source: CGImageSource? = {
            if let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) {
                return CGImageSourceCreateWithData(data as CFData, nil)
            }
            return CGImageSourceCreateWithURL(url as CFURL, nil)
        }()
        guard let source else { return nil }

        // JPEG cache file: decode stored image, do not synthesize from absent thumbnail.
        if let full = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            let edge = max(full.width, full.height)
            if edge <= maxPixel { return full }
        }

        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func makeIOSurfacePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attrs: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            kCVPixelBufferMetalCompatibilityKey as String: true,
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
        guard status == kCVReturnSuccess else { return nil }
        return pb
    }

    /// vImage copy/convert — not CGContext.draw (no full software raster pass).
    private static func copyIntoPixelBuffer(_ image: CGImage, _ pb: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        var srcFormat = vImage_CGImageFormat(
            bitsPerComponent: UInt32(image.bitsPerComponent),
            bitsPerPixel: UInt32(image.bitsPerPixel),
            colorSpace: Unmanaged.passUnretained(image.colorSpace ?? CGColorSpaceCreateDeviceRGB()),
            bitmapInfo: image.bitmapInfo,
            version: 0,
            decode: nil,
            renderingIntent: .defaultIntent
        )

        var src = vImage_Buffer()
        guard vImageBuffer_InitWithCGImage(&src, &srcFormat, nil, image, vImage_Flags(kvImageNoFlags)) == kvImageNoError else {
            return false
        }
        defer { free(src.data) }

        var dst = vImage_Buffer(
            data: CVPixelBufferGetBaseAddress(pb),
            height: vImagePixelCount(CVPixelBufferGetHeight(pb)),
            width: vImagePixelCount(CVPixelBufferGetWidth(pb)),
            rowBytes: CVPixelBufferGetBytesPerRow(pb)
        )

        if image.bitsPerPixel == 24 {
            return vImageConvert_RGB888toBGRA8888(&src, nil, 255, &dst, false, vImage_Flags(kvImageNoFlags)) == kvImageNoError
        }
        if image.bitsPerPixel == 32 {
            return vImageCopyBuffer(&src, &dst, 4, vImage_Flags(kvImageNoFlags)) == kvImageNoError
        }
        return false
    }
}
