import XCTest
@testable import Lumina

@MainActor
final class TechnicalAssistTests: XCTestCase {
    func testClosedVocabularyRefusesVectorsAndGeometry() {
        let stats = ModelTestSupport.stats(mean: 0.2)
        for json: [String: Any] in [
            ["action": "rotate", "observation": "horizon"],
            ["action": "liftExposure", "observation": "dark", "exposure": 5],
            ["action": "auto", "observation": "use auto"],
            ["exposure": -1, "saturation": 15]
        ] {
            let result = TechnicalAssist.parse(json, base: .neutral, stats: stats)
            XCTAssertEqual(result.action, .abstain)
            XCTAssertEqual(result.recipe.valueFingerprint, EditRecipe.neutral.valueFingerprint)
        }
    }

    func testMeasuredConstraintsAndSingleControlBounds() {
        let dark = ModelTestSupport.stats(mean: 0.2)
        let base = EditRecipe(temperature: 5200, tint: 12, straightenDegrees: 90)
        let candidate = TechnicalAssist.recipe(.liftExposure, base: base, stats: dark)
        XCTAssertEqual(candidate?.exposure ?? 0, 1.0 / 3.0, accuracy: 0.00001)
        XCTAssertEqual(candidate?.temperature, base.temperature)
        XCTAssertEqual(candidate?.tint, base.tint)
        XCTAssertEqual(candidate?.straightenDegrees, base.straightenDegrees)
        XCTAssertNil(TechnicalAssist.recipe(.lowerExposure, base: base, stats: dark))
        XCTAssertNil(TechnicalAssist.recipe(.liftExposure, base: base, stats: ModelTestSupport.stats(mean: 0.2, high: 0.02)))
        XCTAssertEqual(TechnicalAssist.deterministicAction(ModelTestSupport.stats(mean: .nan)), .abstain)
    }

    func testInvalidPixelsNeverReachTransport() async {
        let transport = FakeModelTransport.unreachable
        let result = await TechnicalAssist.propose(neutralJPEG: Data([1, 2]), base: .neutral,
            stats: ModelTestSupport.stats(), client: ChatCompletionsClient(endpoint: .localVision, transport: transport))
        XCTAssertEqual(result.action, .abstain)
        XCTAssertTrue(transport.sentRequests.isEmpty)
        XCTAssertFalse(TechnicalAssist.enabledByDefault)
    }
    func testUnavailableAndCancelledControllerKeepNeutral() async throws {
        let path = try ModelTestSupport.writeTinyJPEG()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let jpeg = try Data(contentsOf: URL(fileURLWithPath: path))
        let unavailable = FakeModelTransport.unreachable
        let fallback = await TechnicalAssist.propose(neutralJPEG: jpeg, base: .neutral,
            stats: ModelTestSupport.stats(), client: ChatCompletionsClient(endpoint: .localVision, transport: unavailable))
        XCTAssertEqual(fallback.action, .abstain)
        XCTAssertEqual(fallback.recipe.valueFingerprint, EditRecipe.neutral.valueFingerprint)
        let gate = ModelGate()
        let delayed = FakeModelTransport([.content("{\"action\":\"liftExposure\",\"observation\":\"dark\"}")], gate: gate)
        let task = Task { await TechnicalAssist.propose(neutralJPEG: jpeg, base: .neutral,
            stats: ModelTestSupport.stats(mean: 0.2), client: ChatCompletionsClient(endpoint: .localVision, transport: delayed)) }
        await gate.waitForArrivals(1)
        task.cancel()
        gate.open()
        let cancelled = await task.value
        XCTAssertEqual(cancelled.action, .abstain)
        XCTAssertEqual(cancelled.recipe.valueFingerprint, EditRecipe.neutral.valueFingerprint)
        XCTAssertLessThanOrEqual(delayed.sentRequests[0].timeoutInterval, 8)
    }

    func testDeterministicBatchPreservesHandEditsAndUndoesOnce() {
        let session = P0SessionModel()
        let dark = ModelTestSupport.makeAsset(stats: ModelTestSupport.stats(mean: 0.2))
        let bright = ModelTestSupport.makeAsset(stats: ModelTestSupport.stats(mean: 0.8))
        let hand = ModelTestSupport.makeAsset(recipe: EditRecipe(exposure: 0.7), source: .hand,
            stats: ModelTestSupport.stats(mean: 0.2))
        session.assets = [dark, bright, hand]
        XCTAssertEqual(session.applyTechnicalPolicy(to: [dark.id, dark.id, bright.id, hand.id]), 2)
        XCTAssertEqual(session.undoCoordinator.stack.count, 1)
        XCTAssertEqual(session.recipe(for: hand.id).exposure, 0.7)
        session.undoLast()
        XCTAssertEqual(session.assets[0].recipeSource, .shot)
        XCTAssertEqual(session.assets[1].recipeSource, .shot)
        XCTAssertEqual(session.recipe(for: dark.id).exposure, 0)
        XCTAssertEqual(session.recipe(for: hand.id).exposure, 0.7)
    }

}
