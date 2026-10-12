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

/// The page's chrome lying over the photo (zoom pill, state chip, colour chip, the working-files
/// pill): `canvasLayout`'s `holes`, which the canvas leaves see-through so the web view below
/// shows. A mask on the view's layer; the canvas stays one view that draws nothing of its own.
nonisolated enum LookCanvasHoles {
    static let maxCount = 16

    /// `holes` as the page sends them (CSS px, the same frame as `rect`) → rects in the canvas's
    /// own frame, top-left origin, clipped to the canvas. Only the first `maxCount` entries are
    /// read; one that is not four finite numbers with a positive size, or that misses the canvas,
    /// is dropped.
    static func parse(_ value: Any?, in rect: CGRect) -> [CGRect] {
        guard let list = value as? [Any], LookCanvasController.layable(rect, dpr: 1), rect.width > 0, rect.height > 0 else { return [] }
        let bounds = CGRect(origin: .zero, size: rect.size)
        return list.prefix(maxCount).compactMap { item in
            guard let d = item as? [String: Any], let x = number(d["x"]), let y = number(d["y"]),
                  let w = number(d["w"]), let h = number(d["h"]), w > 0, h > 0 else { return nil }
            let r = CGRect(x: x - rect.minX, y: y - rect.minY, width: w, height: h).intersection(bounds)
            return r.isNull || r.width <= 0 || r.height <= 0 ? nil : r
        }
    }

    /// The layer mask for `holes` (canvas frame, top-left origin) on a canvas of `size` points: the
    /// whole canvas less the holes, in the layer's frame (bottom-left origin unless `flipped`).
    /// Overlapping holes are one hole. No holes: nil, no mask.
    static func maskPath(_ holes: [CGRect], size: CGSize, flipped: Bool) -> CGPath? {
        guard !holes.isEmpty else { return nil }
        // Do not put disjoint rects into one compound path before subtracting. CGPath's point
        // queries read that shape as expected, but CAShapeLayer can fill the space between
        // parallel subpaths (Crop's four grid lines became a broad black cross). Subtracting
        // one rect at a time leaves exactly those hairlines transparent. Repeated and
        // overlapping holes stay holes.
        var mask = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        for h in holes {
            let cut = flipped ? h : CGRect(x: h.minX, y: size.height - h.maxY, width: h.width, height: h.height)
            mask = mask.subtracting(CGPath(rect: cut, transform: nil))
        }
        return mask
    }

    /// A page number: an `NSNumber` that is not a boolean, finite, within the reach of a layable rect.
    private static func number(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d = n.doubleValue
        return d.isFinite && abs(d) <= 3 * Double(LookCanvasController.maxDrawableEdge) ? d : nil
    }
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
        /// The page chrome the canvas leaves see-through (`LookCanvasHoles`).
        var holes = 0
    }

    /// What the last `layout` placed: the same again, holes aside, changes nothing.
    private struct Placement: Equatable { let rect: CGRect; let visible: Bool; let dpr: CGFloat; let hostHeight: CGFloat; let viewportHeight: CGFloat? }

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
    /// A crop guide the page drew under the photo, drawn here on top of it. `axis` is a dotted
    /// gold arm (the one that turns). `grid` is a light hairline you can see the picture through.
    /// `level` is the faint cross that stays horizontal.
    struct Guide: Equatable {
        enum Kind: Equatable { case grid, level, axis }
        var kind: Kind
        var a: CGPoint
        var b: CGPoint

        /// `canvasZoom`'s `guides`: viewport CSS px. `k` is `axis`, `level` or `grid`. At most 24.
        static func parse(_ value: Any?) -> [Guide] {
            guard let list = value as? [Any] else { return [] }
            return list.prefix(24).compactMap { item in
                guard let d = item as? [String: Any],
                      let x0 = SetsNumber.double(d["x0"], in: -20_000...20_000),
                      let y0 = SetsNumber.double(d["y0"], in: -20_000...20_000),
                      let x1 = SetsNumber.double(d["x1"], in: -20_000...20_000),
                      let y1 = SetsNumber.double(d["y1"], in: -20_000...20_000) else { return nil }
                let kind: Kind
                switch d["k"] as? String {
                case "axis": kind = .axis
                case "level": kind = .level
                default: kind = .grid
                }
                return Guide(kind: kind, a: CGPoint(x: x0, y: y0), b: CGPoint(x: x1, y: y1))
            }
        }
    }

    /// Crop's draft, which the look does not carry until Apply: the image's straighten (`angle`,
    /// CSS clockwise degrees, and `cover`, the scale that keeps the frame full) and the crop frame
    /// in CSS px from the viewport's top-left. Empty unless the crop tool is open.
    private struct CropDraft: Equatable {
        var angle = 0.0
        var cover = 1.0
        var frame: CGRect?
        var guides: [Guide] = []
        var active: Bool { frame != nil || abs(angle) > 0.05 || abs(cover - 1) > 0.001 }
    }
    private var cropDraft = CropDraft()
    /// The full frame Crop turns. The applied crop is already baked into the photo on screen;
    /// turning that by the draft angle stacks a second straighten. Nil unless Crop is open.
    private var draftSource: (key: LookBases.Key, entry: LookBases.Entry?)?
    /// `standIn`: the photo's embedded JPEG as bases, drawn at once while the RAW develops (`entry`
    /// is nil until then) and gone when it lands. Never what a slider edits: the look string is.
    private var current: (rel: String, url: URL, key: LookBases.Key, look: Look, entry: LookBases.Entry?, preview: LookBases.PreviewFallback?, decoder: Int?, regionDecoder: Int?,
                          standIn: (key: LookBases.Key, entry: LookBases.Entry)?)?
    /// The stand-ins are built on their own queue and context (`warm`, idle until the base is on
    /// screen), so the embedded JPEG never waits behind a RAW develop.
    private let standIns: LookBases
    /// A RAW that did not develop is tried again after these delays (s), then left to the facts line.
    nonisolated static let developRetries: [TimeInterval] = [1, 4]
    private var developTries = 0
    private var developRetrying = false
    /// Why nothing at all can be drawn for the photo (no RAW develop, no embedded JPEG).
    private var cannotDevelop: String?
    /// A base of this photo has landed: from then on a new size or crop waits on its own base,
    /// as before; the embedded JPEG is only what a photo opens with.
    private var baseSeen = false
    /// Frames in a row the drawable refused; a few are tried again (`drawAgain`).
    private var drawFails = 0
    private var region: LookRegionTiles.Region?
    private var regionSeq = 0
    private var placement: Placement?
    private var holes: [CGRect] = []
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
    /// The as-shot white balance of the photo on the canvas became known (or changed with the
    /// decoder) after `enter` answered: its rel and the pair. Read from the base the canvas
    /// developed anyway; never a develop of its own.
    var onAsShot: ((String, Look.WhiteBalance) -> Void)?
    private var asShotTold: (rel: String, wb: Look.WhiteBalance)?

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
        standIns = LookBases(pipeline: warm, byteCap: LookRawPolicy.baseCacheBytes / 4, maxPhotos: 1)
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
            // The page lays out from the window's top-left: while the window is resized, the canvas
            // keeps its distance to the top until the page's next rect arrives.
            v.autoresizingMask = [.maxXMargin, .minYMargin]
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
    /// `pageSeq`: the page's `seq` for `look`, when the page's first look for the photo comes with
    /// the photo itself (`canvasEnter`), so its frame is acknowledged (`luminaPresented`).
    func enter(rel: String, url: URL, look: String, decoder: Int?, regionDecoder: Int?, preview: LookBases.PreviewFallback?, neighbours: [Neighbour], pageSeq: Int = 0) {
        let parsed = (try? Look.parse(look)) ?? Look()
        let size = canvasPixels()
        let key = LookBases.Key(rel: rel, decoder: decoder, look: parsed, canvas: size)
        let same = current?.rel == rel
        if !same { schedule.reset(); region = nil; supersedeRegion(); stats.region = false; asShotTold = nil; developTries = 0; developRetrying = false; cannotDevelop = nil; drawFails = 0; baseSeen = false; draftSource = nil }
        current = (rel, url, key, parsed, bases.entry(key), preview, decoder, regionDecoder, same ? current?.standIn : nil)
        stats.rel = rel
        bases.pin(key)
        ensureBases()
        // A base kept from a develop that failed (the embedded JPEG stood in): the RAW is tried again.
        if let e = current?.entry { baseSeen = true; if e.why != nil { developAgain(key) } }
        // The neighbours wait until this photo's base is on screen and the canvas is still.
        self.neighbours = neighbours.map { (key: LookBases.Key(rel: $0.rel, decoder: decoder, look: Look(), canvas: size), url: $0.url, look: Look(), preview: $0.preview) }
        prefetchIssued = false
        basePresented = false
        updatePrefetch()
        // Entered again with a look of the page's still waiting for its frame: its `seq` stays.
        let carried = pageSeq > 0 ? pageSeq : (schedule.pending ? schedule.latest?.pageSeq ?? 0 : 0)
        _ = schedule.keystroke(look, at: now(), pageSeq: carried)
        setFacts()
        answerUnshown()
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
        tellAsShot()
        neighbours = neighbours.map { (key: LookBases.Key(rel: $0.key.rel, decoder: decoder, look: Look(), canvas: CGSize(width: $0.key.width, height: $0.key.height)), url: $0.url, look: $0.look, preview: $0.preview) }
        prefetchIssued = false
        basePresented = false
        updatePrefetch()
        if region != nil { region = nil; stats.region = false }
        supersedeRegion()
        if loupe.on { loupe(on: true, roi: loupe.roi) }
        schedule.again(at: now())
        setFacts()
        kick()
    }

    // MARK: The photo's as-shot white balance (for the page's temperature slider)

    /// The decoder's own pair for a developed RAW. Nil for the embedded JPEG standing in, an image
    /// file (their 5500 K is a placeholder, not a reading), and a value no slider can rest on.
    nonisolated static func asShot(of entry: LookBases.Entry?) -> Look.WhiteBalance? {
        guard let e = entry, e.source == "raw", e.asShot.kelvin.isFinite, e.asShot.tint.isFinite, e.asShot.kelvin > 0 else { return nil }
        return e.asShot
    }

    /// What the page's edit header takes (`canvasEnter`'s answer and `__lumina.editHeader`): the
    /// pair and the rel it belongs to.
    nonisolated static func asShotHeader(rel: String, _ wb: Look.WhiteBalance) -> [String: Any] {
        ["asShot": ["kelvin": wb.kelvin, "tint": wb.tint], "asShotRel": rel]
    }

    /// For `canvasEnter`'s answer: the pair of the photo on the canvas when its base is already
    /// there (the cache lookup `enter` made; nothing is developed or waited for), else nil and
    /// `onAsShot` says it when the base lands.
    func asShotForReply() -> (rel: String, wb: Look.WhiteBalance)? {
        guard let c = current, let wb = Self.asShot(of: c.entry) else { return nil }
        asShotTold = (c.rel, wb)
        return (c.rel, wb)
    }

    /// The base of the photo on the canvas landed or changed: say its pair, once per value.
    private func tellAsShot() {
        guard let c = current, let wb = Self.asShot(of: c.entry) else { return }
        if let t = asShotTold, t.rel == c.rel, t.wb == wb { return }
        asShotTold = (c.rel, wb)
        onAsShot?(c.rel, wb)
    }

    func leave() {
        asShotTold = nil
        current = nil
        standIns.pin(nil); standIns.forget()
        developRetrying = false; cannotDevelop = nil; baseSeen = false
        schedule.reset()
        region = nil
        supersedeRegion()
        loupe = (false, nil)
        zoom = nil
        zoomStill?.invalidate(); zoomStill = nil
        zooming = false
        bases.pin(nil)
        warmTarget = nil
        view?.isHidden = true
        stats.visible = false
        placement = nil
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

    /// Where the page's canvas rect (CSS px, origin the viewport's top-left) sits in the host
    /// (bottom-left origin). The web view fills the host, but on macOS 26 it keeps the strip under
    /// the title bar out of the page (its obscured content inset), so CSS y = 0 is that far below
    /// the host's top. The viewport's bottom is the host's bottom either way, so the rect is placed
    /// up from there: `viewportHeight` is the page's `innerHeight`. Without it (or one taller than
    /// the host), the viewport is the whole host, as before.
    nonisolated static func frame(for rect: CGRect, hostHeight: CGFloat, viewportHeight: CGFloat?) -> NSRect {
        let vh = viewportHeight.flatMap { $0.isFinite && $0 > 0 && $0 <= hostHeight ? $0 : nil } ?? hostHeight
        return NSRect(x: rect.minX, y: vh - rect.minY - rect.height, width: rect.width, height: rect.height).integral
    }

    /// The page's canvas rect in CSS px (origin top-left of the page's viewport), whether Edit is
    /// showing, and the page chrome over it to leave see-through (`LookCanvasHoles.parse`'s frame).
    /// Holes alone change only the mask: no base, render or cache key follows them.
    func layout(rect: CGRect, visible: Bool, dpr: CGFloat, holes: [CGRect] = [], viewportHeight: CGFloat? = nil) {
        // Not a rect a display can hold (not finite, negative, absurdly large): the canvas hides and
        // keeps the size it had. `Int(_:)` on such a number stops the app (Q4-hostile F2).
        guard Self.layable(rect, dpr: dpr) else {
            view?.isHidden = true
            stats.visible = false
            placement = nil
            stopLink()
            return
        }
        stats.dpr = Double(dpr)
        guard let view, let host = view.superview else { return }
        let placed = Placement(rect: rect, visible: visible, dpr: dpr, hostHeight: host.bounds.height, viewportHeight: viewportHeight)
        if placed == placement {
            if holes != self.holes { applyHoles(holes) }
            return
        }
        placement = placed
        let r = Self.frame(for: rect, hostHeight: host.bounds.height, viewportHeight: viewportHeight)
        // Never past Metal's largest texture edge (a 16,384 px rect at 2× would ask for twice that).
        let px = CGSize(width: min(Self.maxDrawableEdge, max(1, (rect.width * dpr).rounded())), height: min(Self.maxDrawableEdge, max(1, (rect.height * dpr).rounded())))
        let sizeChanged = view.frame.size != r.size || view.drawableSize != px
        view.frame = r
        view.drawableSize = px
        applyHoles(holes)
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
            tellAsShot()
            schedule.again(at: now())
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
            tellAsShot()
        } else { current?.look = parsed }
        zoom = roi
        if cropDraft.active { ensureDraftSource() }
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
        // A look that took more than a refresh to get here: the wait was before the canvas had it
        // (the page's process or the message's transit), and the trace says so next to the frame.
        if dragging, arrived - emitted > 16 { LookTrace.mark("look arrived \(Int((arrived - emitted).rounded())) ms after the page emitted it", at: arrived) }
        if !schedule.pending { waitingSince = emitted }
        let seq = key ? schedule.keystroke(text, at: arrived, pageSeq: pageSeq, pageAt: t ?? 0) : schedule.submit(text, at: arrived, roi: roi, pageSeq: pageSeq, pageAt: t ?? 0)
        answerUnshown()
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

    /// The page zoomed or panned its picture: `roi` is its canvas box in fractions of the photo as
    /// the page shows it (beyond 0 … 1 where the box reaches past the photo), nil at fit. While
    /// Crop is open, `angle` / `cover` are the draft straighten on the page's image and `frame` is
    /// the crop rect (CSS px, the viewport's top-left). The angle is absolute — the straighten
    /// the crop is at now, including 0 — and it is applied once, to the full frame. The look's
    /// crop stays baked for when Crop closes; it is not turned again underneath.
    /// The look on the canvas is drawn again there. A zoom that moves is a drag: a frame per
    /// refresh from `small`, with the warm-up, the neighbours' prefetch and the RAW 9 region held;
    /// `rest` (the page saw it still) ends it with one render from `base`. The picture is the same,
    /// so its histogram is not computed again.
    func zoom(to roi: LookCanvasSchedule.ROI?, angle: Double = 0, cover: Double = 1, frame: CGRect? = nil, guides: [Guide] = [], rest: Bool = false) {
        let next = roi == nil ? CropDraft() : CropDraft(angle: angle, cover: cover, frame: frame, guides: Array(guides.prefix(24)))
        let moved = roi != zoom || next != cropDraft
        zoom = roi
        cropDraft = next
        if next.active { ensureDraftSource() } else { draftSource = nil }
        guard current != nil else { zoomEnd(); return }
        if moved {
            if !zooming {
                zooming = true
                // A look still owed its rest render keeps its histogram.
                zoomOwed = schedule.restPending
                // Tiles for the region left behind would only take the GPU from the frames.
                if regionBusy { supersedeRegion(); refiningTimer?.invalidate(); stats.refining = false }
                LookTrace.mark("zoomStart")
                updatePrefetch()
                if !dragging { schedule.dragStart(at: now()) }
            }
            var seq = 0
            if let l = schedule.latest {
                seq = schedule.submit(l.look, at: now(), roi: roi, pageSeq: l.pageSeq)
            } else if let l = schedule.presentedLook {
                seq = schedule.submit(l, at: now(), roi: roi)
            }
            placeOnly = zoomOwed ? 0 : seq
        }
        zoomStill?.invalidate(); zoomStill = nil
        if rest {
            zoomEnd()
        } else if zooming {
            // The page's `rest` never came (it stopped, or Edit closed over it): the hold still ends.
            zoomStill = Timer.scheduledTimer(withTimeInterval: Self.zoomStillMs / 1000, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.zoomEnd() }
            }
        }
        kick()
    }

    private func zoomEnd() {
        zoomStill?.invalidate(); zoomStill = nil
        guard zooming else { return }
        zooming = false
        LookTrace.mark("zoomEnd")
        if !dragging { schedule.dragEnd(at: now()) }
        updatePrefetch()
        kick()
    }

    /// Crop draws the full frame and turns it by the draft angle once. The base on screen already
    /// has the applied crop baked in, so a second Crop would otherwise turn that result again and
    /// lay it over the page's own rotated picture. This base is the same look with the crop taken
    /// out. The embedded JPEG stands in until the RAW one lands; until either exists the baked
    /// photo is shown without another turn.
    private func ensureDraftSource() {
        guard cropDraft.active, let c = current else { return }
        var bare = c.look
        bare.crop = nil
        let canvas = CGSize(width: CGFloat(c.key.width), height: CGFloat(c.key.height))
        let key = LookBases.Key(rel: c.rel, decoder: c.decoder, look: bare, canvas: canvas)
        if draftSource?.key == key, draftSource?.entry != nil { return }
        if key == c.key {
            draftSource = (key, c.entry ?? c.standIn?.entry)
            return
        }
        if let e = bases.entry(key) {
            draftSource = (key, e)
            return
        }
        if draftSource?.key != key { draftSource = (key, nil) }
        let url = c.url, preview = c.preview
        if let p = preview, LookPipeline.isRAW(url) {
            standIns.request(key, url: url, look: bare, preview: p, previewOnly: true) { [weak self] r in
                guard let self, self.cropDraft.active, self.draftSource?.key == key, self.draftSource?.entry == nil, case .success(let e) = r else { return }
                self.draftSource = (key, e)
                self.schedule.again(at: self.now())
                self.kick()
            }
        }
        bases.request(key, url: url, look: bare, preview: preview) { [weak self] r in
            guard let self, self.cropDraft.active, self.draftSource?.key == key, case .success(let e) = r else { return }
            self.draftSource = (key, e)
            self.schedule.again(at: self.now())
            self.kick()
        }
    }

    /// The page says a zoom rests after 300 ms without a change (plumbing's ZOOM_REST); this long
    /// without either, the canvas ends the zoom itself.
    nonisolated static let zoomStillMs: Double = 1000
    /// A zoom is moving (`zoom(to:)` … its `rest`): background work holds, as during a slider drag.
    private var zooming = false
    private var zoomOwed = false
    private var zoomStill: Timer?
    /// The schedule's count of the look `zoom(to:)` resubmitted last: the same picture in another place.
    private var placeOnly = 0

    /// 100 % with G held: RAW 9 on the visible region (RAW 9 §2). Waits for stillness when the
    /// Mac is hot or on Low Power; never disabled. A pan that only moves the region (no new look)
    /// places the photo again at once. Tiles for a region that is still moving wait until it rests.
    func loupe(on: Bool, roi: LookCanvasSchedule.ROI?) {
        let moving = on && loupe.on && loupe.roi != nil && loupe.roi != roi
        loupe = (on, roi)
        // Crop places the photo through zoom(to:), angle and frame included. A loupe region must
        // not replace that draft. Outside Crop, the region is the placement.
        if !cropDraft.active, zoom != roi {
            zoom = roi
            if on { kickRest(); kick() }
        }
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
        let policy = LookRawPolicy.regionDelayMs(thermalState: LookDecoderProbe.thermalLevel(ProcessInfo.processInfo.thermalState), lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        stats.slowed = policy > 0
        let delay = moving ? max(policy, 120) : policy
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
        // The base is still coming (the embedded JPEG stands in): the warm-up has not begun, it is not done.
        else if path == .native, stats.warm.enabled, current != nil, cannotDevelop == nil { stats.warm.pending = 1 }
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
        ensureStandIn()
        bases.request(c.key, url: c.url, look: c.look, preview: c.preview) { [weak self] r in self?.baseLanded(r, key: c.key) }
    }

    /// The embedded JPEG as this photo's bases, asked for with the RAW's and drawn until they land.
    private func ensureStandIn() {
        guard path == .native, !baseSeen, let c = current, c.entry == nil, c.standIn?.key != c.key, let p = c.preview, LookPipeline.isRAW(c.url) else { return }
        standIns.pin(c.key)
        standIns.request(c.key, url: c.url, look: c.look, preview: p, previewOnly: true) { [weak self] r in
            guard let self, let cur = self.current, cur.key == c.key, cur.entry == nil, case .success(let e) = r else { return }
            self.current?.standIn = (c.key, e)
            self.schedule.again(at: self.now())
            self.setFacts()
            self.kick()
        }
    }

    private func baseLanded(_ r: Result<LookBases.Entry, Error>, key: LookBases.Key) {
        guard let cur = current, cur.key == key else { return }
        developRetrying = false
        switch r {
        case .success(let e):
            // A second failure with the first one's JPEG already on the canvas changes nothing there.
            let redraw = !(e.why != nil && cur.entry?.why != nil)
            current?.entry = e
            if draftSource?.key == key { draftSource = (key, e) }
            current?.standIn = nil
            baseSeen = true
            standIns.pin(nil); standIns.forget()
            cannotDevelop = nil
            // The look on the canvas (from the stand-in, or still waiting) again, on this base.
            if redraw { schedule.again(at: now()) }
            tellAsShot()
            if e.why != nil { stats.renderErrors += 1; developAgain(key) }
            setFacts()
            kick()
            updatePrefetch()
        case .failure(let e):
            stats.renderErrors += 1
            if cur.entry == nil { cannotDevelop = "\(e)" }
            developAgain(key)
            setFacts()
            answerUnshown()
        }
    }

    /// The RAW did not develop: again after `developRetries`, while this photo stays on the canvas
    /// (the embedded JPEG keeps standing in). The facts line says why, and `retrying` until the last.
    private func developAgain(_ key: LookBases.Key) {
        guard !developRetrying, developTries < Self.developRetries.count else { return }
        let delay = Self.developRetries[developTries]
        developTries += 1
        developRetrying = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.developRetrying else { return }
                guard let c = self.current, c.key == key else { self.developRetrying = false; return }
                self.bases.drop(key)
                self.bases.request(key, url: c.url, look: c.look, preview: c.preview) { [weak self] r in self?.baseLanded(r, key: key) }
            }
        }
    }

    /// Nothing can be drawn for this photo (no RAW develop, no embedded JPEG): the page's look is
    /// answered so it stops waiting on a frame, and the facts line says why.
    private func answerUnshown() {
        guard cannotDevelop != nil, let c = current, c.entry == nil, let seq = schedule.latest?.pageSeq, seq > 0 else { return }
        onPresented?(seq)
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

    /// The layer mask that leaves `new` see-through; no holes, no mask. Masks only: the drawable,
    /// the bases and the schedule never see the holes.
    private func applyHoles(_ new: [CGRect]) {
        holes = new
        stats.holes = new.count
        guard let view, let layer = view.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let path = LookCanvasHoles.maskPath(new, size: view.bounds.size, flipped: view.isFlipped) {
            let mask = (layer.mask as? CAShapeLayer) ?? CAShapeLayer()
            mask.frame = CGRect(origin: .zero, size: view.bounds.size)
            mask.contentsScale = view.window?.backingScaleFactor ?? layer.contentsScale
            mask.path = path
            layer.mask = mask
        } else {
            layer.mask = nil
        }
        CATransaction.commit()
    }

    private func kickRest() { if schedule.presentedLook != nil { schedule.again(at: now()) } }

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
        guard !rendering, let c = current, let entry = c.entry ?? c.standIn?.entry, let view, !view.isHidden, let request = schedule.tick(at: now()) else { return }
        let look = (try? Look.parse(request.look)) ?? c.look
        let seen = warmPlan.rendering(look, tier: request.tier, stages: pipeline.rules.lookStages, env: warmEnv(entry))
        let t0 = LookTrace.now()
        render(request, entry: entry, standIn: c.entry == nil && cannotDevelop == nil, look: look, view: view)
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
        // The draft angle is the crop's straighten, absolute. It turns the full frame once.
        // The on-screen base already contains the applied crop, so turning that as well stacks
        // a second rotated copy. Until the full frame is ready, that base is shown unturned.
        let source: LookBases.Entry
        let applyDraft: Bool
        if cropDraft.active, let e = draftSource?.entry {
            source = e
            applyDraft = true
        } else if cropDraft.active, current?.look.crop != nil {
            source = entry
            applyDraft = false
        } else {
            source = entry
            applyDraft = cropDraft.active
        }
        let src: CIImage, srcSize: CGSize
        if tier == .small { src = source.small; srcSize = source.smallSize } else { src = source.base; srcSize = source.baseSize }
        var image = pipeline.apply(look, to: LookPipeline.Developed(image: src, asShot: source.asShot, anchor: source.anchor), crop: false)
        // Where the photo goes: fit the canvas (contain), or the zoomed region filling it.
        let dw = size.width, dh = size.height
        var visible = CGRect(origin: .zero, size: srcSize)
        if let z = zoom ?? roi, !z.isFit {
            visible = CGRect(x: z.x * srcSize.width, y: (1 - z.y - z.h) * srcSize.height, width: z.w * srcSize.width, height: z.h * srcSize.height)
            // A draft straighten needs the whole photo: cropping to the upright window first would
            // cut off the corners the rotation and cover scale bring into the frame.
            if tier == .small, let roi, !roi.isWhole, !cropDraft.active { image = image.cropped(to: visible) }
        }
        // The loupe's RAW 9 region, when it covers the visible part, replaces the base there.
        // Not during a draft crop: that region is the upright window, and the page is showing the
        // full photo turned.
        var region: LookRegionTiles.Region?
        if tier == .base, !cropDraft.active, let reg = self.region, reg.rel == current?.rel, let z = zoom, reg.roi == z, reg.rot == look.rot {
            region = reg
            let regionImage = pipeline.apply(look, to: LookPipeline.Developed(image: reg.image, asShot: reg.asShot, anchor: reg.anchor), crop: false)
            let vis = CGRect(x: z.x * reg.photoSize.width, y: (1 - z.y - z.h) * reg.photoSize.height, width: z.w * reg.photoSize.width, height: z.h * reg.photoSize.height)
            image = regionImage.cropped(to: vis.intersection(reg.rect))
            visible = vis
        }
        let s = min(dw / max(1, visible.width), dh / max(1, visible.height))
        let out = image.transformed(by: CGAffineTransform(translationX: -visible.minX, y: -visible.minY).concatenating(CGAffineTransform(scaleX: s, y: s)))
        let ox = ((dw - visible.width * s) / 2).rounded(), oy = ((dh - visible.height * s) / 2).rounded()
        var placed = pipeline.output(out).transformed(by: CGAffineTransform(translationX: ox, y: oy))
        if applyDraft {
            // The page's photo box, in the drawable (y up): the full frame fills it, then rotates
            // and scales once about its centre. Corners that leave the box stay in the picture.
            let photo = CGRect(x: ox - visible.minX * s, y: oy - visible.minY * s, width: srcSize.width * s, height: srcSize.height * s)
            placed = draftPlaced(placed, photo: photo, size: size)
        }
        return (placed, image, region)
    }

    /// The crop frame in drawable pixels (y up), from the viewport CSS rect the page sent.
    private func draftFrame(_ size: CGSize) -> CGRect? {
        guard let frame = cropDraft.frame, let canvas = placement?.rect, canvas.width > 1, canvas.height > 1, size.width > 1, size.height > 1 else { return nil }
        let sx = size.width / canvas.width, sy = size.height / canvas.height
        let w = frame.width * sx, h = frame.height * sy
        let r = CGRect(x: (frame.minX - canvas.minX) * sx, y: size.height - (frame.minY - canvas.minY) * sy - h, width: w, height: h)
        return r.width > 1 && r.height > 1 ? r : nil
    }

    /// Straighten and cover scale about the photo's centre. The turned rectangle is kept whole:
    /// a corner that leaves the upright photo stays drawn, and takes the page's dim (rgba 22,21,20
    /// at 0.64) where it falls outside the crop frame. Pixels outside the canvas are dropped.
    /// Where the frame covers the whole picture the margin stays undrawn, so the page's shadow shows.
    private func draftPlaced(_ image: CIImage, photo: CGRect, size: CGSize) -> CIImage {
        Self.draftPlaced(image, photo: photo, canvas: size, angle: cropDraft.angle, cover: cropDraft.cover, frame: draftFrame(size))
    }

    /// `frame` is the crop window in the same pixel space as `photo` (y up). Nil leaves the turn undimmed.
    static func draftPlaced(_ image: CIImage, photo: CGRect, canvas: CGSize, angle: Double, cover: Double, frame: CGRect?) -> CIImage {
        var out = image
        if abs(angle) > 0.05 || abs(cover - 1) > 0.001 {
            let c = CGPoint(x: photo.midX, y: photo.midY)
            let turn = CGAffineTransform(translationX: c.x, y: c.y)
                .rotated(by: -angle * .pi / 180)
                .scaledBy(x: cover, y: cover)
                .translatedBy(x: -c.x, y: -c.y)
            out = out.transformed(by: turn)
        }
        // The drawable's edge, not the upright photo. A corner in the canvas margin stays.
        let raw = out.extent
        if canvas.width > 1, canvas.height > 1, !raw.isNull, !raw.isInfinite, raw.width.isFinite, raw.height.isFinite {
            let visible = raw.intersection(CGRect(origin: .zero, size: canvas))
            if !visible.isNull, !visible.isInfinite, visible.width > 1, visible.height > 1 {
                out = out.cropped(to: visible)
            }
        }
        guard let frame else { return out }
        let bounds = out.extent
        guard !bounds.isNull, !bounds.isInfinite, bounds.width.isFinite, bounds.height.isFinite, bounds.width > 1, bounds.height > 1 else { return out }
        let window = frame.intersection(bounds)
        guard !window.isNull, window.width > 1, window.height > 1, window.width < bounds.width - 4 || window.height < bounds.height - 4 else { return out }
        let veil = CIImage(color: CIColor(red: 22.0 / 255, green: 21.0 / 255, blue: 20.0 / 255, alpha: 0.64)).cropped(to: bounds)
        // Source-atop darkens the photo and stays clear in the bounding box's empty corners.
        let dimmed = veil.applyingFilter("CISourceAtopCompositing", parameters: [kCIInputBackgroundImageKey: out]).cropped(to: bounds)
        return out.cropped(to: window).composited(over: dimmed).cropped(to: bounds)
    }

    /// The page's crop guides, on top of the photo. The grid and the level cross are a light
    /// hairline you can see the picture through. The dotted axis is the gold dash, in front,
    /// including once it has turned off the horizontal.
    private func withGuides(_ image: CIImage, size: CGSize) -> CIImage {
        guard !cropDraft.guides.isEmpty, let canvas = placement?.rect, canvas.width > 1, canvas.height > 1, size.width > 1, size.height > 1 else { return image }
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        guard w > 1, h > 1, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        let sx = size.width / canvas.width, sy = size.height / canvas.height
        // The bitmap's origin is the bottom left, matching the drawable (y up).
        func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - canvas.minX) * sx, y: size.height - (p.y - canvas.minY) * sy) }
        ctx.setLineCap(.butt)
        // Level sits under the grid, and the dotted axis is last, so a turn still reads in front.
        for kind in [Guide.Kind.level, .grid, .axis] {
            for g in cropDraft.guides where g.kind == kind {
                switch kind {
                case .axis:
                    ctx.setStrokeColor(red: 1, green: 210.0 / 255, blue: 122.0 / 255, alpha: 0.95)
                    ctx.setLineDash(phase: 0, lengths: [7 * sx, 5 * sx])
                case .level:
                    ctx.setStrokeColor(red: 239.0 / 255, green: 236.0 / 255, blue: 230.0 / 255, alpha: 0.22)
                    ctx.setLineDash(phase: 0, lengths: [])
                case .grid:
                    ctx.setStrokeColor(red: 239.0 / 255, green: 236.0 / 255, blue: 230.0 / 255, alpha: 0.5)
                    ctx.setLineDash(phase: 0, lengths: [])
                }
                ctx.setLineWidth(max(1, sx))
                ctx.move(to: pt(g.a))
                ctx.addLine(to: pt(g.b))
                ctx.strokePath()
            }
        }
        guard let cg = ctx.makeImage() else { return image }
        return CIImage(cgImage: cg).composited(over: image)
    }

    private func render(_ r: LookCanvasSchedule.Request, entry: LookBases.Entry, standIn: Bool, look: Look, view: LookCanvasView) {
        let waited = LookTrace.now()
        guard let queue = commandQueue, let layer = view.layer as? CAMetalLayer, let drawable = layer.nextDrawable() else {
            schedule.failed(r); drawAgain(); return
        }
        // Both drawables still queued for a refresh: the wait is the display's, not the look's.
        if LookTrace.now() - waited > 2 { LookTrace.mark("nextDrawable waited", ms: LookTrace.now() - waited, at: waited) }
        rendering = true
        renderStartedAt = CACurrentMediaTime()
        flightSeq = r.seq
        let t0 = CACurrentMediaTime()
        let dw = CGFloat(drawable.texture.width), dh = CGFloat(drawable.texture.height)
        let composed = compose(look, tier: r.tier, roi: r.roi, entry: entry, size: CGSize(width: dw, height: dh))
        let placed = cropDraft.guides.isEmpty ? composed.placed : withGuides(composed.placed, size: CGSize(width: dw, height: dh))
        let image = composed.image, region = composed.region
        guard let cb = queue.makeCommandBuffer() else { schedule.failed(r); rendering = false; drawAgain(); return }
        let dest = CIRenderDestination(mtlTexture: drawable.texture, commandBuffer: cb)
        dest.colorSpace = displaySpace
        dest.alphaMode = .premultiplied
        do {
            try pipeline.context.startTask(toClear: dest)
            try pipeline.context.startTask(toRender: placed, from: CGRect(x: 0, y: 0, width: dw, height: dh), to: dest, at: .zero)
        } catch {
            stats.renderErrors += 1
            schedule.failed(r); rendering = false
            drawAgain()
            return
        }
        drawFails = 0
        let wasDragEnd = dragEndAt
        // The frame's time on our clock: the GPU end time when the command buffer completes, replaced
        // by the drawable's presented time when the window really presents (it is 0 when it doesn't,
        // e.g. the probe's transparent window). Latency = frame − the look's page time + the clock offset.
        drawable.addPresentedHandler { [weak self] d in
            let presented = d.presentedTime
            guard presented > 0 else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.frameShown(r, at: presented, dragEnd: wasDragEnd, presented: true, standIn: standIn) }
            }
        }
        inFlightFinish = { [weak self] end in
            guard let self else { return }
            self.rendering = false
            self.stats.renders += 1
            self.stats.lastRenderMs = (CACurrentMediaTime() - t0) * 1000
            self.stats.lastRestTier = r.tier.rawValue
            _ = self.schedule.finished(r)
            self.frameShown(r, at: end, dragEnd: wasDragEnd, presented: false, standIn: standIn)
            if r.stats, r.lookSeq != self.placeOnly || region != nil { self.restStats(image, region: region, seq: r.pageSeq) }
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

    /// A frame the drawable refused (no drawable in time, no command buffer, a render error): the
    /// schedule counts that look as started, so the newest look is asked for again, a few times.
    private func drawAgain() {
        guard drawFails < 3 else { return }
        drawFails += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated { guard let self, self.current != nil else { return }; self.schedule.again(at: self.now()); self.kick() }
        }
    }

    /// Runs the finished render's bookkeeping once, whichever of the tick or the completion's
    /// main-queue hop gets here first.
    private func drainCompletion() {
        guard let end = gpuDone.take(), let finish = inFlightFinish else { return }
        inFlightFinish = nil
        finish(end)
    }

    private var sampleIndex: [Int: Int] = [:]        // render seq → its latency sample's index
    private var sampledLook = 0                      // the newest look (the schedule's count) with a latency sample

    /// A render's frame time (seconds on our clock): records the latency sample (once per render,
    /// the presented time overriding the GPU end time), the rest render's delay after drag end, and
    /// tells the page which look is on screen. A frame of the stand-in (`standIn`) is not the look
    /// on the RAW yet: the page hears when that frame comes (the look is drawn again on the base).
    private func frameShown(_ r: LookCanvasSchedule.Request, at frame: CFTimeInterval, dragEnd: CFTimeInterval?, presented: Bool, standIn: Bool) {
        let frameMs = frame * 1000
        // A look's latency is to its first frame. The rest render of a look already on screen from
        // `small` (a pause in a drag, drag end) is a second frame of the same value, as late as the
        // pause was long: not a sample (`lastRestMs` times it after drag end).
        if r.pageAt > 0, clockOffset < Double.greatestFiniteMagnitude, sampleIndex[r.seq] != nil || r.lookSeq > sampledLook {
            sampledLook = max(sampledLook, r.lookSeq)
            let latency = frameMs - (r.pageAt + clockOffset)
            if let i = sampleIndex[r.seq], i < latencies.count { latencies[i] = latency }
            else { latencies.append(latency); sampleIndex[r.seq] = latencies.count - 1 }
            if latencies.count > 4000 { latencies.removeFirst(2000); sampleIndex = [:] }
        }
        if r.tier == .base, let de = dragEnd, frame >= de { stats.lastRestMs = (frame - de) * 1000; dragEndAt = nil }
        if r.tier == .base, !standIn, !basePresented { basePresented = true; updatePrefetch() }
        else if r.tier == .base, !dragging { updatePrefetch() }
        if r.seq > lastPresentedSeq { lastPresentedSeq = r.seq; if r.pageSeq > 0, !standIn { onPresented?(r.pageSeq) } }
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
        let hold = dragging || zooming || regionBusy || current?.entry == nil || (view != nil && !basePresented)
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
        let name = current.map { String($0.rel.split(separator: "/").last ?? "") } ?? ""
        let again = developRetrying || developTries < Self.developRetries.count ? " · retrying" : ""
        if let e = current?.entry {
            parts.append(e.source == "jpeg" ? "from the embedded JPEG" : e.source == "image" ? "image file" : "raw \(e.decoder ?? 0)")
            if let why = e.why { parts.append("can't develop \(name) (\(why))\(again)") }
        } else if current?.standIn != nil {
            parts.append("from the embedded JPEG")
        } else if let why = cannotDevelop {
            parts.append("can't develop \(name) (\(why))\(again)")
        }
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
