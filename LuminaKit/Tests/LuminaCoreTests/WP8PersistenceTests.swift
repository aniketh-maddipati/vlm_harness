import XCTest
@testable import LuminaCore

// WP-8. Persistence, two windows and faults, headless: a `Harness` on a store in a temp
// directory; a second `Harness` on a new store object over the same directory is a relaunch
// (nothing is flushed first: the app may have been killed), and a second `Harness` on the same
// store object is a second window. Nothing is written outside the temp directory.

@MainActor
final class WP8PersistenceTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("lumina-wp8-\(UUID().uuidString)", isDirectory: true)
    }
    override func tearDown() async throws {
        Faults.shared.clearAll()
        try? FileManager.default.removeItem(at: dir)
    }

    private func store() -> FilePersistence { FilePersistence(directory: dir) }
    private func launch(card: String = "demo117", copyRate: Int = 66, _ s: (any PersistenceStore)? = nil) -> Harness {
        Harness(card: card, copyRate: copyRate, store: s ?? store())
    }
    private func files() -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() }
    private func onDisk(_ key: String = "card-demo-117") throws -> Snapshot? { try store().load(shootKey: key) }

    // MARK: R-70

    func test_R70_relaunchOnEveryStep_comesBackTheSame() throws {
        var h = launch(); h.startCulling(); h.keepN(6)
        h.go(3, settle: 1.1); h.key("."); h.key("."); h.key("right"); h.key("]"); h.key("."); h.wait(0.3)
        let keep = h.state.keep, looks = h.model.edits.looks
        XCTAssertEqual(keep.count, 6); XCTAssertEqual(looks.count, 2, "harness: two photos edited")
        for n in [2, 3, 4, 1] {
            h.go(n, settle: n == 3 ? 0.9 : 0.4)
            let want = h.state, editCur = h.model.editCur, cullCur = h.model.cullCur
            h = launch()
            XCTAssertEqual(h.state.step, want.step, "relaunched on \(want.step), came back on \(h.state.step)")
            XCTAssertEqual(h.state.keep, keep, "decisions changed after relaunching on \(want.step)")
            XCTAssertEqual(h.model.edits.looks, looks, "edits changed after relaunching on \(want.step)")
            XCTAssertEqual(h.state.cur, want.cur, "current photo on \(want.step)")
            XCTAssertEqual(h.model.cullCur, cullCur, "Cull's photo on \(want.step)")
            XCTAssertEqual(h.model.editCur, editCur, "Edit's photo on \(want.step)")
            XCTAssertEqual(h.state.copied, 117); XCTAssertFalse(h.model.copying)
            XCTAssertEqual(h.state.look, want.look)
        }
        XCTAssertEqual(h.state.errors, 0, "R-73")
    }

    func test_R70_movingInCullIsSaved_andEditsTagsDoneSaveOptions() throws {
        var h = launch(); h.startCulling(); h.keepN(4)
        h.key("right"); h.key("right"); h.key("down"); h.wait(0.3)          // parity fix 1: moving saves
        let cur = h.state.cur
        h = launch()
        XCTAssertEqual(h.state.step, "cull"); XCTAssertEqual(h.state.cur, cur, "Cull came back on the last decided photo, not the one on screen")

        h.go(3, settle: 1.1); h.key("."); h.key("return"); h.go(4)
        h.model.setFormat(.jpeg); h.model.setWithEdits(false); h.wait(2); h.model.saveNow(); h.wait(0.3)
        let saved = try XCTUnwrap(h.state.saved), tags = h.model.edits.tags, done = h.model.edits.done
        XCTAssertFalse(tags.isEmpty); XCTAssertFalse(done.isEmpty)
        h = launch()
        XCTAssertEqual(h.state.saved, saved); XCTAssertEqual(h.model.save.saved?.at, try onDisk()?.saved?.at)
        XCTAssertEqual(h.model.save.fmt, .jpeg); XCTAssertFalse(h.model.save.withEdits)
        XCTAssertEqual(h.model.edits.tags, tags); XCTAssertEqual(h.model.edits.done, done)
        // Arriving on Save by relaunch is arriving: a ⏎ still held doesn't save again (R-33).
        h.model.setFormat(.folder); h.key("return", settle: 0.1)
        XCTAssertEqual(h.state.saved?.fmt, "jpeg")
    }

    // MARK: R-07

    func test_R07_editThenLeaveWithin50ms_isSaved() throws {
        var h = launch(); h.startCulling(); h.keepN(4); h.go(3, settle: 1.2)
        let before = h.state.look
        for _ in 0..<3 { h.key(".", settle: 0.015) }
        let after = h.state.look
        XCTAssertNotEqual(after, before, "harness: nudge did nothing")
        h.key("cmd+2", settle: 0)                                            // killed right here: no flush, no time passes
        h = launch(); h.go(3, settle: 1.2)
        XCTAssertEqual(h.state.look, after, "R-07 edit made just before ⌘2 was lost")
    }

    func test_flushPersistence_writesWhatTheTimerStillHolds() throws {
        let h = launch(); h.startCulling(); h.keepN(4); h.go(3, settle: 1.2)
        h.key(".", settle: 0); h.key(".", settle: 0); h.key(".", settle: 0)  // the first is written, the rest wait for the timer
        XCTAssertNotEqual(try onDisk()?.looks, h.model.edits.looks, "harness: nothing was waiting")
        h.model.flushPersistence()
        XCTAssertEqual(try onDisk()?.looks, h.model.edits.looks)
        let n = h.model.persistence.writes
        AppModel.flushAllPersistence(); h.model.flushPersistence()
        XCTAssertEqual(h.model.persistence.writes, n, "a flush with nothing new wrote again")
    }

    // MARK: R-1A

    func test_R1A_relaunchMidCopy_resumesWithin15_andOnlyCountsUp() throws {
        var h = launch(copyRate: 30); h.key("return"); h.wait(1.63)
        let c1 = h.state.copied
        XCTAssertTrue((20..<100).contains(c1), "harness: \(c1) copied")
        h = launch(copyRate: 30)
        var seen = [h.state.copied]
        XCTAssertGreaterThanOrEqual(seen[0], c1 - 15, "resumed far behind (saved every 15)")
        XCTAssertLessThanOrEqual(seen[0], c1)
        XCTAssertEqual(h.state.step, "cull")
        for _ in 0..<80 { h.wait(0.1); seen.append(h.state.copied) }
        XCTAssertEqual(seen, seen.sorted(), "count went backwards")
        XCTAssertEqual(seen.last, 117, "copy never finished after relaunch")
        XCTAssertFalse(h.model.copying)
        XCTAssertEqual(try onDisk()?.copied, 117)
    }

    func test_R1A_killedBeforeTheFirst15_copyStillResumes() throws {
        var h = launch(copyRate: 30); h.key("return"); h.wait(0.2)
        XCTAssertLessThan(h.state.copied, 15)
        h = launch(copyRate: 30)
        XCTAssertEqual(h.state.step, "cull")
        h.wait(6)
        XCTAssertEqual(h.state.copied, 117, "relaunched on Cull with nothing copied and no copy running")
    }

    func test_R1A_storedCountNeverPullsTheCopyBack() throws {
        let s = store()
        try s.save(Snapshot(shootKey: "card-demo-117", step: .cull, copied: 400, photoCount: 117))
        let h = launch(s)
        XCTAssertEqual(h.state.copied, 117, "a stored count beyond the card")
    }

    // MARK: R-71

    func test_R71_storageFull_warns_keepsWorking_recovers() throws {
        let h = launch(); h.startCulling(); h.keepN(4); h.go(3, settle: 1.0)
        let saved = h.model.edits.looks
        Faults.shared.inject(.storageFull)
        h.key("."); h.key("."); h.wait(0.7)
        XCTAssertEqual(h.model.edit.warning, AppModel.storageWarning)
        XCTAssertEqual(h.state.look["ev"] ?? 0, 0.1, accuracy: 0.001, "stopped working in memory")
        XCTAssertEqual(try onDisk()?.looks, saved, "something was written on a full disk")
        h.key("right"); h.key("."); h.go(2); h.key("r"); h.wait(0.5)        // keeps working, keeps warning
        XCTAssertEqual(h.model.edit.warning, AppModel.storageWarning)
        XCTAssertEqual(h.state.kept, 5)
        XCTAssertEqual(h.state.errors, 0, "a full disk is not an unexpected error (R-73)")

        Faults.shared.clear(.storageFull)
        h.key("r"); h.wait(0.5)                                              // retried on the next change
        XCTAssertNil(h.model.edit.warning, "warning stayed after a write succeeded")
        XCTAssertEqual(try onDisk()?.keep, h.state.keep)
        XCTAssertEqual(try onDisk()?.looks, h.model.edits.looks)
        XCTAssertEqual(launch().state.kept, 6)
    }

    func test_R71_recoversWithoutAnotherChange_andAtQuit() throws {
        var h = launch(); h.startCulling(); h.keepN(3)
        Faults.shared.inject(.storageFull)
        h.key("r"); h.wait(0.5)
        XCTAssertEqual(h.model.edit.warning, AppModel.storageWarning)
        Faults.shared.clear(.storageFull)
        h.wait(PersistenceState.retryInterval + 0.1)                         // nothing changes; the retry lands
        XCTAssertNil(h.model.edit.warning)
        XCTAssertEqual(try onDisk()?.keep.count, 4)

        Faults.shared.inject(.storageFull); h.key("r"); h.wait(0.3); Faults.shared.clear(.storageFull)
        h.model.flushPersistence()                                           // quitting after the disk has room again
        XCTAssertNil(h.model.edit.warning)
        h = launch(); XCTAssertEqual(h.state.kept, 5)
    }

    func test_R71_realDiskFullIsStorageFull_otherWriteErrorsAreReportedOnce() throws {
        for code in [ENOSPC, EDQUOT] {
            guard case PersistenceError.storageFull = FilePersistence.posix(code) else { return XCTFail("errno \(code) is not storageFull") }
        }
        let s = store(), h = launch(s); h.startCulling()
        s.writeHook = { stage, _ in if stage == .tempWritten { throw FilePersistence.posix(ENOSPC) } }
        h.key("r"); h.wait(0.5)
        XCTAssertEqual(h.model.edit.warning, AppModel.storageWarning); XCTAssertEqual(h.state.errors, 0)
        s.writeHook = { stage, _ in if stage == .tempWritten { throw FilePersistence.posix(EIO) } }
        h.key("r"); h.key("r"); h.wait(0.5)
        XCTAssertEqual(h.model.edit.warning, AppModel.storageWarning, "a write that fails for another reason still isn't saved")
        XCTAssertEqual(h.state.errors, 1, "reported through ErrorFunnel, once")
        s.writeHook = nil
        h.key("r"); h.wait(0.5)
        XCTAssertNil(h.model.edit.warning); XCTAssertEqual(try onDisk()?.keep.count, 4)
    }

    // MARK: R-72

    func test_R72_twoWindows_editInOneWarnsTheOther() throws {
        let s = store()
        let w1 = launch(s); w1.startCulling(); w1.keepN(4); w1.go(3, settle: 1.1)
        let w2 = Harness(store: s)                                           // {"openSecondWindow":true}
        XCTAssertEqual(w2.state.step, "edit"); XCTAssertEqual(w2.state.kept, 4)
        XCTAssertNil(w1.model.edit.warning, "opening a second window is not a change")
        XCTAssertNil(w2.model.edit.warning)

        w1.key("."); w1.key("."); w1.wait(0.9)
        XCTAssertEqual(w2.model.edit.warning, AppModel.otherWindowWarning)
        XCTAssertNil(w1.model.edit.warning, "a window warned about its own write")
        XCTAssertEqual(w2.state.look, [:], "the second window keeps its own state (the prototype: no reload)")

        w2.key("right"); w2.key("]"); w2.key("."); w2.wait(0.5)             // the last change made wins
        XCTAssertEqual(w1.model.edit.warning, AppModel.otherWindowWarning)
        XCTAssertEqual(try onDisk()?.looks, w2.model.edits.looks)
        XCTAssertEqual(w2.state.errors, 0)
    }

    func test_R72_sameDirectoryIsOneStore_otherShootsDontWarn() throws {
        var config = LaunchConfig(); config.storeDir = dir
        let a = makePersistence(config: config), b = makePersistence(config: config)
        XCTAssertTrue(a === b, "two windows must share one store per directory")
        XCTAssertTrue(a is FilePersistence)
        XCTAssertTrue(makePersistence(config: LaunchConfig()) is MemoryPersistence, "a test process must never get the user's real store")
        XCTAssertTrue(FilePersistence.defaultDirectory.path.hasSuffix("Application Support/Lumina/native"))

        let w1 = launch(a); w1.startCulling()
        let w2 = Harness(card: "demo:200", store: a); w2.startCulling(); w2.key("r"); w2.wait(0.5)
        XCTAssertNil(w1.model.edit.warning, "another shoot changed, not this one")
    }

    func test_offlineFault_showsTheOfflineLine_underTheOthers() throws {
        let s = store(), h = launch(s); h.startCulling(); h.keepN(2)
        Faults.shared.inject(.offline)
        h.key("r"); h.wait(0.3)
        XCTAssertEqual(h.model.edit.warning, AppModel.offlineWarning)
        XCTAssertEqual(try onDisk()?.keep.count, 3, "offline still saves on this computer")
        Faults.shared.inject(.storageFull); h.key("r"); h.wait(0.3)
        XCTAssertEqual(h.model.edit.warning, AppModel.storageWarning)
        Faults.shared.clearAll(); h.key("r"); h.wait(0.3)
        XCTAssertNil(h.model.edit.warning)
    }

    // MARK: corrupt files

    func test_corruptFile_reportedOnce_treatedAsEmpty_neverDeleted() throws {
        var h = launch(); h.startCulling(); h.keepN(5); h.wait(0.3)
        let file = store().url(for: "card-demo-117")
        let good = try Data(contentsOf: file)
        for (i, bad) in [Data("{\"v\":1,\"snapshot\":{\"shootKey\":".utf8), good.prefix(good.count / 2), Data([0xff, 0x00, 0x13]), Data()].enumerated() {
            try bad.write(to: file)
            try? FileManager.default.removeItem(atPath: file.path + ".corrupt")
            let s = store()
            h = launch(s)
            XCTAssertEqual(h.state.step, "open", "case \(i)"); XCTAssertEqual(h.state.kept, 0, "case \(i)"); XCTAssertEqual(h.state.copied, 0)
            XCTAssertEqual(h.state.errors, 1, "case \(i): reported through ErrorFunnel")
            XCTAssertNil(try s.load(shootKey: "card-demo-117")); XCTAssertNil(try s.loadLast())
            XCTAssertEqual(ErrorFunnel.count, 1, "case \(i): reported once")
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: file.path + ".corrupt")), bad, "case \(i): the unreadable file is set aside, not lost")
            h.startCulling(); h.keepN(2); h.wait(0.3)                        // and the app works from there
            XCTAssertEqual(try onDisk()?.keep.count, 2, "case \(i)")
        }
    }

    func test_corruptLastPointer_fallsBackToTheNewestShoot() throws {
        let s = store()
        try s.save(Snapshot(shootKey: "folder-A", folderName: "A", photoCount: 3))
        try s.save(Snapshot(shootKey: "folder-B", folderName: "B", photoCount: 4))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: s.url(for: "folder-A").path)
        try Data("nope".utf8).write(to: s.lastURL)
        ErrorFunnel.reset()
        XCTAssertEqual(try store().loadLast()?.shootKey, "folder-B")
        XCTAssertEqual(ErrorFunnel.count, 1)
        XCTAssertNil(try store().loadLast(), "the damaged pointer was set aside; no pointer means no last shoot")
        XCTAssertTrue(files().contains("last.json.corrupt"))
    }

    // MARK: atomic writes, and only inside the directory

    func test_atomicity_aFailedWriteLeavesTheOldFileAndNoTempFile() throws {
        let s = store()
        let a = Snapshot(shootKey: "k", step: .cull, keep: ["a": true], photoCount: 1)
        try s.save(a)
        var temp: Data?
        s.writeHook = { stage, url in
            if stage == .tempWritten { temp = try Data(contentsOf: url); throw NSError(domain: NSPOSIXErrorDomain, code: Int(EIO)) }
        }
        var b = a; b.keep = ["a": false, "b": true]; b.step = .save
        XCTAssertThrowsError(try s.save(b))
        XCTAssertNotNil(temp, "harness: the write never got as far as the temp file")
        XCTAssertEqual(try store().load(shootKey: "k"), a, "the old file must be whole")
        XCTAssertEqual(files().filter { $0.hasPrefix(".tmp-") }, [], "temp file left behind")
        s.writeHook = nil
        try s.save(b)
        XCTAssertEqual(try store().load(shootKey: "k"), b)

        // A write killed half-way leaves a temp file; it is never read, and the next write clears it.
        try Data("{\"v\":1,\"snap".utf8).write(to: dir.appendingPathComponent(".tmp-killed"))
        let s2 = store()
        XCTAssertEqual(try s2.load(shootKey: "k"), b)
        try s2.save(a)
        XCTAssertEqual(files().filter { $0.hasPrefix(".tmp-") }, [])
    }

    func test_storeWritesOnlyItsOwnFiles_andOddKeysWork() throws {
        // The store two levels down in a directory nobody else uses: whatever it creates must be inside its own.
        let own = dir.appendingPathComponent("a/store", isDirectory: true)
        func fresh() -> FilePersistence { FilePersistence(directory: own) }
        func list(_ u: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: u.path)) ?? []).sorted() }
        let s = fresh()
        _ = try s.load(shootKey: "x"); _ = try s.loadLast()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path), "nothing is created before the first write")
        let keys = ["card-demo-117", "folder-🌅 sunset ✨", "folder-" + String(repeating: "x", count: 220), "folder-../../etc", "folder-a/b", "folder-a_b", ""]
        for (i, k) in keys.enumerated() { try s.save(Snapshot(shootKey: k, copied: i)) }
        for (i, k) in keys.enumerated() { XCTAssertEqual(try fresh().load(shootKey: k)?.copied, i, k) }
        XCTAssertEqual(try fresh().loadLast()?.shootKey, "")
        XCTAssertEqual(list(own).count, keys.count + 1)
        XCTAssertTrue(list(own).allSatisfy { $0 == "last.json" || ($0.hasPrefix("shoot-") && $0.hasSuffix(".json")) }, "\(list(own))")
        XCTAssertTrue(list(own).allSatisfy { $0.utf8.count < 100 })
        try s.clear(shootKey: ""); try s.clear(shootKey: "folder-a/b")
        XCTAssertNil(try fresh().load(shootKey: "folder-a/b")); XCTAssertNil(try fresh().loadLast())
        XCTAssertEqual(try fresh().load(shootKey: "folder-a_b")?.copied, 5)
        XCTAssertEqual(list(own).count, keys.count - 2)
        XCTAssertEqual(list(dir), ["a"], "wrote outside its directory"); XCTAssertEqual(list(dir.appendingPathComponent("a")), ["store"], "wrote next to its directory")
    }

    // MARK: coalescing

    func test_coalescing_manyFastChangesAreFewWrites_lastStateOnDisk() throws {
        let s = store(), h = launch(s); h.startCulling()
        var w0 = s.writeCount
        for i in 0..<1000 { h.model.perform(i % 2 == 0 ? .keep : .cullMove(-1)); h.wait(0.001) }    // 1,000 changes in one second
        XCTAssertLessThanOrEqual(s.writeCount - w0, 6, "\(s.writeCount - w0) writes for a second of changes")
        XCTAssertGreaterThanOrEqual(s.writeCount - w0, 3, "writes must keep coming while changes do, not wait for them to stop")
        h.wait(0.3)
        XCTAssertEqual(try onDisk()?.keep, h.state.keep, "the last change never reached the disk")
        XCTAssertEqual(try onDisk()?.cur, h.model.cullCur)

        w0 = s.writeCount                                                    // no time passes at all
        for _ in 0..<500 { h.model.perform(.cullMove(1)); h.model.perform(.out) }
        XCTAssertLessThanOrEqual(s.writeCount - w0, 1)
        h.model.flushPersistence()
        XCTAssertLessThanOrEqual(s.writeCount - w0, 2)
        XCTAssertEqual(try onDisk()?.keep, h.state.keep)

        h.keepN(3); h.go(3, settle: 1.1); h.wait(0.5); w0 = s.writeCount     // a two-second slider drag at 200 Hz
        for i in 0..<400 { h.model.setValue("ev", Double(i % 100) / 20, coalesce: true); h.wait(0.005) }
        XCTAssertLessThanOrEqual(s.writeCount - w0, 10, "\(s.writeCount - w0) writes for a 2 s drag")
        h.wait(0.3)
        XCTAssertEqual(try onDisk()?.looks, h.model.edits.looks)
    }

    func test_shootSwappedRightAfterAChange_theOldShootKeepsIt() throws {
        let s = store(), h = launch(s); h.startCulling()
        h.key("r", settle: 0); h.key("r", settle: 0)                         // the second is still waiting for the timer
        let folder = Self.folder("Holiday", 5)
        h.model.setShoot(folder); h.model.changed()
        XCTAssertEqual(try onDisk()?.keep.count, 2, "the card's last decision was dropped when the shoot changed")
        XCTAssertEqual(try onDisk("folder-Holiday")?.photoCount, 5)
    }

    // MARK: R-84, R-86

    func test_R84_relaunchAt5000Photos_with1000Decisions() throws {
        var h = launch(card: "demo:5000", copyRate: 400); h.startCulling()
        let total = h.state.total
        XCTAssertGreaterThanOrEqual(total, 4990)
        for i in 0..<1000 { h.key(i % 2 == 0 ? "r" : "x", settle: 0.01) }
        h.go(3, settle: 1.1)
        for i in 0..<300 { h.model.setValue("ev", Double(i % 40) / 20 + 0.05); h.model.setValue("con", Double(i % 30) + 1); h.key("right", settle: 0.01) }
        h.wait(0.3)
        let keep = h.state.keep, looks = h.model.edits.looks, cur = h.state.cur
        XCTAssertEqual(keep.count, 1000); XCTAssertGreaterThan(looks.count, 100)   // kept burst frames share one edit
        let key = h.model.shoot.key, file = store().url(for: key)
        let bytes = try Data(contentsOf: file).count

        var best = Double.infinity, read = Double.infinity
        for _ in 0..<3 {
            let s = store(), t0 = Date()
            _ = try s.loadWithExtras(shootKey: key)
            read = min(read, Date().timeIntervalSince(t0))
            let t1 = Date()
            h = launch(card: "demo:5000", copyRate: 400)                     // the shoot, the store, restore
            best = min(best, Date().timeIntervalSince(t1))
        }
        XCTAssertEqual(h.state.step, "edit"); XCTAssertEqual(h.state.keep, keep); XCTAssertEqual(h.model.edits.looks, looks)
        XCTAssertEqual(h.state.cur, cur); XCTAssertEqual(h.state.copied, total)
        print(String(format: "R-84 (WP-8 share, debug build): read + decode %.1f ms, launch + restore %.1f ms, file %d KB, %d photos", read * 1000, best * 1000, bytes / 1024, total))
        XCTAssertLessThan(best, 1.0, "relaunch to a restored model took \(best) s of the 4 s budget (R-84)")

        let t = Date(); h.key("r"); let first = Date().timeIntervalSince(t)   // a keypress with its write, at 5,000
        XCTAssertLessThan(first, 0.1, "a decision with its write took \(first) s (R-80)")

        // The worst case: every photo decided.
        h.model.decisions.mark(h.model.shoot.photos.map(\.id), keep: true); h.model.changed(); h.wait(0.3)
        let tw = Date(); h.model.perform(.cullMove(1)); h.model.flushPersistence(); let write = Date().timeIntervalSince(tw)
        let tr = Date(); h = launch(card: "demo:5000", copyRate: 400); let relaunch = Date().timeIntervalSince(tr)
        XCTAssertEqual(h.state.kept, total)
        print(String(format: "R-84 all %d decided: encode + atomic write %.1f ms, launch + restore %.1f ms, file %d KB", total, write * 1000, relaunch * 1000, (try Data(contentsOf: file).count) / 1024))
        XCTAssertLessThan(relaunch, 1.0); XCTAssertLessThan(write, 0.1)
    }

    func test_R86_storedEditsFor300PhotosUnder2MB() throws {
        var looks: [String: Look] = [:]
        for i in 0..<300 {
            var l: Look = [:]
            for (j, s) in EditSetting.all.enumerated() { l[s.key] = s.clamp(s.min + (s.max - s.min) * Double((i * 7 + j * 13) % 97 + 1) / 99) }
            for k in CropKey.all { l[k] = Double(i % 17) / 16.3 }
            looks["DSC\(10000 + i)"] = l
        }
        let s = store()
        try s.save(Snapshot(shootKey: "big", step: .edit, copied: 5000, keep: Dictionary(uniqueKeysWithValues: (0..<5000).map { ("DSC\(10000 + $0)", $0 % 3 != 0) }),
                            looks: looks, tags: looks.mapValues { _ in "Edited" }, done: Array(looks.keys), photoCount: 5000))
        let bytes = try Data(contentsOf: s.url(for: "big")).count
        print("R-86: 300 photos with every setting edited + 5,000 decisions = \(bytes / 1024) KB on disk")
        XCTAssertLessThan(bytes, 2_000_000)
        XCTAssertEqual(try store().load(shootKey: "big")?.looks, looks, "values must come back exactly")
    }

    // MARK: versions and migration

    func test_fileFormat_isVersioned() throws {
        let s = store(); try s.save(Snapshot(shootKey: "k", copied: 3), extras: SnapshotExtras(editCur: "p1"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: s.url(for: "k"))) as? [String: Any])
        XCTAssertEqual(obj["v"] as? Int, 1); XCTAssertEqual(SnapshotFile.version, 1)
        XCTAssertNotNil(obj["snapshot"] as? [String: Any])
        XCTAssertEqual(try store().loadWithExtras(shootKey: "k")?.extras.editCur, "p1")
        try s.save(Snapshot(shootKey: "k", copied: 4))                       // the plain protocol call keeps the extras
        XCTAssertEqual(try store().loadWithExtras(shootKey: "k")?.extras.editCur, "p1")
    }

    func test_migration_version0FileIsReadWithoutLosingAnything() throws {
        // Version 0: no "v", the fields at the top level, some missing, `done` as the prototype's {key: true}.
        let v0 = """
        {"shootKey":"card-demo-117","step":"edit","cur":"DSC03263","copied":117,"keep":{"DSC03260":true,"DSC03261":false,"DSC03262":true},
         "looks":{"DSC03260":{"ev":0.35,"wb":5600}},"tags":{"DSC03260":"Edited"},"done":{"DSC03260":true,"DSC03262":false},"editCur":"DSC03260"}
        """
        let f = try SnapshotFile.decode(Data(v0.utf8))
        XCTAssertEqual(f.v, 1); XCTAssertEqual(f.snapshot.step, .edit); XCTAssertEqual(f.snapshot.keep.count, 3)
        XCTAssertEqual(f.snapshot.looks["DSC03260"], ["ev": 0.35, "wb": 5600]); XCTAssertEqual(f.snapshot.done, ["DSC03260"])
        XCTAssertEqual(f.snapshot.fmt, .xmp); XCTAssertTrue(f.snapshot.withEdits); XCTAssertEqual(f.extras?.editCur, "DSC03260")
        XCTAssertNotNil(SnapshotFile.migrations[0]); XCTAssertNil(SnapshotFile.migrations[SnapshotFile.version], "a migration for the current version")

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(v0.utf8).write(to: store().url(for: "card-demo-117"))
        let h = launch()
        XCTAssertEqual(h.state.errors, 0)
        XCTAssertEqual(h.state.step, "edit"); XCTAssertEqual(h.state.kept, 2); XCTAssertEqual(h.state.out, 1)
        XCTAssertEqual(h.state.cur, "DSC03260"); XCTAssertEqual(h.state.look["ev"], 0.35); XCTAssertEqual(h.model.cullCur, "DSC03263")
        h.key("."); h.wait(0.3)                                              // the next write is the current version
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store().url(for: "card-demo-117"))) as? [String: Any])
        XCTAssertEqual(obj["v"] as? Int, 1)
        XCTAssertEqual(try onDisk()?.keep.count, 3)

        // A version-0 file with only a key from its name, and one with nothing usable.
        XCTAssertEqual(try SnapshotFile.decode(Data("{\"keep\":{\"a\":true}}".utf8), shootKey: "k").snapshot.keep, ["a": true])
        XCTAssertThrowsError(try SnapshotFile.decode(Data("{\"keep\":{\"a\":true}}".utf8)))
        XCTAssertThrowsError(try SnapshotFile.decode(Data("[1,2]".utf8), shootKey: "k"))
    }

    func test_newerVersionFile_isReadAndACopyKeptBeforeItIsWrittenOver() throws {
        let s = store(); try s.save(Snapshot(shootKey: "card-demo-117", step: .cull, copied: 117, keep: ["DSC03260": true], photoCount: 117))
        let file = s.url(for: "card-demo-117")
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        obj["v"] = 7; obj["fromTheFuture"] = ["x": 1]
        let newer = try JSONSerialization.data(withJSONObject: obj)
        try newer.write(to: file)
        let h = launch()
        XCTAssertEqual(h.state.kept, 1); XCTAssertEqual(h.state.errors, 0)
        h.key("r"); h.wait(0.3)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: file.path + ".v7.bak")), newer)
    }

    func test_setsSession_decisionsAndPlaceMapByPath() throws {
        let shoot = Self.folder("Wedding", 4)
        let session = """
        {"v":2,"cur":"Wedding-2.jpg","saved":null,"marks":{"Wedding-0.jpg":"keep","Wedding-1.jpg":"out","gone.ARW":"keep"},
         "flags":{},"stars":{},"cuts":{},"look":{"Wedding-0.jpg":"ev:+0.70 wb:5200/+3"},"seen":{}}
        """
        let snap = try XCTUnwrap(SetsSessionMigration.snapshot(fromSession: Data(session.utf8), shoot: shoot))
        XCTAssertEqual(snap.keep, ["L0": true, "L1": false]); XCTAssertEqual(snap.cur, "L2"); XCTAssertEqual(snap.shootKey, shoot.key)
        XCTAssertTrue(snap.looks.isEmpty, "Sets look strings are not guessed into this UI's values")
        XCTAssertNil(SetsSessionMigration.snapshot(fromSession: Data("{}".utf8), shoot: shoot))
    }

    // MARK: R-19

    private static func folder(_ name: String, _ n: Int) -> Shoot {
        let photos = (0..<n).map { Photo(id: "L\($0)", file: "\(name)-\($0).jpg", source: .demo(seed: $0, bw: false), rel: "\(name)-\($0).jpg", size: 100) }
        return Shoot(photos: photos, scenes: [PhotoScene(id: "r0", index: 0, hm: "", ids: photos.map(\.id))], name: name, local: true, key: "folder-\(name)")
    }

    func test_R19_relaunch_offersTheFolder_reopeningRestoresDecisions() throws {
        let place = dir.appendingPathComponent("photos/Holiday", isDirectory: true)   // stands in for the user's folder
        try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
        let storeDir = dir.appendingPathComponent("store", isDirectory: true)
        let folder = Self.folder("Holiday", 5)

        var h = Harness(card: "none", store: FilePersistence(directory: storeDir))
        XCTAssertNil(h.model.folderToReopen); XCTAssertNil(h.model.open.reopenName)
        h.model.setShoot(folder); h.model.rememberFolder(place); h.model.go(.cull)   // what WP-2's import does
        h.key("r", settle: 0.15); h.key("r", settle: 0.3)
        XCTAssertEqual(h.state.kept, 2)
        let cur = h.state.cur

        h = Harness(card: "none", store: FilePersistence(directory: storeDir))        // relaunch: nothing on screen yet
        XCTAssertEqual(h.state.total, 0)
        XCTAssertEqual(h.model.open.reopenName, "Holiday"); XCTAssertEqual(h.model.open.reopenCount, 5)
        let offer = try XCTUnwrap(h.model.folderToReopen)
        XCTAssertEqual(offer.shootKey, "folder-Holiday"); XCTAssertEqual(offer.photoCount, 5)
        XCTAssertEqual(offer.path, place.path); XCTAssertNotNil(offer.bookmark, "no bookmark stored")
        XCTAssertEqual(h.model.resolveFolderToReopen()?.resolvingSymlinksInPath().path, place.resolvingSymlinksInPath().path)
        XCTAssertEqual(h.model.savedSnapshot(shootKey: "folder-Holiday")?.keep.count, 2)

        XCTAssertTrue(h.model.setShootRestoring(folder, restoreStep: true))           // WP-2 reopened it
        XCTAssertEqual(h.state.kept, 2); XCTAssertEqual(h.state.step, "cull"); XCTAssertEqual(h.state.cur, cur)
        XCTAssertNil(h.model.open.reopenName); XCTAssertNil(h.model.folderToReopen)
        h.key("r", settle: 0.3)

        h = Harness(card: "demo117", store: FilePersistence(directory: storeDir))     // with a card in: still offered
        XCTAssertEqual(h.model.open.reopenName, "Holiday")
        XCTAssertEqual(h.model.folderToReopen?.path, place.path, "the bookmark was lost by the second session")
        XCTAssertEqual(h.model.savedSnapshot(shootKey: "folder-Holiday")?.keep.count, 3)
        XCTAssertEqual(h.state.kept, 0, "the folder's decisions leaked onto the card")

        try FileManager.default.removeItem(at: place)                                 // the folder is gone: offer, don't reopen
        h = Harness(card: "none", store: FilePersistence(directory: storeDir))
        XCTAssertNil(h.model.resolveFolderToReopen()); XCTAssertEqual(h.model.open.reopenName, "Holiday")
        XCTAssertFalse(h.model.setShootRestoring(Self.folder("Other", 2)), "a folder never seen has nothing to restore")
        XCTAssertEqual(h.state.total, 2); XCTAssertEqual(h.state.errors, 0)
    }

    func test_setShootRestoring_midSession_staysOnItsStep_andDropsIdsTheShootLost() throws {
        let s = store()
        var snap = Snapshot(shootKey: "folder-Trip", step: .save, cur: "L1", keep: ["L0": true, "L1": false, "L9": true], looks: ["L0": ["ev": 0.5], "L9": ["ev": 1]],
                            tags: ["L0": "Edited", "L9": "Edited"], done: ["L0", "L9"], fmt: .jpeg, folderName: "Trip", photoCount: 10)
        snap.saved = SavedRecord(sig: "x", n: 1, ne: 1, fmt: .jpeg, at: Date(timeIntervalSince1970: 1_790_000_000.25), again: false)
        try s.save(snap, extras: SnapshotExtras(editCur: "L0"))
        let h = launch(s); h.startCulling()
        XCTAssertTrue(h.model.setShootRestoring(Self.folder("Trip", 3)))              // a drop while on Cull (R-17)
        XCTAssertEqual(h.state.step, "cull"); XCTAssertEqual(h.state.kept, 1); XCTAssertEqual(h.state.out, 1)
        XCTAssertEqual(h.model.edits.looks, ["L0": ["ev": 0.5]]); XCTAssertEqual(h.model.edits.done, ["L0"])
        XCTAssertEqual(h.model.cullCur, "L1"); XCTAssertEqual(h.model.editCur, "L0")
        XCTAssertEqual(h.model.save.fmt, .jpeg); XCTAssertEqual(h.model.save.saved, snap.saved)
        XCTAssertEqual(h.state.copied, 3)
    }

    // MARK: the real clock: writes leave the main thread

    func test_liveClock_writesInTheBackground_flushIsSynchronous_fullDiskStillWarns() throws {
        let s = store()
        var config = LaunchConfig(arguments: [], environment: ["LUMINA_CARD": "demo117", "LUMINA_COPY_RATE": "2000"])
        config.storeDir = dir
        Faults.shared.clearAll(); ErrorFunnel.reset()
        let m = AppModel.launch(config: config, services: Services(images: DefaultImageProvider(), exporter: RecordingExporter(), persistence: s), clock: LiveScheduler())
        XCTAssertTrue(m.persistence.background)
        func pump(_ timeout: TimeInterval = 5, until done: () -> Bool) -> Bool {
            let end = Date().addingTimeInterval(timeout)
            while !done(), Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            return done()
        }
        m.startCulling()
        XCTAssertTrue(pump { m.copied == 117 && !m.copying })
        for _ in 0..<40 { m.perform(.keep) }                                 // one burst: a write at once, the rest coalesced
        XCTAssertTrue(pump { (try? self.onDisk()?.keep.count) == 40 }, "the last change never reached the disk")
        XCTAssertTrue(pump { m.persistence.inFlight == 0 })
        XCTAssertLessThanOrEqual(m.persistence.writes, 14, "\(m.persistence.writes) writes")

        for _ in 0..<5 { m.perform(.out) }
        m.flushPersistence()                                                 // quit: on disk before it returns
        XCTAssertEqual(try onDisk()?.keep.count, 45)

        Faults.shared.inject(.storageFull)
        m.perform(.keep)
        XCTAssertTrue(pump { m.edit.warning == AppModel.storageWarning })
        Faults.shared.clear(.storageFull)
        XCTAssertTrue(pump(1) { m.persistence.inFlight == 0 })
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        m.perform(.keep)
        XCTAssertTrue(pump { m.edit.warning == nil })
        XCTAssertTrue(pump { (try? self.onDisk()?.keep.count) == 47 })
        XCTAssertEqual(ErrorFunnel.count, 0)
        m.flushPersistence()
    }
}
