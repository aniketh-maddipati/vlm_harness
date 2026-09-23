import XCTest
@testable import Lumina

/// A plan is one undoable move. Cull is never touched. Provenance survives ⌘Z.
@MainActor
final class AskApplyTests: XCTestCase {

    private typealias S = ModelTestSupport

    private func session(_ assets: [AssetRecord], focus: UUID?, selected: [UUID] = []) -> P0SessionModel {
        let session = P0SessionModel()
        session.assets = assets
        session.inspectingAssetID = focus
        session.selectedAssetIDs = selected
        return session
    }

    // MARK: - Pure step outcomes

    func testAdjustOnShotBecomesHandOnEngineBecomesAutoHand() {
        let asset = S.makeAsset()
        let delta = AskAction.adjust(AskDelta(exposure: 0.3))
        for (from, to) in [(RecipeSource.shot, RecipeSource.hand), (.hand, .hand), (.sidecar, .hand),
                           (.auto, .autoHand), (.model, .autoHand), (.autoHand, .autoHand)] {
            let outcome = AskPlanApply.outcome(of: delta, on: asset, current: .neutral, currentSource: from, focusRecipe: nil)
            XCTAssertEqual(outcome?.source, to, "\(from) → \(to)")
            XCTAssertEqual(outcome?.recipe.exposure ?? 0, 0.3, accuracy: 1e-9)
        }
    }

    func testEmptyDeltaDoesNothing() {
        XCTAssertNil(AskPlanApply.outcome(of: .adjust(AskDelta()), on: S.makeAsset(), current: .neutral, currentSource: .shot, focusRecipe: nil))
    }

    func testSyncCopiesOnlyTheNamedGroupsAndNeverGeometry() {
        let focus = EditRecipe(exposure: 1.1, temperature: 4_000, contrast: 30, vibrance: 20, sharpness: 80, crop: EditCrop(x: 0.1, y: 0.1, width: 0.5, height: 0.5), straightenDegrees: 2)
        let target = EditRecipe(exposure: -0.5, temperature: 7_000, contrast: -10, vibrance: -5, sharpness: 0, straightenDegrees: -1)

        let light = AskPlanApply.copy([.light], from: focus, onto: target)
        XCTAssertEqual(light.exposure, 1.1)
        XCTAssertEqual(light.contrast, 30)
        XCTAssertEqual(light.temperature, 7_000, "color is not light")
        XCTAssertEqual(light.vibrance, -5)
        XCTAssertNil(light.crop, "geometry is never copied")
        XCTAssertEqual(light.straightenDegrees, -1)

        let all = AskPlanApply.copy([.light, .color, .detail, .profile], from: focus, onto: target)
        XCTAssertEqual(all.temperature, 4_000)
        XCTAssertEqual(all.vibrance, 20)
        XCTAssertEqual(all.sharpness, 80)
        XCTAssertNil(all.crop)
        XCTAssertEqual(all.straightenDegrees, -1)
    }

    func testSyncNeedsAFocusRecipeAndAtLeastOneGroup() {
        let asset = S.makeAsset()
        XCTAssertNil(AskPlanApply.outcome(of: .syncFromFocus([.light]), on: asset, current: .neutral, currentSource: .shot, focusRecipe: nil))
        XCTAssertNil(AskPlanApply.outcome(of: .syncFromFocus([]), on: asset, current: .neutral, currentSource: .shot, focusRecipe: .neutral))
    }

    func testVersionOneIsAsShotButKeepsTheFraming() {
        let current = EditRecipe(exposure: 1, temperature: 4_000, contrast: 40, crop: EditCrop(x: 0, y: 0, width: 0.5, height: 0.5), straightenDegrees: 3)
        let outcome = AskPlanApply.outcome(of: .version(1), on: S.makeAsset(), current: current, currentSource: .hand, focusRecipe: nil)
        XCTAssertEqual(outcome?.source, .shot)
        XCTAssertEqual(outcome?.recipe.exposure, 0)
        XCTAssertEqual(outcome?.recipe.temperature, EditRecipe.neutralTemperature)
        XCTAssertEqual(outcome?.recipe.contrast, 0)
        XCTAssertNotNil(outcome?.recipe.crop, "as shot must not silently un-crop")
        XCTAssertEqual(outcome?.recipe.straightenDegrees, 3)
        XCTAssertEqual(outcome?.recipe.id, current.id, "the recipe keeps its identity")
    }

    func testVersionTwoIsAutoAndRefusesWithoutMeasurements() {
        XCTAssertNil(AskPlanApply.outcome(of: .version(2), on: S.makeAsset(), current: .neutral, currentSource: .shot, focusRecipe: nil))
        let measured = S.makeAsset(stats: S.stats(mean: 0.2))
        let outcome = AskPlanApply.outcome(of: .version(2), on: measured, current: .neutral, currentSource: .hand, focusRecipe: nil)
        XCTAssertEqual(outcome?.source, .auto)
        XCTAssertEqual(outcome?.recipe.valueFingerprint, AutoDevelop.recipe(for: measured, stats: S.stats(mean: 0.2)).valueFingerprint)
    }

    func testVersionThreeIsTheHandRecipeAndRefusesWithoutOne() {
        XCTAssertNil(AskPlanApply.outcome(of: .version(3), on: S.makeAsset(), current: .neutral, currentSource: .auto, focusRecipe: nil))
        let hand = EditRecipe(exposure: 0.77)
        let outcome = AskPlanApply.outcome(of: .version(3), on: S.makeAsset(handRecipe: hand), current: .neutral, currentSource: .auto, focusRecipe: nil)
        XCTAssertEqual(outcome?.source, .hand)
        XCTAssertEqual(outcome?.recipe.exposure, 0.77)
    }

    func testAutoRefusesWithoutMeasurementsLikeApplyAuto() {
        XCTAssertNil(AskPlanApply.outcome(of: .auto, on: S.makeAsset(), current: .neutral, currentSource: .shot, focusRecipe: nil))
    }

    // MARK: - Session: one plan, one undo

    func testMultiStepPlanIsOneUndoAndRestoresRecipesAndSources() throws {
        let focus = UUID(), other = UUID(), third = UUID()
        let focusRecipe = EditRecipe(exposure: 1, temperature: 4_500)
        let session = session([
            S.makeAsset(id: focus, recipe: focusRecipe, source: .hand, stats: S.stats(mean: 0.3), cull: .keep),
            S.makeAsset(id: other, source: .shot, stats: S.stats(mean: 0.2), cull: .reject),
            S.makeAsset(id: third, recipe: EditRecipe(exposure: -0.4), source: .auto, stats: S.stats(mean: 0.6), cull: .hold),
        ], focus: focus)
        XCTAssertFalse(session.canUndo)

        // Step 1: match light onto the moment (focus excluded). Step 2: warm the moment.
        let plan = AskPlan(steps: [
            AskStep(scope: .moment, action: .syncFromFocus([.light])),
            AskStep(scope: .moment, action: .adjust(AskDelta(temperature: 300))),
        ], summary: "", planner: "test")

        let changed = session.applyPlan(plan)

        XCTAssertEqual(changed, 3)
        // Step 2 composed on step 1 for `other`: exposure copied from focus, then warmed.
        let otherAfter = try XCTUnwrap(session.assets.first { $0.id == other })
        XCTAssertEqual(otherAfter.recipe?.exposure, 1)
        XCTAssertEqual(otherAfter.recipe?.temperature, EditRecipe.neutralTemperature + 300)
        XCTAssertEqual(otherAfter.recipeSource, .hand)
        let thirdAfter = try XCTUnwrap(session.assets.first { $0.id == third })
        XCTAssertEqual(thirdAfter.recipeSource, .autoHand, "a hand move on an auto recipe is autoHand")
        let focusAfter = try XCTUnwrap(session.assets.first { $0.id == focus })
        XCTAssertEqual(focusAfter.recipe?.temperature, 4_800, "focus was warmed but not matched onto itself")

        XCTAssertTrue(session.canUndo)
        session.undoLast()

        XCTAssertFalse(session.canUndo, "the whole plan was exactly one undo step")
        let restored = Dictionary(uniqueKeysWithValues: session.assets.map { ($0.id, $0) })
        XCTAssertEqual(restored[focus]?.recipe?.valueFingerprint, focusRecipe.valueFingerprint)
        XCTAssertEqual(restored[focus]?.recipeSource, .hand)
        XCTAssertNil(restored[other]?.recipe)
        XCTAssertEqual(restored[other]?.recipeSource, .shot)
        XCTAssertEqual(restored[third]?.recipe?.exposure, -0.4)
        XCTAssertEqual(restored[third]?.recipeSource, .auto, "provenance is restored, not just values")
    }

    func testCullSelectionAndOrderAreNeverTouched() {
        let a = UUID(), b = UUID(), c = UUID()
        let session = session([
            S.makeAsset(id: a, stats: S.stats(mean: 0.2), cull: .keep),
            S.makeAsset(id: b, stats: S.stats(mean: 0.2), cull: .reject),
            S.makeAsset(id: c, stats: S.stats(mean: 0.2), cull: .hold),
        ], focus: a, selected: [c])
        let cullBefore = session.assets.map(\.cull)
        let selectionBefore = session.selectedAssetIDs

        session.applyPlan(AskPlan(steps: [
            AskStep(scope: .moment, action: .auto),
            AskStep(scope: .set, action: .adjust(AskDelta(exposure: -0.2))),
            AskStep(scope: .selection, action: .version(1)),
        ], summary: "", planner: "test"))

        XCTAssertEqual(session.assets.map(\.cull), cullBefore)
        XCTAssertEqual(session.selectedAssetIDs, selectionBefore)
        session.undoLast()
        XCTAssertEqual(session.assets.map(\.cull), cullBefore)
        XCTAssertEqual(session.selectedAssetIDs, selectionBefore)
    }

    func testAPlanThatChangesNothingCostsNoUndoStep() {
        let id = UUID()
        let session = session([S.makeAsset(id: id)], focus: id)   // no stats, no hand recipe
        let changed = session.applyPlan(AskPlan(steps: [
            AskStep(scope: .frame, action: .auto),
            AskStep(scope: .frame, action: .version(3)),
            AskStep(scope: .frame, action: .version(1)),   // already as shot
        ], summary: "", planner: "test"))
        XCTAssertEqual(changed, 0)
        XCTAssertFalse(session.canUndo)
    }

    func testMarksRecordTheStateBeforeThePlanNotAnIntermediateOne() throws {
        let id = UUID()
        let session = session([S.makeAsset(id: id, recipe: EditRecipe(exposure: 0.5), source: .hand)], focus: id)
        session.applyPlan(AskPlan(steps: [
            AskStep(scope: .frame, action: .adjust(AskDelta(exposure: 0.2))),
            AskStep(scope: .frame, action: .adjust(AskDelta(exposure: 0.2))),
            AskStep(scope: .frame, action: .adjust(AskDelta(contrast: 10))),
        ], summary: "", planner: "test"))
        XCTAssertEqual(session.assets[0].recipe?.exposure ?? 0, 0.9, accuracy: 1e-9)
        session.undoLast()
        XCTAssertEqual(session.assets[0].recipe?.exposure, 0.5, "one ⌘Z returns to before the plan")
        XCTAssertEqual(session.assets[0].recipe?.contrast, 0)
    }

    func testScopeCountsInContextNeverCarryIDs() {
        let focus = UUID(), other = UUID()
        let session = session([
            S.makeAsset(id: focus, filename: "DSC00001.ARW", cull: .keep),
            S.makeAsset(id: other, filename: "DSC00002.ARW", cull: .keep),
        ], focus: focus)
        let context = session.askContext()
        XCTAssertEqual(context.focusedFilename, "DSC00001.ARW")
        XCTAssertEqual(context.scopeCounts[.frame], 1)
        XCTAssertEqual(context.scopeCounts[.set], 2)
        XCTAssertEqual(context.scopeCounts[.selection], 0)
        XCTAssertFalse("\(context)".contains(focus.uuidString))
    }

    func testPlanAskReturnsNilWhenNothingIsUnderstood() async {
        let id = UUID()
        let session = session([S.makeAsset(id: id)], focus: id)
        let plan = await session.planAsk("???", planner: KeywordAskPlanner())
        XCTAssertNil(plan)
        XCTAssertFalse(session.canUndo, "planning never applies")
    }

    func testPlanAskWithKeywordsThenApplyRoundTrips() async throws {
        let focus = UUID(), other = UUID()
        let session = session([
            S.makeAsset(id: focus, cull: .keep, capturedAt: Date()),
            S.makeAsset(id: other, cull: .keep, capturedAt: Date()),
        ], focus: focus)
        let planned = await session.planAsk("warm the set", planner: KeywordAskPlanner())
        let plan = try XCTUnwrap(planned)
        XCTAssertEqual(plan.steps.first?.scope, .set)
        XCTAssertEqual(session.applyPlan(plan), 2)
        XCTAssertEqual(session.assets.map { $0.recipe?.temperature }, [6_800, 6_800])
    }
}
