import CoreImage
import Foundation
import XCTest
@testable import Lumina

/// W6 / A02 step 1 — dump `ImageStats` and the incumbent Auto proposal for every
/// labelled frame, so the regression itself can be trained outside the app target.
///
/// This is deliberately a dump, not a model. It exists because `ImageStats` and
/// `AutoDevelop` are app code: the features A02 regresses on must be the *same*
/// numbers the shipping auto pass measures, or the comparison against A00 is
/// between two different feature sets and means nothing.
///
/// Stats are taken exactly as the product takes them — `PreparedRawSession.imageStats()`,
/// which decodes at `RawIntent.neutral` on the interactive tier, so the measurement
/// describes the photograph rather than any recipe already on it.
///
/// Fixture-gated: needs labels.jsonl from T1 and the RAW volume mounted.
///   LUMINA_A02_LABELS  labels.jsonl  (default ~/LuminaEvidence/export-labels-01/labels.jsonl)
///   LUMINA_A02_OUT     output folder (default ~/LuminaEvidence/a02-regression)
@MainActor
final class A02FeatureExtractionTests: XCTestCase {

    private static let controls = ["exposure", "contrast", "highlights", "shadows",
                                   "vibrance", "saturation"]

    override func setUp() {
        super.setUp()
        executionTimeAllowance = 4 * 60 * 60
    }

    func testDumpStatsAndIncumbentProposals() async throws {
        let env = ProcessInfo.processInfo.environment
        let labelsURL = URL(fileURLWithPath: env["LUMINA_A02_LABELS"]
            ?? NSString(string: "~/LuminaEvidence/export-labels-01/labels.jsonl").expandingTildeInPath)
        let outDir = URL(fileURLWithPath: env["LUMINA_A02_OUT"]
            ?? NSString(string: "~/LuminaEvidence/a02-regression").expandingTildeInPath,
            isDirectory: true)

        guard let text = try? String(contentsOf: labelsURL, encoding: .utf8) else {
            throw XCTSkip("T1 labels required at \(labelsURL.path)")
        }
        let labels: [[String: Any]] = text
            .split(separator: "\n")
            .compactMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }
        XCTAssertFalse(labels.isEmpty, "labels.jsonl parsed to nothing")

        var rows: [[String: Any]] = []
        var missingRaw = 0
        var noStats = 0

        for label in labels {
            guard let rawPath = label["raw"] as? String else { continue }
            let url = URL(fileURLWithPath: rawPath)
            guard FileManager.default.fileExists(atPath: rawPath) else { missingRaw += 1; continue }

            let session = PreparedRawSession(assetID: UUID(), rawURL: url)
            guard let stats = await session.imageStats() else { noStats += 1; continue }

            let asset = ModelTestSupport.makeAsset(stats: stats)
            let auto = AutoDevelop.recipe(for: asset, stats: stats)

            var row: [String: Any] = [
                "raw": rawPath,
                "jpeg": label["jpeg"] as? String ?? "",
                "dateTimeOriginal": label["dateTimeOriginal"] as? String ?? "",
                "rawSha256": label["rawSha256"] as? String ?? "",
                // features — exactly what the product measures
                "luminanceBins": stats.luminanceBins,
                "shadowClipFraction": stats.shadowClipFraction,
                "highlightClipFraction": stats.highlightClipFraction,
                "mean": stats.mean,
                "sampleCount": stats.sampleCount,
            ]
            row["nativeTemperature"] = stats.nativeTemperature ?? NSNull()
            row["horizonAngle"] = stats.horizonAngle ?? NSNull()

            // A00 — the incumbent deterministic proposal for the same frame.
            row["a00_exposure"] = auto.exposure
            row["a00_contrast"] = auto.contrast
            row["a00_highlights"] = auto.highlights
            row["a00_shadows"] = auto.shadows
            row["a00_vibrance"] = auto.vibrance
            row["a00_saturation"] = auto.saturation

            // The photographer's own values, carried through unchanged.
            for key in Self.controls {
                row["label_" + key] = label[key] as? Double ?? 0
            }
            rows.append(row)
        }

        XCTAssertGreaterThan(rows.count, 0, "no frame produced stats")

        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let out = outDir.appendingPathComponent("features.jsonl")
        var blob = ""
        for row in rows {
            let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            blob += String(decoding: data, as: UTF8.self) + "\n"
        }
        try blob.write(to: out, atomically: true, encoding: .utf8)

        let summary: [String: Any] = [
            "labelsRead": labels.count,
            "rowsEmitted": rows.count,
            "missingRawFile": missingRaw,
            "statsFailed": noStats,
            "binCount": ImageStats.binCount,
        ]
        let sdata = try JSONSerialization.data(withJSONObject: summary,
                                               options: [.prettyPrinted, .sortedKeys])
        try sdata.write(to: outDir.appendingPathComponent("extraction-summary.json"))
        print("A02-EXTRACT rows=\(rows.count) missingRaw=\(missingRaw) statsFailed=\(noStats)")
    }
}
