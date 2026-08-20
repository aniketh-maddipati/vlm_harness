import Foundation

/// Embedded build provenance (F11.4) — install page + bug reports cite this JSON.
struct LuminaBuildManifest: Codable, Equatable, Sendable {
    struct BetaDiagnostics: Codable, Equatable, Sendable {
        var kind: String
        var path: String
        var expiresAtMarketingVersion: String
        var cite: [String]?
    }

    var schemaVersion: Int
    var gitSha: String
    var tokensHash: String
    var fixtureManifestVersion: String
    var contractVersion: String
    var buildDate: String
    var marketingVersion: String
    var bundleVersion: String
    var configuration: String
    var betaDiagnostics: BetaDiagnostics?

    static let resourceName = "LuminaBuildManifest"
    static let resourceExtension = "json"

    /// Load manifest bundled in `Lumina.app/Contents/Resources/`.
    static func load(from bundle: Bundle = .main) -> LuminaBuildManifest? {
        for candidate in candidateBundles(startingWith: bundle) {
            guard let url = candidate.url(
                forResource: resourceName,
                withExtension: resourceExtension
            ) else { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            if let manifest = try? JSONDecoder().decode(LuminaBuildManifest.self, from: data) {
                return manifest
            }
        }
        return nil
    }

    /// One-line citation for bug reports / About surfaces.
    var bugReportLine: String {
        var parts = [
            "Lumina \(marketingVersion) (\(gitSha.prefix(12)))",
            "tokens=\(tokensHash.prefix(12))",
            "fixture=\(fixtureManifestVersion)",
            "contract=\(contractVersion)",
            "built=\(buildDate)",
        ]
        if let beta = betaDiagnostics {
            parts.append("betaDiag=\(beta.kind) expires=\(beta.expiresAtMarketingVersion)")
        }
        return parts.joined(separator: " · ")
    }

    private static func candidateBundles(startingWith bundle: Bundle) -> [Bundle] {
        var seen = Set<ObjectIdentifier>()
        var ordered: [Bundle] = []

        func append(_ candidate: Bundle) {
            let key = ObjectIdentifier(candidate)
            guard seen.insert(key).inserted else { return }
            ordered.append(candidate)
        }

        append(bundle)
        append(.main)
        Bundle.allBundles.forEach(append)
        Bundle.allFrameworks.forEach(append)
        return ordered
    }
}
