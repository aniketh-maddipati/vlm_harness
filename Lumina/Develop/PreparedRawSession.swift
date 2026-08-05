import CoreImage
import Foundation
import ImageIO
import os

/// Per-photo prepared RAW session with serial (actor) ownership.
///
/// Owns metadata plus **two** mutable `CIRAWFilter` instances for one asset:
/// - `interactive` — reduced-scale, draft-mode-allowed rendering
/// - `authoritative` — non-draft settled / 1:1 / export rendering
///
/// Draft mode is never flipped back and forth on one filter; the two
/// configurations stay separate. `CIFilter` is mutable and not thread-safe,
/// so all property application happens inside this actor. The returned
/// `CIImage` is an immutable recipe snapshot and is safe to render elsewhere.
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

    enum Tier: String, Sendable {
        case interactive
        case authoritative
    }

    /// Cached RAW-stage output keyed by intent + scale + tier.
    private struct RawStageEntry {
        let image: CIImage
        let scale: Double
        var lastAccess: CFAbsoluteTime
    }

    let assetID: UUID
    let rawURL: URL

    private var interactiveFilter: CIRAWFilter?
    private var authoritativeFilter: CIRAWFilter?
    private(set) var capabilities = Capabilities()
    private(set) var metadata: Metadata?
    private var rawStageCache: [String: RawStageEntry] = [:]
    private let rawStageCacheLimit = 4

    /// Bumped whenever Apple's decoder or our mapping changes meaningfully.
    static let decoderMappingVersion = "lumina-ciraw-1"

    init(assetID: UUID, rawURL: URL) {
        self.assetID = assetID
        self.rawURL = rawURL
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

    // MARK: - RAW stage

    /// Renders the RAW-domain stage (demosaic + RAW-applied intent) as a CIImage.
    /// `targetLongEdge` of nil / 0 means full resolution.
    ///
    /// Reduced scale is applied through `CIRAWFilter.scaleFactor` so the decoder
    /// never produces a full-size image only to throw pixels away.
    func rawStageImage(
        intent: RawIntent,
        targetLongEdge: Int?,
        tier: Tier
    ) -> (image: CIImage, cacheHit: Bool)? {
        prepareIfNeeded()

        let scale = scaleFactor(for: targetLongEdge)
        let key = [
            intent.fingerprint,
            String(format: "%.4f", scale),
            tier.rawValue,
            Self.decoderMappingVersion,
        ].joined(separator: "#")

        if var hit = rawStageCache[key] {
            hit.lastAccess = CFAbsoluteTimeGetCurrent()
            rawStageCache[key] = hit
            return (hit.image, true)
        }

        let filter: CIRAWFilter?
        switch tier {
        case .interactive: filter = interactiveFilter
        case .authoritative: filter = authoritativeFilter
        }
        guard let filter else { return nil }

        apply(intent: intent, to: filter, tier: tier, scale: scale)
        guard let output = filter.outputImage else { return nil }

        rawStageCache[key] = RawStageEntry(image: output, scale: scale, lastAccess: CFAbsoluteTimeGetCurrent())
        evictRawStageIfNeeded()
        return (output, false)
    }

    /// Drop cached RAW-stage surfaces (RawIntent changed upstream or memory pressure).
    func invalidateRawStage() {
        rawStageCache.removeAll()
    }

    /// Memory-pressure trim — keep at most one entry per tier.
    func trimForMemoryPressure() {
        let sorted = rawStageCache.sorted { $0.value.lastAccess > $1.value.lastAccess }
        rawStageCache = Dictionary(uniqueKeysWithValues: Array(sorted.prefix(1)))
    }

    // MARK: - Internals

    private func prepareIfNeeded() {
        guard metadata == nil else { return }

        guard let auth = CIRAWFilter(imageURL: rawURL) else {
            // Not RAW-capable — ImageIO fallback handled by the graph with an
            // honest proxy fidelity label.
            return
        }
        let inter = CIRAWFilter(imageURL: rawURL)

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
            decoderVersion: Self.decoderMappingVersion,
            fileModificationDate: mtime ?? .distantPast,
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

    private func apply(intent: RawIntent, to filter: CIRAWFilter, tier: Tier, scale: Double) {
        filter.exposure = Float(intent.exposureEV)

        if intent.isAsShotWhiteBalance {
            // Restore camera as-shot neutral rather than forcing 6500 K.
            if let metadata {
                filter.neutralTemperature = Float(metadata.nativeNeutralTemperature)
                filter.neutralTint = Float(metadata.nativeNeutralTint)
            }
        } else {
            filter.neutralTemperature = Float(intent.temperature)
            filter.neutralTint = Float(intent.tint)
        }

        if capabilities.luminanceNoiseReduction == .supported {
            filter.luminanceNoiseReductionAmount = Float(min(max(intent.luminanceNR / 100.0, 0), 1))
        }
        if capabilities.sharpness == .supported {
            filter.sharpnessAmount = Float(min(max(intent.sharpness / 150.0, 0), 1))
        }

        filter.scaleFactor = Float(scale)
    }

    private func evictRawStageIfNeeded() {
        while rawStageCache.count > rawStageCacheLimit {
            guard let oldest = rawStageCache.min(by: { $0.value.lastAccess < $1.value.lastAccess }) else { break }
            rawStageCache.removeValue(forKey: oldest.key)
        }
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
