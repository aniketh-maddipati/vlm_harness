import XCTest
@testable import Lumina

/// Checkpoint 02's real-RAW gate: auto must produce a real, non-identity recipe
/// from genuinely decoded pixels — not just from synthesized stats.
///
/// Fixture-gated, never fixture-faked. Point `LUMINA_RAW_DIR` at a folder of RAW
/// files to run it; with no folder the test reports skipped rather than passing
/// vacuously (the repo's committed `.ARW` fixture is a 4-byte placeholder and
/// cannot stand in for a decode).
@MainActor
final class AutoDevelopRawFixtureTests: XCTestCase {

    private static let fixtureCount = 8

    private func rawFixtureURLs() throws -> [URL] {
        guard let root = ProcessInfo.processInfo.environment["LUMINA_RAW_DIR"] else { return [] }
        let folder = URL(fileURLWithPath: root, isDirectory: true)
        let contents = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        let rawExtensions: Set<String> = ["arw", "cr2", "cr3", "nef", "raf", "dng"]
        return contents
            .filter { rawExtensions.contains($0.pathExtension.lowercased()) }
            // A placeholder byte-stub is not a fixture.
            .filter { (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 1_000_000 }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .prefix(Self.fixtureCount)
            .map { $0 }
    }

    func testAutoChangesEveryRawFixture() async throws {
        let urls = try rawFixtureURLs()
        try XCTSkipIf(
            urls.isEmpty,
            "No RAW fixtures. Set LUMINA_RAW_DIR to a folder of RAW files to run this gate."
        )
        XCTAssertEqual(
            urls.count,
            Self.fixtureCount,
            "gate wants \(Self.fixtureCount) fixtures; found \(urls.count)"
        )

        var fingerprints: [String: String] = [:]

        for url in urls {
            let assetID = UUID()
            let session = PreparedRawSession(assetID: assetID, rawURL: url)

            let measured = await session.imageStats()
            let stats = try XCTUnwrap(measured, "no stats measured for \(url.lastPathComponent)")
            XCTAssertGreaterThan(stats.sampleCount, 0, "\(url.lastPathComponent): measured no pixels")
            XCTAssertEqual(
                stats.luminanceBins.count,
                ImageStats.binCount,
                "\(url.lastPathComponent): wrong bin count"
            )
            XCTAssertTrue(
                (0...1).contains(stats.mean),
                "\(url.lastPathComponent): mean \(stats.mean) outside 0…1"
            )
            XCTAssertTrue(
                stats.luminanceBins.contains { $0 > 0 },
                "\(url.lastPathComponent): histogram is empty — decode produced nothing"
            )

            let asset = AssetRecord(
                id: assetID,
                sourceKey: "fixture-\(assetID.uuidString)",
                source: SourceReference(
                    originalPath: url.path,
                    relativePath: url.lastPathComponent,
                    volumeID: "LOCAL",
                    availability: .available
                ),
                filename: url.lastPathComponent,
                imageStats: stats
            )
            let recipe = AutoDevelop.recipe(for: asset, stats: stats)

            XCTAssertNotEqual(
                recipe.valueFingerprint,
                EditRecipe.neutral.valueFingerprint,
                "\(url.lastPathComponent): auto produced an identity recipe — it would change no pixels"
            )
            XCTAssertTrue(
                recipe.hasSettings,
                "\(url.lastPathComponent): auto recipe carries no settings"
            )

            // Determinism on real measurements, not just synthetic ones.
            XCTAssertEqual(
                AutoDevelop.recipe(for: asset, stats: stats).valueFingerprint,
                recipe.valueFingerprint,
                "\(url.lastPathComponent): auto is not deterministic"
            )

            fingerprints[url.lastPathComponent] = recipe.valueFingerprint
        }

        XCTAssertEqual(fingerprints.count, urls.count)
        // Different photographs should not all collapse onto one recipe; if they do,
        // the measurements are not actually reaching the formulas.
        XCTAssertGreaterThan(
            Set(fingerprints.values).count,
            1,
            "every fixture produced the same recipe — stats are not influencing the result"
        )
    }
}
