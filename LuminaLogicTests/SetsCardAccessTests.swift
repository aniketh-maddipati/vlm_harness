import XCTest
@testable import Lumina

/// The camera card in the App Sandbox (T10, R1c), without a sandbox: the watcher's "may I list
/// DCIM" answer, the volume's identity, start / stop and bookmarks are fakes. A card is a temp
/// folder with DCIM/100MSDCF and three ARWs. First insert with no grant: an unknown card, and
/// "Cull this card" asks the chooser at its DCIM; after the pick, a second insert (a new bridge,
/// as after a relaunch) inspects through the kept bookmark with no panel; a pick on another
/// volume is refused and asked again; removal lets go of the card's access.
@MainActor
final class SetsCardAccessTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!
    private var support: URL!
    private var volume: URL!
    private var active: [String: Int] = [:]
    private var log: [String] = []

    /// Records every card panel and answers from a queue (empty = Cancel).
    @MainActor final class Chooser: SetsChooser {
        var answers: [URL] = []
        var asked: [(name: String, at: URL, refusal: String?)] = []
        var sources = 0
        func chooseSource(allowsDirectories: Bool) async -> URL? { sources += 1; return nil }
        func chooseDestination(label: String, suggested: URL?, refusal: String?) async -> URL? { nil }
        func chooseCard(name: String, at: URL, refusal: String?) async -> URL? {
            asked.append((name, at, refusal))
            return answers.isEmpty ? nil : answers.removeFirst()
        }
    }

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("sets-card-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        support = root.appendingPathComponent("support", isDirectory: true)
        volume = root.appendingPathComponent("LTCARD", isDirectory: true)
        let dir = volume.appendingPathComponent("DCIM/100MSDCF", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        for i in 1...3 { try Data(repeating: 7, count: 1000).write(to: dir.appendingPathComponent(String(format: "DSC%05d.ARW", i))) }
        active = [:]; log = []
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    /// Fakes: a "bookmark" is the folder's path; start / stop counted per path.
    private func calls() -> SetsAccess.Calls {
        SetsAccess.Calls(
            start: { [unowned self] u in active[u.path, default: 0] += 1; log.append("start \(u.lastPathComponent)"); return true },
            stop: { [unowned self] u in active[u.path, default: 0] -= 1; if active[u.path] == 0 { active[u.path] = nil }; log.append("stop \(u.lastPathComponent)") },
            resolve: { data in (URL(fileURLWithPath: String(decoding: data, as: UTF8.self), isDirectory: true), false) },
            bookmark: { Data($0.path.utf8) },
            exists: { u in var d: ObjCBool = false; return FileManager.default.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue })
    }

    /// A bridge as the sandboxed app has it: DCIM refused to list, the volume's identity readable.
    /// `sandboxed: false` is the unsandboxed build: the real access check, which reads.
    private func bridge(_ chooser: Chooser, sandboxed: Bool = true) -> SetsBridge {
        let b = SetsBridge(chooser: chooser, supportDir: support, access: SetsAccess(calls: calls()))
        b.cards.identify = { _ in ("UUID-LTCARD", "LTCARD") }
        if sandboxed { b.cards.access = { _ in .refused } }
        return b
    }

    private func pageCard(_ b: SetsBridge) throws -> [String: Any] {
        let c = try XCTUnwrap(b.cards.current)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(b.cardJSON(c).utf8)) as? [String: Any])
    }

    func testFirstInsertIsUnknownAndCullAsksAtDCIM() async throws {
        let chooser = Chooser()
        let b = bridge(chooser)
        b.cards.mounted(volume)

        let card = try XCTUnwrap(b.cards.current)
        XCTAssertFalse(card.known)
        XCTAssertEqual(card.name, "LTCARD")
        let page = try pageCard(b)
        XCTAssertTrue(page["photos"] is NSNull, "the count is not known before the grant")
        XCTAssertTrue(page["sony"] is NSNull)
        XCTAssertEqual(page["known"] as? Bool, false)
        XCTAssertTrue(log.isEmpty, "nothing started without a grant")

        chooser.answers = [volume.appendingPathComponent("DCIM")]
        let opened = await b.cullCard()
        XCTAssertTrue(opened)
        XCTAssertEqual(chooser.asked.count, 1)
        XCTAssertEqual(chooser.asked.first?.at.path, volume.appendingPathComponent("DCIM").path)
        XCTAssertNil(chooser.asked.first?.refusal)

        let known = try XCTUnwrap(b.cards.current)
        XCTAssertTrue(known.known)
        XCTAssertEqual(known.grant, "panel")
        XCTAssertEqual(known.arwCount, 3)
        XCTAssertTrue(known.sony)
        XCTAssertEqual(try pageCard(b)["photos"] as? Int, 3)
        XCTAssertNotNil(SetsCardGrants(supportDir: support).bookmark("UUID-LTCARD"), "the pick is kept by volume UUID")
        XCTAssertTrue(log.isEmpty, "a panel's grant is the system's: nothing started here")

        // The card's DCIM is what opens, with no second panel.
        let urls = await b.openPanel(allowsDirectories: true)
        XCTAssertEqual(urls?.first.map(SetsIngest.plainPath), SetsIngest.plainPath(volume.appendingPathComponent("DCIM")))
        XCTAssertEqual(chooser.sources, 0)
    }

    func testSecondInsertAfterRelaunchNeedsNoPanel() async throws {
        let first = Chooser()
        let a = bridge(first)
        a.cards.mounted(volume)
        first.answers = [volume]                       // the card's root will do too
        let ok = await a.cullCard()
        XCTAssertTrue(ok)
        a.cards.unmounted(volume)

        // A relaunch: a new bridge, the same support folder, no panel grants.
        let second = Chooser()
        let b = bridge(second)
        b.cards.mounted(volume)
        let card = try XCTUnwrap(b.cards.current)
        XCTAssertTrue(card.known)
        XCTAssertEqual(card.grant, "bookmark")
        XCTAssertEqual(card.arwCount, 3)
        XCTAssertEqual(log, ["start LTCARD"], "the bookmark's access is started once")
        XCTAssertEqual(b.access.started, 1)

        let opened = await b.cullCard()
        XCTAssertTrue(opened)
        XCTAssertTrue(second.asked.isEmpty, "no panel the second time")
        XCTAssertEqual(second.sources, 0)
    }

    func testPickOnAnotherVolumeIsRefusedAndAskedAgain() async throws {
        let elsewhere = root.appendingPathComponent("OTHER/DCIM", isDirectory: true)
        try fm.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let chooser = Chooser()
        let b = bridge(chooser)
        b.cards.mounted(volume)
        chooser.answers = [elsewhere, volume.appendingPathComponent("DCIM/100MSDCF"), volume.appendingPathComponent("DCIM")]
        let opened = await b.cullCard()
        XCTAssertTrue(opened)
        XCTAssertEqual(chooser.asked.count, 3)
        XCTAssertNil(chooser.asked[0].refusal)
        XCTAssertEqual(chooser.asked[1].refusal, "That folder is not on the card LTCARD. Choose the card.")
        XCTAssertEqual(chooser.asked[2].refusal, "Choose the card LTCARD itself, or its DCIM folder.")
        XCTAssertTrue(b.cards.current?.known ?? false)
        XCTAssertEqual(SetsCardGrants(supportDir: support).bookmark("UUID-LTCARD").map { String(decoding: $0, as: UTF8.self) },
                       volume.appendingPathComponent("DCIM").path, "only the accepted pick is kept")
    }

    func testCancelledPanelLeavesTheCardUnknown() async throws {
        let chooser = Chooser()
        let b = bridge(chooser)
        b.cards.mounted(volume)
        let handled = await b.cullCard()
        XCTAssertTrue(handled, "a cancelled panel is the user's answer: the page does nothing more")
        XCTAssertFalse(b.cards.current?.known ?? true)
        XCTAssertNil(SetsCardGrants(supportDir: support).bookmark("UUID-LTCARD"))
    }

    func testRemovalReleasesTheCardsAccess() async throws {
        try SetsCardGrants(supportDir: support).save("UUID-LTCARD", bookmark: Data(volume.appendingPathComponent("DCIM").path.utf8), path: "")
        let b = bridge(Chooser())
        b.cards.mounted(volume)
        XCTAssertEqual(b.cards.current?.grant, "bookmark")
        XCTAssertEqual(active.count, 1)

        b.cards.unmounted(volume)
        XCTAssertNil(b.cards.current)
        XCTAssertTrue(active.isEmpty, "stopped when the card went")
        XCTAssertEqual(log, ["start DCIM", "stop DCIM"])
        XCTAssertEqual(b.access.started, 0)

        // Back in: started again, once.
        b.cards.mounted(volume)
        XCTAssertEqual(b.cards.current?.grant, "bookmark")
        XCTAssertEqual(log, ["start DCIM", "stop DCIM", "start DCIM"])
    }

    func testAShootOpenOnTheCardKeepsItsFolderOverAPull() async throws {
        try SetsCardGrants(supportDir: support).save("UUID-LTCARD", bookmark: Data(volume.appendingPathComponent("DCIM").path.utf8), path: "")
        let b = bridge(Chooser())
        b.cards.mounted(volume)
        let opened = await b.cullCard()
        XCTAssertTrue(opened)
        _ = await b.openPanel(allowsDirectories: true)          // the shoot now holds DCIM too
        b.cards.unmounted(volume)
        XCTAssertEqual(log, ["start DCIM"], "the open shoot still uses the folder: not stopped under it")
        b.closeShoot()
        XCTAssertEqual(log, ["start DCIM", "stop DCIM"])
    }

    func testARecentShootOpenedAtTheCardsDCIMIsAGrantToo() throws {
        let dcim = volume.appendingPathComponent("DCIM")
        let store = SetsShootStore(supportDir: support)
        // File ▸ Open on the card's DCIM earlier, and a shoot in one of its folders (not a grant for DCIM).
        try store.upsert(.init(id: "00000000000000a1", title: "100MSDCF", path: dcim.appendingPathComponent("100MSDCF").path, volumeUUID: "UUID-LTCARD",
                               photos: 3, firstCapture: "", opened: Date(), bookmark: Data(dcim.appendingPathComponent("100MSDCF").path.utf8)))
        try store.upsert(.init(id: "00000000000000a2", title: "DCIM", path: dcim.path, volumeUUID: "UUID-LTCARD",
                               photos: 3, firstCapture: "", opened: Date(), bookmark: Data(dcim.path.utf8)))
        let b = bridge(Chooser())
        b.cards.mounted(volume)
        XCTAssertEqual(b.cards.current?.grant, "recent")
        XCTAssertEqual(b.cards.current?.arwCount, 3)
        XCTAssertEqual(log, ["start DCIM"])
    }

    func testUnsandboxedInsertReadsAsBeforeWithNoPanel() async throws {
        let chooser = Chooser()
        let b = bridge(chooser, sandboxed: false)
        b.cards.mounted(volume)
        let card = try XCTUnwrap(b.cards.current)
        XCTAssertTrue(card.known)
        XCTAssertEqual(card.grant, "open")
        XCTAssertEqual(card.arwCount, 3)
        XCTAssertEqual(card.bytes, 3000)
        let opened = await b.cullCard()
        XCTAssertTrue(opened)
        XCTAssertTrue(chooser.asked.isEmpty)
        XCTAssertTrue(log.isEmpty)
        XCTAssertNil(SetsCardGrants(supportDir: support).bookmark("UUID-LTCARD"), "no grant is stored when none was needed")
    }

    func testAVolumeWithoutDCIMIsNotACard() throws {
        let b = bridge(Chooser(), sandboxed: false)
        let disk = root.appendingPathComponent("SSD", isDirectory: true)
        try fm.createDirectory(at: disk, withIntermediateDirectories: true)
        b.cards.mounted(disk)
        XCTAssertNil(b.cards.current)
    }

    func testAccessCheckTellsMissingFromReadable() {
        XCTAssertEqual(SetsCardWatcher.access(volume.appendingPathComponent("DCIM")), .readable)
        XCTAssertEqual(SetsCardWatcher.access(volume.appendingPathComponent("NOPE")), .missing)
    }
}
