import CoreImage
import CryptoKit
import Foundation
import XCTest
@testable import Lumina

/// Fixture-gated diagnostic only. No product/catalog mutation and no proxy substitution.
@MainActor
final class Raw100DevelopmentDiagnosticTests: XCTestCase {
    private struct Selection: Decodable { let fixtures: [Fixture] }
    private struct Fixture: Decodable {
        let id: String
        let split: String
        let input_path: String
        let sha256: String
    }

    func testFrozenDevelopmentWhiteBalance() async throws {
        guard let directory = ProcessInfo.processInfo.environment["LUMINA_RAW_DEV_ROOT"] else {
            throw XCTSkip("Development diagnostic root not configured")
        }
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        let fixtures = try JSONDecoder().decode(Selection.self, from: Data(contentsOf: root.appendingPathComponent("selection.json"))).fixtures
        XCTAssertEqual(fixtures.count, 5)
        let output = root.appendingPathComponent("renders", isDirectory: true)
        let report = output.appendingPathComponent("renders.json")
        guard !FileManager.default.fileExists(atPath: report.path) else { throw XCTSkip("Refusing to overwrite diagnostic evidence") }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let context = CIContext(options: DevelopColorPolicy.ciContextOptions)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var records: [[String: Any]] = []
        for fixture in fixtures {
            XCTAssertEqual(fixture.split, "development")
            guard fixture.split == "development" else { return XCTFail("Held-out input refused") }
            let input = URL(fileURLWithPath: fixture.input_path)
            let digest = try hash(input)
            XCTAssertEqual(digest, fixture.sha256)
            guard digest == fixture.sha256 else { return XCTFail("Input integrity mismatch") }
            let assetID = UUID()
            let session = PreparedRawSession(assetID: assetID, rawURL: input)
            let measured = await session.imageStats()
            let stats = try XCTUnwrap(measured, fixture.id)
            let metadata = await session.metadata
            let decoder = try XCTUnwrap(metadata, fixture.id)
            let capabilities = await session.capabilities
            let asset = AssetRecord(id: assetID, sourceKey: fixture.id,
                source: SourceReference(originalPath: input.path, relativePath: input.lastPathComponent, volumeID: "DISPOSABLE", availability: .available),
                filename: input.lastPathComponent, imageStats: stats)
            let current = AutoDevelop.recipe(for: asset, stats: stats)
            let tintOnly = current.updating { $0.tint = decoder.nativeNeutralTint }
            let changed = try fieldsChanged(from: current, to: tintOnly)
            XCTAssertEqual(changed, decoder.nativeNeutralTint == current.tint ? [] : ["tint"])
            let arms: [(String, EditRecipe)] = [("E-neutral", .neutral), ("F-current-auto", current), ("T-native-tint-only", tintOnly)]
            for (label, recipe) in arms {
                let destination = output.appendingPathComponent("\(fixture.id)-\(label).tif")
                guard !FileManager.default.fileExists(atPath: destination.path) else { return XCTFail("Refusing existing TIFF") }
                let request = RawRenderRequest(generation: 1, photoID: assetID, rawURL: input,
                    recipe: recipe, quality: .export, source: .originalRAW, longEdgeCap: 0, forDisplay: false)
                let result = await DevelopRenderGraph.render(request)
                let image = try XCTUnwrap(result.ciImage, fixture.id + label)
                XCTAssertFalse(result.usedProxyFallback)
                guard !result.usedProxyFallback else { return XCTFail("Proxy forbidden") }
                try context.writeTIFFRepresentation(of: image, to: destination, format: .RGBA16, colorSpace: space)
                records.append([
                    "id": fixture.id, "split": fixture.split, "arm": label, "inputSHA256": digest,
                    "recipe": try object(recipe), "currentAutoRecipe": try object(current),
                    "tintDiagnosticChangedFields": changed, "stats": try object(stats),
                    "decoder": ["version": decoder.decoderVersion, "nativeTemperature": decoder.nativeNeutralTemperature,
                        "nativeTint": decoder.nativeNeutralTint, "pixelWidth": decoder.pixelWidth,
                        "pixelHeight": decoder.pixelHeight, "capabilities": capabilities.summary],
                    "proxy": result.usedProxyFallback, "fidelity": result.fidelity.rawValue,
                    "width": image.extent.width, "height": image.extent.height,
                    "requestID": request.id.uuidString, "assetID": assetID.uuidString,
                    "requestedLongEdge": 0, "format": "TIFF RGBA16 sRGB SDR full resolution",
                    "outputSharpening": "none added", "detailPolicy": "Existing decoder/recipe NR/sharpening unchanged",
                    "output": destination.lastPathComponent, "outputSHA256": try hash(destination)
                ])
                try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]).write(to: report, options: .atomic)
            }
            XCTAssertEqual(try hash(input), digest)
        }
        XCTAssertEqual(records.count, 15)
    }

    private func hash(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    private func fieldsChanged(from before: EditRecipe, to after: EditRecipe) throws -> [String] {
        let a = try object(before), b = try object(after)
        return Set(a.keys).union(b.keys).filter { key in
            guard key != "id" else { return false }
            return String(describing: a[key]) != String(describing: b[key])
        }.sorted()
    }
}
