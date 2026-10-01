import XCTest
@testable import LuminaCore

// WP-2. Open and import, headless: the FirstTimerTests rules R-10…R-19, plus R-1A, R-31 and R-85,
// on a model with a virtual clock and real fixture folders. No window.

/// Fixture folders are built in one shared temp directory (`Fixtures.root`), and other workers'
/// test runs rebuild the same names. Each test works on its own copy (modified times survive a copy).
private func own(_ fixture: URL) -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lumina-wp2-\(ProcessInfo.processInfo.processIdentifier)/\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let to = dir.appendingPathComponent(fixture.lastPathComponent)
    try! FileManager.default.copyItem(at: fixture, to: to)
    return to
}

@MainActor
private extension Harness {
    func importAndWait(_ urls: URL...) async { model.importURLs(urls); await model.importsIdle() }
    var message: String { model.imports.message ?? "" }
}

@MainActor
final class WP2ImportTests: XCTestCase {
    override class func tearDown() {
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("lumina-wp2-\(ProcessInfo.processInfo.processIdentifier)"))
    }

    // MARK: wrong files

    func test_R10_R11_R12_messyFolder_onlyRealPhotos_everySkipExplained() async {
        let h = Harness()
        await h.importAndWait(own(Fixtures.messy))
        XCTAssertEqual(h.state.total, Fixtures.messyExpectedAdded)
        XCTAssertEqual(h.message, "Added 6 photos from Card dump. Skipped 1 video · 1 zip/archive (unzip it first) · 1 damaged or not really a photo · 1 empty (0 bytes) · 2 not a photo.")
        XCTAssertNil(h.message.range(of: #"DS_Store|xmp|\._"#, options: .regularExpression), "mentions system files")
        XCTAssertFalse(h.model.imports.failed)
        XCTAssertEqual(h.state.step, "cull"); XCTAssertTrue(h.model.shoot.local)
        XCTAssertEqual(h.state.import?.msg, h.message); XCTAssertEqual(h.state.import?.n, 6); XCTAssertEqual(h.state.import?.local, true)
        XCTAssertEqual(h.state.copied, 6, "a local shoot has no copy step")
        XCTAssertEqual(Set(h.model.shoot.photos.map(\.file)), ["a.jpg", "b.png", "c.heic", "d.gif", "E.JPG", "f-really-png.jpg"])
        XCTAssertNotNil(h.state.cur); XCTAssertEqual(h.state.errors, 0)
    }

    func test_R13_onlyJunk_staysOnOpen_saysWhatOpens() async {
        let h = Harness(), n0 = h.state.total
        await h.importAndWait(own(Fixtures.onlyJunk))
        XCTAssertEqual(h.state.step, "open"); XCTAssertEqual(h.state.total, n0); XCTAssertFalse(h.model.shoot.local)
        XCTAssertEqual(h.message, "No photos added. Skipped 1 video · 2 not a photo. Lumina opens JPEG, PNG, WebP, HEIC, AVIF and RAW.")
        XCTAssertTrue(h.model.imports.failed, "error colour")
        XCTAssertEqual(h.model.openImportMessage, h.message)
        // The same from another step: stay there, and say where the details are.
        h.startCulling()
        await h.importAndWait(own(Fixtures.onlyJunk))
        XCTAssertEqual(h.state.step, "cull"); XCTAssertEqual(h.state.total, n0)
        XCTAssertEqual(h.model.toast?.text, "No photos added. Open has the details.")
    }

    func test_R12_fakeRawFiles_reportedAsDamaged_notCrashing() async {
        let h = Harness()
        await h.importAndWait(own(Fixtures.raws))
        XCTAssertEqual(h.message, "No photos added. Skipped 4 damaged or not really a photo. Lumina opens JPEG, PNG, WebP, HEIC, AVIF and RAW.")
        XCTAssertEqual(h.state.step, "open"); XCTAssertEqual(h.state.errors, 0)
        for n in ["A.CR2", "B.NEF", "C.ARW", "D.dng"] { XCTAssertEqual(ImportClassifier.classify(name: n, size: 5000), .raw) }
    }

    func test_R13_emptyFolder_andFolderOfSidecars() async {
        let h = Harness()
        await h.importAndWait(own(Fixtures.empty))
        XCTAssertEqual(h.message, "That folder is empty."); XCTAssertTrue(h.model.imports.failed); XCTAssertEqual(h.state.step, "open")
        let hidden = own(Fixtures.folder("Hidden") { d in Fixtures.bytes(d.appendingPathComponent(".DS_Store"), 600); Fixtures.bytes(d.appendingPathComponent("._a.jpg"), 4096) })
        await h.importAndWait(hidden)
        XCTAssertEqual(h.message, "That folder is empty.", "hidden files are not there, to the person importing")
        let sidecars = own(Fixtures.folder("Sidecars") { d in Fixtures.text(d.appendingPathComponent("a.xmp"), "<x:xmpmeta/>"); Fixtures.bytes(d.appendingPathComponent("Thumbs.db"), 90) })
        await h.importAndWait(sidecars)
        XCTAssertEqual(h.message, "No photos found there. Lumina opens JPEG, PNG, WebP, HEIC, AVIF and RAW.")
        await h.importAndWait(URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        XCTAssertEqual(h.message, ImportSummary.wentWrong); XCTAssertEqual(h.state.step, "open"); XCTAssertEqual(h.state.errors, 0)
    }

    func test_R14_samePhotosTwice_noDuplicates() async {
        let h = Harness(), f = own(Fixtures.batch("Pick", 3))
        await h.importAndWait(f); await h.importAndWait(f)
        XCTAssertEqual(h.state.total, 3)
        XCTAssertEqual(h.message, "No photos added. Skipped 3 already in this shoot. Lumina opens JPEG, PNG, WebP, HEIC, AVIF and RAW.")
        // Within one batch too.
        let g = Harness(), f2 = own(Fixtures.batch("Twice", 2))
        g.model.importURLs([f2, f2]); await g.model.importsIdle()
        XCTAssertEqual(g.state.total, 2); XCTAssertTrue(g.message.contains("Skipped 2 already in this shoot"), g.message)
        XCTAssertEqual(Set(g.model.shoot.photos.map(\.id)).count, 2)
    }

    func test_R15_nestedFolders_groupedBySubfolder() async {
        let h = Harness()
        await h.importAndWait(own(Fixtures.nested))
        XCTAssertEqual(h.state.total, 4)
        XCTAssertEqual(h.model.shoot.scenes.map(\.header), ["08:00 · Day 1", "09:00 · Day 2", "18:00 · Trip"])
        XCTAssertEqual(h.model.shoot.scenes.map(\.ids.count), [2, 1, 1])
        XCTAssertEqual(h.model.shoot.photos.map(\.rel), ["Trip/Day 1/a.jpg", "Trip/Day 1/b.jpg", "Trip/Day 2/c.jpg", "Trip/e.jpg"])
        XCTAssertEqual(h.model.shoot.name, "Trip"); XCTAssertEqual(h.model.shoot.span, "08:00–18:00")
        XCTAssertTrue(h.model.shoot.bursts.isEmpty, "4 s apart is not a burst")
        for p in h.model.shoot.photos { XCTAssertEqual(h.model.shoot.scenes[p.scene].ids.contains(p.id), true) }
    }

    func test_R16_exif_groupsByShotTime_fillsCamera_missingFieldsStayNil() async throws {
        let h = Harness()
        await h.importAndWait(own(Fixtures.exifDay))
        XCTAssertEqual(h.model.shoot.scenes.map(\.hm), ["09:00", "18:30"], "grouped by file date, not shot time")
        let p = try XCTUnwrap(h.model.shoot.photos.first)
        XCTAssertEqual(p.file, "m1.jpg"); XCTAssertEqual(p.camera, "Canon EOS R6"); XCTAssertEqual(p.focal, 85); XCTAssertEqual(p.aperture, 2.8)
        XCTAssertEqual(p.shutter, "1/250"); XCTAssertEqual(p.iso, 800); XCTAssertEqual(p.time, "09:00:00"); XCTAssertEqual(p.shot, Fixtures.day(9))
        XCTAssertNil(p.lens, "no lens in the file: left out, not invented")
        // No EXIF at all: the file's modified time stands in, and nothing else is made up.
        let plain = own(Fixtures.folder("Plain") { d in Fixtures.write(d.appendingPathComponent("x.png"), type: .png, seed: 3, modified: Fixtures.day(14, 5, 9)) })
        let g = Harness()
        await g.importAndWait(plain)
        let q = try XCTUnwrap(g.model.shoot.photos.first)
        XCTAssertEqual(q.time, "14:05:09"); XCTAssertEqual(g.model.shoot.scenes.first?.hm, "14:05")
        XCTAssertNil(q.camera); XCTAssertNil(q.focal); XCTAssertNil(q.aperture); XCTAssertNil(q.shutter); XCTAssertNil(q.iso)
    }

    func test_R1B_oddNames_import_andKeepTheirNames() async {
        let h = Harness()
        await h.importAndWait(own(Fixtures.names))
        XCTAssertEqual(h.state.total, 6); XCTAssertEqual(h.state.errors, 0)
        let files = h.model.shoot.photos.map(\.file)
        for want in ["🌅 sunset ✨.jpg", String(repeating: "a", count: 200) + ".jpg", "IMG 0001 (1).JPG", "שלום עולם.jpg", "noext", "spaced   .jpg"] { XCTAssertTrue(files.contains(want), want) }
        XCTAssertEqual(Set(h.model.shoot.photos.map(\.id)).count, 6)
        XCTAssertTrue(h.model.shoot.photos.allSatisfy { $0.id.range(of: "^L[0-9a-z]+$", options: .regularExpression) != nil }, "ids are plain")
        XCTAssertEqual(ImportClassifier.classify(name: "holiday.final version", size: 9), .photo, "not an extension: try decoding")
        XCTAssertEqual(ImportClassifier.classify(name: "  padded.MOV  ", size: 9), .video)
    }

    func test_R1C_oddShapes_keepTheirTrueAspect() async {
        let h = Harness()
        await h.importAndWait(own(Fixtures.shapes))
        XCTAssertEqual(h.state.total, 5)
        let want: [String: Double] = ["shape0.jpg": 1, "shape1.jpg": 40, "shape2.jpg": 1.0 / 40, "shape3.jpg": 1.5, "shape4.jpg": 2.0 / 3000]
        for p in h.model.shoot.photos { XCTAssertEqual(p.aspect, want[p.file] ?? -1, accuracy: (want[p.file] ?? 1) * 0.001, p.file) }
    }

    func test_R1D_rotatedPhonePhoto_isPortrait() async throws {
        let h = Harness()
        await h.importAndWait(own(Fixtures.rotated))
        XCTAssertEqual(try XCTUnwrap(h.model.shoot.photos.first).aspect, 420.0 / 640.0, accuracy: 0.001)
    }

    // MARK: drops

    func test_R17_dropOnAnyStep_addsAndStays_decisionsSurvive() async {
        let h = Harness()
        await h.importAndWait(own(Fixtures.batch("First", 1)))
        XCTAssertEqual(h.state.step, "cull"); XCTAssertEqual(h.state.total, 1)
        h.key("r"); XCTAssertEqual(h.state.kept, 1)
        let first = h.model.shoot.photos[0].id, key = h.model.shoot.key
        await h.importAndWait(own(Fixtures.batch("Second", 2, startHour: 11)))
        XCTAssertEqual(h.state.total, 3); XCTAssertEqual(h.state.step, "cull")
        XCTAssertEqual(h.state.keep[first], true, "the decision on the photo already there was lost")
        XCTAssertEqual(h.model.shoot.key, key, "appending keeps the shoot's store key")
        XCTAssertEqual(h.model.toast?.text, "Added 2 photos from Second.")
        XCTAssertEqual(h.model.shoot.scenes.map(\.title), ["First", "Second"])
        XCTAssertFalse(h.model.imports.dropTargeted)
        h.go(3)
        await h.importAndWait(own(Fixtures.batch("Third", 1, startHour: 13)))
        XCTAssertEqual(h.state.step, "edit"); XCTAssertEqual(h.state.total, 4)
        XCTAssertEqual(h.model.toast?.text, "Added 1 photo from Third. They show in Cull now, and in Edit next time you open it.")
        XCTAssertEqual(h.state.cur, first, "Edit lost its photo")
        h.go(4)
        await h.importAndWait(own(Fixtures.batch("Fourth", 1, startHour: 15)))
        XCTAssertEqual(h.state.step, "save"); XCTAssertEqual(h.state.total, 5); XCTAssertEqual(h.state.kept, 1); XCTAssertEqual(h.state.errors, 0)
    }

    func test_R17_dropWhileTheCardIsCopying_replacesTheCardAndStopsTheCopy() async {
        let h = Harness()
        h.key("return"); h.wait(0.5)
        XCTAssertTrue(h.model.copying)
        await h.importAndWait(own(Fixtures.batch("Mid", 2)))
        XCTAssertEqual(h.state.step, "cull"); XCTAssertEqual(h.state.total, 2); XCTAssertFalse(h.model.copying)
        h.wait(3)
        XCTAssertEqual(h.state.copied, 2); XCTAssertEqual(h.state.total, 2)
    }

    func test_R18_dropWhileChecking_bothBatchesAdded() async {
        let h = Harness(), a = own(Fixtures.batch("A", 24)), b = own(Fixtures.batch("B", 6, startHour: 13))
        h.model.importURLs([a])
        XCTAssertTrue(h.model.imports.busy, "busy from the moment of the drop")
        XCTAssertEqual(h.model.openImportProgress, "Checking 0 of 0 files…"); XCTAssertNil(h.model.openImportMessage)
        h.model.importURLs([b])
        await h.model.importsIdle()
        XCTAssertFalse(h.model.imports.busy); XCTAssertEqual(h.state.total, 30)
        XCTAssertEqual(h.message, "Added 6 photos from B."); XCTAssertNil(h.model.openImportProgress)
        XCTAssertEqual(h.model.shoot.scenes.count, 2)
    }

    // MARK: relaunch

    func test_R19_relaunch_reopensTheFolder_decisionsKept() async throws {
        let store = MemoryPersistence(), f = own(Fixtures.batch("Holiday", 5))
        let h = Harness(store: store)
        await h.importAndWait(f)
        h.key("r"); h.key("r"); h.key("x")
        let keep = h.state.keep, cur = h.state.cur
        XCTAssertEqual(h.state.kept, 2)

        // A relaunch: the card comes up first, then the folder opens by itself through its bookmark.
        let h2 = Harness(store: store)
        XCTAssertEqual(h2.state.total, 117)
        h2.model.reopenLastFolder()
        XCTAssertTrue(h2.model.openShowsReopen, "offered while it opens")
        await h2.model.importsIdle()
        XCTAssertEqual(h2.state.total, 5); XCTAssertEqual(h2.state.keep, keep); XCTAssertEqual(h2.state.kept, 2); XCTAssertEqual(h2.state.out, 1)
        XCTAssertEqual(h2.state.step, "cull", "back on the step it was closed on"); XCTAssertEqual(h2.state.cur, cur)
        XCTAssertNil(h2.model.imports.message, "reopening is silent"); XCTAssertFalse(h2.model.openShowsReopen)
        XCTAssertEqual(h2.model.shoot.key, h.model.shoot.key)

        // The folder is gone at the next launch (kept aside as a copy: a bookmark would follow a move).
        // Open offers it, and choosing it again restores the decisions.
        let away = f.deletingLastPathComponent().appendingPathComponent("Elsewhere")
        try FileManager.default.copyItem(at: f, to: away); try FileManager.default.removeItem(at: f)
        let h3 = Harness(store: store)
        h3.model.reopenLastFolder(); await h3.model.importsIdle()
        XCTAssertEqual(h3.state.total, 117); XCTAssertTrue(h3.model.openShowsReopen)
        XCTAssertEqual(h3.model.openReopenTitle, "Folder · Holiday")
        XCTAssertEqual(h3.model.openReopenDetails, "5 photos · choose the folder again to see them. Your decisions are kept.")
        try FileManager.default.moveItem(at: away, to: f)
        await h3.importAndWait(f)
        XCTAssertEqual(h3.state.total, 5); XCTAssertEqual(h3.state.keep, keep); XCTAssertEqual(h3.state.step, "cull")
        XCTAssertEqual(h3.state.errors, 0)
    }

    func test_R19_cardButtonGoesBackToTheCard_folderRowComesBack() async {
        let h = Harness()
        h.startCulling(); h.keepN(3)
        await h.importAndWait(own(Fixtures.batch("Side", 4)))
        XCTAssertEqual(h.state.total, 4); XCTAssertEqual(h.state.kept, 0); XCTAssertEqual(h.state.step, "cull")
        h.key("x")
        h.go(1)
        XCTAssertEqual(h.model.openCardButton, "Continue culling"); XCTAssertFalse(h.model.openShowsReopen)
        h.key("return")
        XCTAssertEqual(h.state.total, 117); XCTAssertEqual(h.state.kept, 3, "the card's decisions"); XCTAssertEqual(h.state.copied, 117); XCTAssertEqual(h.state.step, "cull")
        h.go(1)
        XCTAssertTrue(h.model.openShowsReopen); XCTAssertEqual(h.model.openReopenTitle, "Folder · Side")
        h.model.reopenFolder()
        XCTAssertEqual(h.state.total, 4); XCTAssertEqual(h.state.out, 1, "the folder's decisions"); XCTAssertEqual(h.state.step, "cull")
        XCTAssertEqual(h.state.errors, 0)
    }

    func test_R1A_copyOnlyCountsUp_andResumesAfterARelaunch() throws {
        let store = MemoryPersistence()
        let h = Harness(copyRate: 30, store: store)
        XCTAssertEqual(h.model.openCardButton, "Copy & start culling"); XCTAssertNil(h.model.openCopyFraction)
        h.key("return")
        var seen: [Int] = []
        for _ in 0..<15 { h.wait(0.1); seen.append(h.state.copied) }
        XCTAssertEqual(seen, seen.sorted()); XCTAssertEqual(seen.last ?? 0, 46, accuracy: 2, "30 a second")
        XCTAssertEqual(h.model.openCardButton, "Copying… start culling")
        XCTAssertEqual(h.model.openCopyFraction ?? 0, Double(h.model.copied) / 117, accuracy: 0.001)
        // Pressing again, or anything else calling startCopy, never doubles the speed.
        h.model.startCopy(); h.model.startCopy(); h.wait(1)
        XCTAssertEqual(h.state.copied, (seen.last ?? 0) + 30, accuracy: 2)
        let c1 = h.state.copied, saved = try XCTUnwrap(store.load(shootKey: h.model.shoot.key)).copied
        XCTAssertGreaterThanOrEqual(saved, c1 - 15, "saved at least every 15 photos"); XCTAssertLessThanOrEqual(saved, c1)

        let h2 = Harness(copyRate: 30, store: store)
        XCTAssertEqual(h2.state.copied, saved); XCTAssertTrue(h2.model.copying, "the copy didn’t resume")
        seen = [h2.state.copied]
        for _ in 0..<40 { h2.wait(0.1); seen.append(h2.state.copied) }
        XCTAssertEqual(seen, seen.sorted(), "count went backwards"); XCTAssertEqual(seen.last, 117); XCTAssertFalse(h2.model.copying)
        XCTAssertEqual(h2.model.openCardButton, "Continue culling"); XCTAssertEqual(try XCTUnwrap(store.load(shootKey: h2.model.shoot.key)).copied, 117)
    }

    // MARK: Open

    func test_R31_startOverNeedsTwoClicks() async {
        let h = Harness()
        h.startCulling(); h.keepN(4); h.key("x"); h.go(1)
        XCTAssertEqual(h.model.openStartOverTitle, "Start over"); XCTAssertTrue(h.model.openShowsRecent)
        h.model.startOverClick()
        XCTAssertEqual(h.state.kept, 4, "one stray click wiped decisions")
        XCTAssertEqual(h.model.openStartOverTitle, "Click again to clear 5 decisions")
        h.wait(4.1)
        XCTAssertEqual(h.model.openStartOverTitle, "Start over", "still armed after 4 s"); XCTAssertEqual(h.state.kept, 4)
        h.model.startOverClick(); h.wait(3.9)
        XCTAssertEqual(h.model.openStartOverTitle, "Click again to clear 5 decisions")
        h.model.startOverClick()
        XCTAssertEqual(h.state.kept + h.state.out, 0); XCTAssertEqual(h.state.step, "open")
        XCTAssertEqual(h.state.copied, 0); XCTAssertFalse(h.model.openShowsRecent); XCTAssertEqual(h.model.openCardButton, "Copy & start culling")
        XCTAssertEqual(h.model.openStartOverTitle, "Start over")
        h.wait(5); XCTAssertEqual(h.state.copied, 0, "the old copy kept running")

        // An imported folder: the decisions go, the photos stay.
        await h.importAndWait(own(Fixtures.batch("Clear", 3)))
        h.key("r"); h.key("x"); h.go(1)
        h.model.startOverClick(); XCTAssertEqual(h.state.kept, 1)
        h.model.startOverClick()
        XCTAssertEqual(h.state.kept + h.state.out, 0); XCTAssertEqual(h.state.total, 3); XCTAssertTrue(h.model.openShowsRecent)
    }

    func test_openCopy_cardTile_recentRow_wording() async {
        let h = Harness()
        XCTAssertEqual(h.model.openCardName, "SD card · Untitled")
        XCTAssertEqual(h.model.openCardDetails, "ILCE-7M4 · 117 photos · 5 scenes · 09:12–19:14")
        XCTAssertFalse(h.model.openShowsRecent); XCTAssertFalse(h.model.openShowsReopen)
        h.startCulling(); h.keepN(6); h.go(1)
        XCTAssertEqual(h.model.openRecentTitle, "Today · Untitled"); XCTAssertEqual(h.model.openRecentDetails, "117 photos · 6 decided")
        XCTAssertEqual(h.model.openRecentAction, "Resume culling")
        h.model.resumeRecent(); XCTAssertEqual(h.state.step, "cull")
        XCTAssertEqual(AppModel.grouped(1000), "1,000"); XCTAssertEqual(AppModel.grouped(1234567), "1,234,567"); XCTAssertEqual(AppModel.grouped(999), "999")

        let g = Harness()
        await g.importAndWait(own(Fixtures.batch("Two", 2)))
        g.key("r"); g.key("x"); g.go(1)
        XCTAssertEqual(g.model.openCardDetails, "Folder · Two · 2 photos · 1 scenes · 09:00–09:00")
        XCTAssertEqual(g.model.openRecentTitle, "Today · Two"); XCTAssertEqual(g.model.openRecentAction, "Ready to save")
        g.model.resumeRecent(); XCTAssertEqual(g.state.step, "save")
    }

    // MARK: load

    func test_R85_bigFolder_exactCounts_keysStayQuickWhileChecking() async throws {
        let big = own(Fixtures.big(400)), h = Harness()
        h.startCulling()
        h.model.importURLs([big])
        var ms: [Double] = [], progress: [Int] = []
        while h.model.imports.busy {
            let t = Date()
            try await Task.sleep(nanoseconds: 2_000_000)                 // let the import's own main-thread work in
            h.model.handle(KeyEvent(ms.count % 2 == 0 ? "right" : "left"))
            ms.append(Date().timeIntervalSince(t) * 1000 - 2)
            if h.model.imports.busy { progress.append(h.model.imports.checked) }
            if ms.count > 20_000 { break }
        }
        await h.model.importsIdle()
        XCTAssertEqual(h.state.total, 400); XCTAssertEqual(h.model.imports.added, 400); XCTAssertEqual(h.message, "Added 400 photos from Big folder 400.")
        XCTAssertEqual(h.state.step, "cull", "R-17")
        XCTAssertEqual(h.model.shoot.scenes.count, 10); XCTAssertEqual(h.model.shoot.scenes.map(\.ids.count), Array(repeating: 40, count: 10))
        XCTAssertTrue(h.model.shoot.bursts.allSatisfy { (2...8).contains($0.ids.count) })
        XCTAssertEqual(Set(h.model.shoot.photos.map(\.id)).count, 400)
        XCTAssertEqual(progress, progress.sorted(), "the progress count went backwards")
        XCTAssertFalse(ms.isEmpty)
        let p95 = ms.sorted()[min(ms.count - 1, Int(Double(ms.count) * 0.95))]
        XCTAssertLessThan(p95, 150, "keys slow while checking (R-85)")
        XCTAssertEqual(h.state.errors, 0)
    }

    // MARK: grouping

    func test_grouper_burstsNeedTheSameShape_andIdsAreStable() {
        let t = Fixtures.day(10)
        let items = [ImportItem(rel: "S/1.jpg", shot: t, aspect: 1.5), ImportItem(rel: "S/2.jpg", shot: t.addingTimeInterval(1), aspect: 1.5),
                     ImportItem(rel: "S/3.jpg", shot: t.addingTimeInterval(2), aspect: 0.667), ImportItem(rel: "S/4.jpg", shot: t.addingTimeInterval(3), aspect: 0.667),
                     ImportItem(rel: "S/5.jpg", shot: t.addingTimeInterval(6), aspect: 0.667)]
        let s = SceneGrouper.group(items, name: "S"), again = SceneGrouper.group(items.reversed(), name: "S")
        XCTAssertEqual(s.bursts.map(\.ids.count), [2, 2]); XCTAssertNil(s.photos[4].burst)
        XCTAssertEqual(s.photos.map(\.id), again.photos.map(\.id), "order and ids don’t depend on the order files arrive in")
        XCTAssertEqual(s.bursts.map(\.id), again.bursts.map(\.id)); XCTAssertEqual(s.bursts[0].id, "g" + s.photos[0].id)
        XCTAssertTrue(s.local); XCTAssertEqual(s.scenes.count, 1); XCTAssertEqual(s.scenes[0].hm, "10:00"); XCTAssertEqual(s.span, "10:00–10:00")
        // No time at all: one scene, no header time, nothing invented.
        let bare = SceneGrouper.group([ImportItem(rel: "a.jpg"), ImportItem(rel: "b.jpg")], name: "Dropped photos")
        XCTAssertEqual(bare.scenes.count, 1); XCTAssertEqual(bare.scenes[0].hm, ""); XCTAssertEqual(bare.scenes[0].title, "Dropped photos")
        XCTAssertNil(bare.photos[0].time); XCTAssertNil(bare.span); XCTAssertTrue(bare.bursts.isEmpty)
        XCTAssertEqual(SceneGrouper.shutter(1.0 / 250), "1/250"); XCTAssertEqual(SceneGrouper.shutter(2.5), "2.5s"); XCTAssertEqual(SceneGrouper.shutter(30), "30s")
    }
}
