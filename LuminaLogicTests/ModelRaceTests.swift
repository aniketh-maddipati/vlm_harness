import XCTest
@testable import Lumina

/// What happens when the world moves while the model is thinking. Every test here
/// holds requests at a gate, changes the session, then opens the gate — no sleeps.
@MainActor
final class ModelRaceTests: XCTestCase {

    private typealias S = ModelTestSupport

    private func client(_ transport: FakeModelTransport) -> ChatCompletionsClient {
        ChatCompletionsClient(
            endpoint: ModelEndpoint(baseURL: URL(string: "http://127.0.0.1:1234/v1")!, model: "m", timeout: 1)!,
            transport: transport
        )
    }

    /// N measured frames with a real preview, all `.shot`.
    private func session(count: Int) throws -> (P0SessionModel, [UUID]) {
        let path = try S.writeTinyJPEG()
        let ids = (0..<count).map { _ in UUID() }
        let session = P0SessionModel()
        session.assets = ids.map { S.makeAsset(id: $0, stats: S.stats(mean: 0.3), thumbPath: path) }
        return (session, ids)
    }

    private func transport(replies: Int, gate: ModelGate?) -> FakeModelTransport {
        FakeModelTransport(Array(repeating: .content(S.mildProposal), count: replies), gate: gate)
    }

    // MARK: - Stale answers are dropped

    func testHandEditWhileTheModelThinksWinsForThatFrameOnly() async throws {
        let (session, ids) = try session(count: 2)
        let gate = ModelGate()
        let transport = transport(replies: 2, gate: gate)

        let batch = Task { await session.applyModelAuto(to: ids, client: self.client(transport)) }
        await gate.waitForArrivals(2)

        // The photographer moves the first frame by hand while both are in flight.
        let index = session.assets.firstIndex { $0.id == ids[0] }!
        session.assets[index].recipe = EditRecipe(exposure: 0.9)
        session.assets[index].recipeSource = .hand
        gate.open()

        let changed = await batch.value
        XCTAssertEqual(changed, 1, "only the untouched frame takes the model's answer")
        let first = session.assets.first { $0.id == ids[0] }!
        XCTAssertEqual(first.recipe?.exposure, 0.9, "the hand edit is never overwritten")
        XCTAssertEqual(first.recipeSource, .hand)
        let second = session.assets.first { $0.id == ids[1] }!
        XCTAssertEqual(second.recipeSource, .model)
        XCTAssertEqual(second.recipe?.contrast, 10)
    }

    func testUndoDuringFlightMakesTheInFlightAnswerStale() async throws {
        let (session, ids) = try session(count: 1)
        // An earlier deterministic auto pass exists to be undone.
        XCTAssertEqual(session.applyAuto(to: ids), 1)
        XCTAssertEqual(session.assets[0].recipeSource, .auto)

        let gate = ModelGate()
        let transport = transport(replies: 1, gate: gate)
        let batch = Task { await session.applyModelAuto(to: ids, force: true, client: self.client(transport)) }
        await gate.waitForArrivals(1)

        session.undoLast()   // back to .shot, nil recipe
        XCTAssertEqual(session.assets[0].recipeSource, .shot)
        gate.open()

        let changed = await batch.value
        XCTAssertEqual(changed, 0, "the answer was computed against a recipe that no longer exists")
        XCTAssertEqual(session.assets[0].recipeSource, .shot)
        XCTAssertNil(session.assets[0].recipe, "an undone recipe is not resurrected by a late answer")
        XCTAssertFalse(session.canUndo)
    }

    func testFrameRemovedDuringFlightProducesNoMark() async throws {
        let (session, ids) = try session(count: 2)
        let gate = ModelGate()
        let transport = transport(replies: 2, gate: gate)

        let batch = Task { await session.applyModelAuto(to: ids, client: self.client(transport)) }
        await gate.waitForArrivals(2)
        session.assets.removeAll { $0.id == ids[0] }
        gate.open()

        let changed = await batch.value
        XCTAssertEqual(changed, 1)
        XCTAssertEqual(session.assets.count, 1)
        XCTAssertEqual(session.assets[0].id, ids[1])
        XCTAssertEqual(session.assets[0].recipeSource, .model)
    }

    // MARK: - Bounded concurrency, one undo step

    func testAtMostFourFramesAreInFlightAndTheBatchIsOneUndoStep() async throws {
        let (session, ids) = try session(count: 7)
        let gate = ModelGate()
        let transport = transport(replies: 7, gate: gate)

        let batch = Task { await session.applyModelAuto(to: ids, client: self.client(transport)) }
        await gate.waitForArrivals(ModelAutoBatch.concurrency)
        XCTAssertEqual(gate.arrived, ModelAutoBatch.concurrency,
                       "the fifth frame must not have been sent while four are in flight")
        gate.open()

        let changed = await batch.value
        XCTAssertEqual(changed, 7)
        XCTAssertEqual(transport.peakInFlight, ModelAutoBatch.concurrency)
        XCTAssertTrue(session.assets.allSatisfy { $0.recipeSource == .model })
        XCTAssertTrue(session.canUndo)
        session.undoLast()
        XCTAssertFalse(session.canUndo, "seven frames, one ⌘Z")
        XCTAssertTrue(session.assets.allSatisfy { $0.recipeSource == .shot && $0.recipe == nil })
    }

    func testNothingCommitsUntilEveryFrameHasAnswered() async throws {
        let (session, ids) = try session(count: 3)
        let gate = ModelGate()
        let transport = transport(replies: 3, gate: gate)

        let batch = Task { await session.applyModelAuto(to: ids, client: self.client(transport)) }
        await gate.waitForArrivals(3)
        // All three are waiting on the server. Nothing may have landed yet.
        XCTAssertTrue(session.assets.allSatisfy { $0.recipeSource == .shot })
        XCTAssertFalse(session.canUndo, "no partial batch, ever")
        gate.open()
        let changed = await batch.value
        XCTAssertEqual(changed, 3)
    }

    func testOneUnreachableFrameFallsBackWhileTheRestTakeTheModel() async throws {
        let (session, ids) = try session(count: 3)
        let transport = FakeModelTransport([.content(S.mildProposal), .unreachable, .content(S.mildProposal)])
        let changed = await session.applyModelAuto(to: ids, client: client(transport))
        XCTAssertEqual(changed, 3, "the unreachable frame still gets the deterministic recipe")
        let sources = session.assets.map(\.recipeSource)
        XCTAssertEqual(sources.filter { $0 == .model }.count, 2)
        XCTAssertEqual(sources.filter { $0 == .auto }.count, 1)
        session.undoLast()
        XCTAssertFalse(session.canUndo, "mixed model/auto batch is still one step")
    }

    // MARK: - Cancellation

    func testCancelledBeforeStartSendsNothingAndCommitsNothing() async throws {
        // Deterministic: no gate, no parked continuation. The task is cancelled before
        // it gets to run, so the pre-flight guard returns before any fan-out.
        let (session, ids) = try session(count: 2)
        let transport = transport(replies: 2, gate: nil)
        let batch = Task { await session.applyModelAuto(to: ids, client: self.client(transport)) }
        batch.cancel()
        let changed = await batch.value
        XCTAssertEqual(changed, 0)
        XCTAssertTrue(transport.sentRequests.isEmpty, "a cancelled batch fans nothing out")
        XCTAssertFalse(session.canUndo)
        XCTAssertTrue(session.assets.allSatisfy { $0.recipeSource == .shot && $0.recipe == nil })
    }

    func testCancellationWhileInFlightCommitsNothing() async throws {
        let (session, ids) = try session(count: 2)
        let gate = ModelGate()
        let transport = transport(replies: 2, gate: gate)

        let batch = Task { await session.applyModelAuto(to: ids, client: self.client(transport)) }
        await gate.waitForArrivals(2)
        batch.cancel()
        gate.open()

        let changed = await batch.value
        XCTAssertEqual(changed, 0)
        XCTAssertFalse(session.canUndo, "a cancelled batch is not a torn batch")
        XCTAssertTrue(session.assets.allSatisfy { $0.recipeSource == .shot && $0.recipe == nil })
    }

    // MARK: - Plan staleness

    func testPlanAppliesToWhatWasPreviewedOrNotAtAll() async throws {
        let a = UUID(), b = UUID(), c = UUID(), lone = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let session = P0SessionModel()
        session.assets = [
            S.makeAsset(id: a, stats: S.stats(mean: 0.3), capturedAt: t0),
            S.makeAsset(id: b, stats: S.stats(mean: 0.3), capturedAt: t0.addingTimeInterval(1)),
            S.makeAsset(id: c, stats: S.stats(mean: 0.3), capturedAt: t0.addingTimeInterval(2)),
            S.makeAsset(id: lone, stats: S.stats(mean: 0.3), capturedAt: t0.addingTimeInterval(86_400)),
        ]
        session.inspectingAssetID = a
        let planned = await session.planAsk("auto the moment", planner: KeywordAskPlanner())
        let plan = try XCTUnwrap(planned)
        XCTAssertEqual(plan.expectedCounts?[.moment], 3)

        // Focus moves to a frame whose moment is a different size before ⏎.
        session.inspectingAssetID = lone
        XCTAssertEqual(session.applyPlan(plan), 0, "12 on screen must never become 40 on ⏎")
        XCTAssertFalse(session.canUndo)

        // Back on the previewed frame, the same plan applies.
        session.inspectingAssetID = a
        XCTAssertEqual(session.applyPlan(plan), 3)
    }

    func testPlanWithoutExpectedCountsStillApplies() {
        let id = UUID()
        let session = P0SessionModel()
        session.assets = [S.makeAsset(id: id, stats: S.stats(mean: 0.2))]
        session.inspectingAssetID = id
        let plan = AskPlan(steps: [AskStep(scope: .frame, action: .auto)], summary: "", planner: "test")
        XCTAssertEqual(session.applyPlan(plan), 1)
    }

    // MARK: - Two batches on the same frames

    func testTwoBatchesOnTheSameFramesAreTwoUndoStepsWithNoTornState() async throws {
        let (session, ids) = try session(count: 2)
        let gate = ModelGate()
        let transport = transport(replies: 4, gate: gate)

        let first = Task { await session.applyModelAuto(to: ids, client: self.client(transport)) }
        await gate.waitForArrivals(2)
        // Second batch dispatched against the same, still-.shot frames (force so it isn't skipped).
        let second = Task { await session.applyModelAuto(to: ids, force: true, client: self.client(transport)) }
        await gate.waitForArrivals(4)
        gate.open()

        let results = await (first.value, second.value)
        // Whichever committed first changed both frames; the other's snapshots are stale.
        XCTAssertEqual(results.0 + results.1, 2, "the same frame is never written twice from one snapshot")
        XCTAssertTrue(session.assets.allSatisfy { $0.recipeSource == .model })
        XCTAssertTrue(session.canUndo)
        session.undoLast()
        XCTAssertFalse(session.canUndo, "exactly one batch landed, so exactly one undo step")
    }
}
