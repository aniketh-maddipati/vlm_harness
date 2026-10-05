import Foundation

/// `rules-v1.json`: the stage order, the working space and every stage's fitted coefficients.
/// Shipped in the app bundle; `Tools/parity/loop.sh` rewrites `coefficients` and `locked` and
/// commits the file after each locked stage. Coefficient names are the contract between this
/// module, the Metal kernels (`LookKernels`) and the numpy mirror (`Tools/parity/lookmath.py`).
nonisolated struct LookRules: Codable, Equatable, Sendable {
    struct Stage: Codable, Equatable, Sendable {
        var locked: Bool = false
        var form: String = ""
        var coefficients: [String: Double] = [:]
        /// outputTransform only: which display mapper ends the pipeline (`Mapper`). Absent = clamp.
        var mapper: String? = nil
    }

    /// How outputTransform brings the working space into 0…1: `clamp` (what ships) or `sigmoid`
    /// (`LookMath.DisplayMapper`, a prototype: measured, not adopted).
    enum Mapper: String, Sendable { case clamp, sigmoid }
    var mapper: Mapper { stages["outputTransform"]?.mapper.flatMap(Mapper.init(rawValue:)) ?? .clamp }

    var version: Int = 1
    var about: String? = nil
    var workingSpace: String = "extendedLinearSRGB"
    var perceptualGamma: Double = 2.2
    var luma: [Double] = [0.2126, 0.7152, 0.0722]
    var order: [String] = LookRules.canonicalOrder
    var stages: [String: Stage] = [:]

    /// Where the stages sit, and why the two added ones sit where they do:
    ///
    /// - `curve` (the tone curve) comes after every stage that sets the tones (exposure, white
    ///   balance, whites and blacks, highlights and shadows, contrast): it is display-referred, a
    ///   map from the tone the picture has to the tone it should have, as in Lightroom, where the
    ///   curve follows the Basic panel's tone controls. It comes before `colour`, so vibrance and
    ///   saturation work on the tones the curve left, and before the local stages and the
    ///   vignette, which belong on the finished tones.
    /// - `mixer` (the colour mixer) follows `colour`: the global chroma first, then the per-hue
    ///   trims (with `bw` the picture has no chroma left and the mixer does nothing, as on the
    ///   page, which hides it then). Clarity and sharpening then see the final luminances, and
    ///   the vignette stays last, over everything, as a post-crop effect.
    static let canonicalOrder = ["rawDevelop", "exposure", "whiteBalance", "whitesBlacks", "tone", "contrast", "curve", "colour", "mixer",
                                 "clarity", "sharpen", "vignette", "outputTransform"]
    static let fileName = "rules-v1.json"

    struct LoadError: Error, CustomStringConvertible { let description: String }

    static func load(from url: URL) throws -> LookRules {
        let rules = try JSONDecoder().decode(LookRules.self, from: Data(contentsOf: url)).upgraded()
        try rules.validate()
        return rules
    }

    static func load(json: Data) throws -> LookRules {
        let rules = try JSONDecoder().decode(LookRules.self, from: json).upgraded()
        try rules.validate()
        return rules
    }

    /// The stages added since the first rules files, each with the stage it follows. A file
    /// written before one existed (a candidate under `LUMINA_RULES`, a report's copy) still
    /// loads: the stage is put at its canonical place with no coefficients, i.e. the code's
    /// fallbacks, which are the shipped numbers. It changes nothing for a look that does not
    /// use the stage.
    static let addedStages: [(name: String, after: String)] = [("curve", "contrast"), ("mixer", "colour")]

    func upgraded() -> LookRules {
        var r = self
        for (name, after) in Self.addedStages where !r.order.contains(name) {
            let at = r.order.firstIndex(of: after).map { $0 + 1 } ?? r.order.lastIndex(of: "outputTransform") ?? r.order.count
            r.order.insert(name, at: at)
            if r.stages[name] == nil { r.stages[name] = Stage() }
        }
        return r
    }

    /// The copy in the app bundle. In Debug builds and in the tools (the probe, which has no
    /// bundle, and the parity loop; `LUMINA_TOOLS` in their Package.swift), `LUMINA_RULES` (a
    /// path) when set: a work-in-progress file without rebuilding. The app's Release build reads
    /// only its own bundle (S4): the look's coefficients never come from a path in the environment.
    static func bundled(bundle: Bundle = .main) throws -> LookRules {
        #if DEBUG || LUMINA_TOOLS
        if let p = ProcessInfo.processInfo.environment["LUMINA_RULES"], !p.isEmpty { return try load(from: URL(fileURLWithPath: p)) }
        #endif
        guard let url = bundle.url(forResource: "rules-v1", withExtension: "json") else { throw LoadError(description: "\(fileName) is not in the bundle") }
        return try load(from: url)
    }

    /// Every stage in `order` must exist, in canonical order (the loop may try other orders only
    /// through `order`), and every coefficient must be finite.
    func validate() throws {
        guard version == 1 else { throw LoadError(description: "rules version \(version), this build reads 1") }
        guard Set(order) == Set(Self.canonicalOrder) else { throw LoadError(description: "order must name every stage once: \(order)") }
        guard order.first == "rawDevelop", order.last == "outputTransform" else { throw LoadError(description: "rawDevelop comes first and outputTransform last") }
        for name in order where name != "rawDevelop" && name != "outputTransform" {
            guard stages[name] != nil else { throw LoadError(description: "stage \(name) has no entry") }
        }
        guard perceptualGamma > 1, perceptualGamma < 4 else { throw LoadError(description: "perceptualGamma \(perceptualGamma)") }
        guard luma.count == 3, abs(luma.reduce(0, +) - 1) < 1e-3 else { throw LoadError(description: "luma weights must sum to 1") }
        if let m = stages["outputTransform"]?.mapper, Mapper(rawValue: m) == nil { throw LoadError(description: "outputTransform.mapper \(m): clamp or sigmoid") }
        for (s, st) in stages { for (k, v) in st.coefficients where !v.isFinite { throw LoadError(description: "\(s).\(k) is \(v)") } }
    }

    /// A coefficient, or `fallback` when the file doesn't name it (an older rules file after a
    /// stage gains a parameter).
    func k(_ stage: String, _ name: String, _ fallback: Double) -> Double {
        stages[stage]?.coefficients[name] ?? fallback
    }

    func isLocked(_ stage: String) -> Bool { stages[stage]?.locked ?? false }

    /// The stages between rawDevelop and outputTransform, in the order they run.
    var lookStages: [String] { order.filter { $0 != "rawDevelop" && $0 != "outputTransform" } }

    func encoded() throws -> Data {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(self)
    }
}
