import AppKit
import Foundation
import Metal

/// One decode owner for contact-sheet, focused-preview, and Metal browse pixels.
///
/// Runtime browse requests are JPEG-only. The service coalesces identical
/// ImageIO work, keeps a byte-bounded LRU, and hands the same decoded CGImage to
/// AppKit and Metal so opening a photograph cannot trigger two disk decodes.
actor BrowsePixelService {
    static let shared = BrowsePixelService()

    nonisolated enum Tier: Int, Sendable {
        case grid = 0
        case focused = 1
        /// Guaranteed-resident small entry for every frame the viewport can
        /// reach; a tile draws it when the grid tier has not landed.
        case floor = 2

        var maxPixelSize: Int {
            switch self {
            case .grid: PhotoImageTier.gridMaxPixelSize
            case .focused: PhotoImageTier.focusedPreviewLongEdge
            case .floor: PhotoImageTier.floorLongEdge
            }
        }
    }

    nonisolated final class Pixel: @unchecked Sendable {
        let cgImage: CGImage
        let nsImage: NSImage
        let decodeMs: Double

        init(cgImage: CGImage, decodeMs: Double) {
            self.cgImage = cgImage
            self.decodeMs = decodeMs
            let scale: CGFloat = 2
            self.nsImage = NSImage(
                cgImage: cgImage,
                size: NSSize(
                    width: CGFloat(cgImage.width) / scale,
                    height: CGFloat(cgImage.height) / scale
                )
            )
        }

        var byteEstimate: Int { cgImage.bytesPerRow * cgImage.height }
    }

    nonisolated struct Diagnostics: Sendable {
        let residentBytes: Int
        let residentCount: Int
        let inflightCount: Int
        let cacheHits: Int
        let cacheMisses: Int
        let floorResidentCount: Int
        let floorBytes: Int
        let floorQueued: Int
        let floorEvicted: Int
        let prefetchIssued: Int
        let prefetchCancelled: Int
        let prefetchActive: Int
    }

    nonisolated private struct Key: Hashable, Sendable {
        let path: String
        let maxPixelSize: Int
    }

    /// The sampling side of the cache: what is resident right now, readable
    /// from any isolation without an actor hop. Scroll must never wait on the
    /// actor to learn that it has nothing to draw — the well and the enqueue
    /// are decided from here. Mirrors `pixels` exactly; written only by the
    /// actor, read from anywhere.
    nonisolated private final class ResidentIndex: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [Key: Pixel] = [:]

        func lookup(_ key: Key) -> Pixel? {
            lock.lock()
            defer { lock.unlock() }
            return entries[key]
        }

        func set(_ pixel: Pixel?, for key: Key) {
            lock.lock()
            defer { lock.unlock() }
            entries[key] = pixel
        }

        func removeAll() {
            lock.lock()
            defer { lock.unlock() }
            entries.removeAll()
        }
    }

    nonisolated private let residentIndex = ResidentIndex()

    private struct Inflight {
        let id: UUID
        let epoch: UInt64
        let task: Task<Pixel?, Never>
    }

    private var pixels: [Key: Pixel] = [:]
    private var order: [Key] = []
    private var residentBytes = 0
    private var inflight: [Key: Inflight] = [:]
    private var epoch: UInt64 = 0
    private var pinnedPaths: Set<String> = []
    private var cacheHits = 0
    private var cacheMisses = 0

    // MARK: Floor tier
    //
    // Its own store, outside the LRU: the floor is evicted by distance from the
    // viewport, never by how recently a tile drew it, so a flick to the far end
    // of the shoot cannot push out what the reader is about to scroll back to.

    private let floorBudgetBytes: Int
    private var floorPixels: [String: Pixel] = [:]
    private var floorBytes = 0
    private var floorEvicted = 0
    /// Shoot order by path — the distance metric.
    private var scrollIndex: [String: Int] = [:]
    private var scrollPaths: [String] = []
    private var viewportCenter = 0
    /// Paths waiting for a floor decode, nearest first. Re-sorted whenever the
    /// centre moves, so a stale far-away request is never ahead of a near one.
    private var floorQueue: [String] = []
    private var floorInflight: Set<String> = []
    private var floorGeneration: UInt64 = 0

    // MARK: Velocity prefetch (grid tier)
    //
    // The tracker hands over a window: paths to warm ahead of the cursor, in
    // issue order, and the set to keep. Prefetch outside the keep set is
    // cancelled — a task cancelled before its decode started costs nothing,
    // which is the point of cancelling behind a flick.

    private var gridPrefetchTasks: [String: Task<Void, Never>] = [:]
    private var prefetchIssued = 0
    private var prefetchCancelled = 0

    init(floorBudgetBytes: Int = PhotoImageCacheBudget.floorCeilingBytes) {
        self.floorBudgetBytes = floorBudgetBytes
    }

    nonisolated private static let rawExtensions: Set<String> = [
        "ARW", "CR2", "CR3", "NEF", "RAF", "DNG", "ORF", "RW2", "PEF", "SRW", "3FR", "IIQ",
    ]

    func pinFocused(paths: [String]) {
        pinnedPaths = Set(paths)
    }

    func clearFocusedPin() {
        pinnedPaths.removeAll()
    }

    /// Already-decoded pixels for `path` at `tier`, or nil — never a decode,
    /// never a wait. Does not touch the LRU: sampling is not use.
    nonisolated func residentPixel(path: String, tier: Tier) -> Pixel? {
        residentIndex.lookup(Key(path: path, maxPixelSize: tier.maxPixelSize))
    }

    nonisolated func isResident(path: String, tier: Tier) -> Bool {
        residentPixel(path: path, tier: tier) != nil
    }

    func image(path: String, tier: Tier) async -> NSImage? {
        await pixel(path: path, tier: tier)?.nsImage
    }

    func image(path: String, maxPixelSize: Int) async -> NSImage? {
        await pixel(path: path, maxPixelSize: maxPixelSize)?.nsImage
    }

    func pixel(path: String, tier: Tier) async -> Pixel? {
        await pixel(path: path, maxPixelSize: tier.maxPixelSize, priority: tier == .focused ? .userInitiated : .utility)
    }

    func pixel(path: String, maxPixelSize: Int) async -> Pixel? {
        await pixel(path: path, maxPixelSize: maxPixelSize, priority: .userInitiated)
    }

    private func pixel(
        path: String,
        maxPixelSize: Int,
        priority: TaskPriority
    ) async -> Pixel? {
        let key = Key(path: path, maxPixelSize: maxPixelSize)
        if let hit = pixels[key] {
            cacheHits &+= 1
            touch(key)
            LatencyMetrics.record("browse.pixel.cache_hit", milliseconds: 0)
            return hit
        }
        if let pending = inflight[key] {
            let decoded = await pending.task.value
            guard pending.epoch == epoch else { return nil }
            return decoded
        }

        // Cancelled before the decode started — behind a flick, or a window
        // that moved on. Costs nothing, which is why cancelling is worth it.
        guard !Task.isCancelled else { return nil }

        cacheMisses &+= 1
        let requestID = UUID()
        let requestEpoch = epoch
        let task = Task.detached(priority: priority) {
            Self.decode(path: path, maxPixelSize: maxPixelSize)
        }
        inflight[key] = Inflight(id: requestID, epoch: requestEpoch, task: task)
        let decoded = await task.value
        if inflight[key]?.id == requestID {
            inflight[key] = nil
        }
        guard requestEpoch == epoch, let decoded else { return nil }
        store(decoded, for: key)
        LatencyMetrics.record("browse.pixel.decode_ms", milliseconds: decoded.decodeMs)
        return decoded
    }

    /// Decode once and upload the same pixels to the shared Metal pool.
    func prepareTexture(
        assetID: UUID,
        path: String,
        tier: Tier,
        generation: UInt64,
        distanceBias: Int = 0
    ) async {
        if let info = MetalPreviewPool.shared.textureInfo(for: assetID),
           generation == 0 || info.generation == generation {
            return
        }
        guard let decoded = await pixel(path: path, tier: tier) else { return }
        _ = await Task.detached(priority: tier == .focused ? .userInitiated : .utility) {
            MetalPreviewPool.shared.upload(
                id: assetID,
                decoded: decoded.cgImage,
                distanceBias: distanceBias,
                generation: generation,
                decodeMs: decoded.decodeMs
            )
        }.value
    }

    func prefetch(_ requests: [(assetID: UUID, path: String)], tier: Tier) {
        prefetch(paths: requests.map(\.path), maxPixelSize: tier.maxPixelSize)
    }

    func prefetch(paths: [String], tier: Tier) {
        prefetch(paths: paths, maxPixelSize: tier.maxPixelSize)
    }

    func prefetch(paths: [String], maxPixelSize: Int) {
        for path in Set(paths) {
            Task(priority: .utility) {
                _ = await pixel(path: path, maxPixelSize: maxPixelSize, priority: .utility)
            }
        }
    }

    func trimForMemoryPressure() {
        for key in order where !pinnedPaths.contains(key.path) {
            remove(key)
        }
        // The floor is what keeps scroll honest under pressure; halve it by
        // distance rather than drop it.
        evictFloor(toBytes: floorBudgetBytes / 2)
    }

    // MARK: - Velocity prefetch

    /// Warm `ahead` at the grid tier in that order; cancel any prefetch whose
    /// path is not in `keep`. Called by the tracker whenever the window it
    /// computes changes, so a flick that reverses cancels its own wake.
    func setGridPrefetchWindow(ahead: [String], keep: Set<String>) {
        for (path, task) in gridPrefetchTasks where !keep.contains(path) {
            task.cancel()
            gridPrefetchTasks[path] = nil
            prefetchCancelled += 1
        }
        let size = Tier.grid.maxPixelSize
        for path in ahead {
            let key = Key(path: path, maxPixelSize: size)
            guard pixels[key] == nil, gridPrefetchTasks[path] == nil else { continue }
            prefetchIssued += 1
            gridPrefetchTasks[path] = Task(priority: .utility) { [weak self] in
                guard let self else { return }
                _ = await self.pixel(path: path, maxPixelSize: size, priority: .utility)
                await self.gridPrefetchFinished(path: path)
            }
        }
    }

    private func gridPrefetchFinished(path: String) {
        gridPrefetchTasks[path] = nil
    }

    // MARK: - Floor tier

    /// The shoot in scroll order. Distances are measured along it. Paths not
    /// in the new order lose their floor entry; the queue is rebuilt from the
    /// current centre.
    func setScrollOrder(paths: [String]) {
        guard paths != scrollPaths else { return }
        scrollPaths = paths
        var index: [String: Int] = [:]
        for (offset, path) in paths.enumerated() where index[path] == nil {
            index[path] = offset
        }
        scrollIndex = index
        for path in floorPixels.keys where index[path] == nil {
            removeFloor(path)
        }
        floorGeneration &+= 1
        rebuildFloorQueue()
        pumpFloor()
    }

    /// Where the viewport is, as an index into the scroll order. Cheap enough
    /// to call on every appearance; the queue is re-sorted only when it moves.
    func setViewportCenter(index: Int) {
        guard index != viewportCenter else { return }
        viewportCenter = index
        rebuildFloorQueue()
        evictFloor(toBytes: floorBudgetBytes)
        pumpFloor()
    }

    private func distance(_ path: String) -> Int {
        guard let index = scrollIndex[path] else { return .max }
        return abs(index - viewportCenter)
    }

    /// The floor is the nearest K frames, K being what the budget holds at the
    /// size entries have actually turned out to be (a 3:2 estimate until one
    /// has landed). Residents outside that set are evicted here, before the
    /// budget forces it, so the floor is always the nearest frames and never
    /// "the nearest plus whatever happened to fit".
    private func rebuildFloorQueue() {
        let estimate = PhotoImageTier.floorLongEdge * (PhotoImageTier.floorLongEdge * 2 / 3) * 4
        let perEntry = floorPixels.isEmpty ? estimate : max(1, floorBytes / floorPixels.count)
        let wantedCount = max(1, floorBudgetBytes / perEntry)
        let wanted = scrollPaths.sorted { distance($0) < distance($1) }.prefix(wantedCount)
        let wantedSet = Set(wanted)
        for path in floorPixels.keys where !wantedSet.contains(path) {
            removeFloor(path)
            floorEvicted += 1
        }
        floorQueue = wanted.filter { floorPixels[$0] == nil && !floorInflight.contains($0) }
    }

    private func pumpFloor() {
        while floorInflight.count < PhotoImageCacheBudget.floorDecodeWidth, !floorQueue.isEmpty {
            let path = floorQueue.removeFirst()
            floorInflight.insert(path)
            let generation = floorGeneration
            let size = Tier.floor.maxPixelSize
            Task.detached(priority: .utility) { [weak self] in
                let decoded = Self.decode(path: path, maxPixelSize: size)
                await self?.floorDecodeFinished(path: path, pixel: decoded, generation: generation)
            }
        }
    }

    private func floorDecodeFinished(path: String, pixel: Pixel?, generation: UInt64) {
        floorInflight.remove(path)
        defer { pumpFloor() }
        guard generation == floorGeneration, let pixel, scrollIndex[path] != nil else { return }
        storeFloor(pixel, for: path)
        LatencyMetrics.record("browse.floor.decode_ms", milliseconds: pixel.decodeMs)
    }

    private func storeFloor(_ pixel: Pixel, for path: String) {
        if let previous = floorPixels[path] {
            floorBytes -= previous.byteEstimate
        }
        floorPixels[path] = pixel
        floorBytes += pixel.byteEstimate
        residentIndex.set(pixel, for: Key(path: path, maxPixelSize: Tier.floor.maxPixelSize))
        evictFloor(toBytes: floorBudgetBytes)
    }

    /// Farthest from the viewport goes first. The entry just stored can be the
    /// one evicted, if it is the farthest — that is the contract, not a bug.
    private func evictFloor(toBytes budget: Int) {
        while floorBytes > budget,
              let farthest = floorPixels.keys.max(by: { distance($0) < distance($1) }) {
            removeFloor(farthest)
            floorEvicted += 1
        }
    }

    private func removeFloor(_ path: String) {
        if let removed = floorPixels.removeValue(forKey: path) {
            floorBytes -= removed.byteEstimate
            residentIndex.set(nil, for: Key(path: path, maxPixelSize: Tier.floor.maxPixelSize))
        }
    }

    /// Test seam: the floor's resident paths.
    func floorResidentPaths() -> Set<String> { Set(floorPixels.keys) }

    /// Harness seam: forget the grid and focused tiers but keep the floor,
    /// the order and the window — a cold LRU over a warm floor, which is the
    /// state a long shoot is in after a memory-pressure trim.
    func dropGridTierForMeasurement() {
        for (path, task) in gridPrefetchTasks {
            task.cancel()
            gridPrefetchTasks[path] = nil
        }
        for key in order { remove(key) }
        order.removeAll()
    }

    func removeAll() {
        epoch &+= 1
        inflight.values.forEach { $0.task.cancel() }
        inflight.removeAll()
        gridPrefetchTasks.values.forEach { $0.cancel() }
        gridPrefetchTasks.removeAll()
        pixels.removeAll()
        order.removeAll()
        pinnedPaths.removeAll()
        residentBytes = 0
        floorGeneration &+= 1
        floorQueue.removeAll()
        floorPixels.removeAll()
        floorBytes = 0
        scrollPaths.removeAll()
        scrollIndex.removeAll()
        residentIndex.removeAll()
    }

    func diagnostics() -> Diagnostics {
        Diagnostics(
            residentBytes: residentBytes,
            residentCount: pixels.count,
            inflightCount: inflight.count,
            cacheHits: cacheHits,
            cacheMisses: cacheMisses,
            floorResidentCount: floorPixels.count,
            floorBytes: floorBytes,
            floorQueued: floorQueue.count + floorInflight.count,
            floorEvicted: floorEvicted,
            prefetchIssued: prefetchIssued,
            prefetchCancelled: prefetchCancelled,
            prefetchActive: gridPrefetchTasks.count
        )
    }

    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func store(_ pixel: Pixel, for key: Key) {
        if let previous = pixels[key] {
            residentBytes -= previous.byteEstimate
        }
        pixels[key] = pixel
        residentIndex.set(pixel, for: key)
        residentBytes += pixel.byteEstimate
        touch(key)

        while residentBytes > PhotoImageCacheBudget.totalCeilingBytes,
              let candidate = order.first(where: { !pinnedPaths.contains($0.path) }) {
            remove(candidate)
        }
    }

    private func remove(_ key: Key) {
        order.removeAll { $0 == key }
        if let removed = pixels.removeValue(forKey: key) {
            residentBytes -= removed.byteEstimate
            residentIndex.set(nil, for: key)
        }
    }

    nonisolated private static func decode(path: String, maxPixelSize: Int) -> Pixel? {
        autoreleasepool {
            let url = URL(fileURLWithPath: path)
            let ext = url.pathExtension.uppercased()
            // PhotoRecord preview candidates may deliberately fall back to the
            // source path. Decline that candidate; BrowsePixelService must never
            // demosaic RAW, but a missing JPEG tier is not a programmer error.
            guard !rawExtensions.contains(ext) else { return nil }
            guard FileManager.default.fileExists(atPath: path) else { return nil }

            let started = CFAbsoluteTimeGetCurrent()
            guard let image = OrientedDisplayImage.cgImage(
                at: url,
                maxPixelSize: maxPixelSize
            ) else { return nil }
            return Pixel(
                cgImage: image,
                decodeMs: (CFAbsoluteTimeGetCurrent() - started) * 1000
            )
        }
    }
}
