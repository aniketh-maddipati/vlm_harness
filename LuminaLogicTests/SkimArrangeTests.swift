import XCTest
@testable import Lumina

/// Arrange (`SkimArrange`, Export's workshop): clips move on one drive into the folders they were dragged onto, with their
/// Sony sidecars, never outside the folders Skim was let into, onto a refused place or over a file; each run is noted
/// before it moves anything, and Undo puts back only what is still where Skim put it, then removes the folders it made
/// if they are empty. Foundation only.
final class SkimArrangeTests: XCTestCase {
    private var tmp: URL!, root: URL!, log: URL!
    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("skim-arrange-\(UUID().uuidString)", isDirectory: true)
        root = tmp.appendingPathComponent("dump", isDirectory: true); log = tmp.appendingPathComponent("skim/arrange.json")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("CLIP"), withIntermediateDirectories: true)
        try Data(count: 10_000).write(to: root.appendingPathComponent("CLIP/C0001.MP4"))
        try Data(count: 300).write(to: root.appendingPathComponent("CLIP/C0001M01.XML"))
        try Data(count: 20_000).write(to: root.appendingPathComponent("CLIP/C0002.MP4"))
        try Data(count: 5).write(to: tmp.appendingPathComponent("outside.MP4"))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private var arrange: SkimArrange { SkimArrange(log: log) }
    private func p(_ rel: String) -> String { root.appendingPathComponent(rel).path }
    private func inside(_ path: String) -> Bool { SkimPlaces.inside(path, root: root) }
    private func has(_ rel: String) -> Bool { FileManager.default.fileExists(atPath: p(rel)) }
    private func apply(_ moves: [SkimArrange.Move], refuse: @escaping (String) -> String? = { _ in nil }) -> (run: String?, answers: [SkimArrange.Answer]) {
        arrange.apply(moves, shoot: "dump", allowed: inside, refuse: refuse)
    }

    func testAClipMovesWithItsSidecarAndUndoPutsThemBack() throws {
        let r = apply([.init(from: p("CLIP/C0001.MP4"), dir: p("Selected/Day 1")), .init(from: p("CLIP/C0002.MP4"), dir: p("Maybe"))])
        XCTAssertNotNil(r.run)
        XCTAssertEqual(r.answers.map(\.ok), [true, true])
        XCTAssertEqual(r.answers[0].to, p("Selected/Day 1/C0001.MP4"))
        XCTAssertTrue(has("Selected/Day 1/C0001.MP4") && has("Selected/Day 1/C0001M01.XML") && has("Maybe/C0002.MP4"))
        XCTAssertFalse(has("CLIP/C0001.MP4") || has("CLIP/C0001M01.XML"), "a move, not a copy")
        let run = try XCTUnwrap(arrange.runs().first)
        XCTAssertEqual(run.steps.filter(\.done).count, 3)
        XCTAssertEqual(run.made.map { ($0 as NSString).lastPathComponent }, ["Selected", "Day 1", "Maybe"], "the folders it made, outermost first")
        XCTAssertEqual(run.json["clips"] as? Int, 2)
        XCTAssertEqual(run.json["bytes"] as? Int64, 30_000)

        let back = arrange.undo(id: try XCTUnwrap(r.run))
        XCTAssertEqual(Set(back.map(\.from)), [p("CLIP/C0001.MP4"), p("CLIP/C0002.MP4")])
        XCTAssertTrue(back.allSatisfy(\.ok))
        XCTAssertTrue(has("CLIP/C0001.MP4") && has("CLIP/C0001M01.XML") && has("CLIP/C0002.MP4"))
        XCTAssertFalse(has("Selected") || has("Maybe"), "the folders it made were empty, so they went")
        XCTAssertEqual(arrange.runs().first?.undone, true)
        XCTAssertTrue(arrange.undo(id: r.run!).isEmpty, "a run undoes once")
    }

    func testRefusedMovesSayWhyAndMoveNothing() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Selected"), withIntermediateDirectories: true)
        try Data(count: 1).write(to: root.appendingPathComponent("Selected/C0002.MP4"))
        let r = apply([
            .init(from: tmp.appendingPathComponent("outside.MP4").path, dir: p("Selected")),   // not let in
            .init(from: p("CLIP/C0001.MP4"), dir: tmp.path),                                   // out of the folders let in
            .init(from: p("CLIP/C0002.MP4"), dir: p("Selected")),                              // a file of that name is there
            .init(from: p("CLIP/C0001.MP4"), dir: p("CLIP")),                                  // already there
            .init(from: p("CLIP/missing.MP4"), dir: p("Selected")),
            .init(from: p("CLIP/../CLIP/C0001.MP4"), dir: p("Selected")),
            .init(from: p("CLIP/C0001.MP4"), dir: p("CLIP/C0001.MP4/x")),                      // a file where a folder would be
        ])
        XCTAssertNil(r.run)
        XCTAssertTrue(r.answers.allSatisfy { !$0.ok && !$0.why.isEmpty })
        XCTAssertTrue(r.answers[2].why.contains("C0002.MP4"))
        XCTAssertTrue(has("CLIP/C0001.MP4") && has("CLIP/C0002.MP4") && has("Selected/C0002.MP4"))
        XCTAssertTrue(arrange.runs().isEmpty, "no run is kept when nothing moved")

        let card = apply([.init(from: p("CLIP/C0001.MP4"), dir: p("Selected"))], refuse: { _ in "on a camera card" })
        XCTAssertEqual(card.answers.first?.why, "on a camera card")
        XCTAssertTrue(has("CLIP/C0001.MP4"))
    }

    func testTwoClipsOfOneNameCannotLandInOneFolder() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("B"), withIntermediateDirectories: true)
        try Data(count: 7).write(to: root.appendingPathComponent("B/C0002.MP4"))
        let r = apply([.init(from: p("CLIP/C0002.MP4"), dir: p("Out")), .init(from: p("B/C0002.MP4"), dir: p("Out"))])
        XCTAssertEqual(r.answers.map(\.ok), [true, false])
        XCTAssertTrue(has("B/C0002.MP4"), "the second stays where it was")
    }

    func testUndoLeavesWhatChangedOrWhatTookItsPlace() throws {
        let r = apply([.init(from: p("CLIP/C0001.MP4"), dir: p("A")), .init(from: p("CLIP/C0002.MP4"), dir: p("A"))])
        try Data(count: 3).write(to: root.appendingPathComponent("A/C0002.MP4"))           // changed since
        try Data(count: 1).write(to: root.appendingPathComponent("CLIP/C0001.MP4"))        // something took its old place
        try Data(count: 1).write(to: root.appendingPathComponent("A/note.txt"))
        let back = arrange.undo(id: try XCTUnwrap(r.run))
        XCTAssertEqual(back.count, 2)
        XCTAssertTrue(back.allSatisfy { !$0.ok })
        XCTAssertTrue(has("A/C0001.MP4") && has("A/C0002.MP4") && has("A/note.txt"), "nothing guessed, nothing removed")
        XCTAssertEqual(arrange.runs().first?.undone, false, "still on the list to try again")
    }

    func testARunCutShortUndoesWhatDidMove() throws {
        // The note as it is written before anything moves; then only the clip moved (the app stopped).
        let to = p("A/C0002.MP4")
        let step = SkimArrange.Step(clip: p("CLIP/C0002.MP4"), from: p("CLIP/C0002.MP4"), to: to, bytes: SkimArrange.size(p("CLIP/C0002.MP4")), mtime: SkimArrange.mtime(p("CLIP/C0002.MP4")), done: false)
        let run = SkimArrange.Run(id: "r1", shoot: "dump", at: 0, steps: [step], made: [], undone: false)
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode([run]).write(to: log)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("A"), withIntermediateDirectories: true)
        try FileManager.default.moveItem(atPath: p("CLIP/C0002.MP4"), toPath: to)
        XCTAssertEqual(arrange.undo(id: "r1").map(\.ok), [true])
        XCTAssertTrue(has("CLIP/C0002.MP4"))
    }
}
