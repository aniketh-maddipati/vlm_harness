import XCTest
@testable import Lumina

/// The handoff's acceptance fixtures (`design/handoff/lumina-cull/lumina-core.fixtures.json`),
/// asserted against the Swift port exactly as `lumina-core.test.mjs` asserts them against the JS.
final class CullCoreFixtureTests: XCTestCase {

    static let handoff = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("design/handoff/lumina-cull")

    private func fixtures() throws -> [String: Any] {
        let data = try Data(contentsOf: Self.handoff.appendingPathComponent("lumina-core.fixtures.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func input(_ p: [String: Any]) -> CullCoreShoot.Input {
        CullCoreShoot.Input(
            name: p["name"] as? String ?? "", path: p["path"] as? String ?? "", date: p["date"] as? String,
            exposure: (p["exp"] as? NSNumber)?.doubleValue, focalLength: (p["fl"] as? NSNumber)?.doubleValue,
            exposureBias: (p["ev"] as? NSNumber)?.doubleValue,
            luminance: (p["lum"] as? NSNumber)?.doubleValue ?? 0, focus: (p["focus"] as? NSNumber)?.doubleValue ?? 0,
            clip: (p["clip"] as? NSNumber)?.doubleValue ?? 0
        )
    }

    func testBuildShootMatchesPrototype() throws {
        let fx = try XCTUnwrap(try fixtures()["buildShoot"] as? [String: Any])
        let list = try XCTUnwrap(fx["input"] as? [[String: Any]]).map(Self.input)
        let expect = try XCTUnwrap(fx["expect"] as? [String: Any])
        let shoot = CullCoreShoot.build(list)

        let rows = try XCTUnwrap(expect["rows"] as? [[String: Any]])
        XCTAssertEqual(shoot.moments.count, rows.count)
        for (moment, row) in zip(shoot.moments, rows) {
            XCTAssertEqual(moment.time, row["time"] as? String)
            let groups = try XCTUnwrap(row["groups"] as? [[String: Any]])
            XCTAssertEqual(moment.groups.count, groups.count, moment.time)
            for (gid, want) in zip(moment.groups, groups) {
                let group = try XCTUnwrap(shoot.group(gid))
                XCTAssertEqual(group.kind.rawValue, want["kind"] as? String, gid)
                XCTAssertEqual(group.frames.map { shoot.photos[$0].input.name }, want["files"] as? [String], gid)
            }
        }

        let flags = try XCTUnwrap(expect["flags"] as? [[String: Any]])
        XCTAssertEqual(shoot.photos.count, flags.count)
        for (photo, want) in zip(shoot.photos, flags) {
            XCTAssertEqual(photo.input.name, want["file"] as? String)
            XCTAssertEqual(photo.soft, want["soft"] as? Bool, photo.input.name)
            XCTAssertEqual(photo.blown, want["blown"] as? Bool, photo.input.name)
            XCTAssertEqual(photo.shake, want["shake"] as? Bool, photo.input.name)
            XCTAssertEqual(photo.rank, want["rank"] as? Int, photo.input.name)
        }

        XCTAssertEqual(shoot.suggestedKeeps.compactMap { shoot.photo($0)?.input.name }, expect["keep"] as? [String])
    }

    func testMergeXmpKeepsLightroomEdits() throws {
        for c in try XCTUnwrap(try fixtures()["mergeXmp"] as? [[String: Any]]) {
            let got = CullCoreXMP.merge(try XCTUnwrap(c["src"] as? String), rating: try XCTUnwrap(c["rating"] as? Int),
                                        label: c["label"] as? String)
            XCTAssertEqual(got, c["expect"] as? String)
        }
    }

    func testFreshXmpMatchesPrototype() throws {
        for c in try XCTUnwrap(try fixtures()["freshXmp"] as? [[String: Any]]) {
            let dev = (c["dev"] as? [String: Any]).map { d in
                CullCoreXMP.Develop(
                    exposure: (d["Exposure"] as? NSNumber)?.doubleValue, contrast: (d["Contrast"] as? NSNumber)?.doubleValue,
                    highlights: (d["Highlights"] as? NSNumber)?.doubleValue, shadows: (d["Shadows"] as? NSNumber)?.doubleValue,
                    temperature: (d["Temp"] as? NSNumber)?.doubleValue
                )
            }
            let got = CullCoreXMP.fresh(rating: try XCTUnwrap(c["rating"] as? Int), label: c["label"] as? String, develop: dev)
            XCTAssertEqual(got, c["expect"] as? String)
        }
    }

    func testHasDevelopMatchesPrototype() throws {
        for c in try XCTUnwrap(try fixtures()["hasDevelop"] as? [[String: Any]]) {
            XCTAssertEqual(CullCoreXMP.hasDevelop(c["src"] as? String), c["expect"] as? Bool)
        }
    }

    func testExportPlanMatchesPrototype() throws {
        for c in try XCTUnwrap(try fixtures()["exportPlan"] as? [[String: Any]]) {
            let target = try XCTUnwrap(CullCoreExportPlan.Target(rawValue: try XCTUnwrap(c["target"] as? String)))
            let items = try XCTUnwrap(c["items"] as? [[String: Any]]).map {
                CullCoreExportPlan.Item(file: $0["file"] as? String ?? "", xmp: $0["xmp"] as? String ?? "", rel: $0["rel"] as? String)
            }
            let got = CullCoreExportPlan.plan(target, shoot: try XCTUnwrap(c["shoot"] as? String), items: items)
            let want = try XCTUnwrap(c["expect"] as? [[String: Any]])
            XCTAssertEqual(got.map(\.path), want.map { $0["path"] as? String ?? "" })
            XCTAssertEqual(got.map(\.kind.rawValue), want.map { $0["kind"] as? String ?? "" })
        }
    }

    func testCRC32MatchesPrototype() throws {
        let c = try XCTUnwrap(try fixtures()["crc32"] as? [String: Any])
        XCTAssertEqual(CullCoreArchive.crc32(Array((try XCTUnwrap(c["input"] as? String)).utf8)),
                       (c["expect"] as? NSNumber)?.uint32Value)
    }
}
