import Foundation
import Metal
import CoreVideo
import ImageIO
import CoreGraphics

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

    struct TextureInfo: Sendable {
        let texture: MTLTexture
        let pixelWidth: Int
        let pixelHeight: Int
        let generation: UInt64
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
        var pixelWidth: Int = 0
        var pixelHeight: Int = 0
        var uploadGeneration: UInt64 = 0
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

    func textureInfo(for id: UUID) -> TextureInfo? {
        lock.lock()
        defer { lock.unlock() }
        guard let slot = slots.first(where: { $0.photoID == id }),
              let texture = slot.texture,
              slot.pixelWidth > 0, slot.pixelHeight > 0 else { return nil }
        return TextureInfo(
            texture: texture,
            pixelWidth: slot.pixelWidth,
            pixelHeight: slot.pixelHeight,
            generation: slot.uploadGeneration
        )
    }

    /// Background-only upload. Never call from the main thread.
    @discardableResult
    func upload(id: UUID, jpegPath: String, distanceBias: Int = 0, generation: UInt64 = 0) -> UploadTimings {
        assert(!Thread.isMainThread, "MetalPreviewPool.upload must not run on the main thread")

        lock.lock()
        if let existing = slots.firstIndex(where: { $0.photoID == id }),
           slots[existing].texture != nil,
           slots[existing].uploadGeneration == generation || generation == 0 {
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

        let pixelWidth = cg.width
        let pixelHeight = cg.height

        let blitStart = CFAbsoluteTimeGetCurrent()
        guard let pb = Self.makeIOSurfacePixelBuffer(width: pixelWidth, height: pixelHeight),
              Self.copyIntoPixelBuffer(cg, pb) else { return timings }
        timings.blitMs = (CFAbsoluteTimeGetCurrent() - blitStart) * 1000

        guard let cache = textureCache else { return timings }

        let wrapStart = CFAbsoluteTimeGetCurrent()
        var cvTexture: CVMetalTexture?
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pb, nil, ImagePixelFormat.metalPixelFormat, w, h, 0, &cvTexture
        )
        timings.wrapMs = (CFAbsoluteTimeGetCurrent() - wrapStart) * 1000
        guard status == kCVReturnSuccess, let cvTexture,
              let texture = CVMetalTextureGetTexture(cvTexture) else { return timings }

        lock.lock()
        // Discard stale uploads whose generation no longer matches a rebind.
        if generation > 0,
           let existing = slots.firstIndex(where: { $0.photoID == id }),
           slots[existing].uploadGeneration > generation {
            lock.unlock()
            return timings
        }
        let idx = pickSlotLocked()
        slots[idx] = Slot(
            photoID: id,
            texture: texture,
            pixelBuffer: pb,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            uploadGeneration: generation,
            distanceBias: distanceBias
        )
        ringIndex = (idx + 1) % slotCount
        lock.unlock()

        recordTimings(timings)
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .luminaTextureReady,
                object: nil,
                userInfo: [
                    "photoID": id,
                    "generation": generation,
                    "pixelWidth": pixelWidth,
                    "pixelHeight": pixelHeight,
                ]
            )
        }
        return timings
    }

    /// Schedule upload off the main thread; no-op if texture already resident.
    func scheduleUpload(id: UUID, jpegPath: String, distanceBias: Int = 0, generation: UInt64 = 0) {
        if let info = textureInfo(for: id), generation == 0 || info.generation == generation {
            return
        }
        uploadQueue.async {
            _ = self.upload(id: id, jpegPath: jpegPath, distanceBias: distanceBias, generation: generation)
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

    /// Cached preview JPEG only — EXIF orientation applied once via ImageIO transform.
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

        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
        ]

        if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) {
            return thumb
        }
        if let full = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            let edge = max(full.width, full.height)
            if edge <= maxPixel { return full }
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func makeIOSurfacePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attrs: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
        ]
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            ImagePixelFormat.pixelBufferType,
            attrs as CFDictionary,
            &pb
        )
        guard status == kCVReturnSuccess else { return nil }
        return pb
    }

    /// Convert decoded CGImage into canonical BGRA8 using explicit working color space.
    private static func copyIntoPixelBuffer(_ image: CGImage, _ pb: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        let width = CVPixelBufferGetWidth(pb)
        let height = CVPixelBufferGetHeight(pb)
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return false }

        guard let context = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
            space: ImagePixelFormat.workingColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return false }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
}
