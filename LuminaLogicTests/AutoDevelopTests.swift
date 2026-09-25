import XCTest
@testable import Lumina

/// Checkpoint 02 — the deterministic auto pass and its batched undo.
@MainActor
final class AutoDevelopTests: XCTestCase {

    private func makeAsset(
        id: UUID = UUID(),
        recipe: EditRecipe? = nil,
        source: RecipeSource = .shot,
        stats: ImageStats? = nil,
        cull: CullDecision = .undecided
    ) -> AssetRecord {
        AssetRecord(
            id: id,
            sourceKey: "k-\(id.uuidString)",
            source: SourceReference(
                originalPath: "/proof/\(id.uuidString).ARW",
                relativePath: "\(id.uuidString).ARW",
                volumeID: "PROOF",
                availability: .available
            ),
            filename: "\(id.uuidString).ARW",
            cull: cull,
            recipe: recipe,
            recipeSource: source,
            imageStats: stats
        )
    }

    /// Mid-tone frame, nothing clipping at either end.
    private func evenStats(
        mean: Double = AutoDevelop.meanAnchor,
        low: Double = 0,
        high: Double = 0,
        nativeTemperature: Double? = nil,
        horizonAngle: Double? = nil
    ) -> ImageStats {
        ImageStats(
            luminanceBins: Array(repeating: 32, count: ImageStats.binCount),
            shadowClipFraction: low,
            highlightClipFraction: high,
            mean: mean,
            nativeTemperature: nativeTemperature,
            horizonAngle: horizonAngle
        )
    }

    // MARK: - Determinism

    func testSameStatsProduceIdenticalRecipe() {
        let asset = makeAsset()
        let stats = evenStats(mean: 0.31, low: 0.02, high: 0.011, nativeTemperature: 5_200, horizonAngle: 1.4)

        let first = AutoDevelop.recipe(for: asset, stats: stats)
        let second = AutoDevelop.recipe(for: asset, stats: stats)

        XCTAssertEqual(first.valueFingerprint, second.valueFingerprint)
        // A separate asset carrying the same measurements must land identically too —
        // nothing about identity or ordering may leak into the result.
        let sibling = makeAsset()
        XCTAssertEqual(
            AutoDevelop.recipe(for: sibling, stats: stats).valueFingerprint,
            first.valueFingerprint
        )
    }

    func testExposureIsQuantizedSoNearIdenticalFramesAgree() {
        // Two frames a hair apart in mean must not land on different exposures.
        let a = AutoDevelop.exposure(mean: 0.400)
        let b = AutoDevelop.exposure(mean: 0.401)
        XCTAssertEqual(a, b, accuracy: 1e-9)
        XCTAssertEqual(
            (a / AutoDevelop.exposureStep).rounded(),
            a / AutoDevelop.exposureStep,
            accuracy: 1e-9,
            "exposure must land on a .05 step"
        )
    }

    /// The clamp is asymmetric in practice: `(0.46 − mean) × 3` spans −1.62…+1.38,
    /// so only the darkening side ever reaches ±`exposureLimit`. A pure-black frame
    /// tops out at +1.40 because the formula, not the clamp, is the binding constraint.
    /// Documented rather than "fixed" — tuning the coefficients is the L4 loop's job.
    func testExposureClampsHardFrames() {
        XCTAssertEqual(AutoDevelop.exposure(mean: 1.0), -AutoDevelop.exposureLimit, accuracy: 1e-9)
        XCTAssertEqual(AutoDevelop.exposure(mean: 0.0), 1.40, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(AutoDevelop.exposure(mean: 0.0), AutoDevelop.exposureLimit)
    }

    // MARK: - Identity stats

    /// "Near-identity" means: no exposure move and no white-balance move. It does
    /// not mean `.neutral` — a frame that is not clipping still receives the
    /// documented default curve (highlights −20 / shadows +15 / vibrance 8).
    func testIdentityStatsProduceNearIdentityRecipe() {
        let asset = makeAsset()
        let recipe = AutoDevelop.recipe(for: asset, stats: evenStats())

        XCTAssertEqual(recipe.exposure, 0, accuracy: 1e-9)
        XCTAssertEqual(recipe.temperature, EditRecipe.neutralTemperature, accuracy: 1e-9)
        XCTAssertEqual(recipe.straightenDegrees, 0, accuracy: 1e-9)
        XCTAssertEqual(recipe.highlights, AutoDevelop.defaultHighlights, accuracy: 1e-9)
        XCTAssertEqual(recipe.shadows, AutoDevelop.defaultShadows, accuracy: 1e-9)
    }

    func testInertControlsStayZero() {
        let asset = makeAsset(recipe: EditRecipe(whites: 40, blacks: -30, dehaze: 25))
        let recipe = AutoDevelop.recipe(for: asset, stats: evenStats(mean: 0.2, low: 0.1, high: 0.1))

        XCTAssertEqual(recipe.whites, 0, accuracy: 1e-9)
        XCTAssertEqual(recipe.blacks, 0, accuracy: 1e-9)
        XCTAssertEqual(recipe.dehaze, 0, accuracy: 1e-9)
    }

    func testClippingDrivesRecoveryWithinBounds() {
        let clipped = AutoDevelop.recipe(
            for: makeAsset(),
            stats: evenStats(mean: 0.5, low: 0.4, high: 0.4)
        )
        XCTAssertEqual(clipped.highlights, -80, accuracy: 1e-9, "highlight recovery is capped at −80")
        XCTAssertEqual(clipped.shadows, 60, accuracy: 1e-9, "shadow lift is capped at +60")
    }

    /// Auto deliberately no longer adopts native Kelvin over a partial/manual pair.
    /// Expected effective pairs use the existing RAW intent contract; native tint is
    /// supplied by the decoder, never fabricated in ImageStats.
    func testAutoPreservesCompleteWhiteBalanceAndEffectiveIntent() throws {
        let bases: [(Double, Double, Bool)] = [
            (6500, 0, true), (4800, 12, false), (4800, 0, false),
            (6500, 12, false), (6499, -0.01, true), (6501, 0.01, true),
            (6498.999, 0, false), (6501.001, 0, false),
            (6500, -0.01001, false), (6500, 0.01001, false)
        ]
        for (temperature, tint, asShot) in bases {
            for native in [5200.0, 6499.0, 6500.0, 6501.0] {
                for nativeTint in [-8.0, 12.0] {
                    let base = EditRecipe(temperature: temperature, tint: tint)
                    let stats = evenStats(nativeTemperature: native)
                    let first = AutoDevelop.recipe(for: makeAsset(recipe: base), stats: stats)
                    let second = AutoDevelop.recipe(for: makeAsset(recipe: first), stats: stats)
                    XCTAssertEqual(first.temperature, temperature)
                    XCTAssertEqual(first.tint, tint)
                    XCTAssertEqual(first.rawIntent.isAsShotWhiteBalance, asShot)
                    let effectiveTemperature = first.rawIntent.isAsShotWhiteBalance ? native : first.temperature
                    let effectiveTint = first.rawIntent.isAsShotWhiteBalance ? nativeTint : first.tint
                    XCTAssertEqual(effectiveTemperature, asShot ? native : temperature)
                    XCTAssertEqual(effectiveTint, asShot ? nativeTint : tint)
                    XCTAssertEqual(second.valueFingerprint, first.valueFingerprint)
                    let persisted = try JSONDecoder().decode(EditRecipe.self, from: JSONEncoder().encode(first))
                    XCTAssertEqual(persisted.rawIntent, first.rawIntent)
                }
            }
        }
        let fresh = AutoDevelop.recipe(for: makeAsset(), stats: evenStats(nativeTemperature: 5200))
        XCTAssertTrue(fresh.rawIntent.isAsShotWhiteBalance)
    }

    func testMissingNativeContextAndLegacyRecipesPreserveExistingIntent() throws {
        // Missing fields and explicit near-sentinel legacy values keep their existing
        // interpretation; this patch does not claim to recover old edit provenance.
        for json in ["{}", "{\"temperature\":4800,\"tint\":12}",
                     "{\"temperature\":6500,\"tint\":0}", "{\"temperature\":0,\"tint\":12}"] {
            let base = try JSONDecoder().decode(EditRecipe.self, from: Data(json.utf8))
            let result = AutoDevelop.recipe(for: makeAsset(recipe: base), stats: evenStats())
            XCTAssertEqual(result.temperature, base.temperature)
            XCTAssertEqual(result.tint, base.tint)
            XCTAssertEqual(result.rawIntent.isAsShotWhiteBalance, base.rawIntent.isAsShotWhiteBalance)
        }
    }

    func testWhiteBalanceCorrectionLeavesAllOtherAutoFieldsAtFrozenBaseline() throws {
        let base = EditRecipe(exposure: -0.7, temperature: 4800, tint: 12,
            contrast: 17, highlights: -7, shadows: 4, whites: 30, blacks: -20,
            texture: 9, clarity: 11, dehaze: 15, vibrance: 19, saturation: -6,
            sharpness: 45, luminanceNR: 22, crop: .init(x: 0.1, y: 0.2, width: 0.7, height: 0.6),
            straightenDegrees: 90, sourceNeighbors: ["preserved"], confidence: 0.8,
            cameraProfile: "Adobe Color")
        let stats = evenStats(mean: 0.31, low: 0.02, high: 0.011, nativeTemperature: 5200, horizonAngle: 1.4)
        let result = AutoDevelop.recipe(for: makeAsset(recipe: base), stats: stats)
        // Frozen pre-patch Auto outcome, except WB: +.45 EV, -33 H, +40 S,
        // vibrance8, preserved rotation, inert controls0; every other field inherited.
        let expected = base.updating {
            $0.exposure = 0.45; $0.highlights = -33; $0.shadows = 40
            $0.vibrance = 8
            $0.whites = 0; $0.blacks = 0; $0.dehaze = 0
        }
        XCTAssertEqual(result.valueFingerprint, expected.valueFingerprint)
        XCTAssertEqual(result.id, base.id)
        XCTAssertEqual(result.schemaVersion, base.schemaVersion)
        XCTAssertEqual(result.sourceNeighbors, base.sourceNeighbors)
        XCTAssertEqual(result.confidence, base.confidence)
        XCTAssertEqual(result.cropAspect, base.cropAspect)
    }

    func testHeaderAndVersionAutoPreserveFreshAndManualWhiteBalance() throws {
        for base in [EditRecipe.neutral, EditRecipe(temperature: 4800, tint: 12),
                     EditRecipe(temperature: 4800), EditRecipe(tint: -8)] {
            let stats = evenStats(mean: 0.31, nativeTemperature: 5200)
            let source: RecipeSource = base == .neutral ? .shot : .hand
            let header = P0SessionModel(), version = P0SessionModel()
            let asset = makeAsset(recipe: base, source: source, stats: stats)
            header.assets = [asset]; version.assets = [asset]
            XCTAssertEqual(header.applyAuto(to: [asset.id], force: true), 1)
            version.pickVersion(2, for: asset.id)
            let a = try XCTUnwrap(header.assets[0].recipe)
            let b = try XCTUnwrap(version.assets[0].recipe)
            XCTAssertEqual(a.valueFingerprint, b.valueFingerprint)
            XCTAssertEqual(a.temperature, base.temperature)
            XCTAssertEqual(a.tint, base.tint)
            XCTAssertEqual(a.rawIntent.isAsShotWhiteBalance, base.rawIntent.isAsShotWhiteBalance)
            XCTAssertEqual(header.applyAuto(to: [asset.id], force: true), 0)
            version.pickVersion(2, for: asset.id)
            XCTAssertEqual(version.assets[0].recipe?.valueFingerprint, b.valueFingerprint)
            header.undoLast()
            // Undo stores a neutral recipe as nil; compare the effective recipe.
            XCTAssertEqual(header.recipe(for: asset.id).valueFingerprint, base.valueFingerprint)
            if source == .hand {
                version.pickVersion(3, for: asset.id)
                XCTAssertEqual(version.assets[0].recipe?.valueFingerprint, base.valueFingerprint)
            }
        }
    }

    func testToneAutoPreservesGeometryForAnyHorizonMeasurement() {
        for angle in [-91.5, -2.25, 0, 1.7, 90, 181.3] {
            for horizon: Double? in [nil, 0, 1.75, 12] {
                let base = EditRecipe(crop: .init(x: 0.1, y: 0.2, width: 0.7, height: 0.6),
                                      straightenDegrees: angle)
                let result = AutoDevelop.recipe(for: makeAsset(recipe: base),
                                                stats: evenStats(horizonAngle: horizon))
                XCTAssertEqual(result.straightenDegrees, angle)
                XCTAssertEqual(result.crop, base.crop)
                XCTAssertEqual(result.cropAspect, base.cropAspect)
            }
        }
    }

    // MARK: - applyAuto

    func testApplyAutoSkipsHandAndSidecarAssetsUnlessForced() {
        let shotID = UUID(), handID = UUID(), sidecarID = UUID()
        let session = P0SessionModel()
        session.assets = [
            makeAsset(id: shotID, stats: evenStats(mean: 0.2)),
            makeAsset(id: handID, recipe: EditRecipe(exposure: 0.9), source: .hand, stats: evenStats(mean: 0.2)),
            makeAsset(id: sidecarID, recipe: EditRecipe(exposure: -0.4), source: .sidecar, stats: evenStats(mean: 0.2)),
        ]

        let applied = session.applyAuto(to: [shotID, handID, sidecarID])

        XCTAssertEqual(applied, 1, "only the untouched frame is auto-developed")
        XCTAssertEqual(session.assets[0].recipeSource, .auto)
        XCTAssertEqual(session.assets[1].recipeSource, .hand)
        XCTAssertEqual(session.assets[1].recipe?.exposure, 0.9, "a hand recipe is never overwritten")
        XCTAssertEqual(session.assets[2].recipeSource, .sidecar)
        XCTAssertEqual(session.assets[2].recipe?.exposure, -0.4)

        let forced = session.applyAuto(to: [handID, sidecarID], force: true)
        XCTAssertEqual(forced, 2)
        XCTAssertEqual(session.assets[1].recipeSource, .auto)
        XCTAssertEqual(session.assets[2].recipeSource, .auto)
    }

    func testApplyAutoSkipsAssetsWithoutMeasurements() {
        let id = UUID()
        let session = P0SessionModel()
        session.assets = [makeAsset(id: id)]

        XCTAssertEqual(session.applyAuto(to: [id]), 0, "no stats means no invented correction")
        XCTAssertEqual(session.assets[0].recipeSource, .shot)
        XCTAssertNil(session.assets[0].recipe)
        XCTAssertFalse(session.canUndo)
    }

    func testOneUndoRevertsTheWholeBatchAndRestoresSource() throws {
        let a = UUID(), b = UUID(), c = UUID()
        let session = P0SessionModel()
        session.assets = [
            makeAsset(id: a, stats: evenStats(mean: 0.2)),
            makeAsset(id: b, stats: evenStats(mean: 0.7)),
            makeAsset(id: c, stats: evenStats(mean: 0.35)),
        ]

        XCTAssertEqual(session.applyAuto(to: [a, b, c]), 3)
        XCTAssertTrue(session.assets.allSatisfy { $0.recipeSource == .auto })
        XCTAssertTrue(session.assets.allSatisfy { $0.recipe != nil })
        XCTAssertEqual(session.undoCoordinator.stack.count, 1, "a batch is one undo step, not three")
        guard case .batchEdit(let command)? = session.undoCoordinator.stack.last else {
            return XCTFail("auto must push a batch command")
        }
        XCTAssertEqual(command.marks.count, 3)
        XCTAssertEqual(command.label, "Auto")

        session.undoLast()

        XCTAssertTrue(session.assets.allSatisfy { $0.recipeSource == .shot }, "undo restores provenance too")
        XCTAssertTrue(session.assets.allSatisfy { $0.recipe == nil })
        XCTAssertFalse(session.canUndo)
    }

    func testAutoNeverTouchesCullOrFinalOrder() {
        let a = UUID(), b = UUID()
        let session = P0SessionModel()
        session.assets = [
            makeAsset(id: a, stats: evenStats(mean: 0.2), cull: .keep),
            makeAsset(id: b, stats: evenStats(mean: 0.8), cull: .reject),
        ]
        session.shoot = ShootRecord(
            name: "auto-proof",
            assets: session.assets,
            finalSetOrder: FinalSetOrder(assetIDs: [b, a])
        )

        XCTAssertEqual(session.applyAuto(to: [a, b]), 2)

        XCTAssertEqual(session.assets[0].cull, .keep)
        XCTAssertEqual(session.assets[1].cull, .reject)
        XCTAssertEqual(session.shoot?.finalSetOrder.assetIDs, [b, a])

        session.undoLast()

        XCTAssertEqual(session.assets[0].cull, .keep, "undoing an edit must not disturb cull")
        XCTAssertEqual(session.assets[1].cull, .reject)
        XCTAssertEqual(session.shoot?.finalSetOrder.assetIDs, [b, a])
    }

    // MARK: - ImageStats

    func testMeasureProducesNormalizedBinsAndClipFractions() throws {
        let width = 32, height = 32
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        // Top half pure black, bottom half pure white — half clipped at each end.
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let value: UInt8 = (index / 4) < (width * height / 2) ? 0 : 255
            pixels[index] = value
            pixels[index + 1] = value
            pixels[index + 2] = value
            pixels[index + 3] = 255
        }
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let cgImage = try XCTUnwrap(context.makeImage())

        let stats = try XCTUnwrap(ImageStats.measure(cgImage: cgImage))

        XCTAssertEqual(stats.luminanceBins.count, ImageStats.binCount)
        XCTAssertEqual(stats.sampleCount, width * height)
        XCTAssertEqual(stats.shadowClipFraction, 0.5, accuracy: 0.05)
        XCTAssertEqual(stats.highlightClipFraction, 0.5, accuracy: 0.05)
        XCTAssertEqual(stats.mean, 0.5, accuracy: 0.05)
    }

    func testStatsSurviveOldCatalogsAndRoundTrip() throws {
        let stats = evenStats(mean: 0.42, low: 0.01, high: 0.02, nativeTemperature: 5_600, horizonAngle: -2.5)
        let asset = makeAsset(stats: stats)

        let encoded = try JSONEncoder().encode(asset)
        let decoded = try JSONDecoder().decode(AssetRecord.self, from: encoded)

        XCTAssertEqual(decoded.imageStats, stats)
        XCTAssertEqual(decoded.imageStats?.nativeTemperature, 5_600)
        XCTAssertEqual(decoded.imageStats?.horizonAngle, -2.5)
    }
}
