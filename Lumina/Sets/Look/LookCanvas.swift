import AppKit
import CoreImage
import Metal
import MetalKit
import QuartzCore
import os

/// The Edit canvas (roadmap addendum §2): a Metal view laid over the page's canvas rect. The
/// page keeps drawing the filmstrip, sliders and facts; this view is pixels only, takes no
/// input, and is hidden whenever Edit is not the active step. The look stages render straight
/// into the drawable through `CIRenderDestination`: no readback, no JPEG, no image decode on the
/// slider path. It is the one place the app draws over the page (AGENTS.md).
@MainActor
final class LookCanvasView: MTKView {
    /// Never hit: every click and scroll reaches the page underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }
    override var isOpaque: Bool { false }
}

/// Owns the overlay, its bases and tiles, the schedule and the display link; the bridge talks to
/// it and the probe measures it. Without a Metal device (or a view) the controller still runs
/// the schedule for the image fallback path (`lumina://render`), which plumbing drives.
@MainActor
final class LookCanvasController: NSObject {
    enum Path: String, Codable { case native, image }

    struct Stats: Codable {
        var path = "image"
        var visible = false
        var rel: String? = nil
        var canvas = [0, 0]
        var dpr = 1.0
        var schedule = LookCanvasSchedule.Stats()
        var bases = LookBases.Stats()
        var tiles = LookRegionTiles.Stats()
        /// Look submit (the page's clock) → drawable presented, ms, newest first, at most 600.
        var latencyMs: [Double] = []
        var latencyP50 = 0.0
        var latencyP95 = 0.0
        var latencyMax = 0.0
        /// Presents the canvas missed during a drag: `missedVsyncs + busyTicks`.
        var droppedFrames = 0
        /// Refreshes skipped between two display-link ticks (their vsync timestamps at least 1.75
        /// frames apart) while a look had been waiting since before the skipped refresh. A ProMotion
        /// panel stretching a frame (12.5 or 20.8 ms at a 120 Hz link) with nothing new to show is
        /// the display's cadence, not a miss; those gaps are traced as idle, not counted. A look
        /// the page emitted before a skipped refresh but that arrived only after the gap (the main
        /// thread was held, so the message waited too) counts the refreshes after it was emitted.
        var missedVsyncs = 0
        /// Ticks where a newer look was waiting but the previous render was still in flight.
        var busyTicks = 0
        var ticks = 0
        var renders = 0
        var renderErrors = 0
        var lastRenderMs = 0.0
        var lastRestMs = 0.0             // drag end → the rest render presented
        var lastRestTier = ""
        var region = false
        var regionDecoder = 0
        var refining = false
        /// The loupe's region could not be refined (not a RAW, or every decoder version failed): the
        /// scenario waits on `region || regionFailed`.
        var regionFailed = false
        var regionError = ""
        var facts = ""
        var decoderFallbacks: [String] = []
        var slowed = false
        /// The stage graphs compiled ahead of the user (`LookWarmPlan`), and the drawable's first
        /// render of each set of stages since the last reset: its time on the main thread.
        var warm = LookWarmPlan.Stats()
        var firstRenders: [LookWarmPlan.FirstRender] = []
        /// The last events on the canvas clock (`LookTrace`): what ran around a dropped frame.
        var trace: [LookTrace.Event] = []
    }

    struct Neighbour { let rel: String; let url: URL; let preview: LookBases.PreviewFallback? }

    let path: Path
    let pipeline: LookPipeline
    /// Background renders (bases, tiles, rest statistics); the drawable renders on `pipeline`.
    let work: LookPipeline
    /// The warm-up renders (`LookWarmPlan`) have a context of their own: compiled programs are
    /// shared across contexts on the device, and a warm-up must wait for neither a neighbour's
    /// RAW develop on `work` nor a frame on `pipeline`.
    let warm: LookPipeline
    private var warmPlan: LookWarmPlan
    private var warmRunning = false
    private var warmTarget: MTLTexture?
    private let warmQueue = DispatchQueue(label: "lumina.look.warm", qos: .utility)
    private let statsQueue = DispatchQueue(label: "lumina.look.reststats", qos: .utility)
    private var neighbours: [(key: LookBases.Key, url: URL, look: Look, preview: LookBases.PreviewFallback?)] = []
    private var prefetchIssued = false
    private var basePresented = false
    let bases: LookBases
    let tiles: LookRegionTiles
    let view: LookCanvasView?
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private var displaySpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private var displaySpaceName = "sRGB"
    private var link: CADisplayLink?
    private var schedule = LookCanvasSchedule()
    private var stats = Stats()
    private var latencies: [Double] = []
    private var lastTick: CFTimeInterval = 0
    private var dragging = false
    private var dragEndAt: CFTimeInterval?
    private var zoom: LookCanvasSchedule.ROI?
    private var current: (rel: String, url: URL, key: LookBases.Key, look: Look, entry: LookBases.Entry?, preview: LookBases.PreviewFallback?, decoder: Int?, regionDecoder: Int?)?
    private var region: LookRegionTiles.Region?
    private var regionSeq = 0
    private var loupe: (on: Bool, roi: LookCanvasSchedule.ROI?) = (false, nil)
    private var loupeStillTimer: Timer?
    private var refiningTimer: Timer?
    private var pressure: DispatchSourceMemoryPressure?
    private var fallbackVersions: [String: Int] = [:]       // rel → the version to use after a RAW 9 failure
    private var rendering = false
    /// The render in flight's bookkeeping, run once its command buffer completes: from the tick
    /// when the GPU is already done (the completion's hop to the main queue can lose the runloop
    /// race to the display link, which would hold the next look back a frame), else from that hop.
    private var inFlightFinish: ((CFTimeInterval) -> Void)?
    private var renderStartedAt: CFTimeInterval = 0
    /// When the page emitted the oldest look no render has started yet (ms, `now()`), nil when none waits.
    private var waitingSince: Double?
    /// The last gap between two ticks that had no look waiting when it was seen (ms, `now()`).
    private var idleGap: (start: Double, end: Double, frame: Double, skipped: Int)?
    private let gpuDone = GPUDone()
    private var flightSeq = 0
    private var lastPresentedSeq = 0
    private var facts = ""

    /// Facts for the page's facts line ("canvas: native", "raw 9 · region", "refining…").
    var onFacts: ((String) -> Void)?
    /// After a rest render: histogram (64 bins per channel), clipping, and the region's facts.
    var onStats: (([String: Any]) -> Void)?
    /// A file's RAW 9 render failed and the previous version took over (logged once per file).
    var onDecoderFallback: ((String, Int, Int) -> Void)?

    /// `host`: the view the overlay is laid into (above the web view). Nil host or no Metal
    /// device → the image path: the controller answers the bridge with `path == .image`.
    init(pipeline: LookPipeline, host: NSView?) {
        self.pipeline = pipeline
        // Bases, prefetch, region tiles and the rest statistics render on their own context (same
        // Metal device, so the textures are shared): a CIContext serialises its renders, and a
        // neighbour's full RAW develop must never hold up the drawable's render on the main thread.
        let work = (pipeline.device != nil ? try? LookPipeline(rules: pipeline.rules, device: pipeline.device) : nil) ?? pipeline
        self.work = work
        warm = (pipeline.device != nil && host != nil ? try? LookPipeline(rules: pipeline.rules, device: pipeline.device) : nil) ?? work
        // LUMINA_CANVAS_WARM=0 (the probe's "before" measure) leaves every program to its first frame.
        // Debug builds and the probe only; the app's Release build always warms (S4).
        #if DEBUG || LUMINA_TOOLS
        warmPlan = LookWarmPlan(enabled: ProcessInfo.processInfo.environment["LUMINA_CANVAS_WARM"] != "0")
        #else
        warmPlan = LookWarmPlan(enabled: true)
        #endif
        bases = LookBases(pipeline: work)
        tiles = LookRegionTiles(pipeline: work)
        device = pipeline.device
        if let dev = pipeline.device, let host {
            let v = LookCanvasView(frame: .zero, device: dev)
            v.colorPixelFormat = .rgba16Float
            v.framebufferOnly = false
            v.isPaused = true
            v.enableSetNeedsDisplay = false
            v.autoResizeDrawable = false
            v.isHidden = true
            v.layer?.isOpaque = false
            if let layer = v.layer as? CAMetalLayer {
                layer.wantsExtendedDynamicRangeContent = false
                layer.allowsNextDrawableTimeout = true
                layer.maximumDrawableCount = 2
            }
            host.addSubview(v)
            view = v
            commandQueue = dev.makeCommandQueue()
            path = commandQueue == nil ? .image : .native
        } else {
            view = nil
            commandQueue = nil
            path = .image
        }
        super.init()
        stats.path = path.rawValue
        watchMemory()
        updateDisplaySpace()
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateDisplaySpace() }
        }
    }

    // MARK: The page's calls (through the bridge)

    /// Entering Edit for a photo: build its bases (the previous state is dropped), prefetch its
    /// neighbours' at `.utility`. `decoder` is the canvas tier's version, `regionDecoder` the
    /// loupe's (RAW 9 when pinned and present).
    func enter(rel: String, url: URL, look: String, decoder: Int?, regionDecoder: Int?, preview: LookBases.PreviewFallback?, neighbours: [Neighbour]) {
        let parsed = (try? Look.parse(look)) ?? Look()
        let size = canvasPixels()
        let key = LookBases.Key(rel: rel, decoder: decoder, look: parsed, canvas: size)
        if current?.rel != rel { schedule.reset(); region = nil; supersedeRegion(); stats.region = false }
        current = (rel, url, key, parsed, bases.entry(key), preview, decoder, regionDecoder)
        stats.rel = rel
        bases.pin(key)
        ensureBases()
        // The neighbours wait until this photo's base is on screen and the canvas is still.
        self.neighbours = neighbours.map { (key: LookBases.Key(rel: $0.rel, decoder: decoder, look: Look(), canvas: size), url: $0.url, look: Look(), preview: $0.preview) }
        prefetchIssued = false
        basePresented = false
        updatePrefetch()
        _ = schedule.keystroke(look, at: now())
        setFacts()
        kick()
    }

    /// The shoot's decoder map arrived after Edit was entered (it is measured at `.utility` on
    /// shoot open): the photo on the canvas and its neighbours move to the versions it names.
    func setDecoders(decoder: Int?, regionDecoder: Int?) {
        guard let c = current, c.decoder != decoder || c.regionDecoder != regionDecoder else { return }
        let key = LookBases.Key(rel: c.rel, decoder: decoder, look: c.look, canvas: canvasPixels())
        current?.decoder = decoder
        current?.regionDecoder = regionDecoder
        current?.key = key
        current?.entry = bases.entry(key)
        bases.pin(key)
        ensureBases()
        neighbours = neighbours.map { (key: LookBases.Key(rel: $0.key.rel, decoder: decoder, look: Look(), canvas: CGSize(width: $0.key.width, height: $0.key.height)), url: $0.url, look: $0.look, preview: $0.preview) }
        prefetchIssued = false
        basePresented = false
        updatePrefetch()
        if region != nil { region = nil; stats.region = false }
        supersedeRegion()
        if loupe.on { loupe(on: true, roi: loupe.roi) }
        if let l = schedule.presentedLook ?? current?.look.format() { _ = schedule.keystroke(l, at: now()) }
        setFacts()
        kick()
    }

    func leave() {
        current = nil
        schedule.reset()
        region = nil
        supersedeRegion()
        loupe = (false, nil)
        bases.pin(nil)
        warmTarget = nil
        view?.isHidden = true
        stats.visible = false
        stopLink()
    }

    /// The largest drawable edge in px: Metal's texture limit on Apple silicon, and more than
    /// twice an 8K display (7,680).
    nonisolated static var maxDrawableEdge: CGFloat { 16_384 }

    /// A rect `layout` can place: every number finite, the size 0 … `maxDrawableEdge` points, the
    /// origin within ± 2 × that, the pixel ratio above 0 and at most 16.
    nonisolated static func layable(_ rect: CGRect, dpr: CGFloat) -> Bool {
        let o = rect.origin, s = rect.size
        guard o.x.isFinite, o.y.isFinite, s.width.isFinite, s.height.isFinite, dpr.isFinite else { return false }
        return s.width >= 0 && s.height >= 0 && s.width <= maxDrawableEdge && s.height <= maxDrawableEdge
            && abs(o.x) <= 2 * maxDrawableEdge && abs(o.y) <= 2 * maxDrawableEdge && dpr > 0 && dpr <= 16
    }

    /// The page's canvas rect in CSS px (origin top-left of the web view) and whether Edit is showing.
    func layout(rect: CGRect, visible: Bool, dpr: CGFloat) {
        // Not a rect a display can hold (not finite, negative, absurdly large): the canvas hides and
        // keeps the size it had. `Int(_:)` on such a number stops the app (Q4-hostile F2).
        guard Self.layable(rect, dpr: dpr) else {
            view?.isHidden = true
            stats.visible = false
            stopLink()
            return
        }
        stats.dpr = Double(dpr)
        guard let view, let host = view.superview else { return }
        let r = NSRect(x: rect.minX, y: host.bounds.height - rect.minY - rect.height, width: rect.width, height: rect.height).integral
        // Never past Metal's largest texture edge (a 16,384 px rect at 2× would ask for twice that).
        let px = CGSize(width: min(Self.maxDrawableEdge, max(1, (rect.width * dpr).rounded())), height: min(Self.maxDrawableEdge, max(1, (rect.height * dpr).rounded())))
        let sizeChanged = view.frame.size != r.size || view.drawableSize != px
        view.frame = r
        view.drawableSize = px
        stats.canvas = [Int(px.width), Int(px.height)]
        let show = visible && rect.width >= 2 && rect.height >= 2
        view.isHidden = !show
        stats.visible = show
        if show { startLink() } else { stopLink() }
        if sizeChanged, let c = current {
            // A new canvas size means new bases (keyed by it); the old ones stay cached until evicted.
            let key = LookBases.Key(rel: c.rel, decoder: c.decoder, look: c.look, canvas: px)
            current?.key = key
            current?.entry = bases.entry(key)
            bases.pin(key)
            ensureBases()
            if let l = schedule.presentedLook ?? current?.look.format() { _ = schedule.keystroke(l, at: now()) }
        }
        kick()
    }

    /// A slider value. `t` is the page's wall clock for the event (ms since the epoch) so the
    /// latency to the presented frame can be measured across the two processes.
    func look(_ text: String, drag: Bool, key: Bool, roi: LookCanvasSchedule.ROI?, at t: Double?, pageSeq: Int = 0) -> Int {
        guard var c = current else { return 0 }
        let parsed = (try? Look.parse(text)) ?? c.look
        let base = LookBases.Key(rel: c.rel, decoder: c.decoder, look: parsed, canvas: canvasPixels())
        if base != c.key {
            c.key = base; c.entry = bases.entry(base); c.look = parsed; current = c
            bases.pin(base)
            ensureBases()
        } else { current?.look = parsed }
        zoom = roi
        // The page's clock → ours: the smallest arrival − emit gap seen is the offset within a message's transit.
        let arrived = now()
        if let t, t > 0 { clockOffset = min(clockOffset, arrived - t) }
        // When the page emitted it, on our clock (never earlier than the truth: the offset includes
        // the fastest transit seen). A main thread that sat through refreshes delivers the looks
        // emitted meanwhile only afterwards; they were waiting all the same.
        let emitted = t.flatMap { $0 > 0 && clockOffset < Double.greatestFiniteMagnitude ? min(arrived, $0 + clockOffset) : nil } ?? arrived
        if let g = idleGap {
            idleGap = nil
            // The skipped refreshes that came after the look was emitted.
            let missed = dragging ? (1...g.skipped).filter { g.start + Double($0) * g.frame >= emitted }.count : 0
            if missed > 0 {
                stats.missedVsyncs += missed; stats.droppedFrames += missed
                LookTrace.mark("missed vsync ×\(missed), a look emitted \(Int((g.end - emitted).rounded())) ms before the gap ended arrived after it (main thread held)", ms: g.end - g.start, at: g.start)
            }
        }
        if !schedule.pending { waitingSince = emitted }
        let seq = key ? schedule.keystroke(text, at: arrived, pageSeq: pageSeq, pageAt: t ?? 0) : schedule.submit(text, at: arrived, roi: roi, pageSeq: pageSeq, pageAt: t ?? 0)
        kick()
        return seq
    }

    /// Our clock (ms, `CACurrentMediaTime`) minus the page's (`performance.now()`), estimated from
    /// message transit: the true offset is at most this.
    private var clockOffset = Double.greatestFiniteMagnitude

    /// A render reached the screen: the page's `seq` for the look it shows (`luminaPresented`).
    var onPresented: ((Int) -> Void)?

    func dragStart() { LookTrace.mark("dragStart"); dragging = true; dragEndAt = nil; idleGap = nil; updatePrefetch(); schedule.dragStart(at: now()); kick() }
    func dragEnd() { LookTrace.mark("dragEnd"); dragging = false; dragEndAt = CACurrentMediaTime(); schedule.dragEnd(at: now()); kick() }

    /// 100 % with G held: RAW 9 on the visible region (RAW 9 §2). Waits for stillness when the
    /// Mac is hot or on Low Power; never disabled.
    func loupe(on: Bool, roi: LookCanvasSchedule.ROI?) {
        loupe = (on, roi)
        loupeStillTimer?.invalidate(); loupeStillTimer = nil
        stats.regionFailed = false; stats.regionError = ""
        guard on, let roi, let c = current else {
            if !on { region = nil; supersedeRegion(); stats.region = false; stats.refining = false; setFacts(); kickRest(); updatePrefetch() }
            return
        }
        // No RAW decoder for this file (the embedded JPEG stands in, or the body offers none): nothing to refine.
        guard let decoder = c.regionDecoder ?? c.decoder ?? LookPipeline.supportedDecoderVersions(url: c.url).max(), c.entry?.source != "jpeg" else {
            stats.regionFailed = true; stats.regionError = "not a RAW Core Image decodes: no region refinement"
            setFacts()
            return
        }
        let delay = LookRawPolicy.regionDelayMs(thermalState: LookDecoderProbe.thermalLevel(ProcessInfo.processInfo.thermalState), lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        stats.slowed = delay > 0
        let rel = c.rel, url = c.url
        if delay > 0 {
            loupeStillTimer = Timer.scheduledTimer(withTimeInterval: delay / 1000, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.refine(rel: rel, url: url, decoder: decoder, roi: roi) }
            }
        } else {
            refine(rel: rel, url: url, decoder: decoder, roi: roi)
        }
    }

    private func refine(rel: String, url: URL, decoder: Int, roi: LookCanvasSchedule.ROI) {
        guard loupe.on, current?.rel == rel else { return }
        let version = fallbackVersions[rel] ?? decoder
        supersedeRegion()
        let seq = regionSeq
        regionBusy = true
        updatePrefetch()
        refiningTimer?.invalidate()
        refiningTimer = Timer.scheduledTimer(withTimeInterval: LookRawPolicy.refiningAfterMs / 1000, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { guard let self, self.regionSeq == seq else { return }; self.stats.refining = true; self.setFacts() }
        }
        tiles.region(rel: rel, url: url, decoder: version, nr: current?.look.nr, roi: roi, rot: current?.look.rot ?? 0, seq: seq, first: { [weak self] ms in
            guard let self, self.regionSeq == seq else { return }
            if ms <= LookRawPolicy.refiningAfterMs { self.refiningTimer?.invalidate() }
        }, done: { [weak self] r in
            guard let self, self.regionSeq == seq else { return }
            self.refiningTimer?.invalidate()
            self.stats.refining = false
            self.regionBusy = false
            defer { self.updatePrefetch() }
            switch r {
            case .success(let region):
                self.region = region
                self.stats.region = true
                self.stats.regionDecoder = region.decoder
                self.setFacts()
                self.onStats?(["facts": ["sharpness": region.facts.sharpness, "clipHi": region.facts.clipHi, "clipLo": region.facts.clipLo, "source": region.facts.source], "rel": rel, "decoder": region.decoder])
                self.kickRest()
            case .failure(is LookRegionTiles.Cancelled):
                break
            case .failure(let e):
                // A RAW 9 failure: the file re-renders once with the previous version, silently.
                let supported = LookPipeline.supportedDecoderVersions(url: url)
                if self.fallbackVersions[rel] == nil, let prev = LookRawPolicy.fallback(after: version, supported: supported) {
                    self.fallbackVersions[rel] = prev
                    self.stats.decoderFallbacks.append("\(rel): \(version) → \(prev) (\(e))")
                    LuminaLog.canvas.error("RAW decoder \(version, privacy: .public) failed for \(rel, privacy: .private) (\(String(describing: e), privacy: .private)); using \(prev, privacy: .public)")
                    self.onDecoderFallback?(rel, version, prev)
                    self.refine(rel: rel, url: url, decoder: prev, roi: roi)
                } else {
                    self.stats.region = false
                    self.stats.regionFailed = true
                    self.stats.regionError = "\(e)"
                    self.setFacts()
                }
            }
        })
    }

    /// The probe reads these; JSON-safe.
    func snapshot() -> [String: Any] {
        stats.schedule = schedule.stats
        stats.bases = bases.stats
        stats.tiles = tiles.stats
        let sorted = latencies.sorted()
        let q = { (p: Double) -> Double in sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] }
        stats.latencyMs = Array(latencies.suffix(600).reversed())
        stats.latencyP50 = q(0.5); stats.latencyP95 = q(0.95); stats.latencyMax = sorted.last ?? 0
        stats.facts = facts
        stats.warm = warmPlan.stats
        stats.warm.running = warmRunning
        if path == .native, let c = current, let entry = c.entry { stats.warm.pending = warmPlan.jobs(around: c.look, stages: pipeline.rules.lookStages, env: warmEnv(entry)).count }
        stats.trace = LookTrace.events
        guard let data = try? JSONEncoder().encode(stats), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    /// The probe's latency measure starts fresh per drag.
    func resetMeasures() { latencies = []; stats.droppedFrames = 0; stats.missedVsyncs = 0; stats.busyTicks = 0; stats.ticks = 0; stats.renders = 0; stats.renderErrors = 0; stats.firstRenders = [] }

    /// The current look rendered from `base` into a bitmap (the parity probe compares it with the
    /// export at the same size). Nil until the bases exist.
    func renderToImage() -> CGImage? {
        guard let c = current, let e = c.entry else { return nil }
        let img = pipeline.apply(c.look, to: LookPipeline.Developed(image: e.base, asShot: e.asShot, anchor: e.anchor), crop: false)
        return pipeline.context.createCGImage(pipeline.output(img), from: img.extent.integral, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }

    var currentEntry: LookBases.Entry? { current?.entry }
    var currentPreview: LookBases.PreviewFallback? { current?.preview }
    /// The look `renderToImage` renders (the newest the canvas was given).
    var currentLook: String { current?.look.format() ?? "" }

    // MARK: Bases

    private func ensureBases() {
        guard let c = current, c.entry == nil else { return }
        bases.request(c.key, url: c.url, look: c.look, preview: c.preview) { [weak self] r in
            guard let self, let cur = self.current, cur.key == c.key else { return }
            switch r {
            case .success(let e):
                self.current?.entry = e
                self.setFacts()
                self.kick()
                self.updatePrefetch()
            case .failure(let e):
                self.stats.renderErrors += 1
                self.facts = "canvas: \(self.path.rawValue) · can't develop \(c.rel.split(separator: "/").last ?? "") (\(e))"
                self.onFacts?(self.facts)
            }
        }
    }

    // MARK: The display link

    private func startLink() {
        guard link == nil, let view else { return }
        let l = view.displayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        lastTick = 0
    }

    private func stopLink() { link?.invalidate(); link = nil }

    /// An event that may need a frame now: the link ticks on its own while visible; without a
    /// link (image path, hidden) nothing renders here.
    private func kick() { if link == nil, view != nil, stats.visible { startLink() } }

    private func kickRest() { if let l = schedule.presentedLook { _ = schedule.keystroke(l, at: now()) } }

    @objc private func tick(_ l: CADisplayLink) {
        stats.ticks += 1
        let t = l.timestamp
        if dragging, lastTick > 0, l.duration > 0 {
            let skipped = Int(((t - lastTick) / l.duration + 0.25).rounded(.down)) - 1
            if skipped > 0 {
                // Missed only if a look was already waiting when the first skipped refresh came.
                if let w = waitingSince, w <= (lastTick + l.duration) * 1000 {
                    stats.missedVsyncs += skipped; stats.droppedFrames += skipped
                    LookTrace.mark("missed vsync ×\(skipped), a look waiting \(Int((t * 1000 - w).rounded())) ms", ms: (t - lastTick) * 1000, at: lastTick * 1000)
                } else {
                    LookTrace.mark("idle gap (no look waiting)", ms: (t - lastTick) * 1000, at: lastTick * 1000)
                    // Unless the next look to arrive turns out to have been emitted before the gap's first refresh (`look`).
                    idleGap = (lastTick * 1000, t * 1000, l.duration * 1000, skipped)
                }
            }
        }
        drainCompletion()
        if dragging, lastTick > 0, rendering, schedule.pending {
            stats.busyTicks += 1; stats.droppedFrames += 1
            LookTrace.mark("busy tick: GPU still on the render started \(Int(((CACurrentMediaTime() - renderStartedAt) * 1000).rounded())) ms ago", at: t * 1000)
        }
        lastTick = t
        guard !rendering, let c = current, let entry = c.entry, let view, !view.isHidden, let request = schedule.tick(at: now()) else { return }
        let look = (try? Look.parse(request.look)) ?? c.look
        let seen = warmPlan.rendering(look, tier: request.tier, stages: pipeline.rules.lookStages, env: warmEnv(entry))
        let t0 = LookTrace.now()
        render(request, entry: entry, look: look, view: view)
        let ms = LookTrace.now() - t0
        LookTrace.mark("render \(request.tier.rawValue)", ms: ms, at: t0)
        if seen.first {
            // The first frame of a set of stages is where a program compiled on the main thread would show.
            LookTrace.mark("first \(request.tier.rawValue) render of \(seen.stages) (\(seen.warmed ? "warmed" : "not warmed"))", ms: ms, at: t0)
            stats.firstRenders.append(LookWarmPlan.FirstRender(stages: seen.stages, tier: request.tier.rawValue, ms: (ms * 100).rounded() / 100, warmed: seen.warmed, drag: dragging))
            if stats.firstRenders.count > 128 { stats.firstRenders.removeFirst(64) }
        }
    }

    /// The picture for one render: the look's stages on `small` or `base`, fitted into a drawable
    /// of `size` (contain), or the zoomed region filling it. The drawable's render and the warm-up
    /// both build it here, so they compile the same programs. `image` is the look before placing
    /// (the rest statistics read it); `region` the loupe's RAW 9 region when it was used.
    private func compose(_ look: Look, tier: LookCanvasSchedule.Tier, roi: LookCanvasSchedule.ROI?, entry: LookBases.Entry, size: CGSize) -> (placed: CIImage, image: CIImage, region: LookRegionTiles.Region?) {
        let src: CIImage, srcSize: CGSize
        if tier == .small { src = entry.small; srcSize = entry.smallSize } else { src = entry.base; srcSize = entry.baseSize }
        var image = pipeline.apply(look, to: LookPipeline.Developed(image: src, asShot: entry.asShot, anchor: entry.anchor), crop: false)
        // Where the photo goes: fit the canvas (contain), or the zoomed region filling it.
        let dw = size.width, dh = size.height
        var visible = CGRect(origin: .zero, size: srcSize)
        if let z = zoom ?? roi, !z.isWhole {
            visible = CGRect(x: z.x * srcSize.width, y: (1 - z.y - z.h) * srcSize.height, width: z.w * srcSize.width, height: z.h * srcSize.height)
            if tier == .small, let roi, !roi.isWhole { image = image.cropped(to: visible) }
        }
        // The loupe's RAW 9 region, when it covers the visible part, replaces the base there.
        var region: LookRegionTiles.Region?
        if tier == .base, let reg = self.region, reg.rel == current?.rel, let z = zoom, reg.roi == z, reg.rot == look.rot {
            region = reg
            let regionImage = pipeline.apply(look, to: LookPipeline.Developed(image: reg.image, asShot: reg.asShot, anchor: reg.anchor), crop: false)
            let vis = CGRect(x: z.x * reg.photoSize.width, y: (1 - z.y - z.h) * reg.photoSize.height, width: z.w * reg.photoSize.width, height: z.h * reg.photoSize.height)
            image = regionImage.cropped(to: vis.intersection(reg.rect))
            visible = vis
        }
        let s = min(dw / max(1, visible.width), dh / max(1, visible.height))
        let out = image.transformed(by: CGAffineTransform(translationX: -visible.minX, y: -visible.minY).concatenating(CGAffineTransform(scaleX: s, y: s)))
        let ox = ((dw - visible.width * s) / 2).rounded(), oy = ((dh - visible.height * s) / 2).rounded()
        return (pipeline.output(out).transformed(by: CGAffineTransform(translationX: ox, y: oy)), image, region)
    }

    private func render(_ r: LookCanvasSchedule.Request, entry: LookBases.Entry, look: Look, view: LookCanvasView) {
        let waited = LookTrace.now()
        guard let queue = commandQueue, let layer = view.layer as? CAMetalLayer, let drawable = layer.nextDrawable() else {
            schedule.failed(r); return
        }
        // Both drawables still queued for a refresh: the wait is the display's, not the look's.
        if LookTrace.now() - waited > 2 { LookTrace.mark("nextDrawable waited", ms: LookTrace.now() - waited, at: waited) }
        rendering = true
        renderStartedAt = CACurrentMediaTime()
        flightSeq = r.seq
        let t0 = CACurrentMediaTime()
        let dw = CGFloat(drawable.texture.width), dh = CGFloat(drawable.texture.height)
        let (placed, image, region) = compose(look, tier: r.tier, roi: r.roi, entry: entry, size: CGSize(width: dw, height: dh))
        guard let cb = queue.makeCommandBuffer() else { schedule.failed(r); rendering = false; return }
        let dest = CIRenderDestination(mtlTexture: drawable.texture, commandBuffer: cb)
        dest.colorSpace = displaySpace
        dest.alphaMode = .premultiplied
        do {
            try pipeline.context.startTask(toClear: dest)
            try pipeline.context.startTask(toRender: placed, from: CGRect(x: 0, y: 0, width: dw, height: dh), to: dest, at: .zero)
        } catch {
            stats.renderErrors += 1
            schedule.failed(r); rendering = false
            return
        }
        let wasDragEnd = dragEndAt
        // The frame's time on our clock: the GPU end time when the command buffer completes, replaced
        // by the drawable's presented time when the window really presents (it is 0 when it doesn't,
        // e.g. the probe's transparent window). Latency = frame − the look's page time + the clock offset.
        drawable.addPresentedHandler { [weak self] d in
            let presented = d.presentedTime
            guard presented > 0 else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.frameShown(r, at: presented, dragEnd: wasDragEnd, presented: true) }
            }
        }
        inFlightFinish = { [weak self] end in
            guard let self else { return }
            self.rendering = false
            self.stats.renders += 1
            self.stats.lastRenderMs = (CACurrentMediaTime() - t0) * 1000
            self.stats.lastRestTier = r.tier.rawValue
            _ = self.schedule.finished(r)
            self.frameShown(r, at: end, dragEnd: wasDragEnd, presented: false)
            if r.stats { self.restStats(image, region: region, seq: r.pageSeq) }
        }
        let done = gpuDone
        cb.addCompletedHandler { [weak self] buffer in
            done.set(buffer.gpuEndTime > 0 ? buffer.gpuEndTime : CACurrentMediaTime())
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.drainCompletion() } }
        }
        cb.present(drawable)
        cb.commit()
        waitingSince = nil
    }

    /// Runs the finished render's bookkeeping once, whichever of the tick or the completion's
    /// main-queue hop gets here first.
    private func drainCompletion() {
        guard let end = gpuDone.take(), let finish = inFlightFinish else { return }
        inFlightFinish = nil
        finish(end)
    }

    private var sampleIndex: [Int: Int] = [:]        // render seq → its latency sample's index

    /// A render's frame time (seconds on our clock): records the latency sample (once per render,
    /// the presented time overriding the GPU end time), the rest render's delay after drag end, and
    /// tells the page which look is on screen.
    private func frameShown(_ r: LookCanvasSchedule.Request, at frame: CFTimeInterval, dragEnd: CFTimeInterval?, presented: Bool) {
        let frameMs = frame * 1000
        if r.pageAt > 0, clockOffset < Double.greatestFiniteMagnitude {
            let latency = frameMs - (r.pageAt + clockOffset)
            if let i = sampleIndex[r.seq], i < latencies.count { latencies[i] = latency }
            else { latencies.append(latency); sampleIndex[r.seq] = latencies.count - 1 }
            if latencies.count > 4000 { latencies.removeFirst(2000); sampleIndex = [:] }
        }
        if r.tier == .base, let de = dragEnd, frame >= de { stats.lastRestMs = (frame - de) * 1000; dragEndAt = nil }
        if r.tier == .base, !basePresented { basePresented = true; updatePrefetch() }
        else if r.tier == .base, !dragging { updatePrefetch() }
        if r.seq > lastPresentedSeq { lastPresentedSeq = r.seq; if r.pageSeq > 0 { onPresented?(r.pageSeq) } }
    }

    /// Histogram and clipping, on rest renders only (§3): one CIAreaHistogram pass, 256 bins
    /// (Prompt 1's `luminaHistogram`), read back on the work context off the main thread; the
    /// page hears on the main thread.
    private func restStats(_ image: CIImage, region: LookRegionTiles.Region?, seq: Int) {
        let work = self.work
        statsQueue.async { [weak self] in
            guard let out = LookTrace.span("restStats", { Self.histogram(image, region: region, seq: seq, context: work.context) }) else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.onStats?(out) } }
        }
    }

    nonisolated private static func histogram(_ image: CIImage, region: LookRegionTiles.Region?, seq: Int, context: CIContext) -> [String: Any]? {
        let extent = image.extent
        guard !extent.isEmpty, !extent.isInfinite else { return nil }
        let bins = 256
        let hist = image.applyingFilter("CIAreaHistogram", parameters: [kCIInputExtentKey: CIVector(cgRect: extent), "inputCount": bins, "inputScale": 1.0])
        var px = [Float](repeating: 0, count: bins * 4)
        context.render(hist, toBitmap: &px, rowBytes: bins * 16, bounds: CGRect(x: 0, y: 0, width: bins, height: 1), format: .RGBAf, colorSpace: nil)
        var r: [Double] = [], g: [Double] = [], b: [Double] = []
        for i in 0..<bins { r.append(Double(px[4 * i])); g.append(Double(px[4 * i + 1])); b.append(Double(px[4 * i + 2])) }
        let total = max(1e-9, r.reduce(0, +))
        var out: [String: Any] = ["seq": seq, "histogram": ["r": r, "g": g, "b": b], "clipHi": (r[bins - 1] + g[bins - 1] + b[bins - 1]) / (3 * total), "clipLo": (r[0] + g[0] + b[0]) / (3 * total), "source": region == nil ? "jpeg" : "raw9-region"]
        if let region { out["facts"] = ["sharpness": region.facts.sharpness, "clipHi": region.facts.clipHi, "clipLo": region.facts.clipLo, "source": region.facts.source] }
        return out
    }

    // MARK: Prefetch and region numbering

    private var regionBusy = false

    /// The neighbours' bases run only while nobody waits on the canvas: after this photo's base
    /// is on screen (built, on the image path), never during a drag or while the loupe's region renders. A build already
    /// running finishes (on the work context, so it never holds up a drawable); the next waits.
    private func updatePrefetch() {
        // No drawable on the image path (the page shows lumina://render images): the built base is the cue.
        let hold = dragging || regionBusy || current?.entry == nil || (view != nil && !basePresented)
        bases.prefetchPaused = hold
        if !hold, !prefetchIssued, !neighbours.isEmpty {
            prefetchIssued = true
            LookTrace.mark("prefetch released")
            bases.prefetch(neighbours)
        }
        updateWarm(hold: hold)
    }

    // MARK: Warm-up (LookWarmPlan)

    /// What the canvas's programs depend on besides the set of stages: the two source sizes (the
    /// blurs' radii follow them), the drawable's size, the display's colour space, zoomed or not.
    private func warmEnv(_ entry: LookBases.Entry) -> String {
        let d = view?.drawableSize ?? .zero
        let zoomed = zoom.map { !$0.isWhole } ?? false
        return "\(Int(entry.baseSize.width))x\(Int(entry.baseSize.height))/\(Int(entry.smallSize.width))x\(Int(entry.smallSize.height))>\(Int(d.width))x\(Int(d.height))|\(displaySpaceName)|\(zoomed ? (region != nil ? "region" : "zoom") : "fit")"
    }

    /// One warm-up render at a time, on its own queue and context, into an offscreen texture of
    /// the drawable's size and format: the look on the canvas and each stage switched, both tiers.
    /// Held under the same conditions as the neighbours' prefetch (never during a drag; a render
    /// already running finishes, about as long as one frame's GPU time).
    private func updateWarm(hold: Bool) {
        guard path == .native, !hold, !warmRunning, let c = current, let entry = c.entry, let view, let device else { return }
        let size = view.drawableSize
        guard size.width > 1, size.height > 1, let job = warmPlan.next(around: c.look, stages: pipeline.rules.lookStages, env: warmEnv(entry)) else {
            warmTarget = nil                    // nothing owed: the offscreen texture goes
            return
        }
        if warmTarget?.width != Int(size.width) || warmTarget?.height != Int(size.height) {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: view.colorPixelFormat, width: Int(size.width), height: Int(size.height), mipmapped: false)
            desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
            desc.storageMode = .private
            warmTarget = device.makeTexture(descriptor: desc)
        }
        guard let target = warmTarget else { return }
        let placed = compose(job.look, tier: job.tier, roi: job.tier == .small ? zoom : nil, entry: entry, size: size).placed
        warmRunning = true
        let context = warm.context, space = displaySpace
        warmQueue.async { [weak self] in
            let t0 = LookTrace.now()
            Self.warmRender(placed, into: target, context: context, space: space)
            let ms = LookTrace.now() - t0
            LookTrace.mark("warm \(job.stages) \(job.tier.rawValue)", ms: ms, at: t0)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.warmRunning = false
                    self.warmPlan.finished(job, ms: ms)
                    self.updatePrefetch()
                }
            }
        }
    }

    /// The same destination settings as the drawable's (`render`), so the output transform fused
    /// into the last program is the same one.
    nonisolated private static func warmRender(_ image: CIImage, into target: MTLTexture, context: CIContext, space: CGColorSpace) {
        let dest = CIRenderDestination(mtlTexture: target, commandBuffer: nil)
        dest.colorSpace = space
        dest.alphaMode = .premultiplied
        _ = try? context.startTask(toRender: image, from: CGRect(x: 0, y: 0, width: target.width, height: target.height), to: dest, at: .zero).waitUntilCompleted()
    }

    /// A new region number from the tile queue (which also stops the older requests there).
    private func supersedeRegion() { regionSeq = tiles.nextSeq(); regionBusy = false }

    // MARK: Facts, colour, memory

    private func setFacts() {
        var parts = ["canvas: \(path.rawValue)"]
        if let e = current?.entry { parts.append(e.source == "jpeg" ? "from the embedded JPEG" : e.source == "image" ? "image file" : "raw \(e.decoder ?? 0)") }
        if stats.region { parts.append("raw \(stats.regionDecoder) · region") }
        if stats.refining { parts.append("refining…") }
        if stats.slowed { parts.append("raw 9 · slowed by thermal state") }
        let f = parts.joined(separator: " · ")
        if f != facts { facts = f; onFacts?(f) }
    }

    private func updateDisplaySpace() {
        let space = view?.window?.screen?.colorSpace?.cgColorSpace ?? NSScreen.main?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        displaySpace = space
        displaySpaceName = (space.name as String?) ?? "icc-\(CFHash(space))"
        (view?.layer as? CAMetalLayer)?.colorspace = space
    }

    private func watchMemory() {
        let src = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Region tiles first, then the neighbours' bases, never the current photo's (§5).
                let t = self.tiles.drop(), b = self.bases.dropPrefetched()
                LuminaLog.canvas.notice("memory pressure: dropped \(t, privacy: .public) region tiles and \(b, privacy: .public) prefetched bases")
            }
        }
        src.resume()
        pressure = src
    }

    private func canvasPixels() -> CGSize {
        guard let view else { return CGSize(width: 1024, height: 768) }
        let s = view.drawableSize
        return s.width > 1 && s.height > 1 ? s : CGSize(width: 1024, height: 768)
    }

    /// The schedule's clock: `CACurrentMediaTime` in ms, the base Metal's GPU and presented times use.
    private func now() -> Double { CACurrentMediaTime() * 1000 }
}

/// The GPU end time of the render in flight, set on Metal's completion thread, taken on main.
nonisolated private final class GPUDone: @unchecked Sendable {
    private let lock = NSLock()
    private var end: CFTimeInterval?
    func set(_ t: CFTimeInterval) { lock.withLock { end = t } }
    func take() -> CFTimeInterval? { lock.withLock { defer { end = nil }; return end } }
}
