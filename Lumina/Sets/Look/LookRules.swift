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
        /// profile only: its lookup tables (`hsm`: hueDivisions × satDivisions × valDivisions entries of
        /// hueShift, satScale, valScale in value-hue-sat order; `curve`: curveNodes values 0 → 1).
        var tables: [String: [Double]]? = nil
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

    /// Where the stages sit, and why the added ones sit where they do:
    ///
    /// - `camera` (the camera profile) comes first, right on the base: it swaps Adobe Color for the
    ///   camera's own look, and every slider then works on top of it, as in Lightroom, where the
    ///   profile sits under the Basic panel.
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
    /// - `dehaze` follows `contrast`: like Highlights and Contrast it sets the tones (and the
    ///   colour that comes with taking the airlight out), so the curve, colour and the local
    ///   stages work on what it leaves, as in Lightroom, where Dehaze sits in the Basic panel.
    static let canonicalOrder = ["rawDevelop", "camera", "exposure", "whiteBalance", "whitesBlacks", "tone", "contrast", "dehaze", "curve", "colour", "mixer",
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
    static let addedStages: [(name: String, after: String)] = [("curve", "contrast"), ("mixer", "colour"), ("camera", "rawDevelop"), ("dehaze", "contrast")]

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
        if let p = stages["profile"] { try Self.validateProfile(p) }
    }

    /// The camera profile's tables (`LookMath.Profile`): sizes that match its divisions, finite
    /// numbers, a monotone curve from 0 to 1, valScale 1 wherever saturation is 0 (a grey stays
    /// grey), positive scales.
    static func validateProfile(_ p: Stage) throws {
        let hue = Int(p.coefficients["hueDivisions"] ?? 30), sat = Int(p.coefficients["satDivisions"] ?? 8), val = Int(p.coefficients["valDivisions"] ?? 1)
        let nodes = Int(p.coefficients["curveNodes"] ?? 33)
        guard hue >= 1, sat >= 1, val >= 1, nodes >= 2, hue * sat * val <= 65536 else { throw LoadError(description: "profile: divisions \(hue) × \(sat) × \(val), nodes \(nodes)") }
        if let hsm = p.tables?["hsm"] {
            guard hsm.count == hue * sat * val * 3 else { throw LoadError(description: "profile.hsm has \(hsm.count) numbers, wants \(hue * sat * val * 3)") }
            for (i, v) in hsm.enumerated() {
                guard v.isFinite else { throw LoadError(description: "profile.hsm[\(i)] is \(v)") }
                let field = i % 3, cell = i / 3, s = cell % sat
                if field == 1, v < 0 { throw LoadError(description: "profile.hsm: satScale below 0 at \(cell)") }
                if field == 2, v <= 0 { throw LoadError(description: "profile.hsm: valScale not positive at \(cell)") }
                if field == 2, s == 0, abs(v - 1) > 1e-6 { throw LoadError(description: "profile.hsm: valScale must be 1 where saturation is 0 (cell \(cell))") }
            }
        }
        if let c = p.tables?["curve"] {
            guard c.count == nodes else { throw LoadError(description: "profile.curve has \(c.count) nodes, wants \(nodes)") }
            guard c.allSatisfy(\.isFinite), abs(c[0]) < 1e-6, abs(c[nodes - 1] - 1) < 1e-6 else { throw LoadError(description: "profile.curve must run 0 → 1") }
            for i in 1..<nodes where c[i] < c[i - 1] - 1e-9 { throw LoadError(description: "profile.curve is not monotone at node \(i)") }
        }
    }

    /// What the develop caches key on besides rawDevelop's coefficients: the profile's numbers,
    /// shortened. Empty without a profile.
    var profileSignature: String {
        guard let p = stages["profile"] else { return "" }
        // FNV-1a over the canonical text: stable across processes (Hasher is seeded per run), Foundation only
        var text = ""
        for (k, v) in p.coefficients.sorted(by: { $0.key < $1.key }) { text += "\(k)=\(v);" }
        for (k, v) in (p.tables ?? [:]).sorted(by: { $0.key < $1.key }) { text += "\(k):" + v.map { String($0) }.joined(separator: ",") + ";" }
        var h: UInt64 = 0xcbf29ce484222325
        for b in text.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return "profile=\(String(h, radix: 16))"
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
