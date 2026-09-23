import Foundation
import ImageIO
import XCTest
@testable import Lumina

@MainActor
final class HarmonizationRenderHarnessTests: XCTestCase {
    private struct Plan: Decodable {
        let source: String
        let photoID: UUID
        let fullResolution: Bool
        let currentAuto: Bool
        let candidates: [HarmonizationCandidate]
    }

    func testMeasureCandidates() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let input = environment["LUMINA_HARMONIZATION_PLAN"],
              let output = environment["LUMINA_HARMONIZATION_RECEIPTS"] else {
            throw XCTSkip("Private harmonization render plan not supplied")
        }
        let plan = try JSONDecoder().decode(Plan.self, from: Data(contentsOf: URL(fileURLWithPath: input)))
        let sourceURL = URL(fileURLWithPath: plan.source)
        let outputURL = URL(fileURLWithPath: output)
        guard outputURL.pathExtension == "json", !FileManager.default.fileExists(atPath: output),
              outputURL.deletingLastPathComponent() != sourceURL.deletingLastPathComponent(),
              !plan.candidates.isEmpty, plan.candidates.count <= 12,
              plan.candidates.contains(.zero), Set(plan.candidates.map(\.id)).count == plan.candidates.count else {
            XCTFail("Unsafe output or invalid candidate plan")
            return
        }
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(sourceURL as CFURL, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        let tiff = properties?[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        XCTAssertEqual(tiff?[kCGImagePropertyTIFFModel] as? String, "ILCE-7M3")
        guard tiff?[kCGImagePropertyTIFFModel] as? String == "ILCE-7M3" else { return }
        var receipts: [HarmonizationMeasurementBridge.Receipt] = []
        for candidate in plan.candidates {
            let measured = await HarmonizationMeasurementBridge.measure(candidate: candidate, source: sourceURL,
                photoID: plan.photoID, fullResolution: plan.fullResolution)
            receipts.append(try XCTUnwrap(measured))
        }
        if plan.currentAuto {
            let measured = await HarmonizationMeasurementBridge.measureCurrentAuto(source: sourceURL,
                photoID: plan.photoID, fullResolution: plan.fullResolution)
            receipts.append(try XCTUnwrap(measured))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(receipts).write(to: outputURL, options: [.withoutOverwriting])
    }
}
