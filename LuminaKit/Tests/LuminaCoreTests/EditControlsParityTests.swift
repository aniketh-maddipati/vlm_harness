import XCTest
import CoreGraphics
@testable import LuminaCore

/// WP-5, headless: the controls column's parity pieces with the prototype (Lumina Edit v19): the
/// histogram's data and markers, the Curve graph's points and presets, and the footer's save status.
@MainActor
final class EditControlsParityTests: XCTestCase {
    /// Copied, `n` kept, in Edit.
    private func inEdit(_ n: Int = 4, window: CGSize = CGSize(width: 1100, height: 760)) -> Harness {
        let h = Harness(window: window)
        h.startCulling(); h.keepN(n); h.wait(0.3); h.go(3, settle: 1.2)
        return h
    }

    // MARK: the curve's maths

    func test_curve_flatLookIsTheDiagonal_andPassesThroughItsPoints() {
        let flat = ToneCurve.curve([:])
        XCTAssertEqual(flat.count, ToneCurve.samples + 1)
        for (i, y) in flat.enumerated() { XCTAssertEqual(y, Double(i) / Double(ToneCurve.samples), accuracy: 1e-9) }
        let look: Look = ["cDark": 12, "cMid": -6, "cLight": 20]
        let f = ToneCurve.spline(ToneCurve.points(look))
        XCTAssertEqual(f(0.25), 0.31, accuracy: 1e-9); XCTAssertEqual(f(0.5), 0.47, accuracy: 1e-9); XCTAssertEqual(f(0.75), 0.85, accuracy: 1e-9)
        // Monotone between rising points: no overshoot past a flat stretch (Fritsch–Carlson).
        let steep = ToneCurve.curve(["cDark": 50, "cLight": -50])
        for i in 1..<steep.count { XCTAssertGreaterThanOrEqual(steep[i] + 1e-12, steep[i - 1]) }
        XCTAssertTrue(steep.allSatisfy { (0...1).contains($0) })
    }

    func test_curvePresets_areThePrototypesShapesOnTheThreePoints() {
        let p = Dictionary(uniqueKeysWithValues: ToneCurve.presets.map { ($0.name, $0.look) })
        XCTAssertEqual(ToneCurve.presets.map(\.name), ["Linear", "Soft contrast", "Strong contrast", "Brighten"])
        XCTAssertEqual(p["Linear"], ["cDark": 0, "cMid": 0, "cLight": 0])
        XCTAssertEqual(p["Soft contrast"], ["cDark": -8, "cMid": 0, "cLight": 8])
        XCTAssertEqual(p["Strong contrast"], ["cDark": -18, "cMid": 1, "cLight": 20])
        XCTAssertEqual(p["Brighten"]?["cMid"], 20)
    }

    // MARK: the curve on the model

    func test_curvePointDrag_movesItsSetting_isOneUndoStep_andCancels() {
        let h = inEdit(), m = h.model, cur = h.state.cur!
        m.setSection(.curve)
        XCTAssertEqual(m.curveAnchors.map(\.label), ["Darks", "Mids", "Lights"])
        XCTAssertEqual(m.curveAnchors.map(\.text), ["0", "0", "0"])
        XCTAssertFalse(m.curveAnchors.contains { $0.changed })

        m.curveDragBegan("cDark")
        XCTAssertEqual(m.edit.draggingKey, "cDark")
        for _ in 0..<5 { m.curveDragMoved(by: 0.012) }          // 6 % of the graph's height up
        XCTAssertEqual(m.value("cDark"), 12, accuracy: 0.001)
        XCTAssertEqual(m.curveReadout, "In 64 · Out 79")
        m.curveDragMoved(by: 0.05, fine: true)                  // ⇧: a quarter → +2.5
        XCTAssertEqual(m.value("cDark"), 14.5, accuracy: 0.6)
        m.curveDragEnded()
        XCTAssertNil(m.curveReadout); XCTAssertNil(m.edit.draggingKey)
        XCTAssertTrue(m.curveAnchors[0].changed)
        XCTAssertEqual(m.curveAnchors[0].y, 0.25 + m.value("cDark") / 200, accuracy: 1e-9)
        m.editUndo()
        XCTAssertNil(m.edits.looks[m.edits.key(for: cur, decisions: m.decisions)]?["cDark"], "a curve drag is one undo step")

        // Esc during a drag puts the value back.
        m.curveDragBegan("cLight"); m.curveDragMoved(by: -0.1)
        XCTAssertEqual(m.value("cLight"), -20, accuracy: 0.001)
        XCTAssertTrue(m.cancelSliderDrag())
        XCTAssertEqual(m.value("cLight"), 0)
        // Only the three curve settings are points.
        m.curveDragBegan("ev"); XCTAssertNil(m.editControls.drag)
    }

    func test_curvePreset_setsTheThreeValues_inOneUndoStep_andLightsItsChip() {
        let h = inEdit(), m = h.model
        m.setSection(.curve)
        XCTAssertTrue(m.curvePresetIsOn("Linear")); XCTAssertFalse(m.curvePresetIsOn("Soft contrast"))
        m.applyCurvePreset("Strong contrast")
        XCTAssertEqual([m.value("cDark"), m.value("cMid"), m.value("cLight")], [-18, 1, 20])
        XCTAssertTrue(m.curvePresetIsOn("Strong contrast")); XCTAssertFalse(m.curvePresetIsOn("Linear"))
        XCTAssertEqual(m.toast?.text, "Strong contrast curve. ⌘Z undoes it.")
        m.editUndo()
        XCTAssertEqual([m.value("cDark"), m.value("cMid"), m.value("cLight")], [0, 0, 0])
        m.applyCurvePreset("Soft contrast"); m.applyCurvePreset("Linear")
        XCTAssertTrue(m.curvePresetIsOn("Linear"))
        XCTAssertEqual(m.changedCount(.curve), 0, "Linear leaves no curve setting behind")
    }

    // MARK: the histogram

    func test_histogramFromBins_marksClipping_andScalesWithoutTheEnds() throws {
        var bins = [Float](repeating: 0, count: LumaHistogram.bins)
        bins[0] = 0.3; bins[128] = 0.4; bins[255] = 0.3
        let h = try XCTUnwrap(EditHistogram(bins: bins))
        XCTAssertEqual(h.heights.count, EditHistogram.points)
        XCTAssertTrue(h.shadowsClipping); XCTAssertTrue(h.highlightsClipping); XCTAssertTrue(h.measured)
        XCTAssertEqual(h.heights.max(), 1)
        XCTAssertTrue(h.heights.allSatisfy { (0...1).contains($0) })
        bins[0] = 0.001; bins[255] = 0
        let quiet = try XCTUnwrap(EditHistogram(bins: bins))
        XCTAssertFalse(quiet.shadowsClipping); XCTAssertFalse(quiet.highlightsClipping)
        XCTAssertNil(EditHistogram(bins: [Float](repeating: 0, count: 256)))
    }

    func test_histogramEstimate_followsThePrototypesClippingRule() {
        XCTAssertFalse(EditHistogram.estimate([:], brightness: 0.5).shadowsClipping)
        XCTAssertFalse(EditHistogram.estimate([:], brightness: 0.5).highlightsClipping)
        XCTAssertTrue(EditHistogram.estimate(["ev": 1.2], brightness: 0.5).highlightsClipping)
        XCTAssertTrue(EditHistogram.estimate(["hl": 70], brightness: 0.5).highlightsClipping)
        XCTAssertTrue(EditHistogram.estimate(["ev": -1.3], brightness: 0.5).shadowsClipping)
        XCTAssertTrue(EditHistogram.estimate(["sh": -60], brightness: 0.5).shadowsClipping)
        XCTAssertTrue(EditHistogram.estimate(["con": 60, "ev": -0.6], brightness: 0.5).shadowsClipping)
        let e = EditHistogram.estimate(["ev": 0.5], brightness: 0.3)
        XCTAssertEqual(e.heights.count, 44); XCTAssertEqual(e.heights.max(), 1); XCTAssertFalse(e.measured)
    }

    func test_lumaHistogram_ofHalfBlackHalfWhite() throws {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 32, y: 0, width: 32, height: 32))
        let bins = try XCTUnwrap(LumaHistogram.compute(ctx.makeImage()!))
        XCTAssertEqual(bins.count, 256)
        XCTAssertEqual(bins.reduce(0, +), 1, accuracy: 1e-4)
        XCTAssertEqual(bins[0], 0.5, accuracy: 0.02); XCTAssertEqual(bins[255], 0.5, accuracy: 0.02)
        let h = try XCTUnwrap(EditHistogram(bins: bins))
        XCTAssertTrue(h.shadowsClipping && h.highlightsClipping)
    }

    func test_histogramShown_notWhileCropping_notInCurve_notInSmallWindows() {
        let h = inEdit(), m = h.model
        XCTAssertTrue(m.histogramShown)
        XCTAssertNotNil(m.editHistogram, "the estimate shows until the provider has measured")
        m.setSection(.curve); XCTAssertFalse(m.histogramShown)
        m.setSection(.light); m.edit.overlay = .crop; XCTAssertFalse(m.histogramShown)
        m.edit.overlay = nil; m.windowSize = CGSize(width: 850, height: 760); XCTAssertFalse(m.histogramShown)
        m.windowSize = CGSize(width: 1100, height: 600); XCTAssertFalse(m.histogramShown)
    }

    func test_histogramRequest_holdsStillDuringADrag() {
        let h = inEdit(), m = h.model
        let r0 = m.histogramRequest
        m.sliderDragBegan("ev")
        let r1 = m.histogramRequest
        m.sliderDragMoved(by: 0.05)
        XCTAssertEqual(m.histogramRequest, r1, "the histogram is measured on rest renders only")
        m.sliderDragEnded()
        XCTAssertNotEqual(m.histogramRequest, r0)
        XCTAssertNotEqual(m.histogramRequest, r1)
    }

    func test_measuredHistogram_replacesTheEstimate_forThisPhotoOnly() async {
        let h = inEdit(), m = h.model
        await m.measureEditHistogram()
        let measured = m.editHistogram
        XCTAssertEqual(measured?.measured, true, "the default provider measures the demo picture")
        XCTAssertEqual(measured?.heights.count, EditHistogram.points)
        m.editMove(1)
        XCTAssertEqual(m.editHistogram?.measured, false, "another photo's histogram was shown")
    }

    func test_clippingMarkerWords_goInTheHintLine_overASlidersHint() {
        let h = inEdit(), m = h.model
        m.edit.hoverKey = "ev"
        XCTAssertEqual(m.editHintText, EditFormat.hint("ev"))
        m.setHintNote(AppModel.shadowsClippingHint)
        XCTAssertEqual(m.editHintText, "Shadows are clipping: detail is lost in the darkest areas.")
        m.setHintNote(nil)
        XCTAssertEqual(m.editHintText, EditFormat.hint("ev"))
        m.sliderDragBegan("ev"); XCTAssertEqual(m.editHintText, ""); m.sliderDragEnded()
    }

    // MARK: the footer

    func test_saveStatus_savingThenAllSaved_andTheStorageWords() {
        let h = inEdit(), m = h.model
        h.wait(1)
        XCTAssertEqual(m.editSaveStatus, "All changes saved")
        h.key(".", settle: 0.05)
        XCTAssertEqual(m.editSaveStatus, "Saving…")
        h.wait(0.8)
        XCTAssertEqual(m.editSaveStatus, "All changes saved")
        // A drag: "Saving…" at once, though its writes are debounced.
        m.sliderDragBegan("sh"); m.sliderDragMoved(by: 0.05)
        XCTAssertEqual(m.editSaveStatus, "Saving…")
        m.sliderDragEnded(); h.wait(1)
        XCTAssertEqual(m.editSaveStatus, "All changes saved")
        // Undo and Out are changes too.
        h.key("cmd+z", settle: 0.05); XCTAssertEqual(m.editSaveStatus, "Saving…"); h.wait(1)
        m.editOut(); XCTAssertEqual(m.editSaveStatus, "Saving…"); h.wait(1)
        XCTAssertEqual(m.editSaveStatus, "All changes saved")

        m.edit.warning = AppModel.storageWarning
        XCTAssertEqual(m.editSaveStatus, "Couldn’t save. Keep this window open.")
        m.edit.warning = AppModel.offlineWarning
        XCTAssertEqual(m.editSaveStatus, "Offline · saved on this computer")
        m.edit.warning = AppModel.otherWindowWarning
        XCTAssertEqual(m.editSaveStatus, "All changes saved")
    }
}
