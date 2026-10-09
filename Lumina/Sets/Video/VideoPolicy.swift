import Foundation

/// The video module's budgets, tiers, pacing and pressure rules, as plain functions so they are
/// the same in the app, the probe and the tests (the `LookRawPolicy` shape). Nothing here touches
/// AVFoundation, VideoToolbox or Core Image; the schedulers call in with what they measured and
/// get back what to do. Foundation only: it runs in the Linux Swift sandbox too.
///
/// Video is its own module with its own budgets (PROJECT STATE: "Video work is separate and must
/// not destabilize stills"). It shares `LookByteCache` and the probe's sampler with the Edit
/// canvas and nothing else: no pool, no governor, no pressure source is shared with stills.
///
/// Three tiers, by what the user is doing:
/// - `filmstrip`: a few small frames per clip, decoded once in the background at ingest. The grid,
///   and the frames the facts (clipping, exposure, motion, focus) are measured on. Always.
/// - `proxy`: a ~540p frame at the hovered time for the one clip under the cursor, plus a short
///   lookahead in the direction of travel. Never for the grid.
/// - `frame`: one frame at the file's own size when a key asks for it (the focus check). Decoded,
///   shown, released. Never cached.
///
/// The Rec.709 preview transform runs at draw time on every tier; caches hold log frames.
///
/// Every number below is a starting guess, named so the harness can find the right one. The
/// real-clip test on the 8 GB M1 (PROJECT STATE, first tasks §2) is what settles them.
nonisolated enum VideoPolicy {
    enum Tier: String, Sendable, CaseIterable { case filmstrip, proxy, frame }

    // MARK: Sizes

    /// Filmstrip frames are this wide (device px); height follows the clip's aspect.
    static let filmstripWidth = 160
    /// Frames per clip in a filmstrip, for a clip long enough to carry them.
    static let filmstripFrames = 8
    /// A clip shorter than this gets fewer frames: one per `filmstripSecondsPerFrame`, at least 2.
    static let filmstripSecondsPerFrame = 1.0
    /// The proxy's long edge (device px): 960 × 540 for 16:9.
    static let proxyLongEdge = 960

    /// Where in a clip the filmstrip samples, as fractions of its duration: evenly spaced, and
    /// never the very first or last frame (a camera starting and stopping). A 0.3 s clip gets 2.
    static func filmstripFractions(duration: TimeInterval, frames: Int = filmstripFrames) -> [Double] {
        guard duration > 0, frames > 0 else { return [] }
        let n = max(2, min(frames, Int((duration / filmstripSecondsPerFrame).rounded(.down))))
        return (0..<n).map { (Double($0) + 0.5) / Double(n) }
    }

    /// The size a tier decodes at for a `w` × `h` source: the decoder is asked for this size, so
    /// the full frame never lands in memory except for `frame`. Never upscales.
    static func decodeSize(for tier: Tier, width w: Int, height h: Int) -> (width: Int, height: Int) {
        guard w > 0, h > 0 else { return (0, 0) }
        let longEdge: Int
        switch tier {
        case .filmstrip: return fit(w, h, width: filmstripWidth)
        case .proxy: longEdge = proxyLongEdge
        case .frame: return (w, h)
        }
        return w >= h ? fit(w, h, width: longEdge) : fit(w, h, height: longEdge)
    }

    private static func fit(_ w: Int, _ h: Int, width: Int) -> (width: Int, height: Int) {
        guard w > width else { return (w, h) }
        return (width, max(1, Int((Double(h) * Double(width) / Double(w)).rounded())))
    }
    private static func fit(_ w: Int, _ h: Int, height: Int) -> (width: Int, height: Int) {
        guard h > height else { return (w, h) }
        return (max(1, Int((Double(w) * Double(height) / Double(h)).rounded())), height)
    }

    // MARK: Memory

    /// Bytes one decoded frame takes: 4 channels, half float when the frame will carry the log →
    /// Rec.709 transform on the GPU, 8-bit when it is a filmstrip JPEG-sized raster.
    static func frameBytes(width w: Int, height h: Int, halfFloat: Bool) -> Int { max(0, w) * max(0, h) * 4 * (halfFloat ? 2 : 1) }

    /// Fixed, tunable budgets. The three caches are separate `LookByteCache`s; nothing shares a cap.
    struct Budgets: Equatable, Sendable {
        /// Filmstrip frames for the whole shoot, in memory, as compressed JPEG bytes: ~25 KB a
        /// clip measured on an ILCE-7M3 card (2026-10-08), so a 401-clip card is ~10 MB. Raw
        /// RGBA would be 461 KB a clip (185 MB for that card), past this budget, so filmstrips
        /// are kept compressed and decoded to a texture only for the tiles in view, like the
        /// stills thumbnails. `filmstripJPEGBytesPerClip` is the planning figure.
        var filmstripBytes = 96 << 20
        /// Proxy frames in memory: the clip under the cursor and the lookahead.
        var proxyBytes = 192 << 20
        /// Proxy frames spilled to disk, keyed by file identity; deleted when a clip is cut or the shoot closes.
        var proxyDiskBytes = 2 << 30
        /// Decoded frames waiting to be drawn or measured, across all tiers.
        var framesInFlight = 4
        /// Decoder sessions at once. Each holds reference frames at the decode size.
        var decoders = 2
        /// `frame` tier: at most this many full-size frames alive, never cached.
        var fullFrames = 1
    }

    /// The budgets for a Mac with `physicalMemory` bytes: one decoder and smaller caches at 8 GB
    /// or less (the target machine), two decoders above.
    static func budgets(physicalMemory: UInt64) -> Budgets {
        var b = Budgets()
        if physicalMemory <= (8 << 30) { b.decoders = 1; b.proxyBytes = 128 << 20; b.filmstripBytes = 64 << 20 }
        return b
    }

    /// A filmstrip's compressed size for planning: 8 frames at 160 px, JPEG q4, measured 25 KB
    /// a clip; 32 KB leaves room for busier frames.
    static let filmstripJPEGBytesPerClip = 32 << 10

    /// How many clips' filmstrips a budget holds compressed.
    static func filmstripClips(in bytes: Int) -> Int { bytes / filmstripJPEGBytesPerClip }

    /// Admission: a request for `bytes` more is allowed only while what is in flight stays under
    /// the cap. Ask before allocating; a refused request waits in its queue, it never allocates
    /// and hopes.
    static func admits(inFlightBytes: Int, request: Int, cap: Int) -> Bool { inFlightBytes + request <= cap }

    /// Under memory pressure, the order caches are asked to drop, by name: full frames first, then
    /// proxies that are not the hovered clip's current frame, then filmstrips off screen. Never the
    /// hovered clip's frame on screen, never the filmstrips in view (the grid must stay drawn).
    static let pressureOrder = ["fullFrames", "proxiesNotHovered", "filmstripsOffscreen"]

    /// What a pressure level drops: a warning takes the first two, critical takes all three.
    static func drops(pressure: Pressure) -> [String] {
        switch pressure {
        case .none: return []
        case .warning: return Array(pressureOrder.prefix(2))
        case .critical: return pressureOrder
        }
    }

    enum Pressure: Int, Sendable, Comparable {
        case none = 0, warning = 1, critical = 2
        static func < (a: Pressure, b: Pressure) -> Bool { a.rawValue < b.rawValue }
    }

    // MARK: Pacing (thermal, battery, a slowed chip)

    /// Background work (filmstrips, facts, proxy lookahead) runs at a duty cycle: the share of
    /// each second the decoders may work. The clip under the cursor is foreground and is never
    /// paced. Levels step down at once on any worsening signal and step back up one at a time
    /// after `recoverAfterSeconds` without one, because the thermal state lags the temperature
    /// and a quick step-up oscillates.
    struct Pace: Equatable, Sendable {
        /// 0 … 3: nominal, eased, slowed, paused.
        var level: Int
        var dutyCycle: Double
        var decoders: Int
        var paused: Bool { level >= 3 }
        /// The plain-language reason for the footer, nil at nominal.
        var reason: String?
    }

    static let dutyCycles: [Double] = [1.0, 0.6, 0.25, 0.0]
    static let recoverAfterSeconds: TimeInterval = 25
    /// Decode time per frame this much above the clip's nominal baseline means the chip has
    /// slowed, whatever the thermal state says.
    static let slowdownRatio = 1.5

    /// The level the signals ask for right now (0 … 3), from the thermal state as an Int
    /// (`LookDecoderProbe.thermalLevel`, 0 nominal … 3 critical), Low Power Mode, memory pressure,
    /// and the measured decode-time ratio (1.0 = at baseline).
    static func askedLevel(thermalState: Int, lowPower: Bool, pressure: Pressure, slowdown: Double) -> Int {
        var l = 0
        switch thermalState { case ...0: l = 0; case 1: l = 1; case 2: l = 2; default: l = 3 }
        if lowPower { l = max(l, 1) }
        switch pressure { case .none: break; case .warning: l = max(l, 2); case .critical: l = 3 }
        if slowdown >= slowdownRatio * 2 { l = max(l, 2) } else if slowdown >= slowdownRatio { l = max(l, 1) }
        return l
    }

    /// The next level from the current one: down at once to whatever is asked, up by one only
    /// after `quietFor` seconds in which nothing asked for worse.
    static func nextLevel(current: Int, asked: Int, quietFor: TimeInterval) -> Int {
        if asked > current { return asked }
        if asked < current, quietFor >= recoverAfterSeconds { return current - 1 }
        return current
    }

    static func pace(level: Int, budgets: Budgets, reason: String? = nil) -> Pace {
        let l = max(0, min(3, level))
        let why: String? = l == 0 ? nil : (reason ?? ["", "facts eased", "facts slowed", "facts paused"][l])
        return Pace(level: l, dutyCycle: dutyCycles[l], decoders: l >= 2 ? 1 : budgets.decoders, reason: why)
    }

    /// Any key, scroll or hover pauses background work this long so the foreground is answered first.
    static let yieldMs: Double = 200

    // MARK: Seeking

    /// Long GOP (XAVC S) seeks land on the nearest earlier keyframe and show it while the exact
    /// frame decodes forward; All-Intra (XAVC S-I) seeks are exact at once.
    enum Seek: Sendable { case exact, keyframeFirst }
    static func seek(allIntra: Bool) -> Seek { allIntra ? .exact : .keyframeFirst }

    /// Every frame is a keyframe → All-Intra. Judged from the first `sampled` frames' key flags.
    static func isAllIntra(keyFlags: [Bool]) -> Bool { !keyFlags.isEmpty && keyFlags.allSatisfy { $0 } }

    // MARK: Profile → preview transform

    /// The display transform a clip's preview needs, from the capture profile. Sony writes the
    /// profile in the clip's XML sidecar (`<Item name="CaptureGammaEquation">` and
    /// `CaptureColorPrimaries` under `AcquisitionRecord`, `C0001M01.XML` beside `C0001.MP4`); the
    /// MP4's own colour tags say bt709 whatever was shot (measured on an ILCE-7M3 card, 2026-10-08:
    /// 401 clips, every one `rec709-xvycc` / `rec709`). A clip copied without its sidecar has no
    /// profile, and the preview must say so rather than guess.
    ///
    /// The S-Log value strings are Sony's as this module expects them; `.unknown` is the answer for
    /// any string not listed, never a guess. Verify against an ILCE-7SM3 sidecar before trusting
    /// the log cases (open: no S-Log3 clip measured yet).
    enum Transform: String, Sendable, Equatable {
        case display                 // already a display gamma (Rec.709, xvYCC, Cine, HLG shown as is)
        case slog3SGamut3Cine        // PP8 / PP9 with S-Gamut3.Cine
        case slog3SGamut3            // S-Log3 with the wide S-Gamut3
        case slog2SGamut3            // PP7
        case hlg                     // HLG: a display transform of its own, shown as is in v1
        case unknown                 // no sidecar, or a value this list does not know
    }

    static func transform(gamma: String?, primaries: String?) -> Transform {
        guard let g = gamma?.lowercased() else { return .unknown }
        let p = primaries?.lowercased() ?? ""
        switch g {
        case "s-log3-cine", "s-log3":
            if p.contains("cine") || g == "s-log3-cine" { return .slog3SGamut3Cine }
            if p.contains("s-gamut3") { return .slog3SGamut3 }
            return .slog3SGamut3Cine
        case "s-log2": return .slog2SGamut3
        case "hlg", "hlg1", "hlg2", "hlg3", "rec2100-hlg": return .hlg
        case "rec709", "rec709-xvycc", "rec709-xvycc-cine", "cine1", "cine2", "cine3", "cine4", "still", "itu709", "itu709-800": return .display
        default: return .unknown
        }
    }

    /// The sidecar's name for a clip: `C0001.MP4` → `C0001M01.XML`, in the same folder.
    static func sidecarName(forClip name: String) -> String? {
        let u = URL(fileURLWithPath: name)
        let stem = u.deletingPathExtension().lastPathComponent
        guard !stem.isEmpty, ["mp4", "mov", "mxf"].contains(u.pathExtension.lowercased()) else { return nil }
        return stem + "M01.XML"
    }

    /// The user's answer to `What was this shot in?` (PROMPT-video-skim §5) when the sidecar is
    /// missing: remembered per shoot, applied to every clip without a profile.
    static func transform(answer: String) -> Transform {
        switch answer.lowercased() {
        case "s-log3", "slog3": return .slog3SGamut3Cine
        case "s-log2", "slog2": return .slog2SGamut3
        case "hlg": return .hlg
        case "none", "rec709", "rec.709": return .display
        default: return .unknown
        }
    }

    // MARK: Levels (PROMPT-video-skim §2)

    /// The four levels the page folds between. Each keeps one more tier resident than the one
    /// above it; furling a level releases its tier and nothing above it.
    enum Level: Int, Sendable, Comparable, CaseIterable {
        case chapters = 0, takes = 1, clip = 2, frame = 3
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    /// What is resident at a level: Chapters needs no decoded frame at all (metadata and one
    /// filmstrip frame per chapter, already in the filmstrip cache); Takes the filmstrips; Clip
    /// the hovered clip's proxies on top; Frame one full frame on top of that.
    static func residentTiers(at level: Level) -> [Tier] {
        switch level {
        case .chapters, .takes: return [.filmstrip]
        case .clip: return [.filmstrip, .proxy]
        case .frame: return [.filmstrip, .proxy, .frame]
        }
    }

    /// Moving from one level to another: the tiers to release (going up) — never the filmstrips.
    static func release(from: Level, to: Level) -> [Tier] {
        let was = Set(residentTiers(at: from).map(\.rawValue)), now = Set(residentTiers(at: to).map(\.rawValue))
        return Tier.allCases.filter { was.contains($0.rawValue) && !now.contains($0.rawValue) && $0 != .filmstrip }
    }

    // MARK: Mode (PROJECT STATE, video v1 §2; PROMPT-video-skim §10)

    enum Mode: String, Sendable { case video, photos }

    /// A card with mostly clips opens in video mode, mostly photos in photo mode; equal counts
    /// open in photos (the shipped step). The page shows both counts and one key switches.
    static func mode(clips: Int, photos: Int) -> Mode { clips > photos ? .video : .photos }

    // MARK: Facts → chips (PROMPT-video-skim §6, §7)

    /// One clip's measurements, as the Mac computed them from the filmstrip frames after the
    /// preview transform. Nil = not measured (yet, or unreliable). Numbers only.
    struct Facts: Equatable, Sendable {
        /// Mean exposure against middle grey, stops.
        var ev: Double? = nil
        /// Share of pixels at the clip point, 0 … 1.
        var clip: Double? = nil
        /// Share of pixels crushed to black, 0 … 1.
        var crush: Double? = nil
        /// The lowest sharpness among the frames, in the measure's own units.
        var sharp: Double? = nil
        /// Mean frame-to-frame motion, px per frame at proxy size, split into a consistent
        /// (pan) and an inconsistent (shake) part.
        var pan: Double? = nil
        var shake: Double? = nil
        /// One frame far from its neighbours.
        var bump: Bool? = nil
        var state: State = .pending
        enum State: String, Sendable { case pending, ready, unreliable }
    }

    enum Chip: Equatable, Sendable, Hashable {
        case stops(Double)           // `+1.3 stops`
        case clipped(Double)         // `4% clipped`
        case crushed(Double)         // `9% crushed`
        case soft
        case shake
        case pan
        case bump
        case rate(String)            // `120p`, only when it differs from the shoot's
        case sidecarMissing

        /// The fact a chip stands for, the name `lumina.video.dismiss(id, fact)` uses.
        var fact: String {
            switch self {
            case .stops: return "ev"; case .clipped: return "clip"; case .crushed: return "crush"
            case .soft: return "sharp"; case .shake: return "shake"; case .pan: return "pan"
            case .bump: return "bump"; case .rate: return "rate"; case .sidecarMissing: return "sidecar"
            }
        }

        /// The plain words on the chip.
        var text: String {
            switch self {
            case .stops(let v): return String(format: "%@%.1f stops", v >= 0 ? "+" : "−", abs(v))
            case .clipped(let v): return "\(Int((v * 100).rounded()))% clipped"
            case .crushed(let v): return "\(Int((v * 100).rounded()))% crushed"
            case .soft: return "soft"; case .shake: return "shake"; case .pan: return "pan"; case .bump: return "bump"
            case .rate(let r): return r; case .sidecarMissing: return "sidecar missing"
            }
        }
    }

    /// The lines a measurement must pass to earn a chip. Starting values; the dismissal rate on
    /// real shoots tunes them (a chip dismissed more than a third of the time is noise).
    struct Lines: Equatable, Sendable {
        var stops = 1.0                 // |ev| at or past this
        var clipped = 0.02              // share of pixels
        var crushed = 0.05
        /// `soft`: sharpness below this share of the shoot's median sharpness (relative, because
        /// the measure's units depend on the lens and the scene).
        var softBelowMedian = 0.35
        /// `shake`: the inconsistent motion part at or past this, px per frame at proxy size.
        var shake = 2.0
        /// `pan`: the consistent part at or past this, when shake is under its line.
        var pan = 6.0
    }
    static let lines = Lines()

    /// Chips for one clip, worst first, at most `max`. `dismissed` facts are left out of the
    /// tile (the page draws them hollow in the facts line). `shootMedianSharp` nil = the
    /// shoot's median isn't known yet, so `soft` can't be judged and isn't shown.
    static func chips(for f: Facts, dismissed: Set<String> = [], fps: Double? = nil, shootFps: Double? = nil,
                      shootMedianSharp: Double? = nil, sidecar: Bool = true, lines: Lines = lines, max: Int = 3) -> [Chip] {
        var out: [(Chip, Double)] = []      // chip, severity (higher is worse)
        if !sidecar { out.append((.sidecarMissing, 1000)) }
        if f.state == .ready {
            if let c = f.clip, c >= lines.clipped { out.append((.clipped(c), 50 + c * 100)) }
            if let c = f.crush, c >= lines.crushed { out.append((.crushed(c), 40 + c * 100)) }
            if let s = f.sharp, let m = shootMedianSharp, m > 0, s < m * lines.softBelowMedian { out.append((.soft, 45)) }
            if f.bump == true { out.append((.bump, 35)) }
            if let e = f.ev, abs(e) >= lines.stops { out.append((.stops(e), 30 + abs(e))) }
            if let sh = f.shake, sh >= lines.shake { out.append((.shake, 20 + sh)) }
            else if let p = f.pan, p >= lines.pan { out.append((.pan, 5)) }
        }
        if let fps, let shootFps, abs(fps - shootFps) >= 0.5 { out.append((.rate("\(Int(fps.rounded()))p"), 10)) }
        return out.filter { !dismissed.contains($0.0.fact) }.sorted { $0.1 > $1.1 }.prefix(Swift.max(0, max)).map(\.0)
    }

    /// The sweep (⇧S): a clip is hidden when a chip that is not dismissed sits past its line and
    /// is one of the technical misses: clipped, crushed, soft, bump. Never exposure, motion or
    /// rate (too often deliberate), never a pending clip.
    static func sweeps(_ f: Facts, dismissed: Set<String> = [], shootMedianSharp: Double? = nil, lines: Lines = lines) -> Bool {
        chips(for: f, dismissed: dismissed, shootMedianSharp: shootMedianSharp, lines: lines, max: 9)
            .contains { ["clip", "crush", "sharp", "bump"].contains($0.fact) }
    }

    /// The footer's sentence before an area action lands (§4): `cut 9 clips · 4.2 GB`.
    static func areaSentence(mark: String, clips: Int, bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        return "\(mark) \(clips) clip\(clips == 1 ? "" : "s") · \(String(format: gb >= 10 ? "%.0f" : "%.1f", gb)) GB"
    }

    // MARK: Skimming (PROMPT-video-skim §12)

    /// Takes-level tile widths, device px: the default and the − / + steps. Nothing to hit on a
    /// tile is under `hitPx`.
    static let tileWidths = [240, 320, 480]
    static let tileWidthDefault = 320
    static let hitPx = 44

    /// The time under the pointer on a tile: the left edge is the clip's start and the right edge
    /// its end. Clamped so the edges never ask past the clip.
    static func skimTime(x: Double, tileWidth: Double, duration: TimeInterval) -> TimeInterval {
        guard tileWidth > 0, duration > 0 else { return 0 }
        return min(1, max(0, x / tileWidth)) * duration
    }

    /// Seconds one pixel of tile covers. Past `approxAbovePerPx` the readout says `≈`: the tile
    /// can't be precise and the Clip level is the precise skim.
    static func secondsPerPx(tileWidth: Double, duration: TimeInterval) -> Double { tileWidth > 0 ? duration / tileWidth : 0 }
    static let approxAbovePerPx = 0.25

    static func skimIsApproximate(tileWidth: Double, duration: TimeInterval) -> Bool { secondsPerPx(tileWidth: tileWidth, duration: duration) > approxAbovePerPx }

    /// The frame to show first for a skim at `t`: the nearest earlier keyframe for Long GOP (shown
    /// at once, sharpened to the exact frame when it lands), the frame itself for All-Intra.
    static func firstFrame(for t: TimeInterval, keyframeEvery: Int, fps: Double, allIntra: Bool) -> TimeInterval {
        guard !allIntra, keyframeEvery > 1, fps > 0 else { return t }
        let frame = (t * fps).rounded(.down)
        return (frame - frame.truncatingRemainder(dividingBy: Double(keyframeEvery))) / fps
    }

    /// Scrub latency the harness holds the Clip level to: the keyframe stand-in within
    /// `scrubFirstMs`, the exact frame within `scrubExactMs`, on the M1.
    static let scrubFirstMs: Double = 50
    static let scrubExactMs: Double = 150

    // MARK: Gates (the probe's `video-budget` scenario)

    /// What the harness holds the minimum loop to on the 8 GB M1, as regression gates. Reported
    /// on any other Mac. Starting values; the first real-clip run sets them.
    struct Gates: Equatable, Sendable {
        /// Open → first rows on screen (metadata only, no decode).
        var firstRowSeconds = 2.0
        /// All fact flags ready for 50 clips, filmstrips included.
        var flags50ClipsSeconds = 90.0
        /// phys_footprint of the app process while the loop runs.
        var peakMB = 1200.0
        /// Proxy cache on disk after the run.
        var proxyDiskMB = 2048.0
        /// Decoder sessions ever alive at once.
        var decodersPeak = 2
        /// Full-size frames ever alive at once.
        var fullFramesPeak = 1
    }
    static let m1Gates = Gates()
}
