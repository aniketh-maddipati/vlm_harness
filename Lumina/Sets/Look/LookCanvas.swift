import AppKit
import CoreImage
import Metal
import MetalKit
import QuartzCore

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
        /// Display link ticks that came more than 1.5 frames after the previous one during a drag.
        var droppedFrames = 0
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
    }

    struct Neighbour { let rel: String; let url: URL; let preview: LookBases.PreviewFallback? }

    let path: Path
    let pipeline: LookPipeline
    let bases: LookBases
    let tiles: LookRegionTiles
    let view: LookCanvasView?
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private var displaySpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
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
        bases = LookBases(pipeline: pipeline)
        tiles = LookRegionTiles(pipeline: pipeline)
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
        if current?.rel != rel { schedule.reset(); region = nil; regionSeq += 1; stats.region = false }
        current = (rel, url, key, parsed, bases.entry(key), preview, decoder, regionDecoder)
        stats.rel = rel
        bases.pin(key)
        ensureBases()
        bases.prefetch(neighbours.map { (key: LookBases.Key(rel: $0.rel, decoder: decoder, look: Look(), canvas: size), url: $0.url, look: Look(), preview: $0.preview) })
        _ = schedule.keystroke(look, at: now())
        setFacts()
        kick()
    }

    func leave() {
        current = nil
        schedule.reset()
        region = nil
        regionSeq += 1
        loupe = (false, nil)
        bases.pin(nil)
        view?.isHidden = true
        stats.visible = false
        stopLink()
    }

    /// The page's canvas rect in CSS px (origin top-left of the web view) and whether Edit is showing.
    func layout(rect: CGRect, visible: Bool, dpr: CGFloat) {
        stats.dpr = Double(dpr)
        guard let view, let host = view.superview else { return }
        let r = NSRect(x: rect.minX, y: host.bounds.height - rect.minY - rect.height, width: rect.width, height: rect.height).integral
        let px = CGSize(width: max(1, (rect.width * dpr).rounded()), height: max(1, (rect.height * dpr).rounded()))
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
        let seq = key ? schedule.keystroke(text, at: arrived, pageSeq: pageSeq, pageAt: t ?? 0) : schedule.submit(text, at: arrived, roi: roi, pageSeq: pageSeq, pageAt: t ?? 0)
        kick()
        return seq
    }

    /// Our clock (ms, `CACurrentMediaTime`) minus the page's (`performance.now()`), estimated from
    /// message transit: the true offset is at most this.
    private var clockOffset = Double.greatestFiniteMagnitude

    /// A render reached the screen: the page's `seq` for the look it shows (`luminaPresented`).
    var onPresented: ((Int) -> Void)?

    func dragStart() { dragging = true; dragEndAt = nil; schedule.dragStart(at: now()); kick() }
    func dragEnd() { dragging = false; dragEndAt = CACurrentMediaTime(); schedule.dragEnd(at: now()); kick() }

    /// 100 % with G held: RAW 9 on the visible region (RAW 9 §2). Waits for stillness when the
    /// Mac is hot or on Low Power; never disabled.
    func loupe(on: Bool, roi: LookCanvasSchedule.ROI?) {
        loupe = (on, roi)
        loupeStillTimer?.invalidate(); loupeStillTimer = nil
        stats.regionFailed = false; stats.regionError = ""
        guard on, let roi, let c = current else {
            if !on { region = nil; regionSeq += 1; stats.region = false; stats.refining = false; setFacts(); kickRest() }
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
        regionSeq += 1
        let seq = regionSeq
        refiningTimer?.invalidate()
        refiningTimer = Timer.scheduledTimer(withTimeInterval: LookRawPolicy.refiningAfterMs / 1000, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { guard let self, self.regionSeq == seq else { return }; self.stats.refining = true; self.setFacts() }
        }
        tiles.region(rel: rel, url: url, decoder: version, nr: current?.look.nr, roi: roi, seq: seq, first: { [weak self] ms in
            guard let self, self.regionSeq == seq else { return }
            if ms <= LookRawPolicy.refiningAfterMs { self.refiningTimer?.invalidate() }
        }, done: { [weak self] r in
            guard let self, self.regionSeq == seq else { return }
            self.refiningTimer?.invalidate()
            self.stats.refining = false
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
                    NSLog("Lumina: RAW decoder \(version) failed for \(rel) (\(e)); using \(prev)")
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
        guard let data = try? JSONEncoder().encode(stats), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    /// The probe's latency measure starts fresh per drag.
    func resetMeasures() { latencies = []; stats.droppedFrames = 0; stats.ticks = 0; stats.renders = 0; stats.renderErrors = 0 }

    /// The current look rendered from `base` into a bitmap (the parity probe compares it with the
    /// export at the same size). Nil until the bases exist.
    func renderToImage() -> CGImage? {
        guard let c = current, let e = c.entry else { return nil }
        let img = pipeline.apply(c.look, to: LookPipeline.Developed(image: e.base, asShot: e.asShot), crop: false)
        return pipeline.context.createCGImage(pipeline.clamped(img), from: img.extent.integral, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
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
        if dragging, lastTick > 0, t - lastTick > l.duration * 1.5 { stats.droppedFrames += 1 }
        lastTick = t
        guard !rendering, let c = current, let entry = c.entry, let view, !view.isHidden, let request = schedule.tick(at: now()) else { return }
        render(request, entry: entry, look: c.look, view: view)
    }

    private func render(_ r: LookCanvasSchedule.Request, entry: LookBases.Entry, look parsedLook: Look, view: LookCanvasView) {
        guard let queue = commandQueue, let layer = view.layer as? CAMetalLayer, let drawable = layer.nextDrawable() else {
            schedule.failed(r); return
        }
        rendering = true
        flightSeq = r.seq
        let t0 = CACurrentMediaTime()
        let look = (try? Look.parse(r.look)) ?? parsedLook
        let src: CIImage, srcSize: CGSize
        if r.tier == .small { src = entry.small; srcSize = entry.smallSize } else { src = entry.base; srcSize = entry.baseSize }
        var image = pipeline.apply(look, to: LookPipeline.Developed(image: src, asShot: entry.asShot), crop: false)
        // Where the photo goes: fit the canvas (contain), or the zoomed region filling it.
        let dw = CGFloat(drawable.texture.width), dh = CGFloat(drawable.texture.height)
        var visible = CGRect(origin: .zero, size: srcSize)
        if let z = zoom ?? (r.roi), !z.isWhole {
            visible = CGRect(x: z.x * srcSize.width, y: (1 - z.y - z.h) * srcSize.height, width: z.w * srcSize.width, height: z.h * srcSize.height)
            if r.tier == .small, let roi = r.roi, !roi.isWhole { image = image.cropped(to: visible) }
        }
        // The loupe's RAW 9 region, when it covers the visible part, replaces the base there.
        var region: LookRegionTiles.Region?
        if r.tier == .base, let reg = self.region, reg.rel == current?.rel, let z = zoom, reg.roi == z {
            region = reg
            let regionImage = pipeline.apply(look, to: LookPipeline.Developed(image: reg.image, asShot: reg.asShot), crop: false)
            let vis = CGRect(x: z.x * reg.photoSize.width, y: (1 - z.y - z.h) * reg.photoSize.height, width: z.w * reg.photoSize.width, height: z.h * reg.photoSize.height)
            image = regionImage.cropped(to: vis.intersection(reg.rect))
            visible = vis
        }
        let s = min(dw / max(1, visible.width), dh / max(1, visible.height))
        let out = image.transformed(by: CGAffineTransform(translationX: -visible.minX, y: -visible.minY).concatenating(CGAffineTransform(scaleX: s, y: s)))
        let ox = ((dw - visible.width * s) / 2).rounded(), oy = ((dh - visible.height * s) / 2).rounded()
        let placed = pipeline.clamped(out).transformed(by: CGAffineTransform(translationX: ox, y: oy))
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
        cb.addCompletedHandler { [weak self] buffer in
            let end = buffer.gpuEndTime > 0 ? buffer.gpuEndTime : CACurrentMediaTime()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.rendering = false
                    self.stats.renders += 1
                    self.stats.lastRenderMs = (CACurrentMediaTime() - t0) * 1000
                    self.stats.lastRestTier = r.tier.rawValue
                    _ = self.schedule.finished(r)
                    self.frameShown(r, at: end, dragEnd: wasDragEnd, presented: false)
                    if r.stats { self.restStats(image, region: region, seq: r.pageSeq) }
                }
            }
        }
        cb.present(drawable)
        cb.commit()
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
        if r.seq > lastPresentedSeq { lastPresentedSeq = r.seq; if r.pageSeq > 0 { onPresented?(r.pageSeq) } }
    }

    /// Histogram and clipping, on rest renders only (§3): one CIAreaHistogram pass, 256 bins
    /// (Prompt 1's `luminaHistogram`).
    private func restStats(_ image: CIImage, region: LookRegionTiles.Region?, seq: Int) {
        let extent = image.extent
        guard !extent.isEmpty, !extent.isInfinite else { return }
        let bins = 256
        let hist = image.applyingFilter("CIAreaHistogram", parameters: [kCIInputExtentKey: CIVector(cgRect: extent), "inputCount": bins, "inputScale": 1.0])
        var px = [Float](repeating: 0, count: bins * 4)
        pipeline.context.render(hist, toBitmap: &px, rowBytes: bins * 16, bounds: CGRect(x: 0, y: 0, width: bins, height: 1), format: .RGBAf, colorSpace: nil)
        var r: [Double] = [], g: [Double] = [], b: [Double] = []
        for i in 0..<bins { r.append(Double(px[4 * i])); g.append(Double(px[4 * i + 1])); b.append(Double(px[4 * i + 2])) }
        let total = max(1e-9, r.reduce(0, +))
        var out: [String: Any] = ["seq": seq, "histogram": ["r": r, "g": g, "b": b], "clipHi": (r[bins - 1] + g[bins - 1] + b[bins - 1]) / (3 * total), "clipLo": (r[0] + g[0] + b[0]) / (3 * total), "source": region == nil ? "jpeg" : "raw9-region"]
        if let region { out["facts"] = ["sharpness": region.facts.sharpness, "clipHi": region.facts.clipHi, "clipLo": region.facts.clipLo, "source": region.facts.source] }
        onStats?(out)
    }

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
        (view?.layer as? CAMetalLayer)?.colorspace = space
    }

    private func watchMemory() {
        let src = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Region tiles first, then the neighbours' bases, never the current photo's (§5).
                let t = self.tiles.drop(), b = self.bases.dropPrefetched()
                NSLog("Lumina: memory pressure: dropped \(t) region tiles and \(b) prefetched bases")
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
