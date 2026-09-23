import Foundation
import XCTest
@testable import Lumina

@MainActor
final class HarmonizationCandidateTests: XCTestCase {
    func testZeroPreservesAsShotAndHasNoGeometryOrTaste() {
        let recipe = HarmonizationCandidate.zero.recipe!
        XCTAssertTrue(recipe.rawIntent.isAsShotWhiteBalance)
        XCTAssertTrue(recipe.lookIntent.isNeutral)
        XCTAssertEqual(recipe.geometryIntent, .identity)
        XCTAssertEqual(recipe.exposure, 0)
    }

    func testRejectsUnboundedNonfiniteAndAmbiguousWhiteBalance() {
        for exposure in [Double.nan, Double.infinity, 1.01] {
            let candidate = HarmonizationCandidate(id: "bad", exposure: exposure, temperature: nil,
                tint: 0, contrast: 0, highlights: 0, shadows: 0, saturation: 0, vibrance: 0)
            XCTAssertNil(candidate.recipe)
        }
        let candidate = HarmonizationCandidate(id: "bad", exposure: 0, temperature: nil,
            tint: 1, contrast: 0, highlights: 0, shadows: 0, saturation: 0, vibrance: 0)
        XCTAssertNil(candidate.recipe)
    }

    func testCandidateZeroCannotBeRelabeledEdit() {
        let candidate = HarmonizationCandidate(id: "zero", exposure: 0.3, temperature: nil,
            tint: 0, contrast: 0, highlights: 0, shadows: 0, saturation: 0, vibrance: 0)
        XCTAssertNil(candidate.recipe)
    }

    func testRenderedPhoneIsUnsupported() async {
        let receipt = await HarmonizationMeasurementBridge.measure(candidate: .zero,
            source: URL(fileURLWithPath: "/unused/phone.heic"), photoID: UUID(), fullResolution: false)
        XCTAssertNil(receipt)
    }
}
