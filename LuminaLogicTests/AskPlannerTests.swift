import XCTest
@testable import Lumina

/// The ask planners: parsing drops rather than guesses, bounds belong to the engine,
/// keywords are the floor, and a failed model is never mistaken for a plan.
final class AskPlannerTests: XCTestCase {

    private let context = AskContext(
        route: "focus",
        focusedFilename: "DSC08241.ARW",
        scopeCounts: [.frame: 1, .burst: 4, .similar: 6, .moment: 12, .set: 30, .selection: 0]
    )

    private func plannerClient(_ transport: FakeModelTransport) -> ChatCompletionsClient {
        ChatCompletionsClient(
            endpoint: ModelEndpoint(baseURL: URL(string: "http://127.0.0.1:1234/v1")!, model: "m", timeout: 1)!,
            transport: transport
        )
    }

    private func json(_ text: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
    }

    // MARK: - Parsing: drop, never guess

    func testUnknownScopeDropsTheStep() {
        let steps = ModelAskPlanner.steps(from: json("""
        {"steps":[{"scope":"everything","action":"auto"},{"scope":"burst","action":"auto"}]}
        """))
        XCTAssertEqual(steps, [AskStep(scope: .burst, action: .auto)])
    }

    func testUnknownActionDropsTheStep() {
        let steps = ModelAskPlanner.steps(from: json("""
        {"steps":[{"scope":"burst","action":"reject"},{"scope":"burst","action":"delete"},
                  {"scope":"frame","action":"auto"}]}
        """))
        XCTAssertEqual(steps, [AskStep(scope: .frame, action: .auto)],
                       "culling verbs are not actions — they are dropped, not mapped to anything")
    }

    func testAdjustWithNoMovementIsDropped() {
        let steps = ModelAskPlanner.steps(from: json("""
        {"steps":[{"scope":"frame","action":"adjust","delta":{"exposure":0,"contrast":0}}]}
        """))
        XCTAssertTrue(steps.isEmpty)
    }

    func testVersionOutsideOneToThreeIsDropped() {
        let steps = ModelAskPlanner.steps(from: json("""
        {"steps":[{"scope":"frame","action":"version","version":0},
                  {"scope":"frame","action":"version","version":4},
                  {"scope":"frame","action":"version","version":2}]}
        """))
        XCTAssertEqual(steps, [AskStep(scope: .frame, action: .version(2))])
    }

    func testNonFiniteOrMissingNumbersAreIgnored() {
        let steps = ModelAskPlanner.steps(from: json("""
        {"steps":[{"scope":"frame","action":"adjust","delta":{"exposure":"lots","contrast":15}}]}
        """))
        XCTAssertEqual(steps, [AskStep(scope: .frame, action: .adjust(AskDelta(contrast: 15)))])
    }

    func testSyncWithUnknownGroupsFallsBackToLightAndColor() {
        let steps = ModelAskPlanner.steps(from: json("""
        {"steps":[{"scope":"similar","action":"sync","groups":["vibes","aura"]}]}
        """))
        XCTAssertEqual(steps, [AskStep(scope: .similar, action: .syncFromFocus([.light, .color]))])
    }

    func testMissingStepsArrayIsEmptyNotACrash() {
        XCTAssertTrue(ModelAskPlanner.steps(from: json("{\"plan\":\"do things\"}")).isEmpty)
        XCTAssertTrue(ModelAskPlanner.steps(from: [:]).isEmpty)
    }

    // MARK: - Bounds belong to the engine

    func testDeltaIsClampedToTheAskBound() {
        let delta = AskDelta(exposure: 5, contrast: 90, temperature: -9000, tint: 100).bounded
        XCTAssertEqual(delta.exposure, AskDelta.Bound.exposure)
        XCTAssertEqual(delta.contrast, AskDelta.Bound.tone)
        XCTAssertEqual(delta.temperature, -AskDelta.Bound.temperature)
        XCTAssertEqual(delta.tint, AskDelta.Bound.tint)
        XCTAssertNil(delta.highlights, "an untouched field stays untouched")
    }

    func testApplyingADeltaNeverLeavesSliderRange() {
        let near = EditRecipe(exposure: 2.8, temperature: 11_800, contrast: 95)
        let out = AskDelta(exposure: 1, contrast: 40, temperature: 1500).apply(to: near)
        XCTAssertEqual(out.exposure, 3)
        XCTAssertEqual(out.temperature, 12_000)
        XCTAssertEqual(out.contrast, 100)
    }

    func testApplyIsRelativeNotAbsolute() {
        let base = EditRecipe(exposure: 0.4, temperature: 5_000)
        let out = AskDelta(exposure: 0.3, temperature: 300).apply(to: base)
        XCTAssertEqual(out.exposure, 0.7, accuracy: 1e-9)
        XCTAssertEqual(out.temperature, 5_300)
    }

    // MARK: - Keywords are the floor

    func testKeywordsWarmTheBurst() async throws {
        let plan = try await KeywordAskPlanner().plan("warm up the rest of this burst a little", context: context)
        XCTAssertEqual(plan.planner, "keywords")
        XCTAssertEqual(plan.steps, [AskStep(scope: .burst, action: .adjust(AskDelta(temperature: 300)))])
        XCTAssertTrue(plan.summary.contains("burst"))
    }

    func testKeywordsMatchGoesToSimilarWhenNoScopeNamed() async throws {
        let plan = try await KeywordAskPlanner().plan("make the others like this", context: context)
        XCTAssertEqual(plan.steps.first?.scope, .similar)
        XCTAssertEqual(plan.steps.first?.action, .syncFromFocus([.light, .color, .profile]))
    }

    func testKeywordsRefuseWhatTheyDoNotUnderstand() async {
        do {
            _ = try await KeywordAskPlanner().plan("please do the thing", context: context)
            XCTFail("nothing understood must throw, not return an empty or invented plan")
        } catch {
            XCTAssertEqual(error as? AskPlanError, .nothingUnderstood)
        }
    }

    func testKeywordsNeverProduceACullingStep() async throws {
        // "reject" and "keep" are the photographer's words. They must not become steps.
        do {
            _ = try await KeywordAskPlanner().plan("reject the blurry ones", context: context)
            XCTFail("a culling request is not understood by design")
        } catch {
            XCTAssertEqual(error as? AskPlanError, .nothingUnderstood)
        }
    }

    // MARK: - Model planner over a fake transport

    func testModelPlannerSendsTextOnlyAndParsesSteps() async throws {
        let transport = FakeModelTransport(content: """
        {"steps":[{"scope":"burst","action":"adjust","delta":{"exposure":0,"contrast":0,"highlights":0,
          "shadows":0,"temperature":300,"tint":0,"vibrance":0,"saturation":0},"groups":[],"version":0}]}
        """)
        let plan = try await ModelAskPlanner(client: plannerClient(transport)).plan("warm the burst", context: context)
        XCTAssertEqual(plan.planner, "model")
        XCTAssertEqual(plan.steps, [AskStep(scope: .burst, action: .adjust(AskDelta(temperature: 300)))])

        let body = try XCTUnwrap(transport.lastBody)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 1, "the ask planner never sends pixels")
        let text = try XCTUnwrap(content[0]["text"] as? String)
        XCTAssertTrue(text.contains("DSC08241.ARW"), "the focused filename is the only one shared")
        XCTAssertFalse(text.contains("-"), "no UUIDs in the prompt")
    }

    func testModelPlannerWithNothingUsableThrows() async {
        let transport = FakeModelTransport(content: "{\"steps\":[{\"scope\":\"galaxy\",\"action\":\"vibe\"}]}")
        do {
            _ = try await ModelAskPlanner(client: plannerClient(transport)).plan("x", context: context)
            XCTFail()
        } catch {
            XCTAssertEqual(error as? AskPlanError, .nothingUnderstood)
        }
    }

    // MARK: - Fallback chain

    func testUnreachableModelFallsBackToKeywordsAndSaysSo() async throws {
        let planner = FallbackAskPlanner(
            primary: ModelAskPlanner(client: plannerClient(.unreachable)),
            fallback: KeywordAskPlanner()
        )
        let plan = try await planner.plan("cooler burst", context: context)
        XCTAssertEqual(plan.planner, "keywords", "a fallback must never be mistaken for the model")
        XCTAssertEqual(plan.steps, [AskStep(scope: .burst, action: .adjust(AskDelta(temperature: -300)))])
    }

    func testModelThatUnderstandsNothingAlsoFallsBackToKeywords() async throws {
        let transport = FakeModelTransport(content: "{\"steps\":[]}")
        let planner = FallbackAskPlanner(
            primary: ModelAskPlanner(client: plannerClient(transport)),
            fallback: KeywordAskPlanner()
        )
        let plan = try await planner.plan("brighter", context: context)
        XCTAssertEqual(plan.planner, "keywords")
    }

    func testWorkingModelIsPreferred() async throws {
        let transport = FakeModelTransport(content: "{\"steps\":[{\"scope\":\"frame\",\"action\":\"auto\"}]}")
        let planner = FallbackAskPlanner(
            primary: ModelAskPlanner(client: plannerClient(transport)),
            fallback: KeywordAskPlanner()
        )
        let plan = try await planner.plan("brighter", context: context)
        XCTAssertEqual(plan.planner, "model")
        XCTAssertEqual(plan.steps, [AskStep(scope: .frame, action: .auto)])
    }

    func testNoPrimaryMeansKeywordsOnly() async throws {
        let planner = FallbackAskPlanner(primary: nil, fallback: KeywordAskPlanner())
        let plan = try await planner.plan("darker", context: context)
        XCTAssertEqual(plan.planner, "keywords")
    }

    func testWhenBothFailTheErrorIsTheFallbacks() async {
        let planner = FallbackAskPlanner(
            primary: ModelAskPlanner(client: plannerClient(.unreachable)),
            fallback: KeywordAskPlanner()
        )
        do {
            _ = try await planner.plan("???", context: context)
            XCTFail()
        } catch {
            XCTAssertEqual(error as? AskPlanError, .nothingUnderstood)
        }
    }
}
