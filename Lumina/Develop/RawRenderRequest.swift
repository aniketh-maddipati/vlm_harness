import CoreGraphics
import CoreImage
import Foundation

/// Preview / export quality tier. Resolution may differ; operation order must not.
nonisolated enum DevelopRenderQuality: String, Codable, Hashable, Sendable, CaseIterable {
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
        // Keep interactive lean so slider scrub stays under the pointer.
        case .interactive: return 1920
        case .settled: return 4096
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
nonisolated enum DevelopFidelityState: String, Codable, Hashable, Sendable {
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

/// How the RAW stage underneath a displayed surface is backed.
///
/// This is a *measurement* fact, not a rendering choice: it records what
/// `PreparedRawSession.rawStageSurface` actually produced for the surface the
/// Metal view is about to walk, so a draw sample can be attributed instead of
/// averaged. Nothing reads it to decide what to render.
///
/// The distinction is the whole reason the attribution exists. Core Image's
/// intermediate cache absorbs an *identical* redraw of a lazy graph, so a lazy
/// tier looks fine while nothing moves; change the geometry transform and the
/// cache misses and the demosaic re-runs on the presentation path.
nonisolated enum DevelopRawStageBacking: String, Codable, Hashable, Sendable {
    /// The RAW stage was evaluated once into an `MTLTexture`
    /// (`materializeInteractiveStage`). A draw walks a texture read.
    case materialized
    /// The RAW stage is still the lazy `CIRAWFilter.outputImage` graph. A draw
    /// that misses the intermediate cache re-runs the demosaic.
    case lazyGraph
    /// Not a RAW stage at all (proxy / ImageIO fallback / browse JPEG), or a
    /// surface that reached the view without attribution. Never sampled — an
    /// unattributed draw is left out of both distributions rather than guessed
    /// into one of them.
    case unattributed
}

/// Source policy for a render request.
nonisolated enum DevelopDecodeSource: String, Codable, Hashable, Sendable {
    /// Decode from original RAW (required for settled / 1:1 / export).
    case originalRAW
    /// Interactive-only demosaic pyramid cache derived from RAW.
    case rawPyramid
    /// Embedded/ingested JPEG — browse or emergency fallback only; never authoritative.
    case jpegProxy
}

/// Normalized 1:1 inspection region in oriented image coordinates (origin top-left).
nonisolated struct DevelopRenderRegion: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let full = DevelopRenderRegion(x: 0, y: 0, width: 1, height: 1)

    static func oneToOne(
        center: CGPoint,
        drawableSize: CGSize,
        imagePixelSize: CGSize
    ) -> DevelopRenderRegion {
        guard drawableSize.width > 0,
              drawableSize.height > 0,
              imagePixelSize.width > 0,
              imagePixelSize.height > 0 else {
            return DevelopRenderRegion(x: 0.35, y: 0.35, width: 0.3, height: 0.3)
        }
        let width = min(max(drawableSize.width / imagePixelSize.width, 0.01), 1)
        let height = min(max(drawableSize.height / imagePixelSize.height, 0.01), 1)
        return DevelopRenderRegion(
            x: Double(center.x - width / 2),
            y: Double(center.y - height / 2),
            width: Double(width),
            height: Double(height)
        ).normalized()
    }

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
nonisolated struct RawRenderRequest: Hashable, Sendable, Identifiable {
    let id: UUID
    /// Monotonic generation — reject stale results at presentation time.
    let generation: UInt64
    let photoID: UUID
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

    init(
        id: UUID = UUID(),
        generation: UInt64,
        photoID: UUID,
        rawURL: URL,
        proxyURL: URL? = nil,
        recipe: EditRecipe,
        quality: DevelopRenderQuality,
        source: DevelopDecodeSource? = nil,
        region: DevelopRenderRegion = .full,
        longEdgeCap: Int? = nil,
        forDisplay: Bool = true
    ) {
        self.id = id
        self.generation = generation
        self.photoID = photoID
        self.rawURL = rawURL
        self.proxyURL = proxyURL
        self.recipe = recipe
        self.quality = quality
        self.source = source ?? Self.defaultSource(for: quality)
        self.region = region
        self.longEdgeCap = longEdgeCap ?? quality.defaultLongEdge
        self.forDisplay = forDisplay
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
            RawDecodeBackendRegistry.mappingVersion,
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
nonisolated struct DevelopRenderResult: @unchecked Sendable {
    var preGeometryExtent: CGRect? = nil
    var displayRecipe: EditRecipe? = nil
    var measurementIdentity: DevelopSelectedImageIdentity? = nil
    /// How the RAW stage under `ciImage` is backed. Measurement attribution only;
    /// no render decision reads it. Defaults to `.unattributed` so a surface that
    /// never passed through the RAW stage is left out of the draw distributions.
    var rawStageBacking: DevelopRawStageBacking = .unattributed
    let requestID: UUID
    let generation: UInt64
    let photoID: UUID
    let quality: DevelopRenderQuality
    let fidelity: DevelopFidelityState
    let ciImage: CIImage?
    let cgImage: CGImage?
    let extent: CGRect
    /// Wall time of `DevelopRenderGraph.render`. On the display-path interactive
    /// tier this is graph construction only; real slider-to-pixels is
    /// `p0.edit.draw_ms` around the Metal `startTask` pair.
    let durationMs: Double
    let cacheHit: Bool
    let rawStageCacheHit: Bool
    let cancelled: Bool
    let usedProxyFallback: Bool
    let colorSpaceName: String
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
nonisolated enum RenderGenerationOrdering {
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
