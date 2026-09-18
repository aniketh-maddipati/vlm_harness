import CoreImage
import Foundation
import ImageIO
import Metal
import os

/// Per-photo prepared RAW session with serial (actor) ownership.
///
/// Owns metadata plus **two** mutable `CIRAWFilter` instances for one asset:
/// - `interactive` — reduced-scale, draft-mode-allowed rendering
/// - `authoritative` — non-draft settled / 1:1 / export rendering
///
/// Draft mode is never flipped back and forth on one filter; the two
/// configurations stay separate. `CIFilter` is mutable and not thread-safe,
/// so all property application happens inside this actor.
///
/// Interactive RAW-stage caches a GPU-materialized texture (the demosaic is
/// evaluated once). Authoritative caches the lazy `CIRAWFilter.outputImage`
/// graph so settled / export evaluate once at their own destination rather
/// than doubling peak memory here. The returned `CIImage` is immutable and
/// safe to render elsewhere.
actor PreparedRawSession {

    /// Capability record per file — a missing feature is an explicit
    /// `unsupported` state, never a silent fake implementation.
    struct Capabilities: Sendable {
        var exposure = CapabilityState.supported
        var whiteBalance = CapabilityState.supported
        var luminanceNoiseReduction = CapabilityState.unsupported
        var sharpness = CapabilityState.unsupported
        var lensCorrection = CapabilityState.unsupported
        var draftMode = CapabilityState.unsupported
        var scaleFactor = CapabilityState.supported

        var summary: String {
            "exposure:\(exposure.rawValue) wb:\(whiteBalance.rawValue) nr:\(luminanceNoiseReduction.rawValue) "
                + "sharpen:\(sharpness.rawValue) lens:\(lensCorrection.rawValue) draft:\(draftMode.rawValue)"
        }
    }

    enum CapabilityState: String, Sendable {
        case supported
        case unsupported
    }

    struct Metadata: Sendable {
        let pixelWidth: Int
        let pixelHeight: Int
        let decoderVersion: String
        let fileModificationDate: Date
        let nativeNeutralTemperature: Double
        let nativeNeutralTint: Double

        var longEdge: Int { max(pixelWidth, pixelHeight) }
    }

    nonisolated enum Tier: String, Sendable {
        case interactive
        case authoritative
    }

    /// Cached RAW-stage output keyed by intent + scale + tier.
    private struct RawStageEntry {
        let image: CIImage
        let scale: Double
        let tier: Tier
        var lastAccess: CFAbsoluteTime
        /// GPU backing for interactive entries (~32 MB at 2048 px rgba16Float).
        /// Nil for lazy authoritative graphs.
        let texture: MTLTexture?
    }

    let assetID: UUID
    let rawURL: URL
    private let decodeBackend: any RawDecodeBackend

    private var interactiveFilter: CIRAWFilter?
    private var authoritativeFilter: CIRAWFilter?
    private(set) var capabilities = Capabilities()
    private(set) var metadata: Metadata?
    private var didMaterializeInteractiveStage = false
    private var didCacheAuthoritativeLazyStage = false
    private var rawStageCache: [String: RawStageEntry] = [:]
    private let rawStageCacheLimit = 4
    /// Interactive stages are realized GPU textures; two × ~32 MB is the cap.
    private let interactiveCacheLimit = 2

    init(
        assetID: UUID,
        rawURL: URL,
        decodeBackend: any RawDecodeBackend = RawDecodeBackendRegistry.production
    ) {
        self.assetID = assetID
        self.rawURL = rawURL
        self.decodeBackend = decodeBackend
    }

    /// Whether CIRAWFilter can open this file at all.
    var isRAWCapable: Bool {
        prepareIfNeeded()
        return authoritativeFilter != nil
    }

    func capabilityReport() -> (Capabilities, Metadata?) {
        prepareIfNeeded()
        return (capabilities, metadata)
    }

    func interactiveStageIsMaterialized() -> Bool {
        didMaterializeInteractiveStage
    }

    func authoritativeStageIsLazy() -> Bool {
        didCacheAuthoritativeLazyStage
    }

    // MARK: - RAW stage

    /// Renders the RAW-domain stage (demosaic + RAW-applied intent) as a CIImage.
    /// `targetLongEdge` of nil / 0 means full resolution.
    ///
    /// Reduced scale is applied through `CIRAWFilter.scaleFactor` so the decoder
    /// never produces a full-size image only to throw pixels away.
    ///
    /// Interactive caches a GPU-materialized pinned decode (camera WB, 0 EV)
    /// and applies exposure / WB as Core Image post-ops so slider ticks stay
    /// cache-valid without re-running demosaic at draw time.
    /// Authoritative still bakes the live intent onto `CIRAWFilter` and keeps
    /// the lazy graph — settled / export evaluate once at their destination.
    func rawStageImage(
        intent: RawIntent,
        targetLongEdge: Int?,
        tier: Tier
    ) -> (image: CIImage, cacheHit: Bool)? {
        prepareIfNeeded()

        let scale = scaleFactor(for: targetLongEdge)
        let decodeIntent = tier == .interactive ? intent.pinnedInteractiveDecode : intent
        let key = [
            decodeIntent.fingerprint,
            String(format: "%.4f", scale),
            tier.rawValue,
            RawDecodeBackendRegistry.mappingVersion,
        ].joined(separator: "#")

        if var hit = rawStageCache[key] {
            hit.lastAccess = CFAbsoluteTimeGetCurrent()
            rawStageCache[key] = hit
            return (finishRawStage(hit.image, intent: intent, tier: tier), true)
        }

        let filter: CIRAWFilter?
        switch tier {
        case .interactive: filter = interactiveFilter
        case .authoritative: filter = authoritativeFilter
        }
        guard let filter else { return nil }

        apply(intent: intent, to: filter, tier: tier, scale: scale)
        guard let output = filter.outputImage else { return nil }

        // Interactive: realize the demosaic once into an MTLTexture so later
        // Metal draws do not re-walk CIRAWFilter. Authoritative stays lazy.
        var cached = output
        var texture: MTLTexture?
        if tier == .interactive, let realized = materializeInteractiveStage(output) {
            cached = realized.image
            texture = realized.texture
            didMaterializeInteractiveStage = true
        } else if tier == .authoritative {
            didCacheAuthoritativeLazyStage = true
        }

        rawStageCache[key] = RawStageEntry(
            image: cached,
            scale: scale,
            tier: tier,
            lastAccess: CFAbsoluteTimeGetCurrent(),
            texture: texture
        )
        evictRawStageIfNeeded()
        return (finishRawStage(cached, intent: intent, tier: tier), false)
    }

    /// Drop cached RAW-stage surfaces (RawIntent changed upstream or memory pressure).
    func invalidateRawStage() {
        for key in Array(rawStageCache.keys) {
            dropStage(key)
        }
    }

    /// Memory-pressure trim — keep at most one most-recent entry (existing policy)
    /// and release GPU textures of every evicted interactive stage.
    func trimForMemoryPressure() {
        let sorted = rawStageCache.sorted { $0.value.lastAccess > $1.value.lastAccess }
        for (key, _) in sorted.dropFirst() {
            dropStage(key)
        }
    }

    // MARK: - Internals

    private func prepareIfNeeded() {
        guard metadata == nil else { return }

        guard let auth = decodeBackend.makeFilter(imageURL: rawURL) else {
            // Not RAW-capable — ImageIO fallback handled by the graph with an
            // honest proxy fidelity label.
            return
        }
        let inter = decodeBackend.makeFilter(imageURL: rawURL)

        auth.isDraftModeEnabled = false
        if let inter {
            // Draft only on the interactive filter — validated visually per camera
            // by the interactive-to-settled fidelity comparison.
            inter.isDraftModeEnabled = true
            capabilities.draftMode = .supported
        }

        capabilities.luminanceNoiseReduction = auth.isLuminanceNoiseReductionSupported ? .supported : .unsupported
        capabilities.sharpness = auth.isSharpnessSupported ? .supported : .unsupported
        capabilities.lensCorrection = auth.isLensCorrectionSupported ? .supported : .unsupported
        if auth.isLensCorrectionSupported {
            auth.isLensCorrectionEnabled = true
            inter?.isLensCorrectionEnabled = true
        }

        let extent = auth.outputImage?.extent ?? .zero
        let mtime = (try? FileManager.default.attributesOfItem(atPath: rawURL.path)[.modificationDate] as? Date) ?? .distantPast

        metadata = Metadata(
            pixelWidth: Int(extent.width),
            pixelHeight: Int(extent.height),
            decoderVersion: RawDecodeBackendRegistry.mappingVersion,
            fileModificationDate: mtime,
            nativeNeutralTemperature: Double(auth.neutralTemperature),
            nativeNeutralTint: Double(auth.neutralTint)
        )

        authoritativeFilter = auth
        interactiveFilter = inter
    }

    private func scaleFactor(for targetLongEdge: Int?) -> Double {
        guard let targetLongEdge, targetLongEdge > 0,
              let metadata, metadata.longEdge > 0,
              targetLongEdge < metadata.longEdge else { return 1 }
        return Double(targetLongEdge) / Double(metadata.longEdge)
    }

    /// Authoritative writes the live `EditRecipe` RAW slice onto `CIRAWFilter`:
    /// `exposure`, `neutralTemperature` / `neutralTint` (or camera as-shot),
    /// `luminanceNoiseReductionAmount`, `sharpnessAmount`, `scaleFactor`.
    ///
    /// Interactive pins exposure to 0 and WB to camera as-shot so the demosaic
    /// stays cache-stable; NR, sharpen, and scale still write through.
    private func apply(intent: RawIntent, to filter: CIRAWFilter, tier: Tier, scale: Double) {
        let decode = tier == .interactive ? intent.pinnedInteractiveDecode : intent
        filter.exposure = Float(decode.exposureEV)

        if decode.isAsShotWhiteBalance {
            // Restore camera as-shot neutral rather than forcing 6500 K.
            if let metadata {
                filter.neutralTemperature = Float(metadata.nativeNeutralTemperature)
                filter.neutralTint = Float(metadata.nativeNeutralTint)
            }
        } else {
            filter.neutralTemperature = Float(decode.temperature)
            filter.neutralTint = Float(decode.tint)
        }

        if capabilities.luminanceNoiseReduction == .supported {
            filter.luminanceNoiseReductionAmount = Float(min(max(decode.luminanceNR / 100.0, 0), 1))
        }
        if capabilities.sharpness == .supported {
            filter.sharpnessAmount = Float(min(max(decode.sharpness / 150.0, 0), 1))
        }

        filter.scaleFactor = Float(scale)
    }

    /// Interactive: cheap CI post-ops on the pinned decode. Authoritative: the
    /// image already carries baked RAW-domain exposure / WB.
    private func finishRawStage(_ image: CIImage, intent: RawIntent, tier: Tier) -> CIImage {
        guard tier == .interactive else { return image }
        return DevelopRenderGraph.applyExposureAndWhiteBalance(intent, to: image)
    }

    /// Evaluate the lazy CIRAWFilter graph once into a texture-backed CIImage.
    /// Returns nil on Metal / render failure; the caller then caches the lazy
    /// graph so the photograph still displays.
    private func materializeInteractiveStage(_ image: CIImage) -> (image: CIImage, texture: MTLTexture)? {
        guard let device = LuminaMetalDevice.shared else { return nil }
        let extent = image.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width >= 1, height >= 1 else { return nil }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        let destination = CIRenderDestination(
            width: width,
            height: height,
            pixelFormat: .rgba16Float,
            commandBuffer: nil
        ) { texture }
        destination.colorSpace = DevelopColorPolicy.workingColorSpace
        // Metal textures are top-left; CIImage(mtlTexture:) assumes that and
        // flips back to CI's bottom-left. Match that convention here.
        destination.isFlipped = true

        do {
            _ = try DevelopRenderGraph.sharedContext.startTask(
                toRender: image,
                from: extent,
                to: destination
            ).waitUntilCompleted()
        } catch {
            return nil
        }

        guard let wrapped = CIImage(
            mtlTexture: texture,
            options: [.colorSpace: DevelopColorPolicy.workingColorSpace]
        ) else { return nil }
        return (wrapped, texture)
    }

    private func evictRawStageIfNeeded() {
        while rawStageCache.count > rawStageCacheLimit {
            guard let oldest = rawStageCache.min(by: { $0.value.lastAccess < $1.value.lastAccess }) else { break }
            dropStage(oldest.key)
        }
        while interactiveStageCount > interactiveCacheLimit {
            guard let oldestInteractive = rawStageCache
                .filter({ $0.value.tier == .interactive })
                .min(by: { $0.value.lastAccess < $1.value.lastAccess }) else { break }
            dropStage(oldestInteractive.key)
        }
    }

    private var interactiveStageCount: Int {
        rawStageCache.values.filter { $0.tier == .interactive }.count
    }

    /// Drop an entry so its CIImage wrapper and MTLTexture can deallocate.
    private func dropStage(_ key: String) {
        guard let entry = rawStageCache.removeValue(forKey: key) else { return }
        // Interactive entries hold a ~32 MB rgba16Float texture; dropping both
        // the wrapper and this handle lets Metal reclaim it.
        _ = entry.texture
    }
}

/// Registry of prepared sessions — leader plus a small warm set.
actor PreparedRawSessionRegistry {
    static let shared = PreparedRawSessionRegistry()

    private var sessions: [UUID: PreparedRawSession] = [:]
    private var order: [UUID] = []
    /// Leader + two visible references + one prefetch.
    private let capacity = 4

    func session(for assetID: UUID, rawURL: URL) -> PreparedRawSession {
        if let existing = sessions[assetID] {
            order.removeAll { $0 == assetID }
            order.append(assetID)
            return existing
        }
        let created = PreparedRawSession(assetID: assetID, rawURL: rawURL)
        sessions[assetID] = created
        order.append(assetID)
        while order.count > capacity, let evict = order.first {
            order.removeFirst()
            sessions.removeValue(forKey: evict)
        }
        return created
    }

    func invalidate(assetID: UUID) {
        sessions.removeValue(forKey: assetID)
        order.removeAll { $0 == assetID }
    }

    /// Memory pressure: drop everything except the most recently used session.
    func trimForMemoryPressure(keeping keepID: UUID?) async {
        let keep = keepID ?? order.last
        for (id, session) in sessions {
            if id == keep {
                await session.trimForMemoryPressure()
            } else {
                sessions.removeValue(forKey: id)
                order.removeAll { $0 == id }
            }
        }
    }

    func removeAll() {
        sessions.removeAll()
        order.removeAll()
    }
}
