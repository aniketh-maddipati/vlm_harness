import XCTest
import ImageIO
@testable import LuminaCore

// WP-7. Save, headless: the rules (R-32…R-36, R-83) on a virtual clock, and the real writers
// (sidecar, verified copy, JPEG) in a temp directory with real image files.

@MainActor
final class WP7SaveRulesTests: XCTestCase {
    /// Culled with `n` keepers, on Save, past the ⏎ guard.
    private func onSave(keep n: Int = 6, card: String = "demo117") -> Harness {
        let h = Harness(card: card); h.startCulling(); h.keepN(n); h.go(4); h.wait(2); return h
    }

    func test_R32_tripleClickAndTwoCmdS_saveOnce() async {
        let h = onSave(keep: 9)
        XCTAssertNil(h.state.saved)
        for _ in 0..<3 { h.model.saveNow() }
        h.key("cmd+s"); h.key("cmd+s")
        XCTAssertEqual(h.state.saved?.n, 9); XCTAssertEqual(h.state.saved?.again, false, "saved more than once")
        await h.model.saveSettled()
        XCTAssertEqual(h.exporter.jobs.count, 1, "one save, one export")
        XCTAssertEqual(h.exporter.jobs.first?.items.count, 9)
        XCTAssertFalse(h.model.save.saving)
    }

    func test_R33_enterRhythmNeverSaves_pausedEnterDoes() {
        let h = Harness(); h.startCulling(); h.keepN(4); h.go(4, settle: 0.1)
        h.key("return")
        XCTAssertNil(h.state.saved, "⏎ just after arriving saved")
        XCTAssertEqual(h.model.save.message, KeyRouter.saveGuard)
        XCTAssertEqual(h.model.savePresentation.note, "Paused so ⏎ doesn’t save by accident. Click Save or press ⌘S.")
        for _ in 0..<8 { h.key("return", settle: 0.55); XCTAssertNil(h.state.saved, "the ⏎ rhythm saved") }
        h.wait(1.3); h.key("return")
        XCTAssertNotNil(h.state.saved, "a deliberate ⏎ after a pause didn’t save")
        XCTAssertNil(h.model.save.message)
        // A second ⏎ straight after is the rhythm again: guarded, and nothing changes.
        let sig = h.state.saved?.sig
        h.key("return", settle: 0.2)
        XCTAssertEqual(h.state.saved?.sig, sig); XCTAssertEqual(h.state.saved?.again, false)
        h.wait(AppModel.saveMessageSeconds + 0.1)
        XCTAssertNil(h.model.save.message, "the guard message stays up")
        XCTAssertEqual(h.state.errors, 0)
    }

    func test_R33_heldEnterIsIgnored() {
        let h = onSave()
        h.key("return", isRepeat: true)
        XCTAssertNil(h.state.saved)
    }

    func test_R34_saveOnce_repeatNoop_formatAndEditsReenable() async {
        let h = onSave(keep: 5)
        XCTAssertEqual(h.model.savePresentation.buttonLabel, "Save 5 photos"); XCTAssertTrue(h.model.savePresentation.buttonEnabled)
        XCTAssertEqual(h.model.savePresentation.note, "")
        h.model.saveNow()
        let s1 = h.state.saved
        XCTAssertEqual(s1?.fmt, "xmp"); XCTAssertEqual(s1?.again, false)
        XCTAssertEqual(h.model.savePresentation.buttonLabel, "✓ Saved"); XCTAssertFalse(h.model.savePresentation.buttonEnabled)
        XCTAssertEqual(h.model.savePresentation.note, "Up to date.")
        h.key("cmd+s")
        XCTAssertEqual(h.state.saved, s1, "repeat save changed something")
        XCTAssertEqual(h.model.save.message, "Already saved. Nothing changed since.")
        XCTAssertEqual(h.model.savePresentation.note, "Already saved. Nothing changed since.")

        h.model.setFormat(.jpeg)
        var p = h.model.savePresentation
        XCTAssertTrue(p.buttonEnabled); XCTAssertEqual(p.buttonLabel, "Save again · 5 photos")
        XCTAssertEqual(p.note, "Changed since \(AppModel.hhmm(h.model.save.saved!.at)). Only what changed is rewritten.")
        h.model.saveNow()
        XCTAssertEqual(h.state.saved?.fmt, "jpeg"); XCTAssertEqual(h.state.saved?.again, true)
        XCTAssertFalse(h.model.savePresentation.buttonEnabled)

        // An edit, then leaving it out, each change the signature.
        h.go(3, settle: 1.2); h.key("."); h.go(4); h.wait(2)
        p = h.model.savePresentation
        XCTAssertTrue(p.buttonEnabled); XCTAssertTrue(p.showsIncludeEdits); XCTAssertEqual(p.editsSubline, "1 edited, 4 as shot")
        h.model.saveNow(); XCTAssertEqual(h.state.saved?.ne, 1)
        h.model.setWithEdits(false)
        p = h.model.savePresentation
        XCTAssertTrue(p.buttonEnabled); XCTAssertEqual(p.editsSubline, "All as shot · edits stay in Lumina")
        h.model.saveNow(); XCTAssertEqual(h.state.saved?.ne, 0)
        h.model.setWithEdits(true)
        XCTAssertTrue(h.model.savePresentation.buttonEnabled, "back to a signature that was saved two saves ago is still a change")

        await h.model.saveSettled()
        XCTAssertEqual(h.exporter.jobs.map(\.format), [.xmp, .jpeg, .jpeg, .jpeg])
        XCTAssertEqual(h.exporter.jobs[2].items.filter { $0.look != nil }.count, 1)
        XCTAssertEqual(h.exporter.jobs[3].items.filter { $0.look != nil }.count, 0, "edits left out still reached the exporter")
    }

    func test_R34_changedOnlyCarriesWhatChanged() async {
        let h = onSave(keep: 6)
        h.model.saveNow()
        h.go(3, settle: 1.2); let edited = h.state.cur!; h.key("."); h.go(4); h.wait(2)
        h.model.saveNow()
        let dropped = h.model.keptIDs.last!
        h.model.decisions.mark(dropped, keep: false); h.model.changed()
        h.model.saveNow()
        h.model.setFormat(.folder); h.model.saveNow()
        await h.model.saveSettled()
        let jobs = h.exporter.jobs
        XCTAssertEqual(jobs.count, 4)
        XCTAssertNil(jobs[0].changedOnly, "the first save writes everything")
        XCTAssertEqual(jobs[1].changedOnly, [edited])
        XCTAssertEqual(jobs[2].changedOnly, [dropped]); XCTAssertEqual(jobs[2].items.count, 5)
        XCTAssertNil(jobs[3].changedOnly, "another format writes everything")
        XCTAssertEqual(jobs[3].destination?.lastPathComponent, "Keepers")
    }

    func test_R35_cmdSFromEditGoesToSaveWithoutSaving() {
        let h = Harness(); h.startCulling(); h.keepN(4); h.go(3, settle: 1.2); h.key(".")
        h.key("cmd+s", settle: 0.6)
        XCTAssertEqual(h.state.step, "save"); XCTAssertNil(h.state.saved, "⌘S in Edit saved")
        h.key("cmd+s", isRepeat: true); XCTAssertNil(h.state.saved, "a held ⌘S saved")
        h.key("cmd+s")
        XCTAssertEqual(h.state.saved?.n, 4); XCTAssertEqual(h.state.saved?.ne, 1)
        // From Cull too.
        h.go(2); h.key("r"); let sig = h.state.saved?.sig
        h.key("cmd+s", settle: 0.6)
        XCTAssertEqual(h.state.step, "save"); XCTAssertEqual(h.state.saved?.sig, sig)
    }

    func test_R36_everythingOut_nothingToSave() async {
        let h = Harness(); h.startCulling()
        for _ in 0..<h.state.total { h.key("x", settle: 0.01) }
        XCTAssertEqual(h.state.out, 117)
        h.go(4); h.wait(2)
        let p = h.model.savePresentation
        XCTAssertEqual(p.buttonLabel, "Nothing to save yet"); XCTAssertFalse(p.buttonEnabled)
        XCTAssertEqual(p.summary, "No keepers yet"); XCTAssertEqual(p.note, "Keep photos in Cull first.")
        XCTAssertEqual(p.behind, "117 out · not saved"); XCTAssertFalse(p.hasUndecided)
        h.model.saveNow(); h.key("return"); h.key("cmd+s"); h.wait(0.4)
        XCTAssertNil(h.state.saved); XCTAssertNil(h.model.save.message)
        await h.model.saveSettled()
        XCTAssertTrue(h.exporter.jobs.isEmpty)
    }

    func test_R83_saveBigShootIsRecordedAtOnce() async {
        let h = Harness(card: "demo:5000", copyRate: 400); h.startCulling()
        XCTAssertEqual(h.state.copied, h.state.total)
        for (i, p) in h.model.shoot.photos.enumerated() { h.model.decisions.mark(p.id, keep: i % 2 == 0) }
        h.model.changed(); h.go(4, settle: 1); h.wait(1)
        let kept = h.model.keptIDs.count
        XCTAssertGreaterThan(kept, 2400)
        _ = h.model.savePresentation
        let clock = ContinuousClock()
        let took = clock.measure { h.model.saveNow() }
        XCTAssertEqual(h.state.saved?.n, kept)
        XCTAssertLessThan(took, .milliseconds(500), "R-83: Save took \(took)")
        // What the screen redraws with after a save, and a repeat save, are cheap too.
        let again = clock.measure { _ = h.model.savePresentation; h.key("cmd+s") }
        XCTAssertLessThan(again, .milliseconds(100))
        XCTAssertEqual(h.state.saved?.again, false)
        await h.model.saveSettled()
        XCTAssertEqual(h.exporter.jobs.count, 1); XCTAssertEqual(h.exporter.jobs.first?.items.count, kept)
    }

    func test_copy_summaryAndSavedCard() {
        let h = onSave(keep: 6)
        var p = h.model.savePresentation
        XCTAssertEqual(p.summary, "6 keepers ready to save"); XCTAssertEqual(p.behind, "111 undecided · not saved"); XCTAssertTrue(p.hasUndecided)
        XCTAssertEqual(p.description, "A small .xmp file next to each RAW: keepers as 3★. The RAW is untouched. Works with Capture One too.")
        XCTAssertTrue(p.destination.hasPrefix("next to the RAWs in ~/Pictures/Lumina/")); XCTAssertFalse(p.canChangeDestination)
        XCTAssertFalse(p.showsIncludeEdits); XCTAssertNil(p.savedTitle)
        h.model.saveNow(); p = h.model.savePresentation
        XCTAssertEqual(p.savedTitle, "Saved · 6 photos, as shot · \(AppModel.hhmm(h.clock.now))")
        XCTAssertEqual(p.savedHint, "In Lightroom: Import → Add, or Metadata → Read Metadata from Files.")
        h.go(3, settle: 1.2); h.key("."); h.go(4); h.wait(2)
        p = h.model.savePresentation
        XCTAssertEqual(p.description, "A small .xmp file next to each RAW: keepers as 3★, edits as develop settings. The RAW is untouched. Works with Capture One too.")
        h.model.setFormat(.folder); p = h.model.savePresentation
        XCTAssertEqual(p.description, "Copies of your keepers, with an .xmp for edited ones. Nothing else.")
        XCTAssertTrue(p.destination.hasSuffix("Untitled/Keepers")); XCTAssertTrue(p.canChangeDestination)
        h.model.setFormat(.jpeg); p = h.model.savePresentation
        XCTAssertEqual(p.description, "Full-size sRGB JPEGs. Edits baked in; the rest as shot.")
        XCTAssertTrue(p.destination.hasSuffix("Untitled/JPEG"))
        h.model.saveNow(); p = h.model.savePresentation
        XCTAssertEqual(p.savedTitle, "Saved again · 6 photos, 1 with edits · \(AppModel.hhmm(h.clock.now))")
        XCTAssertEqual(p.savedHint, "JPEGs are ready to share or upload.")
        h.model.setWithEdits(false)
        XCTAssertEqual(h.model.savePresentation.description, "Full-size sRGB JPEGs. All as shot.")
        h.key("x") // not a Save key: nothing happens
        XCTAssertEqual(h.state.kept, 6)
        XCTAssertEqual(SaveFormat.allCases.map(SavePresentation.formatLabel), ["Lightroom", "Folder", "JPEG"])
    }

    func test_destination_changeReenablesSave_cardRefused() async {
        let h = onSave(keep: 3)
        h.model.setFormat(.folder); h.model.saveNow()
        XCTAssertFalse(h.model.savePresentation.buttonEnabled)
        let d = Fixtures.folder("wp7-dest") { _ in }
        h.model.setDestination(d)
        XCTAssertTrue(h.model.savePresentation.buttonEnabled, "a new destination is a change")
        XCTAssertEqual(h.model.savePresentation.destination, AppModel.tilde(d))
        h.model.saveNow()
        XCTAssertFalse(h.model.savePresentation.buttonEnabled)
        await h.model.saveSettled()
        XCTAssertEqual(h.exporter.jobs.last?.destination, d); XCTAssertNil(h.exporter.jobs.last?.changedOnly)
        XCTAssertEqual(h.model.save.lastResult, d)
        var revealed: URL?
        h.model.hooks.reveal = { revealed = $0 }
        h.model.revealSaved(); XCTAssertEqual(revealed, d)
        var asked = 0
        h.model.hooks.pickDestination = { asked += 1 }
        h.model.chooseDestination(); XCTAssertEqual(asked, 1)
    }

    /// A save whose files didn't land must not keep saying "Saved".
    func test_failedExport_takesTheSavedRecordBack() async {
        final class Failing: Exporter, @unchecked Sendable {
            var fail = true
            func export(_ job: ExportJob) async -> ExportResult {
                fail ? ExportResult(written: job.items.count - 2, failed: [job.items[0].photo.id: "on the card", job.items[1].photo.id: "locked"]) : ExportResult(written: job.items.count)
            }
        }
        Faults.shared.clearAll(); ErrorFunnel.reset()
        let clock = TestScheduler(), ex = Failing()
        var config = LaunchConfig(arguments: [], environment: ["LUMINA_CARD": "demo117", "LUMINA_INTRO": "skip"]); config.copyRate = 400
        let m = AppModel.launch(config: config, services: Services(images: DefaultImageProvider(), exporter: ex, persistence: MemoryPersistence()), clock: clock)
        m.handle(KeyEvent("return")); clock.advance(2)
        for _ in 0..<4 { m.handle(KeyEvent("r")) }
        m.go(.save); clock.advance(2)
        m.saveNow(); XCTAssertNotNil(m.save.saved)
        await m.saveSettled()
        XCTAssertNil(m.save.saved, "still says Saved after a failed export")
        let p = m.savePresentation
        XCTAssertEqual(p.note, "2 of 4 photos weren’t saved: DSC03260 · on the card, and 1 more. Nothing was lost. Save again to retry.")
        XCTAssertTrue(p.noteIsError); XCTAssertTrue(p.buttonEnabled); XCTAssertEqual(p.buttonLabel, "Save 4 photos")
        clock.advance(10); XCTAssertNotNil(m.save.message, "a failure message went away by itself")
        ex.fail = false
        m.saveNow(); await m.saveSettled()
        XCTAssertEqual(m.save.saved?.n, 4); XCTAssertEqual(m.save.saved?.again, false); XCTAssertNil(m.save.message)
    }
}

// MARK: - The writers

final class WP7WriterTests: XCTestCase {
    private func photo(_ url: URL) -> Photo { Photo(id: url.deletingPathExtension().lastPathComponent, file: url.lastPathComponent, source: .file(url)) }
    private func shoot(_ name: String, _ n: Int = 3) -> (dir: URL, photos: [Photo]) {
        let d = Fixtures.folder(name) { d in for i in 0..<n { Fixtures.write(d.appendingPathComponent("DSC0\(i).jpg"), w: 320 + i * 20, h: 200, seed: i + 1) } }
        return (d, (0..<n).map { photo(d.appendingPathComponent("DSC0\($0).jpg")) })
    }
    private func names(_ d: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: d.path)) ?? []).sorted() }
    private func props(_ url: URL) throws -> [String: String] { try XCTUnwrap(XMPSidecar.read(Data(contentsOf: url))) }

    static let lightroom = """
    <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
    <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 7.0-c000 1.000000, 0000/00/00-00:00:00">
     <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
      <rdf:Description rdf:about=""
        xmlns:xmp="http://ns.adobe.com/xap/1.0/"
        xmlns:dc="http://purl.org/dc/elements/1.1/"
        xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
       xmp:Rating="5"
       xmp:Label="Red"
       crs:Version="16.1"
       crs:ProcessVersion="15.4"
       crs:Exposure2012="-1.00"
       crs:Vibrance="+22"
       crs:Texture="+10">
       <dc:subject>
        <rdf:Bag>
         <rdf:li>mehendi</rdf:li>
         <rdf:li>family &amp; friends</rdf:li>
        </rdf:Bag>
       </dc:subject>
       <crs:ToneCurvePV2012>
        <rdf:Seq>
         <rdf:li>0, 0</rdf:li>
         <rdf:li>255, 255</rdf:li>
        </rdf:Seq>
       </crs:ToneCurvePV2012>
      </rdf:Description>
     </rdf:RDF>
    </x:xmpmeta>
    <?xpacket end="w"?>
    """

    func test_sidecar_ratingAndDevelopSettings_photoUntouched() async throws {
        let s = shoot("wp7-sidecar")
        let before = try s.photos.map { try ExportFiles.sha256(file: $0.source.url!) }
        let look: Look = ["ev": 0.5, "wb": 6100, "tint": -4, "hl": -30, "sh": 25, "con": 12, "sat": -8, "cDark": -10, "cLight": 20,
                          "hue_red": 5, "sat_orange": -15, "lum_blue": 30, "vig": -20, "vFeather": 70, "shp": 60, "nr": 15,
                          "cropX": 0.1, "cropY": 0.05, "cropW": 0.8, "cropH": 0.9, "angle": 1.5, "turns": 1]
        let r = await FileExporter().export(ExportJob(format: .xmp, items: [.init(photo: s.photos[0], look: look), .init(photo: s.photos[1], look: nil)], destination: nil))
        XCTAssertEqual(r.written, 2); XCTAssertTrue(r.failed.isEmpty)
        XCTAssertEqual(names(s.dir), ["DSC00.jpg", "DSC00.xmp", "DSC01.jpg", "DSC01.xmp", "DSC02.jpg"], "one sidecar per keeper, nothing else")
        XCTAssertEqual(r.reveal, s.dir.appendingPathComponent("DSC00.xmp"))
        XCTAssertEqual(try s.photos.map { try ExportFiles.sha256(file: $0.source.url!) }, before, "an original changed")

        let p = try props(s.dir.appendingPathComponent("DSC00.xmp"))
        let want = ["xmp:Rating": "3", "crs:Exposure2012": "+0.50", "crs:WhiteBalance": "Custom", "crs:Temperature": "6100", "crs:Tint": "-4",
                    "crs:Highlights2012": "-30", "crs:Shadows2012": "+25", "crs:Contrast2012": "+12", "crs:Saturation": "-8",
                    "crs:ToneCurveName2012": "Custom", "crs:ToneCurvePV2012": "0, 0|64, 51|128, 128|191, 217|255, 255",
                    "crs:HueAdjustmentRed": "+5", "crs:SaturationAdjustmentOrange": "-15", "crs:LuminanceAdjustmentBlue": "+30",
                    "crs:PostCropVignetteAmount": "-20", "crs:PostCropVignetteMidpoint": "50", "crs:PostCropVignetteFeather": "70",
                    "crs:PostCropVignetteRoundness": "0", "crs:PostCropVignetteStyle": "1", "crs:PostCropVignetteHighlightContrast": "0",
                    "crs:Sharpness": "60", "crs:LuminanceSmoothing": "15", "crs:HasCrop": "True", "crs:CropLeft": "0.1", "crs:CropTop": "0.05",
                    "crs:CropRight": "0.9", "crs:CropBottom": "0.95", "crs:CropAngle": "1.5", "tiff:Orientation": "6",
                    "crs:ProcessVersion": "11.0", "crs:HasSettings": "True"]
        for (k, v) in want { XCTAssertEqual(p[k], v, k) }
        let text = try String(contentsOf: s.dir.appendingPathComponent("DSC00.xmp"), encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("<?xpacket begin=")); XCTAssertTrue(text.contains("<x:xmpmeta")); XCTAssertTrue(text.hasSuffix("<?xpacket end=\"w\"?>\n"))

        let plain = try props(s.dir.appendingPathComponent("DSC01.xmp"))
        XCTAssertEqual(plain["xmp:Rating"], "3")
        XCTAssertTrue(plain.keys.allSatisfy { !$0.hasPrefix("crs:") }, "as shot wrote develop settings: \(plain.keys.sorted())")
        XCTAssertFalse(names(s.dir).contains { $0.hasSuffix(".lumina-bak") }, "nothing was replaced, so nothing to back up")
    }

    func test_sidecar_mergesAnExistingOne_keepsABackup_takesBackItsOwnSettings() async throws {
        let s = shoot("wp7-merge", 1)
        let side = s.dir.appendingPathComponent("DSC00.xmp"), bak = s.dir.appendingPathComponent("DSC00.xmp.lumina-bak")
        Fixtures.text(side, Self.lightroom)
        let original = try Data(contentsOf: side)
        let ex = FileExporter()

        var r = await ex.export(ExportJob(format: .xmp, items: [.init(photo: s.photos[0], look: ["ev": 0.35, "con": 20])], destination: nil))
        XCTAssertEqual(r.written, 1); XCTAssertTrue(r.failed.isEmpty, "\(r.failed)")
        var p = try props(side)
        XCTAssertEqual(p["xmp:Rating"], "5", "a 5★ from Lightroom was pulled down to 3")
        XCTAssertEqual(p["crs:Exposure2012"], "+0.35"); XCTAssertEqual(p["crs:Contrast2012"], "+20")
        for (k, v) in ["xmp:Label": "Red", "crs:Vibrance": "+22", "crs:Texture": "+10", "crs:Version": "16.1", "crs:ProcessVersion": "15.4",
                       "dc:subject": "mehendi|family & friends", "crs:ToneCurvePV2012": "0, 0|255, 255"] { XCTAssertEqual(p[k], v, "\(k) was not preserved") }
        XCTAssertEqual(try Data(contentsOf: bak), original, ".lumina-bak is not the sidecar as it was")

        // Lumina's curve over Lightroom's, and back.
        r = await ex.export(ExportJob(format: .xmp, items: [.init(photo: s.photos[0], look: ["ev": 0.35, "con": 20, "cMid": 10])], destination: nil))
        XCTAssertEqual(try props(side)["crs:ToneCurvePV2012"], "0, 0|64, 64|128, 140|191, 191|255, 255")
        r = await ex.export(ExportJob(format: .xmp, items: [.init(photo: s.photos[0], look: ["ev": 0.35, "con": 20])], destination: nil))
        XCTAssertEqual(try props(side)["crs:ToneCurvePV2012"], "0, 0|255, 255"); XCTAssertNil(try props(side)["crs:ToneCurveName2012"])

        // Saving the same thing again changes nothing on disk.
        let once = try Data(contentsOf: side)
        r = await ex.export(ExportJob(format: .xmp, items: [.init(photo: s.photos[0], look: ["ev": 0.35, "con": 20])], destination: nil))
        XCTAssertEqual(try Data(contentsOf: side), once)

        // The edit is reset in Lumina: its own settings go, Lightroom's stay, the first backup stays.
        r = await ex.export(ExportJob(format: .xmp, items: [.init(photo: s.photos[0], look: nil)], destination: nil))
        XCTAssertTrue(r.failed.isEmpty)
        p = try props(side)
        XCTAssertNil(p["crs:Contrast2012"], "Lumina's contrast stayed after the edit was reset")
        XCTAssertEqual(p["crs:Exposure2012"], "-1.00", "Lightroom's own exposure did not come back"); XCTAssertNil(p["lumina:Wrote"]); XCTAssertNil(p["lumina:Replaced"])
        XCTAssertEqual(p["crs:Vibrance"], "+22"); XCTAssertEqual(p["xmp:Rating"], "5"); XCTAssertEqual(p["dc:subject"], "mehendi|family & friends")
        XCTAssertEqual(try Data(contentsOf: bak), original, "the backup was replaced by Lumina's own earlier output")
        XCTAssertEqual(names(s.dir), ["DSC00.jpg", "DSC00.xmp", "DSC00.xmp.lumina-bak"], "temp files left behind")
    }

    func test_sidecar_lowerRatingIsRaised_unreadableIsLeftAlone() async throws {
        let s = shoot("wp7-rating", 2)
        let a = s.dir.appendingPathComponent("DSC00.xmp"), b = s.dir.appendingPathComponent("DSC01.xmp")
        Fixtures.text(a, Self.lightroom.replacingOccurrences(of: "xmp:Rating=\"5\"", with: "xmp:Rating=\"1\""))
        Fixtures.text(b, "this is not xml <<<")
        let r = await FileExporter().export(ExportJob(format: .xmp, items: s.photos.map { .init(photo: $0, look: nil) }, destination: nil))
        XCTAssertEqual(r.written, 1)
        XCTAssertEqual(r.failed, ["DSC01": "the existing .xmp can’t be read"])
        XCTAssertEqual(try props(a)["xmp:Rating"], "3")
        XCTAssertEqual(try String(contentsOf: b, encoding: .utf8), "this is not xml <<<", "an unreadable sidecar was overwritten")
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.path + ".lumina-bak"))
    }

    func test_sidecar_refusedOnACard_missingPhotoReported_demoSkipped() async throws {
        let s = shoot("wp7-card", 3)
        try FileManager.default.removeItem(at: s.photos[2].source.url!)
        let demo = Shoot.demo117.photos[0]
        let items = (s.photos + [demo]).map { ExportJob.Item(photo: $0, look: ["ev": 1]) }
        var r = await FileExporter(isCard: { $0.lastPathComponent.hasPrefix("DSC00") }).export(ExportJob(format: .xmp, items: items, destination: nil))
        XCTAssertEqual(r.failed, ["DSC00": "on the card", "DSC02": "missing"])
        XCTAssertEqual(r.written, 2, "DSC01 and the demo photo (nothing to write)")
        XCTAssertEqual(names(s.dir), ["DSC00.jpg", "DSC01.jpg", "DSC01.xmp"])

        for fmt in [SaveFormat.folder, .jpeg] {
            let dest = Fixtures.root.appendingPathComponent("wp7-card-out"); try? FileManager.default.removeItem(at: dest)
            r = await FileExporter(isCard: { $0 == dest }).export(ExportJob(format: fmt, items: Array(items.prefix(2)) + [items[3]], destination: dest))
            XCTAssertEqual(r.failed, ["DSC00": "on the card", "DSC01": "on the card"], "\(fmt)")
            XCTAssertEqual(r.written, 1)
            XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path), "\(fmt): the folder was made on the card")
            r = await FileExporter().export(ExportJob(format: fmt, items: Array(items.prefix(2)), destination: nil))
            XCTAssertEqual(r.failed.count, 2, "\(fmt) with no folder")
        }
    }

    func test_folder_verifiedCopies_neverMoves_neverOverwritesADifferentFile() async throws {
        let s = shoot("wp7-copy", 3)
        let dest = Fixtures.folder("wp7-copy-out") { d in
            Fixtures.text(d.appendingPathComponent("DSC01.jpg"), "someone else's file")
            try FileManager.default.copyItem(at: s.dir.appendingPathComponent("DSC02.jpg"), to: d.appendingPathComponent("DSC02.jpg"))
        }
        let items = [ExportJob.Item(photo: s.photos[0], look: ["sat": 10]), .init(photo: s.photos[1], look: nil), .init(photo: s.photos[2], look: nil)]
        let ex = FileExporter()
        var r = await ex.export(ExportJob(format: .folder, items: items, destination: dest))
        XCTAssertEqual(r.written, 3); XCTAssertTrue(r.failed.isEmpty, "\(r.failed)"); XCTAssertEqual(r.reveal, dest)
        XCTAssertEqual(names(dest), ["DSC00.jpg", "DSC00.xmp", "DSC01-2.jpg", "DSC01.jpg", "DSC02.jpg"], "copies, an .xmp for the edited one, nothing else")
        XCTAssertEqual(names(s.dir), ["DSC00.jpg", "DSC01.jpg", "DSC02.jpg"], "the originals moved or gained files")
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("DSC01.jpg"), encoding: .utf8), "someone else's file")
        for (src, out) in [("DSC00.jpg", "DSC00.jpg"), ("DSC01.jpg", "DSC01-2.jpg"), ("DSC02.jpg", "DSC02.jpg")] {
            XCTAssertEqual(try ExportFiles.sha256(file: dest.appendingPathComponent(out)), try ExportFiles.sha256(file: s.dir.appendingPathComponent(src)), out)
        }
        XCTAssertEqual(try props(dest.appendingPathComponent("DSC00.xmp"))["crs:Saturation"], "+10")

        // Again: already there, no second set of numbered copies.
        r = await ex.export(ExportJob(format: .folder, items: items, destination: dest))
        XCTAssertEqual(r.written, 3)
        XCTAssertEqual(names(dest).count, 5)

        // The helper itself: outcome per case, and a missing original creates nothing.
        let one = Fixtures.folder("wp7-copy-one") { _ in }
        let src = s.dir.appendingPathComponent("DSC00.jpg")
        XCTAssertEqual(try ExportFiles.copyVerified(src, to: one.appendingPathComponent("a.jpg")), .copied(one.appendingPathComponent("a.jpg")))
        XCTAssertEqual(try ExportFiles.copyVerified(src, to: one.appendingPathComponent("a.jpg")), .alreadyThere(one.appendingPathComponent("a.jpg")))
        XCTAssertThrowsError(try ExportFiles.copyVerified(s.dir.appendingPathComponent("gone.jpg"), to: one.appendingPathComponent("gone.jpg")))
        XCTAssertEqual(names(one), ["a.jpg"])
    }

    func test_jpeg_rendersDecodableFullSizeFiles_backupBeforeReplacing() async throws {
        let s = shoot("wp7-jpeg", 2)
        let png = s.dir.appendingPathComponent("IMG 1.png"); Fixtures.write(png, type: .png, w: 300, h: 450, seed: 9)
        let dest = Fixtures.root.appendingPathComponent("wp7-jpeg-out/JPEG"); try? FileManager.default.removeItem(at: dest.deletingLastPathComponent())
        let items = (s.photos + [photo(png)]).map { ExportJob.Item(photo: $0, look: nil) }
        let ex = FileExporter()
        var r = await ex.export(ExportJob(format: .jpeg, items: items, destination: dest))
        XCTAssertEqual(r.written, 3); XCTAssertTrue(r.failed.isEmpty, "\(r.failed)"); XCTAssertEqual(r.reveal, dest)
        XCTAssertEqual(names(dest), ["DSC00.jpg", "DSC01.jpg", "IMG 1.jpg"])
        for (n, size) in [("DSC00.jpg", (320, 200)), ("DSC01.jpg", (340, 200)), ("IMG 1.jpg", (300, 450))] {
            let src = try XCTUnwrap(CGImageSourceCreateWithURL(dest.appendingPathComponent(n) as CFURL, nil))
            XCTAssertEqual(CGImageSourceGetType(src) as String?, "public.jpeg")
            let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil), "\(n) doesn’t decode")
            XCTAssertEqual(img.width, size.0, n); XCTAssertEqual(img.height, size.1, n)
        }
        XCTAssertEqual(names(s.dir), ["DSC00.jpg", "DSC01.jpg", "IMG 1.png"], "the source folder changed")

        // Only what changed is rewritten: DSC00 changed, the others are left as they are.
        let old = try Data(contentsOf: dest.appendingPathComponent("DSC00.jpg"))
        Fixtures.write(s.photos[0].source.url!, w: 320, h: 200, seed: 77)
        try FileManager.default.removeItem(at: dest.appendingPathComponent("IMG 1.jpg"))
        r = await ex.export(ExportJob(format: .jpeg, items: items, destination: dest, changedOnly: ["DSC00"]))
        XCTAssertEqual(r.written, 3)
        XCTAssertNotEqual(try Data(contentsOf: dest.appendingPathComponent("DSC00.jpg")), old)
        XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent("DSC00.jpg.lumina-bak")), old, "the JPEG being replaced was not kept")
        XCTAssertEqual(names(dest), ["DSC00.jpg", "DSC00.jpg.lumina-bak", "DSC01.jpg", "IMG 1.jpg"], "a missing output is written again; an unchanged one is not touched")
    }

    func test_failuresAreReportedPerFile() async throws {
        let s = shoot("wp7-fail", 3)
        Fixtures.text(s.dir.appendingPathComponent("broken.jpg"), "not a picture")
        try FileManager.default.removeItem(at: s.photos[1].source.url!)
        let items = (s.photos + [photo(s.dir.appendingPathComponent("broken.jpg"))]).map { ExportJob.Item(photo: $0, look: nil) }
        let dest = Fixtures.folder("wp7-fail-out") { _ in }
        var r = await FileExporter().export(ExportJob(format: .jpeg, items: items, destination: dest))
        XCTAssertEqual(r.written, 2); XCTAssertEqual(r.failed, ["DSC01": "missing", "broken": "can’t be opened"])
        r = await FileExporter().export(ExportJob(format: .folder, items: items, destination: dest.appendingPathComponent("copies")))
        XCTAssertEqual(r.written, 3); XCTAssertEqual(r.failed, ["DSC01": "missing"])
        // The destination can't be made: a file is in the way. Every photo is reported, nothing is lost.
        let blocked = dest.appendingPathComponent("DSC00.jpg/inside")
        r = await FileExporter().export(ExportJob(format: .folder, items: items, destination: blocked))
        XCTAssertEqual(r.written, 0); XCTAssertEqual(Set(r.failed.keys), ["DSC00", "DSC01", "DSC02", "broken"])
        // A locked sidecar is reported and left as it is.
        let side = s.dir.appendingPathComponent("DSC00.xmp"); Fixtures.text(side, WP7WriterTests.lightroom)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: side.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: side.path) }
        r = await FileExporter().export(ExportJob(format: .xmp, items: [items[0], items[2]], destination: nil))
        XCTAssertEqual(r.failed, ["DSC00": "locked"]); XCTAssertEqual(r.written, 1)
        XCTAssertEqual(try String(contentsOf: side, encoding: .utf8), WP7WriterTests.lightroom)
    }

    func test_write_backupOnceAtomicAndVerified() throws {
        let d = Fixtures.folder("wp7-write") { _ in }, f = d.appendingPathComponent("sub/a.txt")
        XCTAssertFalse(try ExportFiles.write(Data("one".utf8), to: f))
        XCTAssertFalse(try ExportFiles.write(Data("one".utf8), to: f), "identical bytes are not a replacement")
        XCTAssertTrue(try ExportFiles.write(Data("two".utf8), to: f))
        XCTAssertFalse(try ExportFiles.write(Data("three".utf8), to: f), "the first backup is the original and stays")
        XCTAssertEqual(try String(contentsOf: f, encoding: .utf8), "three")
        XCTAssertEqual(try String(contentsOf: ExportFiles.backupURL(for: f), encoding: .utf8), "one")
        XCTAssertEqual(names(f.deletingLastPathComponent()), ["a.txt", "a.txt.lumina-bak"])
        XCTAssertEqual(ExportFiles.sha256(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertFalse(ExportFiles.isCard(d)); XCTAssertFalse(ExportFiles.isCard(d.appendingPathComponent("not/there/yet")))
    }

    func test_lookMapping_onlyWhatTheLookHolds_turnsFollowTheFile() {
        XCTAssertTrue(XMPSidecar.develop([:]).isEmpty)
        XCTAssertEqual(XMPSidecar.develop(["tint": 6]).map(\.key), ["crs:WhiteBalance", "crs:Temperature", "crs:Tint"])
        XCTAssertEqual(XMPSidecar.develop(["ev": 0]).first?.value, .text("0.00"))
        XCTAssertEqual(XMPSidecar.develop(["ev": -1.25]).first?.value, .text("-1.25"))
        XCTAssertEqual(XMPSidecar.develop(["vMid": 30]).count, 0, "vignette shape without an amount does nothing")
        XCTAssertEqual(XMPSidecar.develop(["turns": 4]).count, 0)
        XCTAssertEqual(XMPSidecar.develop(["turns": -1], orientation: 6).first?.value, .text("1"))
        XCTAssertEqual([1, 2, 3, 4].map { XMPSidecar.turned(1, by: $0) }, [6, 3, 8, 1])
        XCTAssertEqual(XMPSidecar.turned(2, by: 1), 7)
        // Every slider in the README's table lands somewhere.
        var all: Look = [:]; for s in EditSetting.all { all[s.key] = s.max }
        let keys = Set(XMPSidecar.develop(all).map(\.key))
        XCTAssertEqual(keys.count, 1 + 3 + 4 + 2 + 24 + 6 + 2, "exposure, white balance, tone, curve, colours, vignette, detail: \(keys.sorted())")
    }

    /// The model on the real writers, end to end: Save writes sidecars beside the files, off the main thread.
    @MainActor func test_modelSavesThroughTheFileExporter() async throws {
        let s = shoot("wp7-e2e", 4)
        Faults.shared.clearAll(); ErrorFunnel.reset()
        let clock = TestScheduler()
        let m = AppModel(shoot: Shoot(photos: s.photos, scenes: [PhotoScene(id: "r0", index: 0, hm: "09:00", ids: s.photos.map(\.id))], name: "wp7-e2e", local: true, key: "wp7-e2e"),
                         services: Services(images: DefaultImageProvider(), exporter: FileExporter(), persistence: MemoryPersistence()), clock: clock)
        m.setShoot(m.shoot)
        for id in ["DSC00", "DSC01", "DSC03"] { m.decisions.mark(id, keep: true) }
        m.edits.set("ev", 0.7, on: "DSC01", decisions: m.decisions); m.changed()
        m.go(.save); clock.advance(2)
        XCTAssertEqual(m.savePresentation.destination, "next to the RAWs in " + AppModel.tilde(s.dir))
        m.handle(KeyEvent("s", .command))
        XCTAssertEqual(m.save.saved?.n, 3); XCTAssertEqual(m.save.saved?.ne, 1)
        await m.saveSettled()
        XCTAssertNotNil(m.save.saved); XCTAssertNil(m.save.message)
        XCTAssertEqual(names(s.dir), ["DSC00.jpg", "DSC00.xmp", "DSC01.jpg", "DSC01.xmp", "DSC02.jpg", "DSC03.jpg", "DSC03.xmp"])
        XCTAssertEqual(try props(s.dir.appendingPathComponent("DSC01.xmp"))["crs:Exposure2012"], "+0.70")
        XCTAssertEqual(m.save.lastResult, s.dir.appendingPathComponent("DSC00.xmp"))

        // JPEGs into a chosen folder; then one more keeper: only that one is written.
        let out = Fixtures.folder("wp7-e2e-out") { _ in }
        m.setFormat(.jpeg); m.setDestination(out); m.saveNow(); await m.saveSettled()
        XCTAssertEqual(names(out), ["DSC00.jpg", "DSC01.jpg", "DSC03.jpg"])
        let stamp = try FileManager.default.attributesOfItem(atPath: out.appendingPathComponent("DSC00.jpg").path)[.modificationDate] as? Date
        m.decisions.mark("DSC02", keep: true); m.changed(); m.saveNow(); await m.saveSettled()
        XCTAssertEqual(names(out), ["DSC00.jpg", "DSC01.jpg", "DSC02.jpg", "DSC03.jpg"])
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: out.appendingPathComponent("DSC00.jpg").path)[.modificationDate] as? Date, stamp)
        XCTAssertEqual(m.save.saved?.again, true); XCTAssertEqual(ErrorFunnel.count, 0)
    }
}

private extension PhotoSource {
    var url: URL? { if case .file(let u) = self { return u } else { return nil } }
}
