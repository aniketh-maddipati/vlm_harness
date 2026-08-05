import AppKit
import Foundation

/// Bounded cache of decoded / rendered develop surfaces.
actor DevelopRenderCache {
    struct Entry {
        let key: String
        let image: CGImage
        let fidelity: DevelopFidelityState
        let byteEstimate: Int
        var lastAccess: CFAbsoluteTime
    }

    private var entries: [String: Entry] = [:]
    private var totalBytes = 0
    private let budgetBytes: Int

    init(budgetMegabytes: Int = 512) {
        self.budgetBytes = max(budgetMegabytes, 64) * 1_024 * 1_024
    }

    func get(_ key: String) -> Entry? {
        guard var entry = entries[key] else { return nil }
        entry.lastAccess = CFAbsoluteTimeGetCurrent()
        entries[key] = entry
        return entry
    }

    func put(key: String, image: CGImage, fidelity: DevelopFidelityState) {
        let bytes = image.bytesPerRow * image.height
        if let old = entries[key] {
            totalBytes -= old.byteEstimate
        }
        entries[key] = Entry(
            key: key,
            image: image,
            fidelity: fidelity,
            byteEstimate: bytes,
            lastAccess: CFAbsoluteTimeGetCurrent()
        )
        totalBytes += bytes
        evictIfNeeded()
    }

    func invalidate(photoID: UUID) {
        let prefix = photoID.uuidString
        let keys = entries.keys.filter { $0.hasPrefix(prefix) }
        for key in keys {
            if let old = entries.removeValue(forKey: key) {
                totalBytes -= old.byteEstimate
            }
        }
    }

    func invalidateAll() {
        entries.removeAll()
        totalBytes = 0
    }

    private func evictIfNeeded() {
        while totalBytes > budgetBytes, let oldest = entries.values.min(by: { $0.lastAccess < $1.lastAccess }) {
            if let old = entries.removeValue(forKey: oldest.key) {
                totalBytes -= old.byteEstimate
            }
        }
    }
}

/// Debug instrumentation for develop responsiveness.
struct DevelopRenderMetrics {
    var cacheHits = 0
    var cacheMisses = 0
    var cancelled = 0
    var staleRejected = 0
    var completed = 0
    var lastDurationMs: Double = 0
    var lastQuality: DevelopRenderQuality = .interactive
    var lastFidelity: DevelopFidelityState = .interactive

    mutating func record(result: DevelopRenderResult, stale: Bool) {
        if stale {
            staleRejected += 1
            return
        }
        if result.cancelled {
            cancelled += 1
            return
        }
        if result.cacheHit { cacheHits += 1 } else { cacheMisses += 1 }
        completed += 1
        lastDurationMs = result.durationMs
        lastQuality = result.quality
        lastFidelity = result.fidelity
    }

    var summaryLine: String {
        String(
            format: "dev cache hit=%d miss=%d cancel=%d stale=%d last=%.1fms %@/%@",
            cacheHits, cacheMisses, cancelled, staleRejected,
            lastDurationMs, lastQuality.rawValue, lastFidelity.rawValue
        )
    }
}

/// Coalesces slider updates, cancels obsolete work, rejects stale results at presentation.
@MainActor
@Observable
final class DevelopRenderScheduler {
    private(set) var metrics = DevelopRenderMetrics()
    private(set) var presented: [UUID: DevelopRenderResult] = [:]
    private(set) var fidelityByPhoto: [UUID: DevelopFidelityState] = [:]

    private let gate = RenderGenerationGate()
    private let cache = DevelopRenderCache()
    private var inflight: [UUID: Task<Void, Never>] = [:]
    private var settleTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingRecipe: [UUID: EditRecipe] = [:]

    /// Before/After cached surfaces — switch without re-render.
    private var beforeSurface: [UUID: CGImage] = [:]
    private var afterSurface: [UUID: CGImage] = [:]

    func cancelAll() {
        for (_, task) in inflight { task.cancel() }
        for (_, task) in settleTasks { task.cancel() }
        inflight.removeAll()
        settleTasks.removeAll()
        Task { await gate.invalidateAll() }
    }

    /// High-frequency slider path — coalesce + interactive quality only.
    func scrub(
        photoID: UUID,
        rawURL: URL,
        proxyURL: URL?,
        recipe: EditRecipe
    ) {
        pendingRecipe[photoID] = recipe
        fidelityByPhoto[photoID] = .interactive
        inflight[photoID]?.cancel()
        settleTasks[photoID]?.cancel()

        let task = Task { [weak self] in
            // Coalesce: wait a frame-ish beat for further scrub events.
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard !Task.isCancelled, let self else { return }
            guard let latest = self.pendingRecipe[photoID] else { return }
            await self.renderNow(
                photoID: photoID,
                rawURL: rawURL,
                proxyURL: proxyURL,
                recipe: latest,
                quality: .interactive
            )
            guard !Task.isCancelled else { return }
            self.scheduleSettled(photoID: photoID, rawURL: rawURL, proxyURL: proxyURL, recipe: latest)
        }
        inflight[photoID] = task
    }

    /// Settled preview after interaction ends.
    private func scheduleSettled(photoID: UUID, rawURL: URL, proxyURL: URL?, recipe: EditRecipe) {
        settleTasks[photoID]?.cancel()
        fidelityByPhoto[photoID] = .settling
        settleTasks[photoID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.renderNow(
                photoID: photoID,
                rawURL: rawURL,
                proxyURL: proxyURL,
                recipe: recipe,
                quality: .settled
            )
        }
    }

    func renderOneToOne(
        photoID: UUID,
        rawURL: URL,
        proxyURL: URL?,
        recipe: EditRecipe,
        region: DevelopRenderRegion
    ) async {
        fidelityByPhoto[photoID] = .oneToOneRAW
        await renderNow(
            photoID: photoID,
            rawURL: rawURL,
            proxyURL: proxyURL,
            recipe: recipe,
            quality: .oneToOne,
            region: region
        )
    }

    func warmBeforeAfter(
        photoID: UUID,
        rawURL: URL,
        proxyURL: URL?,
        recipe: EditRecipe
    ) async {
        let gen = await gate.next(for: photoID)
        let beforeReq = RawRenderRequest(
            generation: gen,
            photoID: photoID,
            rawURL: rawURL,
            proxyURL: proxyURL,
            recipe: .neutral,
            quality: .settled,
            source: .originalRAW
        )
        let afterReq = RawRenderRequest(
            generation: gen,
            photoID: photoID,
            rawURL: rawURL,
            proxyURL: proxyURL,
            recipe: recipe,
            quality: .settled,
            source: .originalRAW
        )
        let before = await Task.detached(priority: .userInitiated) {
            DevelopRenderGraph.render(beforeReq)
        }.value
        let after = await Task.detached(priority: .userInitiated) {
            DevelopRenderGraph.render(afterReq)
        }.value
        if let img = before.cgImage { beforeSurface[photoID] = img }
        if let img = after.cgImage { afterSurface[photoID] = img }
    }

    /// Instant Before/After using cached surfaces.
    func beforeImage(for photoID: UUID) -> CGImage? { beforeSurface[photoID] }
    func afterImage(for photoID: UUID) -> CGImage? { afterSurface[photoID] ?? presented[photoID]?.cgImage }

    func presentedImage(for photoID: UUID) -> CGImage? { presented[photoID]?.cgImage }

    private func renderNow(
        photoID: UUID,
        rawURL: URL,
        proxyURL: URL?,
        recipe: EditRecipe,
        quality: DevelopRenderQuality,
        region: DevelopRenderRegion = .full
    ) async {
        let generation = await gate.next(for: photoID)
        let request = RawRenderRequest(
            generation: generation,
            photoID: photoID,
            rawURL: rawURL,
            proxyURL: proxyURL,
            recipe: recipe,
            quality: quality,
            region: region
        )

        let key = request.cacheKey
        if let cached = await cache.get(key) {
            let result = DevelopRenderResult(
                requestID: request.id,
                generation: generation,
                photoID: photoID,
                quality: quality,
                fidelity: cached.fidelity,
                cgImage: cached.image,
                extent: CGRect(x: 0, y: 0, width: cached.image.width, height: cached.image.height),
                durationMs: 0,
                cacheHit: true,
                cancelled: false,
                usedProxyFallback: cached.fidelity == .proxyFallback,
                colorSpaceName: DevelopColorPolicy.describeColorSpace(cached.image.colorSpace)
            )
            present(result)
            return
        }

        let rendered = await Task.detached(priority: quality == .interactive ? .userInitiated : .utility) {
            DevelopRenderGraph.render(request)
        }.value

        if Task.isCancelled {
            var cancelled = rendered
            // Reconstruct with cancelled flag — DevelopRenderResult is a struct with let fields.
            let flag = DevelopRenderResult(
                requestID: rendered.requestID,
                generation: rendered.generation,
                photoID: rendered.photoID,
                quality: rendered.quality,
                fidelity: rendered.fidelity,
                cgImage: nil,
                extent: .zero,
                durationMs: rendered.durationMs,
                cacheHit: false,
                cancelled: true,
                usedProxyFallback: rendered.usedProxyFallback,
                colorSpaceName: rendered.colorSpaceName
            )
            metrics.record(result: flag, stale: false)
            _ = cancelled
            return
        }

        let current = await gate.isCurrent(generation, for: photoID)
        guard current else {
            metrics.record(result: rendered, stale: true)
            return
        }

        if let image = rendered.cgImage {
            await cache.put(key: key, image: image, fidelity: rendered.fidelity)
            if quality == .settled || quality == .export {
                afterSurface[photoID] = image
            }
        }
        present(rendered)
    }

    private func present(_ result: DevelopRenderResult) {
        let previousGen = presented[result.photoID]?.generation
        guard RenderGenerationOrdering.shouldPresent(candidate: result.generation, presented: previousGen) else {
            metrics.record(result: result, stale: true)
            return
        }
        presented[result.photoID] = result
        fidelityByPhoto[result.photoID] = result.fidelity
        metrics.record(result: result, stale: false)
        #if DEBUG
        fputs(metrics.summaryLine + "\n", stderr)
        #endif
    }
}
