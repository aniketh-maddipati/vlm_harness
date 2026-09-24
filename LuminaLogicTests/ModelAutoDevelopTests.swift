import XCTest
@testable import Lumina

/// The model proposes, the engine bounds. Every way the model can be wrong, unreachable
/// or absent lands on the deterministic recipe — auto never depends on a server.
final class ModelAutoDevelopTests: XCTestCase {

    private typealias S = ModelTestSupport
    private typealias Band = ModelAutoDevelop.Band

    private func client(_ transport: FakeModelTransport) -> ChatCompletionsClient {
        ChatCompletionsClient(
            endpoint: ModelEndpoint(baseURL: URL(string: "http://127.0.0.1:1234/v1")!, model: "m", timeout: 1)!,
            transport: transport
        )
    }

    private func proposalJSON(
        exposure: Double = 0, contrast: Double = 0, highlights: Double = 0, shadows: Double = 0,
        vibrance: Double = 0, saturation: Double = 0, temperatureShift: Double = 0, tintShift: Double = 0
    ) -> String {
        """
        {"exposure":\(exposure),"contrast":\(contrast),"highlights":\(highlights),"shadows":\(shadows),
         "vibrance":\(vibrance),"saturation":\(saturation),"temperature_shift":\(temperatureShift),
         "tint_shift":\(tintShift)}
        """
    }

    // MARK: - Parsing

    func testProposalWithNoFiniteNumbersIsNil() {
        XCTAssertNil(ModelToneProposal(json: [:]))
        XCTAssertNil(ModelToneProposal(json: ["exposure": "bright", "contrast": Double.nan]))
        XCTAssertNil(ModelToneProposal(json: ["exposure": Double.infinity]))
    }

    func testOmittedFieldsStayNilNotZero() throws {
        let p = try XCTUnwrap(ModelToneProposal(json: ["contrast": 10]))
        XCTAssertEqual(p.contrast, 10)
        XCTAssertNil(p.exposure, "an omitted key means 'leave it', never 'set to zero'")
        XCTAssertNil(p.temperatureShift)
    }

    // MARK: - Bounds

    func testEveryToneMoveIsClampedIntoItsBand() {
        let wild = ModelToneProposal(
            exposure: -5, contrast: 75, highlights: 60, shadows: 90,
            vibrance: 60, saturation: 40, temperatureShift: 4_000, tintShift: 90
        )
        let base = EditRecipe(temperature: 5_200, tint: 4)
        let out = ModelAutoDevelop.bound(wild, onto: base)
        XCTAssertEqual(out.exposure, Band.exposure.lowerBound)
        XCTAssertEqual(out.contrast, Band.contrast.upperBound)
        XCTAssertEqual(out.highlights, Band.highlights.upperBound)
        XCTAssertEqual(out.shadows, Band.shadows.upperBound)
        XCTAssertEqual(out.vibrance, Band.vibrance.upperBound)
        XCTAssertEqual(out.saturation, Band.saturation.upperBound)
        XCTAssertEqual(out.temperature, 5_200)
        XCTAssertEqual(out.tint, 4)
    }

    func testBandsAreNarrowerThanTheSliders() {
        // The whole point: a first pass corrects, it does not restyle.
        XCTAssertLessThan(Band.exposure.upperBound, 3)
        XCTAssertLessThan(Band.contrast.upperBound, 100)
        XCTAssertLessThan(Band.saturation.upperBound, 100)
        XCTAssertLessThan(Band.temperatureShift.upperBound, 10_000)
    }

    func testToneAutoIgnoresWhiteBalanceShiftsForAsShotAndManualPairs() {
        for base in [EditRecipe.neutral, EditRecipe(temperature: 5200, tint: -8)] {
            for shift in [-8000.0, 0, 8000] {
                let out = ModelAutoDevelop.bound(ModelToneProposal(temperatureShift: shift, tintShift: 15), onto: base)
                XCTAssertEqual(out.temperature, base.temperature)
                XCTAssertEqual(out.tint, base.tint)
                XCTAssertEqual(out.rawIntent.isAsShotWhiteBalance, base.rawIntent.isAsShotWhiteBalance)
            }
        }
    }

    func testExposureIsQuantizedToTheAutoStep() {
        let out = ModelAutoDevelop.bound(ModelToneProposal(exposure: 0.333), onto: .neutral)
        XCTAssertEqual(out.exposure, 0.35, accuracy: 1e-9)
    }

    func testInertControlsArePinnedWhateverTheModelSays() {
        let base = EditRecipe(whites: 30, blacks: -20, dehaze: 15)
        let out = ModelAutoDevelop.bound(ModelToneProposal(contrast: 5), onto: base)
        XCTAssertEqual(out.whites, 0)
        XCTAssertEqual(out.blacks, 0)
        XCTAssertEqual(out.dehaze, 0)
    }

    func testOmittedFieldLeavesTheDeterministicValueInPlace() {
        let base = EditRecipe(exposure: 0.4, contrast: 12)
        let out = ModelAutoDevelop.bound(ModelToneProposal(contrast: 5), onto: base)
        XCTAssertEqual(out.exposure, 0.4, "the model said nothing about exposure, so auto's answer stands")
        XCTAssertEqual(out.contrast, 5)
    }

    func testBoundIsPure() {
        let p = ModelToneProposal(exposure: 0.3, contrast: 10)
        let base = EditRecipe(temperature: 5_000)
        XCTAssertEqual(ModelAutoDevelop.bound(p, onto: base).valueFingerprint,
                       ModelAutoDevelop.bound(p, onto: base).valueFingerprint)
    }

    // MARK: - Echo guard

    func testEchoedStatisticIsRefused() {
        // Verbatim from the live run: "2.09% crushed, 0.00% clipped" → highlights 2.09.
        let stats = S.stats(mean: 0.2789, low: 0.020854, high: 0.000006)
        let echo = ModelToneProposal(exposure: -1, contrast: 0.5, highlights: 2.09, shadows: 0, vibrance: 0.3)
        XCTAssertTrue(ModelAutoDevelop.isEcho(echo, stats: stats))
        XCTAssertTrue(ModelAutoDevelop.isEcho(ModelToneProposal(exposure: 0.28), stats: stats),
                      "the mean is quoted too")
    }

    func testZeroIsNeverTreatedAsAnEcho() {
        // The prompt sanctions 0 ("use 0 for anything that needs no change"); a frame
        // with 0.00% clipping must not make every zeroed field look like a parrot.
        let stats = S.stats(mean: 0.5, low: 0, high: 0)
        XCTAssertFalse(ModelAutoDevelop.isEcho(ModelToneProposal(highlights: 0, shadows: 0, tintShift: 0), stats: stats))
        XCTAssertFalse(ModelAutoDevelop.isEcho(ModelToneProposal(contrast: 10), stats: stats))
    }

    func testNearMissIsNotAnEcho() {
        let stats = S.stats(mean: 0.2789, low: 0.020854, high: 0)
        XCTAssertFalse(ModelAutoDevelop.isEcho(ModelToneProposal(highlights: 2.1), stats: stats))
        XCTAssertFalse(ModelAutoDevelop.isEcho(ModelToneProposal(highlights: -2.09), stats: stats))
    }

    func testQuotedStatisticsMatchWhatThePromptActuallyPrints() {
        // Guard and prompt must not drift: every quoted number must appear in the prompt
        // text at the same two-decimal precision the guard compares at.
        let stats = S.stats(mean: 0.2789, low: 0.020854, high: 0.123456, nativeTemperature: 5_200)
        let prompt = ModelAutoDevelop.userPrompt(stats: stats)
        for value in ModelAutoDevelop.quotedStatistics(stats) {
            XCTAssertTrue(prompt.contains(String(format: "%.2f", value)), "\(value) not in prompt")
        }
        XCTAssertEqual(ModelAutoDevelop.quotedStatistics(stats), [0.28, 2.09, 12.35])
    }

    // MARK: - Per-frame fallback through a fake transport

    private func measuredAsset(previewPath: String?) -> AssetRecord {
        S.makeAsset(stats: S.stats(mean: 0.3, nativeTemperature: 5_000), thumbPath: previewPath)
    }

    func testModelProposalIsUsedBoundedAndMarkedModel() async throws {
        let path = try S.writeTinyJPEG()
        let transport = FakeModelTransport(content: proposalJSON(contrast: 75, highlights: 30, temperatureShift: -200))
        let asset = measuredAsset(previewPath: path)
        let stats = try XCTUnwrap(asset.imageStats)

        let result = await ModelAutoDevelop.proposal(for: asset, stats: stats, client: client(transport))

        XCTAssertEqual(result.source, .model)
        XCTAssertNil(result.fallbackReason)
        XCTAssertEqual(result.recipe.contrast, Band.contrast.upperBound, "75 clamped to the band")
        XCTAssertEqual(result.recipe.highlights, Band.highlights.upperBound, "30 clamped: the live case")
        XCTAssertTrue(result.recipe.rawIntent.isAsShotWhiteBalance, "tone Auto retains camera WB instead of applying a model shift")
        let body = try XCTUnwrap(transport.lastBody)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2, "auto sends the downscaled preview")
    }

    func testPublicToneProposalPreservesWholeWhiteBalanceAndNonWBBehavior() async throws {
        let path = try S.writeTinyJPEG()
        for base in [EditRecipe.neutral, EditRecipe(temperature: 4800, tint: 12),
                     EditRecipe(temperature: 4800), EditRecipe(tint: -8)] {
            for native in [Double?](arrayLiteral: 5200, 6500, nil) {
                var asset = measuredAsset(previewPath: path)
                asset.recipe = base
                let stats = S.stats(mean: 0.3, nativeTemperature: native)
                let response = proposalJSON(exposure: 0.35, contrast: 11, highlights: -25,
                    shadows: 18, vibrance: 9, saturation: -3, temperatureShift: -200, tintShift: 8)
                let result = await ModelAutoDevelop.proposal(for: asset, stats: stats,
                    client: client(FakeModelTransport(content: response)))
                XCTAssertEqual(result.source, .model)
                XCTAssertNil(result.fallbackReason)
                XCTAssertEqual(result.recipe.temperature, base.temperature)
                XCTAssertEqual(result.recipe.tint, base.tint)
                XCTAssertEqual(result.recipe.rawIntent.isAsShotWhiteBalance, base.rawIntent.isAsShotWhiteBalance)
                var expected = AutoDevelop.recipe(for: asset, stats: stats)
                expected.exposure = (0.35 / AutoDevelop.exposureStep).rounded() * AutoDevelop.exposureStep
                expected.contrast = 11; expected.highlights = -25; expected.shadows = 18
                expected.vibrance = 9; expected.saturation = -3
                XCTAssertEqual(result.recipe, expected)
                asset.recipe = result.recipe
                let repeated = await ModelAutoDevelop.proposal(for: asset, stats: stats,
                    client: client(FakeModelTransport(content: response)))
                XCTAssertEqual(repeated.recipe, result.recipe)
            }
        }
    }

    func testUnreachableModelFallsBackToDeterministicPerFrame() async throws {
        let path = try S.writeTinyJPEG()
        let asset = measuredAsset(previewPath: path)
        let stats = try XCTUnwrap(asset.imageStats)
        let result = await ModelAutoDevelop.proposal(for: asset, stats: stats, client: client(.unreachable))
        XCTAssertEqual(result.source, .auto)
        XCTAssertNotNil(result.fallbackReason)
        XCTAssertEqual(result.recipe.valueFingerprint, AutoDevelop.recipe(for: asset, stats: stats).valueFingerprint)
    }

    func testGarbageReplyFallsBackToDeterministic() async throws {
        let path = try S.writeTinyJPEG()
        let asset = measuredAsset(previewPath: path)
        let stats = try XCTUnwrap(asset.imageStats)
        for reply in ["", "not json", "{\"exposure\":\"lots\"}", "{}"] {
            let result = await ModelAutoDevelop.proposal(
                for: asset, stats: stats, client: client(FakeModelTransport(content: reply))
            )
            XCTAssertEqual(result.source, .auto, "reply \(reply.debugDescription)")
            XCTAssertEqual(result.recipe.valueFingerprint, AutoDevelop.recipe(for: asset, stats: stats).valueFingerprint)
        }
    }

    func testEchoedReplyFallsBackToDeterministic() async throws {
        let path = try S.writeTinyJPEG()
        let asset = S.makeAsset(stats: S.stats(mean: 0.2789, low: 0.020854), thumbPath: path)
        let stats = try XCTUnwrap(asset.imageStats)
        let transport = FakeModelTransport(content: proposalJSON(exposure: -1, highlights: 2.09))
        let result = await ModelAutoDevelop.proposal(for: asset, stats: stats, client: client(transport))
        XCTAssertEqual(result.source, .auto)
        XCTAssertEqual(result.fallbackReason, "model echoed the measurements")
    }

    func testHTTPErrorFallsBackToDeterministic() async throws {
        let path = try S.writeTinyJPEG()
        let asset = measuredAsset(previewPath: path)
        let stats = try XCTUnwrap(asset.imageStats)
        let transport = FakeModelTransport([.raw(Data("{\"error\":{\"message\":\"busy\"}}".utf8), status: 503)])
        let result = await ModelAutoDevelop.proposal(for: asset, stats: stats, client: client(transport))
        XCTAssertEqual(result.source, .auto)
        XCTAssertTrue(result.fallbackReason?.contains("busy") ?? false)
    }

    func testNoPreviewMeansNoNetworkCallAtAll() async throws {
        let transport = FakeModelTransport(content: proposalJSON(contrast: 10))
        let asset = measuredAsset(previewPath: nil)
        let stats = try XCTUnwrap(asset.imageStats)
        let result = await ModelAutoDevelop.proposal(for: asset, stats: stats, client: client(transport))
        XCTAssertEqual(result.source, .auto)
        XCTAssertTrue(transport.sentRequests.isEmpty, "nothing to show the model → nothing sent")
    }

    func testMissingPreviewFileMeansNoNetworkCall() async throws {
        let transport = FakeModelTransport(content: proposalJSON(contrast: 10))
        let asset = measuredAsset(previewPath: "/nonexistent/\(UUID().uuidString).jpg")
        let stats = try XCTUnwrap(asset.imageStats)
        let result = await ModelAutoDevelop.proposal(for: asset, stats: stats, client: client(transport))
        XCTAssertEqual(result.source, .auto)
        XCTAssertTrue(transport.sentRequests.isEmpty)
    }

    func testBandEdgeValuePassesBothGuardAndBand() async throws {
        // Documents the known hole from the live run: exposure −1 on a dark frame sits
        // exactly at Band.exposure.lowerBound. Neither the echo guard nor the band catches
        // it. This test pins the behavior so a future tightening is a deliberate change.
        let path = try S.writeTinyJPEG()
        let asset = S.makeAsset(stats: S.stats(mean: 0.28), thumbPath: path)
        let stats = try XCTUnwrap(asset.imageStats)
        let transport = FakeModelTransport(content: proposalJSON(exposure: -1))
        let result = await ModelAutoDevelop.proposal(for: asset, stats: stats, client: client(transport))
        XCTAssertEqual(result.source, .model)
        XCTAssertEqual(result.recipe.exposure, -1)
    }
}
