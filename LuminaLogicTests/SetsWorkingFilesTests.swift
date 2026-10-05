import Foundation
import XCTest
@testable import Lumina

final class SetsWorkingFilesTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("sets-working-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: dir)
    }

    func testBytesSumsNestedRegularFilesWithoutFollowingOutsideSymlink() throws {
        try write(3, to: dir.appendingPathComponent("a.bin"))
        try write(7, to: dir.appendingPathComponent("nested/b.bin"))
        let outside = fm.temporaryDirectory.appendingPathComponent("sets-working-out-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: outside) }
        try write(101, to: outside)
        try fm.createSymbolicLink(at: dir.appendingPathComponent("nested/out"), withDestinationURL: outside)

        XCTAssertEqual(SetsWorkingFiles.bytes(of: dir), 10)
    }

    func testInventoryUsesKnownShootStoreLayoutOnly() throws {
        let shoot = dir.appendingPathComponent("shoot-a", isDirectory: true)
        try write(5, to: shoot.appendingPathComponent("session.json"))
        try write(8, to: shoot.appendingPathComponent("Lumina.json"))

        let items = SetsWorkingFiles.inventory(root: dir, current: "shoot-a", picks: [])
        XCTAssertEqual(items.count, 2)
        let session = try XCTUnwrap(items.first { $0.url.lastPathComponent == "session.json" })
        XCTAssertEqual(session.kind, .session)
        XCTAssertTrue(session.protected)
        XCTAssertEqual(items.first { $0.url.lastPathComponent == "Lumina.json" }?.kind, .other)
    }

    func testPlanUsesOtherShootsThenCurrentShootAndOldestWithinEach() {
        let now = Date()
        let otherNew = item("other-new.cache", bytes: 20, age: 10, shoot: "other", current: false)
        let currentOld = item("current-old.cache", bytes: 30, age: 100, shoot: "current", current: true)
        let otherOld = item("other-old.cache", bytes: 10, age: 20, shoot: "other", current: false)
        let currentNew = item("current-new.cache", bytes: 40, age: 5, shoot: "current", current: true)
        let pick = item("pick.cache", bytes: 50, age: 200, shoot: "current", current: true, protected: true)
        let session = SetsWorkingFiles.Item(
            url: dir.appendingPathComponent("current/session.json"),
            bytes: 5,
            modified: now.addingTimeInterval(-1_000),
            shoot: "current",
            kind: .session,
            protected: true,
            root: dir,
            isCurrent: true
        )
        let items = [currentNew, pick, otherNew, session, currentOld, otherOld]

        XCTAssertEqual(SetsWorkingFiles.plan(items: items, cap: 145).remove.map(\.url.lastPathComponent), ["other-old.cache"])
        XCTAssertEqual(SetsWorkingFiles.plan(items: items, cap: 125).remove.map(\.url.lastPathComponent), ["other-old.cache", "other-new.cache"])
        XCTAssertEqual(SetsWorkingFiles.plan(items: items, cap: 95).remove.map(\.url.lastPathComponent), ["other-old.cache", "other-new.cache", "current-old.cache"])
    }

    func testNoLimitAndAlreadyUnderCapRemoveNothing() {
        let preview = item("one.cache", bytes: 10, age: 1, shoot: "other", current: false)
        XCTAssertTrue(SetsWorkingFiles.plan(items: [preview], cap: nil).remove.isEmpty)
        XCTAssertTrue(SetsWorkingFiles.plan(items: [preview], cap: 10).remove.isEmpty)
    }

    func testProtectedPickAndSessionNeverEnterPlanAndCapCanRemainUnmet() {
        let pick = item("pick.cache", bytes: 100, age: 100, shoot: "current", current: true, protected: true)
        let session = SetsWorkingFiles.Item(
            url: dir.appendingPathComponent("current/session.json"),
            bytes: 10,
            modified: .distantPast,
            shoot: "current",
            kind: .session,
            protected: true,
            root: dir,
            isCurrent: true
        )

        let plan = SetsWorkingFiles.plan(items: [pick, session], cap: 0)
        XCTAssertTrue(plan.remove.isEmpty)
        XCTAssertEqual(plan.after, 110)
        XCTAssertFalse(plan.metCap)
    }

    func testRemoveAllKeepingSessionLeavesExactlySessionAndReportsFreedBytes() throws {
        try write(3, to: dir.appendingPathComponent("session.json"))
        try write(5, to: dir.appendingPathComponent("Lumina.json"))
        try write(7, to: dir.appendingPathComponent("cache/a.bin"))

        XCTAssertEqual(try SetsWorkingFiles.removeAll(shootDir: dir, keepSession: true), 12)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: dir.path), ["session.json"])
        XCTAssertEqual(SetsWorkingFiles.bytes(of: dir), 3)
    }

    func testRemoveAllRefusesDangerousFilesAndOutsideLinksWithoutDeletingAnything() throws {
        let cases = ["x.ARW", "x.xmp", "x.xmp.lumina-bak", "outside-link"]
        for name in cases {
            let shoot = dir.appendingPathComponent(name.replacingOccurrences(of: ".", with: "-"), isDirectory: true)
            try write(4, to: shoot.appendingPathComponent("safe.bin"))
            let dangerous = shoot.appendingPathComponent(name)
            var outside: URL?
            if name == "outside-link" {
                outside = fm.temporaryDirectory.appendingPathComponent("sets-working-link-\(UUID().uuidString)")
                try write(9, to: try XCTUnwrap(outside))
                try fm.createSymbolicLink(at: dangerous, withDestinationURL: try XCTUnwrap(outside))
            } else {
                try write(6, to: dangerous)
            }

            XCTAssertThrowsError(try SetsWorkingFiles.removeAll(shootDir: shoot, keepSession: false), name)
            XCTAssertTrue(fm.fileExists(atPath: shoot.appendingPathComponent("safe.bin").path), name)
            XCTAssertTrue(fm.fileExists(atPath: dangerous.path), name)
            if let outside { try? fm.removeItem(at: outside) }
        }
    }

    func testApplyPreflightsWholePlanBeforeDeleting() throws {
        let safeURL = dir.appendingPathComponent("safe.cache")
        let rawURL = dir.appendingPathComponent("photo.dng")
        try write(4, to: safeURL)
        try write(7, to: rawURL)
        let safe = SetsWorkingFiles.Item(
            url: safeURL, bytes: 4, modified: .distantPast, shoot: "s", kind: .preview,
            protected: false, root: dir, isCurrent: false
        )
        let raw = SetsWorkingFiles.Item(
            url: rawURL, bytes: 7, modified: .distantPast, shoot: "s", kind: .preview,
            protected: false, root: dir, isCurrent: false
        )

        XCTAssertThrowsError(try SetsWorkingFiles.apply(.init(remove: [safe, raw], after: 0, metCap: true)))
        XCTAssertTrue(fm.fileExists(atPath: safeURL.path))
        XCTAssertTrue(fm.fileExists(atPath: rawURL.path))
    }

    private func item(
        _ name: String,
        bytes: Int64,
        age: TimeInterval,
        shoot: String,
        current: Bool,
        protected: Bool = false
    ) -> SetsWorkingFiles.Item {
        SetsWorkingFiles.Item(
            url: dir.appendingPathComponent("\(shoot)/\(name)"),
            bytes: bytes,
            modified: Date().addingTimeInterval(-age),
            shoot: shoot,
            kind: .preview,
            protected: protected,
            root: dir,
            isCurrent: current
        )
    }

    private func write(_ count: Int, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x61, count: count).write(to: url)
    }
}
