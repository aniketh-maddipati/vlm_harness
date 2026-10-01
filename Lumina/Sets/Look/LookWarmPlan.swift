import Foundation

/// Which stage graphs the Edit canvas compiles before the user needs them.
///
/// `LookPipeline.apply` leaves a stage at its reset value out of the graph, and Core Image fuses
/// the stages that run into one Metal program per *set* of stages, compiled the first time that
/// set renders: 11 to 30 ms on the thread that renders (measured on an M4 Pro with Metal's
/// on-disk cache cold, i.e. after an update changed a kernel; about 0.1 ms afterwards). On the
/// canvas that thread is the main thread, so the first frame of a drag on a slider whose stage
/// was at reset stalled for a frame or two. What the measurements showed, and this plan relies on:
///
/// - the cost is per set of stages (exposure and contrast warm, exposure + contrast still cold),
///   not per kernel and not per slider value;
/// - compiled programs are shared by every `CIContext` on the Metal device, so a render on
///   another context, on a background queue, warms the drawable's context too (its own first
///   render of the set then takes 0.3 to 1.3 ms);
/// - the warm-up has to be the canvas's own graph at its own size: a 16 px corner of it compiles
///   different blur programs (tone, clarity, sharpen) and leaves 9 to 14 ms behind;
/// - an intermediate between stages does not make the programs independent of the set (the
///   first and last kernel still fuse with the source read and the output transform) and costs
///   1 to 3 ms per `base` frame, so the graph is left as it is.
///
/// So while the canvas is idle the controller renders, off the main thread, the look on screen
/// and that look with each stage switched (on when it is at reset, off when it runs): every set
/// a single slider can reach, including a drag through the reset value. Both tiers. It repeats
/// when the look at rest runs a different set of stages. Never during a drag.
///
/// Foundation only: the plan is plain state, tested on Linux (`LookCanvasTests`).
nonisolated struct LookWarmPlan: Sendable {
    struct Job: Equatable, Sendable {
        let look: Look
        /// The stages the look runs, in order ("exposure+contrast", or "none").
        let stages: String
        let tier: LookCanvasSchedule.Tier
        /// What the programs depend on besides the stages (sizes, display colour space, zoom).
        let env: String
        var key: String { "\(env)|\(stages)|\(tier.rawValue)" }
    }

    struct Stats: Codable, Equatable, Sendable {
        var enabled = true
        /// Warm-up renders finished, and the time they took on the background queue.
        var warmed = 0
        var ms = 0.0
        var lastMs = 0.0
        var maxMs = 0.0
        /// Warm-up renders still owed for the look on the canvas; `running` while one is in flight.
        var pending = 0
        var running = false
    }

    /// The first time the drawable rendered a set of stages: its time on the main thread.
    struct FirstRender: Codable, Equatable, Sendable {
        var stages: String
        var tier: String
        var ms: Double
        /// A warm-up render of the same graph had finished before.
        var warmed: Bool
        var drag: Bool
    }

    private var warmed: Set<String> = []
    private var rendered: Set<String> = []
    private(set) var stats = Stats()

    init(enabled: Bool = true) { stats.enabled = enabled }

    /// The stages `look` runs, in the rules' order.
    static func signature(_ look: Look, stages: [String]) -> String {
        let on = stages.filter(look.runs)
        return on.isEmpty ? "none" : on.joined(separator: "+")
    }

    /// The look itself, then the look with each stage switched; one per distinct set of stages.
    static func looks(around look: Look, stages: [String]) -> [Look] {
        var seen: Set<String> = [], out: [Look] = []
        for l in [look] + stages.map(look.toggling) where seen.insert(signature(l, stages: stages)).inserted { out.append(l) }
        return out
    }

    /// The warm-up renders still owed around `look`: `small` first (what a drag renders), then
    /// `base` (the rest render). Sets the drawable has rendered itself are not repeated.
    func jobs(around look: Look, stages: [String], env: String) -> [Job] {
        guard stats.enabled else { return [] }
        let looks = Self.looks(around: look, stages: stages)
        return [LookCanvasSchedule.Tier.small, .base].flatMap { tier in
            looks.map { Job(look: $0, stages: Self.signature($0, stages: stages), tier: tier, env: env) }
        }.filter { !warmed.contains($0.key) && !rendered.contains($0.key) }
    }

    func next(around look: Look, stages: [String], env: String) -> Job? { jobs(around: look, stages: stages, env: env).first }

    mutating func finished(_ job: Job, ms: Double) {
        trim()
        warmed.insert(job.key)
        stats.warmed += 1
        stats.ms += ms
        stats.lastMs = ms
        stats.maxMs = max(stats.maxMs, ms)
    }

    /// The drawable is about to render `look` at `tier`. `first` when it never rendered this set
    /// of stages before (in this `env`); `warmed` when a warm-up render of it had finished.
    mutating func rendering(_ look: Look, tier: LookCanvasSchedule.Tier, stages: [String], env: String) -> (first: Bool, warmed: Bool, stages: String) {
        let sig = Self.signature(look, stages: stages)
        let key = Job(look: look, stages: sig, tier: tier, env: env).key
        if rendered.contains(key) { return (false, true, sig) }
        trim()
        rendered.insert(key)
        return (true, warmed.contains(key), sig)
    }

    /// Bounded: a long session over many canvas sizes starts over (the programs stay compiled).
    private mutating func trim() {
        if warmed.count + rendered.count > 8192 { warmed = []; rendered = [] }
    }
}

nonisolated extension Look {
    /// Whether `LookPipeline.apply` puts `stage` in the graph: a stage whose sliders are all at
    /// reset is left out.
    func runs(_ stage: String) -> Bool {
        switch stage {
        case "exposure": return ev != 0
        case "whiteBalance": return wb != nil
        case "whitesBlacks": return whites != 0 || blacks != 0
        case "tone": return highlights != 0 || shadows != 0
        case "contrast": return contrast != 0
        case "colour": return vibrance != 0 || saturation != 0 || bw
        case "clarity": return clarity != 0
        case "sharpen": return sharpen != 0
        case "vignette": return vignette != 0
        default: return false
        }
    }

    /// The look with `stage` switched: back to reset when it runs, to a small value when it
    /// doesn't (the program is the same for every value). The other stages are untouched.
    func toggling(_ stage: String) -> Look {
        var l = self
        let on = !runs(stage)
        switch stage {
        case "exposure": l.ev = on ? 0.5 : 0
        case "whiteBalance": l.wb = on ? WhiteBalance(kelvin: 5500, tint: 5) : nil
        case "whitesBlacks": l.whites = on ? 10 : 0; l.blacks = 0
        case "tone": l.shadows = on ? 10 : 0; l.highlights = 0
        case "contrast": l.contrast = on ? 10 : 0
        case "colour": l.vibrance = on ? 10 : 0; l.saturation = 0; l.bw = false
        case "clarity": l.clarity = on ? 10 : 0
        case "sharpen": l.sharpen = on ? 30 : 0
        case "vignette": l.vignette = on ? -10 : 0
        default: break
        }
        return l
    }
}
