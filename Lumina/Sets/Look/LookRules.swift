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
    }

    var version: Int = 1
    var about: String? = nil
    var workingSpace: String = "extendedLinearSRGB"
    var perceptualGamma: Double = 2.2
    var luma: [Double] = [0.2126, 0.7152, 0.0722]
    var order: [String] = LookRules.canonicalOrder
    var stages: [String: Stage] = [:]

    static let canonicalOrder = ["rawDevelop", "exposure", "whiteBalance", "whitesBlacks", "tone", "contrast", "colour",
                                 "clarity", "sharpen", "vignette", "outputTransform"]
    static let fileName = "rules-v1.json"

    struct LoadError: Error, CustomStringConvertible { let description: String }

    static func load(from url: URL) throws -> LookRules {
        let rules = try JSONDecoder().decode(LookRules.self, from: Data(contentsOf: url))
        try rules.validate()
        return rules
    }

    static func load(json: Data) throws -> LookRules {
        let rules = try JSONDecoder().decode(LookRules.self, from: json)
        try rules.validate()
        return rules
    }

    /// The copy in the app bundle, or `LUMINA_RULES` (a path) when set: the parity loop points the
    /// app at a work-in-progress file without rebuilding.
    static func bundled(bundle: Bundle = .main) throws -> LookRules {
        if let p = ProcessInfo.processInfo.environment["LUMINA_RULES"], !p.isEmpty { return try load(from: URL(fileURLWithPath: p)) }
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
