import AppKit
import CoreImage
import Foundation
import os

/// Stage-aware bounded cache of final presentation surfaces.
///
/// This cache holds only post-look, geometry-applied results. The RAW-stage
/// linear surfaces live inside each `PreparedRawSession`; prepared sessions
/// and metadata live in `PreparedRawSessionRegistry`.
actor DevelopPresentationCache {
    struct Entry {
        let key: String
        let ciImage: CIImage
        let cgImage: CGImage?
        let fidelity: DevelopFidelityState
        let byteEstimate: Int
        var lastAccess: CFAbsoluteTime
        let speculative: Bool
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

    func put(key: String, ciImage: CIImage, cgImage: CGImage?, fidelity: DevelopFidelityState, speculative: Bool = false) {
        // RGBAh estimate: 8 bytes/pixel for the lazy CI recipe's realized size,
        // plus the bitmap when present.
        let extent = ciImage.extent
        var bytes = Int(extent.width * extent.height) * 8
        if let cg = cgImage { bytes += cg.bytesPerRow * cg.height }
        if let old = entries[key] { totalBytes -= old.byteEstimate }
        entries[key] = Entry(
            key: key,
            ciImage: ciImage,
            cgImage: cgImage,
            fidelity: fidelity,
            byteEstimate: bytes,
            lastAccess: CFAbsoluteTimeGetCurrent(),
            speculative: speculative
        )
        totalBytes += bytes
        evictIfNeeded()
    }

    func invalidate(photoID: UUID) {
        let prefix = photoID.uuidString
        for key in entries.keys where key.hasPrefix(prefix) {
            if let old = entries.removeValue(forKey: key) {
                totalBytes -= old.byteEstimate
            }
        }
    }

    func invalidateAll() {
        entries.removeAll()
        totalBytes = 0
    }

    /// Memory pressure: speculative/prefetch entries go first, then everything
    /// except the given photo's most recent surfaces.
    func trimForMemoryPressure(keeping keepID: UUID?) {
        for (key, entry) in entries where entry.speculative {
            entries.removeValue(forKey: key)
            totalBytes -= entry.byteEstimate
        }
        guard let keepID else { return }
        let keepPrefix = keepID.uuidString
        for (key, entry) in entries where !key.hasPrefix(keepPrefix) {
            entries.removeValue(forKey: key)
            totalBytes -= entry.byteEstimate
        }
    }

    private func evictIfNeeded() {
        while totalBytes > budgetBytes,
              let oldest = entries.values.min(by: { $0.lastAccess < $1.lastAccess }) {
            if let old = entries.removeValue(forKey: oldest.key) {
                totalBytes -= old.byteEstimate
            }
        }
    }
}

/// Async counting semaphore for global render concurrency.
actor RenderGate {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { available = limit }

    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            available += 1
        }
    }
}

/// Debug instrumentation for develop responsiveness.
struct DevelopRenderMetrics {
    var cacheHits = 0
    var cacheMisses = 0
    var rawStageHits = 0
    var cancelled = 0
    var staleRejected = 0
    var completed = 0
    var lastDurationMs: Double = 0
    var lastInputToVisibleMs: Double = 0
    var lastQuality: DevelopRenderQuality = .interactive
    var lastFidelity: DevelopFidelityState = .interactive
    var inputToVisibleSamples: [Double] = []

    mutating func record(result: DevelopRenderResult, stale: Bool, inputToVisibleMs: Double? = nil) {
        if stale {
            staleRejected += 1
            return
        }
        if result.cancelled {
            cancelled += 1
            return
        }
        if result.cacheHit { cacheHits += 1 } else { cacheMisses += 1 }
        if result.rawStageCacheHit { rawStageHits += 1 }
        completed += 1
        lastDurationMs = result.durationMs
        lastQuality = result.quality
        lastFidelity = result.fidelity
        if let ms = inputToVisibleMs {
            lastInputToVisibleMs = ms
            inputToVisibleSamples.append(ms)
            if inputToVisibleSamples.count > 200 {
                inputToVisibleSamples.removeFirst(inputToVisibleSamples.count - 200)
            }
        }
    }

    var summaryLine: String {
        String(
            format: "dev cache hit=%d miss=%d rawHit=%d cancel=%d stale=%d last=%.1fms i2v=%.1fms %@/%@",
            cacheHits, cacheMisses, rawStageHits, cancelled, staleRejected,
            lastDurationMs, lastInputToVisibleMs, lastQuality.rawValue, lastFidelity.rawValue
        )
    }

    func inputToVisiblePercentile(_ p: Double) -> Double? {
        guard !inputToVisibleSamples.isEmpty else { return nil }
        let sorted = inputToVisibleSamples.sorted()
        let idx = min(max(Int((Double(sorted.count - 1) * p).rounded()), 0), sorted.count - 1)
        return sorted[idx]
    }
}

/// Pending interactive scrub payload — coalesced to latest only.
private struct PendingScrub: Sendable {
    let rawURL: URL
    let proxyURL: URL?
    let recipe: EditRecipe
    let preparedSessionID: UUID
    let recipeRevision: UInt64
    let displayProfileID: String
    let inputEventAt: CFAbsoluteTime
}

/// Latest-wins render coordinator.
///
/// Interactive scrub uses a **drain loop**: new slider values only update the
/// pending recipe. At most one interactive render runs per photo; when it
/// finishes, if a newer revision arrived it immediately renders that. Completed
/// work is never discarded via `Task.cancel` — publication is gated by
/// identity + recipe revision instead.
///
/// - At most one authoritative (settled/1:1) render active per photo.
/// - At most `interactiveLimit` interactive/settled renders globally (tunable).
/// - Export is serialized on its own lane and never starves the visible photo.
@MainActor
@Observable
final class DevelopRenderScheduler {
    private(set) var metrics = DevelopRenderMetrics()
    private(set) var presented: [UUID: DevelopRenderResult] = [:]
    private(set) var fidelityByPhoto: [UUID: DevelopFidelityState] = [:]
    /// Latest revision the editor asked for (per photo).
    private(set) var latestRequestedRevision: [UUID: UInt64] = [:]
    /// Revision currently displayed (per photo).
    private(set) var displayedRevision: [UUID: UInt64] = [:]

    /// Tunable global limit for interactive + settled renders.
    static var interactiveLimit = 2

    private let gate = RenderGenerationGate()
    private let cache = DevelopPresentationCache()
    private let renderGate = RenderGate(limit: DevelopRenderScheduler.interactiveLimit)
    private var pendingScrub: [UUID: PendingScrub] = [:]
    private var interactiveLoop: [UUID: Task<Void, Never>] = [:]
    private var settleTasks: [UUID: Task<Void, Never>] = [:]
    private var exportQueue: Task<Void, Never>?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var visiblePhotoID: UUID?
    /// Active editor identity — publication requires a match when set.
    var activeEditorIdentity: DevelopEditorIdentity?
    var activeDisplayProfileID: String = "default"

    private static let signposter = OSSignposter(subsystem: "app.lumina.develop", category: "render")

    /// Before/After cached surfaces — switch without re-render.
    private var beforeSurface: [UUID: CIImage] = [:]
    private var afterSurface: [UUID: CIImage] = [:]
    private var beforeBitmap: [UUID: CGImage] = [:]

    init() {
        installMemoryPressureHandler()
    }

    func cancelAll() {
        for (_, task) in interactiveLoop { task.cancel() }
        for (_, task) in settleTasks { task.cancel() }
        interactiveLoop.removeAll()
        settleTasks.removeAll()
        pendingScrub.removeAll()
        Task { await gate.invalidateAll() }
    }

    // MARK: - Interactive scrub

    /// High-frequency slider path — coalesce to latest recipe, never freeze.
    ///
    /// Does **not** cancel an in-flight interactive evaluate. A completed render
    /// publishes only when its revision is still the latest requested revision
    /// (and editor identity matches). Newer values drain immediately after.
    func scrub(
        photoID: UUID,
        rawURL: URL,
        proxyURL: URL?,
        recipe: EditRecipe,
        preparedSessionID: UUID = UUID(),
        recipeRevision: UInt64 = 0,
        displayProfileID: String? = nil,
        inputEventAt: CFAbsoluteTime = CFAbsoluteTimeGetCurrent(),
        controlName: String? = nil,
        controlValue: Double? = nil
    ) {
        visiblePhotoID = photoID
        let profile = displayProfileID ?? activeDisplayProfileID
        latestRequestedRevision[photoID] = recipeRevision
        fidelityByPhoto[photoID] = .interactive
        settleTasks[photoID]?.cancel()

        pendingScrub[photoID] = PendingScrub(
            rawURL: rawURL,
            proxyURL: proxyURL,
            recipe: recipe,
            preparedSessionID: preparedSessionID,
            recipeRevision: recipeRevision,
            displayProfileID: profile,
            inputEventAt: inputEventAt
        )

        DevelopLiveLog.event(
            "slider event photoID=\(photoID.uuidString) sessionID=\(preparedSessionID.uuidString) "
                + "recipeRevision=\(recipeRevision) control=\(controlName ?? "-") "
                + "value=\(controlValue.map { String(format: "%.3f", $0) } ?? "-")"
        )

        ensureInteractiveLoop(for: photoID)
    }

    private func ensureInteractiveLoop(for photoID: UUID) {
        guard interactiveLoop[photoID] == nil else { return }
        interactiveLoop[photoID] = Task { [weak self] in
            // One interactive evaluate at a time per photo; drain newest pending.
            while !Task.isCancelled {
                guard let self else { return }
                guard let pending = self.pendingScrub.removeValue(forKey: photoID) else { break }

                await self.renderNow(
                    photoID: photoID,
                    rawURL: pending.rawURL,
                    proxyURL: pending.proxyURL,
                    recipe: pending.recipe,
                    quality: .interactive,
                    preparedSessionID: pending.preparedSessionID,
                    recipeRevision: pending.recipeRevision,
                    displayProfileID: pending.displayProfileID,
                    inputEventAt: pending.inputEventAt
                )

                // If nothing newer arrived, schedule settled on the last recipe.
                if self.pendingScrub[photoID] == nil {
                    self.scheduleSettled(
                        photoID: photoID,
                        rawURL: pending.rawURL,
                        proxyURL: pending.proxyURL,
                        recipe: pending.recipe,
                        preparedSessionID: pending.preparedSessionID,
                        recipeRevision: pending.recipeRevision,
                        displayProfileID: pending.displayProfileID
                    )
                    break
                }
            }
            self?.interactiveLoop[photoID] = nil
            // A scrub may have arrived in the gap after break/nil assignment.
            if let self, self.pendingScrub[photoID] != nil {
                self.ensureInteractiveLoop(for: photoID)
            }
        }
    }

    /// Authoritative settled render after input pauses. One per photo.
    private func scheduleSettled(
        photoID: UUID,
        rawURL: URL,
        proxyURL: URL?,
        recipe: EditRecipe,
        preparedSessionID: UUID,
        recipeRevision: UInt64,
        displayProfileID: String
    ) {
        settleTasks[photoID]?.cancel()
        fidelityByPhoto[photoID] = .settling
        settleTasks[photoID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, let self else { return }
            // Drop if a newer interactive scrub arrived.
            if let latest = self.latestRequestedRevision[photoID], latest != recipeRevision {
                return
            }
            await self.renderNow(
                photoID: photoID,
                rawURL: rawURL,
                proxyURL: proxyURL,
                recipe: recipe,
                quality: .settled,
                preparedSessionID: preparedSessionID,
                recipeRevision: recipeRevision,
                displayProfileID: displayProfileID
            )
        }
    }

    func renderOneToOne(
        photoID: UUID,
        rawURL: URL,
        proxyURL: URL?,
        recipe: EditRecipe,
        region: DevelopRenderRegion,
        preparedSessionID: UUID = UUID(),
        recipeRevision: UInt64 = 0
    ) async {
        fidelityByPhoto[photoID] = .oneToOneRAW
        await renderNow(
            photoID: photoID,
            rawURL: rawURL,
            proxyURL: proxyURL,
            recipe: recipe,
            quality: .oneToOne,
            region: region,
            preparedSessionID: preparedSessionID,
            recipeRevision: recipeRevision,
            displayProfileID: activeDisplayProfileID
        )
    }

    // MARK: - Prewarm / Before-After

    func warmBeforeAfter(
        photoID: UUID,
        rawURL: URL,
        proxyURL: URL?,
        recipe: EditRecipe,
        preparedSessionID: UUID = UUID()
    ) async {
        let gen = await gate.next(for: photoID)
        let beforeReq = RawRenderRequest(
            generation: gen,
            photoID: photoID,
            preparedSessionID: preparedSessionID,
            rawURL: rawURL,
            proxyURL: proxyURL,
            recipe: .neutral,
            quality: .settled,
            source: .originalRAW
        )
        let afterReq = RawRenderRequest(
            generation: gen,
            photoID: photoID,
            preparedSessionID: preparedSessionID,
            rawURL: rawURL,
            proxyURL: proxyURL,
            recipe: recipe,
            quality: .settled,
            source: .originalRAW
        )
        let before = await DevelopRenderGraph.render(beforeReq)
        let after = await DevelopRenderGraph.render(afterReq)
        if let img = before.ciImage {
            beforeSurface[photoID] = img
            beforeBitmap[photoID] = before.cgImage
        }
        if let img = after.ciImage { afterSurface[photoID] = img }
    }

    /// Prewarm sessions + settled surfaces for the leader and visible references.
    func prewarm(photos: [(id: UUID, rawURL: URL)], recipe: EditRecipe) {
        for (index, photo) in photos.prefix(3).enumerated() {
            Task(priority: index == 0 ? .userInitiated : .utility) { [weak self] in
                guard let self else { return }
                await self.renderNow(
                    photoID: photo.id,
                    rawURL: photo.rawURL,
                    proxyURL: nil,
                    recipe: recipe,
                    quality: .settled,
                    speculative: index > 0
                )
            }
        }
    }

    /// Instant Before/After using cached surfaces.
    func beforeImage(for photoID: UUID) -> CIImage? { beforeSurface[photoID] }
    func beforeBitmap(for photoID: UUID) -> CGImage? { beforeBitmap[photoID] }
    func afterImage(for photoID: UUID) -> CIImage? { afterSurface[photoID] ?? presented[photoID]?.ciImage }

    func presentedCIImage(for photoID: UUID) -> CIImage? { presented[photoID]?.ciImage }
    func presentedImage(for photoID: UUID) -> CGImage? { presented[photoID]?.cgImage }

    // MARK: - Export lane

    /// Serialized, independent of interactive work.
    func enqueueExport(_ work: @escaping @Sendable () async -> Void) {
        let previous = exportQueue
        exportQueue = Task(priority: .utility) {
            await previous?.value
            await work()
        }
    }

    // MARK: - Core render

    private func renderNow(
        photoID: UUID,
        rawURL: URL,
        proxyURL: URL?,
        recipe: EditRecipe,
        quality: DevelopRenderQuality,
        region: DevelopRenderRegion = .full,
        speculative: Bool = false,
        preparedSessionID: UUID = UUID(),
        recipeRevision: UInt64 = 0,
        displayProfileID: String = "default",
        inputEventAt: CFAbsoluteTime? = nil
    ) async {
        let signpostID = Self.signposter.makeSignpostID()
        let requestState = Self.signposter.beginInterval("request", id: signpostID)
        defer { Self.signposter.endInterval("request", requestState) }

        let queuedAt = CFAbsoluteTimeGetCurrent()

        // Resolve real prepared session so publication gate uses a live ID.
        let session = await PreparedRawSessionRegistry.shared.session(for: photoID, rawURL: rawURL)
        let effectiveSessionID = await session.sessionID

        let generation = await gate.next(for: photoID)
        let request = RawRenderRequest(
            generation: generation,
            photoID: photoID,
            preparedSessionID: effectiveSessionID,
            recipeRevision: recipeRevision,
            displayProfileID: displayProfileID,
            rawURL: rawURL,
            proxyURL: proxyURL,
            recipe: recipe,
            quality: quality,
            region: region,
            inputEventAt: inputEventAt
        )

        DevelopLiveLog.event(
            "render start requestID=\(request.id.uuidString) photoID=\(photoID.uuidString) "
                + "sessionID=\(effectiveSessionID.uuidString) recipeRevision=\(recipeRevision) quality=\(quality.rawValue)"
        )

        let key = request.cacheKey
        if let cached = await cache.get(key) {
            Self.signposter.emitEvent("cacheHit", id: signpostID)
            let result = DevelopRenderResult(
                requestID: request.id,
                generation: generation,
                photoID: photoID,
                preparedSessionID: effectiveSessionID,
                recipeRevision: recipeRevision,
                displayProfileID: displayProfileID,
                quality: quality,
                fidelity: cached.fidelity,
                ciImage: cached.ciImage,
                cgImage: cached.cgImage,
                extent: cached.ciImage.extent,
                durationMs: 0,
                cacheHit: true,
                rawStageCacheHit: true,
                cancelled: false,
                usedProxyFallback: cached.fidelity == .proxyFallback,
                colorSpaceName: "cached",
                inputEventAt: inputEventAt
            )
            present(result, signpostID: signpostID)
            return
        }
        Self.signposter.emitEvent("cacheMiss", id: signpostID)

        await renderGate.acquire()
        let queueDelayMs = (CFAbsoluteTimeGetCurrent() - queuedAt) * 1000
        Self.signposter.emitEvent("queueDelay", id: signpostID, "\(queueDelayMs, format: .fixed(precision: 1))ms")

        // Interactive lane: do not abandon solely because a newer revision is
        // pending — finish this evaluate so the drain loop can converge. Only
        // skip if the photo identity was invalidated entirely.
        if quality != .interactive, await !gate.isCurrent(generation, for: photoID) {
            await renderGate.release()
            Self.signposter.emitEvent("staleDiscardPreRender", id: signpostID)
            DevelopLiveLog.event("publication rejected pre-render requestID=\(request.id.uuidString) reason=superseded")
            return
        }

        let evalState = Self.signposter.beginInterval("evaluate", id: signpostID)
        let rendered = await DevelopRenderGraph.render(request)
        Self.signposter.endInterval("evaluate", evalState)
        await renderGate.release()

        DevelopLiveLog.event(
            "render finish requestID=\(request.id.uuidString) durationMs=\(String(format: "%.1f", rendered.durationMs)) "
                + "rawHit=\(rendered.rawStageCacheHit) cancelled=\(rendered.cancelled)"
        )

        // Interactive results publish via revision gate; settled still uses generation.
        if quality != .interactive {
            let current = await gate.isCurrent(generation, for: photoID)
            guard current else {
                Self.signposter.emitEvent("staleDiscard", id: signpostID)
                metrics.record(result: rendered, stale: true)
                DevelopLiveLog.event("publication rejected requestID=\(request.id.uuidString) reason=generation")
                return
            }
        }

        if let image = rendered.ciImage {
            await cache.put(
                key: key,
                ciImage: image,
                cgImage: rendered.cgImage,
                fidelity: rendered.fidelity,
                speculative: speculative
            )
            if quality == .settled {
                afterSurface[photoID] = image
                Self.signposter.emitEvent("settlement", id: signpostID)
            }
        }
        present(rendered, signpostID: signpostID)
    }

    private func present(_ result: DevelopRenderResult, signpostID: OSSignpostID) {
        // Identity gate — never publish into the wrong editor / session / profile.
        if let identity = activeEditorIdentity {
            guard result.photoID == identity.photoID,
                  result.preparedSessionID == identity.preparedSessionID else {
                metrics.record(result: result, stale: true)
                DevelopLiveLog.event(
                    "publication rejected requestID=\(result.requestID.uuidString) reason=identity "
                        + "resultSession=\(result.preparedSessionID.uuidString) "
                        + "editorSession=\(identity.preparedSessionID.uuidString)"
                )
                return
            }
        }
        if result.displayProfileID != activeDisplayProfileID,
           activeDisplayProfileID != "default",
           result.displayProfileID != "default" {
            metrics.record(result: result, stale: true)
            DevelopLiveLog.event("publication rejected requestID=\(result.requestID.uuidString) reason=displayProfile")
            return
        }

        // Latest-revision gate: interactive/settled may only replace when they
        // match the newest requested revision (or are strictly newer settled of same).
        if let latest = latestRequestedRevision[result.photoID], result.recipeRevision != 0 {
            guard result.recipeRevision == latest else {
                metrics.record(result: result, stale: true)
                DevelopLiveLog.event(
                    "publication rejected requestID=\(result.requestID.uuidString) reason=revision "
                        + "result=\(result.recipeRevision) latest=\(latest)"
                )
                return
            }
        }

        let previousGen = presented[result.photoID]?.generation
        guard RenderGenerationOrdering.shouldPresent(candidate: result.generation, presented: previousGen) else {
            metrics.record(result: result, stale: true)
            DevelopLiveLog.event("publication rejected requestID=\(result.requestID.uuidString) reason=generationOrder")
            return
        }

        // Keep last valid texture if this result has no image.
        guard result.ciImage != nil else {
            metrics.record(result: result, stale: false)
            return
        }

        var inputToVisible: Double?
        if let t0 = result.inputEventAt {
            inputToVisible = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            Self.signposter.emitEvent(
                "inputToVisible",
                id: signpostID,
                "\(inputToVisible!, format: .fixed(precision: 1))ms"
            )
        }

        presented[result.photoID] = result
        displayedRevision[result.photoID] = result.recipeRevision
        fidelityByPhoto[result.photoID] = result.fidelity
        metrics.record(result: result, stale: false, inputToVisibleMs: inputToVisible)
        Self.signposter.emitEvent("presented", id: signpostID)

        let textureID = ObjectIdentifier(result.ciImage! as AnyObject)
        DevelopLiveLog.event(
            "publication accepted requestID=\(result.requestID.uuidString) recipeRevision=\(result.recipeRevision) "
                + "textureID=\(textureID) inputToVisibleMs=\(inputToVisible.map { String(format: "%.1f", $0) } ?? "-")"
        )
    }

    // MARK: - Memory pressure

    private func installMemoryPressureHandler() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let critical = source.data.contains(.critical)
            Task { await self.respondToMemoryPressure(critical: critical) }
        }
        source.resume()
        memoryPressureSource = source
    }

    private func respondToMemoryPressure(critical: Bool) async {
        let keep = visiblePhotoID
        // 1. Speculative prefetch, then presentation surfaces of other photos.
        await cache.trimForMemoryPressure(keeping: critical ? keep : nil)
        // 2. Post-look Before/After surfaces for non-visible photos.
        if critical {
            beforeSurface = beforeSurface.filter { $0.key == keep }
            afterSurface = afterSurface.filter { $0.key == keep }
            beforeBitmap = beforeBitmap.filter { $0.key == keep }
            // 3. RAW sessions except the visible one.
            await PreparedRawSessionRegistry.shared.trimForMemoryPressure(keeping: keep)
            // 4. Core Image resource reclamation outside active presentation.
            DevelopRenderGraph.sharedContext.clearCaches()
        }
    }
}
