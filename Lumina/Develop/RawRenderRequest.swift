import CoreGraphics
import CoreImage
import Foundation

/// Preview / export quality tier. Resolution may differ; operation order must not.
enum DevelopRenderQuality: String, Codable, Hashable, Sendable, CaseIterable {
    /// Cached browse JPEG — never authoritative for editing.
    case browse
    /// Interactive scrub — fast, may use demosaic pyramid / downscaled RAW.
    case interactive
    /// Settled preview after interaction ends (~2560–4096 long edge).
    case settled
    /// 1:1 RAW-derived region.
    case oneToOne
    /// Full-resolution export.
    case export

    var defaultLongEdge: Int {
        switch self {
        case .browse: return 1600
        case .interactive: return 1600
        case .settled: return 3200
        case .oneToOne: return 0 // region-sized
        case .export: return 0 // full
        }
    }

    var userFacingLabel: String {
        switch self {
        case .browse: return "Browse"
        case .interactive: return "Interactive"
        case .settled: return "Full Preview"
        case .oneToOne: return "1:1 RAW"
        case .export: return "Export"
        }
    }
}

/// Honest fidelity label shown while a surface is displayed.
enum DevelopFidelityState: String, Codable, Hashable, Sendable {
    case interactive
    case settling
    case rawSettled
    case oneToOneRAW
    case exportQuality
    case proxyFallback
    case beforeOriginal

    var label: String {
        switch self {
        case .interactive: return "Interactive"
        case .settling: return "Settling"
        case .rawSettled: return "RAW settled"
        case .oneToOneRAW: return "1:1 RAW"
        case .exportQuality: return "Export"
        case .proxyFallback: return "Proxy"
        case .beforeOriginal: return "Original"
        }
    }
}

/// Source policy for a render request.
enum DevelopDecodeSource: String, Codable, Hashable, Sendable {
    /// Decode from original RAW (required for settled / 1:1 / export).
    case originalRAW
    /// Interactive-only demosaic pyramid cache derived from RAW.
    case rawPyramid
    /// Embedded/ingested JPEG — browse or emergency fallback only; never authoritative.
    case jpegProxy
}

/// Normalized 1:1 inspection region in oriented image coordinates (origin top-left).
struct DevelopRenderRegion: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let full = DevelopRenderRegion(x: 0, y: 0, width: 1, height: 1)

    func normalized() -> DevelopRenderRegion {
        let w = min(max(width, 0.01), 1)
        let h = min(max(height, 0.01), 1)
        return DevelopRenderRegion(
            x: min(max(x, 0), 1 - w),
            y: min(max(y, 0), 1 - h),
            width: w,
            height: h
        )
    }

    func pixelRect(in extent: CGRect) -> CGRect {
        let c = normalized()
        let originX = extent.minX + CGFloat(c.x) * extent.width
        let originY = extent.maxY - CGFloat(c.y + c.height) * extent.height
        return CGRect(
            x: originX,
            y: originY,
            width: CGFloat(c.width) * extent.width,
            height: CGFloat(c.height) * extent.height
        )
    }
}

/// Single render request — one conceptual graph for all qualities.
struct RawRenderRequest: Hashable, Sendable, Identifiable {
    let id: UUID
    /// Monotonic generation — reject stale results at presentation time.
    let generation: UInt64
    let photoID: UUID
    /// Prepared session this request was issued against.
    let preparedSessionID: UUID
    /// Monotonic recipe revision from the editor model.
    let recipeRevision: UInt64
    /// Active display profile fingerprint at request time.
    let displayProfileID: String
    let rawURL: URL
    /// Optional JPEG proxy for interactive fallback only.
    let proxyURL: URL?
    let recipe: EditRecipe
    let quality: DevelopRenderQuality
    let source: DevelopDecodeSource
    let region: DevelopRenderRegion
    let longEdgeCap: Int?
    /// When true, output tagged for display; export path uses output profile instead.
    let forDisplay: Bool
    /// Slider-event timestamp for input-to-visible latency (CFAbsoluteTime).
    let inputEventAt: CFAbsoluteTime?

    init(
        id: UUID = UUID(),
        generation: UInt64,
        photoID: UUID,
        preparedSessionID: UUID = UUID(),
        recipeRevision: UInt64 = 0,
        displayProfileID: String = "default",
        rawURL: URL,
        proxyURL: URL? = nil,
        recipe: EditRecipe,
        quality: DevelopRenderQuality,
        source: DevelopDecodeSource? = nil,
        region: DevelopRenderRegion = .full,
        longEdgeCap: Int? = nil,
        forDisplay: Bool = true,
        inputEventAt: CFAbsoluteTime? = nil
    ) {
        self.id = id
        self.generation = generation
        self.photoID = photoID
        self.preparedSessionID = preparedSessionID
        self.recipeRevision = recipeRevision
        self.displayProfileID = displayProfileID
        self.rawURL = rawURL
        self.proxyURL = proxyURL
        self.recipe = recipe
        self.quality = quality
        self.source = source ?? Self.defaultSource(for: quality)
        self.region = region
        self.longEdgeCap = longEdgeCap ?? quality.defaultLongEdge
        self.forDisplay = forDisplay
        self.inputEventAt = inputEventAt
    }

    var renderIdentity: DevelopRenderIdentity {
        DevelopRenderIdentity(
            photoID: photoID,
            preparedSessionID: preparedSessionID,
            recipeRevision: recipeRevision,
            requestID: id,
            quality: quality,
            displayProfileID: displayProfileID
        )
    }

    static func defaultSource(for quality: DevelopRenderQuality) -> DevelopDecodeSource {
        switch quality {
        case .browse:
            return .jpegProxy
        case .interactive:
            return .rawPyramid
        case .settled, .oneToOne, .export:
            return .originalRAW
        }
    }

    /// Stage-aware cache key: asset identity, decoder/mapping version, intent
    /// fingerprints per invalidation domain, scale/ROI, working-space version
    /// and output destination.
    var cacheKey: String {
        [
            photoID.uuidString,
            PreparedRawSession.decoderMappingVersion,
            DevelopColorPolicy.workingSpaceVersion,
            recipe.rawIntent.fingerprint,
            recipe.lookIntent.fingerprint,
            recipe.geometryIntent.fingerprint,
            quality.rawValue,
            source.rawValue,
            region.normalized().x.description,
            region.normalized().y.description,
            region.normalized().width.description,
            region.normalized().height.description,
            String(longEdgeCap ?? 0),
            forDisplay ? OutputIntent.display.fingerprint : OutputIntent.exportProPhotoTIFF.fingerprint,
        ].joined(separator: "#")
    }
}

/// Result delivered to the UI — always includes generation for stale rejection.
///
/// The live display path is `ciImage` → Metal (`DevelopMetalView`); `cgImage`
/// is materialized only for export encode and settled histogram/harness use.
/// `CIImage`/`CGImage` are immutable after creation — safe to move across
/// concurrency domains.
struct DevelopRenderResult: @unchecked Sendable {
    let requestID: UUID
    let generation: UInt64
    let photoID: UUID
    let preparedSessionID: UUID
    let recipeRevision: UInt64
    let displayProfileID: String
    let quality: DevelopRenderQuality
    let fidelity: DevelopFidelityState
    let ciImage: CIImage?
    let cgImage: CGImage?
    let extent: CGRect
    let durationMs: Double
    let cacheHit: Bool
    let rawStageCacheHit: Bool
    let cancelled: Bool
    let usedProxyFallback: Bool
    let colorSpaceName: String
    let inputEventAt: CFAbsoluteTime?

    var renderIdentity: DevelopRenderIdentity {
        DevelopRenderIdentity(
            photoID: photoID,
            preparedSessionID: preparedSessionID,
            recipeRevision: recipeRevision,
            requestID: requestID,
            quality: quality,
            displayProfileID: displayProfileID
        )
    }

    init(
        requestID: UUID,
        generation: UInt64,
        photoID: UUID,
        preparedSessionID: UUID = UUID(),
        recipeRevision: UInt64 = 0,
        displayProfileID: String = "default",
        quality: DevelopRenderQuality,
        fidelity: DevelopFidelityState,
        ciImage: CIImage?,
        cgImage: CGImage?,
        extent: CGRect,
        durationMs: Double,
        cacheHit: Bool,
        rawStageCacheHit: Bool,
        cancelled: Bool,
        usedProxyFallback: Bool,
        colorSpaceName: String,
        inputEventAt: CFAbsoluteTime? = nil
    ) {
        self.requestID = requestID
        self.generation = generation
        self.photoID = photoID
        self.preparedSessionID = preparedSessionID
        self.recipeRevision = recipeRevision
        self.displayProfileID = displayProfileID
        self.quality = quality
        self.fidelity = fidelity
        self.ciImage = ciImage
        self.cgImage = cgImage
        self.extent = extent
        self.durationMs = durationMs
        self.cacheHit = cacheHit
        self.rawStageCacheHit = rawStageCacheHit
        self.cancelled = cancelled
        self.usedProxyFallback = usedProxyFallback
        self.colorSpaceName = colorSpaceName
        self.inputEventAt = inputEventAt
    }
}

/// Tracks in-flight generations per photo and rejects stale presentations.
actor RenderGenerationGate {
    private var latest: [UUID: UInt64] = [:]
    private var counter: UInt64 = 0

    func next(for photoID: UUID) -> UInt64 {
        counter &+= 1
        latest[photoID] = counter
        return counter
    }

    func isCurrent(_ generation: UInt64, for photoID: UUID) -> Bool {
        latest[photoID] == generation
    }

    func invalidate(_ photoID: UUID) {
        counter &+= 1
        latest[photoID] = counter
    }

    func invalidateAll() {
        counter &+= 1
        latest.removeAll()
    }
}

/// Pure ordering helper — testable without rendering.
enum RenderGenerationOrdering {
    /// Returns whether `candidate` should replace `presented` for the same photo.
    static func shouldPresent(candidate: UInt64, presented: UInt64?) -> Bool {
        guard let presented else { return true }
        return candidate >= presented
    }

    /// Coalesce slider updates: keep only the latest pending recipe fingerprint.
    static func coalesce(pending: [String], newest: String) -> [String] {
        [newest]
    }
}
