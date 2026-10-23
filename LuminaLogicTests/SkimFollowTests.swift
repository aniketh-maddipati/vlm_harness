import XCTest
@testable import Lumina

/// Skim's Follow and the matte for Final Cut, the maths (`SkimFollow`): which shape in a frame is the one followed,
/// what the page may send, and which followed frames each matte frame is made from.
final class SkimFollowTests: XCTestCase {
    typealias Box = LookMasks.Box
    typealias P = LookMasks.Point

    private func shape(_ id: String, _ kind: LookMasks.Kind, _ b: Box) -> LookMasks.Found {
        LookMasks.Found(id: id, kind: kind, score: 1, box: b, area: b.w * b.h,
                        outline: [[P(x: b.x, y: b.y), P(x: b.x + b.w, y: b.y), P(x: b.x + b.w, y: b.y + b.h), P(x: b.x, y: b.y + b.h)]])
    }

    func testTheWindowIsAroundTheBoxAndInsideTheFrame() throws {
        // three times the box, around its centre
        let w = try XCTUnwrap(SkimFollow.window(around: Box(x: 0.4, y: 0.4, w: 0.1, h: 0.1)))
        XCTAssertEqual(w.w, 0.3, accuracy: 1e-9); XCTAssertEqual(w.x, 0.3, accuracy: 1e-9); XCTAssertEqual(w.y, 0.3, accuracy: 1e-9)
        // a small box still gets the smallest window; one at the corner is moved inside the frame
        let c = try XCTUnwrap(SkimFollow.window(around: Box(x: 0.97, y: 0, w: 0.02, h: 0.02)))
        XCTAssertEqual(c.w, SkimFollow.windowMin, accuracy: 1e-9)
        XCTAssertEqual(c.x + c.w, 1, accuracy: 1e-9); XCTAssertEqual(c.y, 0, accuracy: 1e-9)
        // a big shape is looked at in the whole frame; so is an empty box
        XCTAssertNil(SkimFollow.window(around: Box(x: 0.2, y: 0.2, w: 0.4, h: 0.5)))
        XCTAssertNil(SkimFollow.window(around: Box(x: 0.2, y: 0.2, w: 0, h: 0.5)))
    }

    func testAShapeFoundInTheWindowIsPlacedInTheFrame() {
        let win = Box(x: 0.5, y: 0.25, w: 0.4, h: 0.5)
        let f = SkimFollow.placed(shape("person-1", .person, Box(x: 0.25, y: 0.5, w: 0.5, h: 0.5)), in: win)
        XCTAssertEqual(f.box.x, 0.6, accuracy: 1e-9); XCTAssertEqual(f.box.y, 0.5, accuracy: 1e-9)
        XCTAssertEqual(f.box.w, 0.2, accuracy: 1e-9); XCTAssertEqual(f.box.h, 0.25, accuracy: 1e-9)
        XCTAssertEqual(f.area, 0.25 * 0.2, accuracy: 1e-9)
        XCTAssertEqual(f.outline[0][2].x, 0.8, accuracy: 1e-9); XCTAssertEqual(f.outline[0][2].y, 0.75, accuracy: 1e-9)
    }

    func testAShapeCutByTheWindowMeansTheWholeFrame() {
        let win = Box(x: 0.3, y: 0, w: 0.4, h: 0.4)
        XCTAssertFalse(SkimFollow.cut(Box(x: 0.4, y: 0.1, w: 0.1, h: 0.1), by: win))
        XCTAssertTrue(SkimFollow.cut(Box(x: 0.3, y: 0.1, w: 0.1, h: 0.1), by: win))     // the window's left edge
        XCTAssertTrue(SkimFollow.cut(Box(x: 0.4, y: 0.1, w: 0.1, h: 0.3), by: win))     // its bottom edge
        XCTAssertFalse(SkimFollow.cut(Box(x: 0.4, y: 0, w: 0.1, h: 0.1), by: win))      // the frame's own top edge
    }

    func testOverlap() {
        let a = Box(x: 0, y: 0, w: 0.5, h: 0.5)
        XCTAssertEqual(SkimFollow.iou(a, a), 1, accuracy: 1e-9)
        XCTAssertEqual(SkimFollow.iou(a, Box(x: 0.5, y: 0.5, w: 0.5, h: 0.5)), 0)
        XCTAssertEqual(SkimFollow.iou(a, Box(x: 0.25, y: 0, w: 0.5, h: 0.5)), 1.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(SkimFollow.iou(Box(x: 0, y: 0, w: 0, h: 0), Box(x: 0, y: 0, w: 0, h: 0)), 0)
    }

    func testTheShapeOnTheBoxIsTheOneFollowed() {
        let found = [shape("person-1", .person, Box(x: 0.1, y: 0.1, w: 0.2, h: 0.5)),
                     shape("person-2", .person, Box(x: 0.6, y: 0.1, w: 0.2, h: 0.5)),
                     shape("sky", .sky, Box(x: 0, y: 0, w: 1, h: 0.3)),
                     shape("background", .background, Box(x: 0, y: 0, w: 1, h: 1))]
        // the box has moved a little since the last frame: still person 2
        XCTAssertEqual(SkimFollow.match(kind: .person, box: Box(x: 0.62, y: 0.12, w: 0.2, h: 0.5), in: found)?.id, "person-2")
        // nothing under the box: not in this frame (the background, which covers it, is never the person)
        XCTAssertNil(SkimFollow.match(kind: .person, box: Box(x: 0.4, y: 0.7, w: 0.1, h: 0.1), in: found))
        XCTAssertNil(SkimFollow.match(kind: .person, box: nil, in: found))
        // the sky and the background are the frame's own, wherever the box is
        XCTAssertEqual(SkimFollow.match(kind: .sky, box: nil, in: found)?.id, "sky")
        XCTAssertEqual(SkimFollow.match(kind: .background, box: Box(x: 0, y: 0, w: 0.1, h: 0.1), in: found)?.id, "background")
        XCTAssertNil(SkimFollow.match(kind: .sky, box: nil, in: Array(found.prefix(2))))
    }

    func testBarelyTouchingIsNotTheShape() {
        let found = [shape("object-1", .object, Box(x: 0, y: 0, w: 0.2, h: 0.2))]
        XCTAssertNil(SkimFollow.match(kind: .object, box: Box(x: 0.15, y: 0.15, w: 0.2, h: 0.2), in: found))
        XCTAssertEqual(SkimFollow.match(kind: .object, box: Box(x: 0.05, y: 0.05, w: 0.2, h: 0.2), in: found)?.id, "object-1")
    }

    func testFlipGoesBothWays() {
        let b = Box(x: 0.1, y: 0.2, w: 0.3, h: 0.4), f = SkimFollow.flipped(b)
        XCTAssertEqual(f.y, 0.4, accuracy: 1e-9)
        XCTAssertEqual(SkimFollow.flipped(f).y, b.y, accuracy: 1e-12)
    }

    func testStartTakesOnlyAKindAndABox() {
        XCTAssertEqual(SkimFollow.start(kind: "person", box: [0.1, 0.2, 0.3, 0.4])?.box, Box(x: 0.1, y: 0.2, w: 0.3, h: 0.4))
        XCTAssertNil(SkimFollow.start(kind: "person", box: [0.1, 0.2, 0.3]))
        XCTAssertNil(SkimFollow.start(kind: "face", box: [0.1, 0.2, 0.3, 0.4]))
        XCTAssertNil(SkimFollow.start(kind: 42, box: [0.1, 0.2, 0.3, 0.4]))
        XCTAssertNil(SkimFollow.start(kind: "person", box: [Double.nan, 0, 1, 1]))
        XCTAssertNil(SkimFollow.start(kind: "person", box: [0.5, 0.5, 0, 0.2]))
        XCTAssertNil(SkimFollow.start(kind: "person", box: ["a", 0, 1, 1]))
        // out of the frame is cut to the frame
        XCTAssertEqual(SkimFollow.start(kind: "object", box: [-0.5, 0.5, 2, 2])?.box, Box(x: 0, y: 0.5, w: 1, h: 0.5))
    }

    func testStepAnswer() {
        let s = SkimFollow.Step(box: Box(x: 0.123456, y: 0, w: 0.5, h: 0.5), held: true, shape: nil)
        XCTAssertEqual(s.json["held"] as? Bool, true)
        XCTAssertEqual((s.json["box"] as? [Double])?.first, 0.1235)
        XCTAssertTrue(s.json["shape"] is NSNull)
        XCTAssertTrue(SkimFollow.Step(box: nil, held: false, shape: nil).json["box"] is NSNull)
    }

    func testMatteSize() {
        XCTAssertEqual(SkimFollow.matteSize(width: 3840, height: 2160).map { [$0.width, $0.height] }, [1920, 1080])
        XCTAssertEqual(SkimFollow.matteSize(width: 1280, height: 720).map { [$0.width, $0.height] }, [1280, 720])
        XCTAssertEqual(SkimFollow.matteSize(width: 2160, height: 3840).map { [$0.width, $0.height] }, [1080, 1920])
        XCTAssertEqual(SkimFollow.matteSize(width: 4096, height: 2161).map { [$0.width % 2, $0.height % 2] }, [0, 0])
        XCTAssertNil(SkimFollow.matteSize(width: 0, height: 1080))
        XCTAssertNil(SkimFollow.matteSize(width: 100_000, height: 1080))
    }

    func testSamplesAreReadInTimeOrder() throws {
        let s = try XCTUnwrap(SkimFollow.samples([
            ["t": 1.0, "outline": [[[0, 0], [1, 0], [1, 1]]]],
            ["t": 0.5, "outline": [] as [Any]],
            ["t": 0.75, "outline": [[[0, 0], [1, 0]], [[0, 0], [1, "x"], [1, 1]], [[0, 0], [0.5, 0], [0.5, 0.5]]]],
        ]))
        XCTAssertEqual(s.map(\.t), [0.5, 0.75, 1.0])
        XCTAssertEqual(s[0].outline.count, 0)
        XCTAssertEqual(s[1].outline.count, 1, "a loop of two points and one with a bad point are left out")
        XCTAssertNil(SkimFollow.samples([] as [Any]))
        XCTAssertNil(SkimFollow.samples([["t": -1, "outline": [] as [Any]]]))
        XCTAssertNil(SkimFollow.samples([["t": Double.infinity]]))
        XCTAssertNil(SkimFollow.samples("samples"))
        XCTAssertNil(SkimFollow.samples(Array(repeating: ["t": 0.0] as [String: Any], count: SkimFollow.maxSamples + 1)))
    }

    func testEachMatteFrameIsMadeFromTheFollowedFramesAroundIt() throws {
        let s = [0.0, 0.125, 0.25, 0.5].map { SkimFollow.Sample(t: $0, outline: []) }
        let a = try XCTUnwrap(SkimFollow.around(0.1875, in: s))
        XCTAssertEqual([a.before, a.after], [1, 2]); XCTAssertEqual(a.weight, 0.5, accuracy: 1e-9)
        let b = try XCTUnwrap(SkimFollow.around(0.3, in: s))
        XCTAssertEqual([b.before, b.after], [2, 3]); XCTAssertEqual(b.weight, 0.2, accuracy: 1e-9)
        XCTAssertEqual(SkimFollow.around(-1, in: s).map { [$0.before, $0.after] }, [0, 0])
        XCTAssertEqual(SkimFollow.around(9, in: s).map { [$0.before, $0.after] }, [3, 3])
        XCTAssertEqual(SkimFollow.around(0.125, in: s).map { $0.before == 1 || $0.after == 1 }, true)
        XCTAssertNil(SkimFollow.around(0, in: []))
    }

    func testFrameLength() {
        XCTAssertEqual(SkimFollow.frameLength([1001, 24000]).map { [$0.n, $0.d] }, [1001, 24000])
        XCTAssertEqual(SkimFollow.frameLength([100, 2500]).map { [$0.n, $0.d] }, [100, 2500])
        XCTAssertNil(SkimFollow.frameLength([0, 24000]))
        XCTAssertNil(SkimFollow.frameLength([1, 1000]), "1000 frames a second")
        XCTAssertNil(SkimFollow.frameLength([2, 1]), "half a frame a second")
        XCTAssertNil(SkimFollow.frameLength([1001]))
    }

    func testMatteName() {
        XCTAssertEqual(SkimFollow.matteName(clip: "C0042.MP4"), "C0042 matte.mov")
        XCTAssertEqual(SkimFollow.matteName(clip: "../../C0042.MP4"), "C0042 matte.mov")
        XCTAssertEqual(SkimFollow.matteName(clip: "a:b.mov"), "ab matte.mov")
        XCTAssertEqual(SkimFollow.matteName(clip: ""), "matte.mov")
        XCTAssertNil(SkimExport.safeName("C0042 matte.mov"), "the .fcpxml's own save still takes only its own kinds")
    }

    // MARK: The Mac's own track

    func testEveryFrameFollowedMeansNoMixing() throws {
        // 24 fps, every frame followed at its start: each matte frame is one outline alone
        let fl = (n: 1, d: 24), s = (0..<48).map { SkimFollow.Sample(t: Double($0) / 24, outline: []) }
        for k in [0, 1, 7, 23, 46] {
            let a = try XCTUnwrap(SkimFollow.matteFrame(k, frameLength: fl, in: s))
            XCTAssertEqual([a.before, a.after], [k, k], "frame \(k)"); XCTAssertEqual(a.weight, 0)
        }
        // past the last followed frame: that one
        XCTAssertEqual(SkimFollow.matteFrame(60, frameLength: fl, in: s).map { [$0.before, $0.after] }, [47, 47])
        // the page's eight a second are still mixed by time
        let sparse = [0.0, 0.125, 0.25].map { SkimFollow.Sample(t: $0, outline: []) }
        let b = try XCTUnwrap(SkimFollow.matteFrame(1, frameLength: fl, in: sparse))
        XCTAssertEqual([b.before, b.after], [0, 1]); XCTAssertEqual(b.weight, 1.5 / 24 / 0.125, accuracy: 1e-9)
        XCTAssertNil(SkimFollow.matteFrame(0, frameLength: fl, in: []))
    }

    func testProxySize() {
        XCTAssertEqual(SkimFollow.proxySize(width: 3840, height: 2160).map { [$0.width, $0.height] }, [720, 406])
        XCTAssertEqual(SkimFollow.proxySize(width: 640, height: 360).map { [$0.width, $0.height] }, [640, 360], "never larger than the clip")
        XCTAssertEqual(SkimFollow.proxySize(width: 2160, height: 3840).map { [$0.width, $0.height] }, [406, 720])
        XCTAssertNil(SkimFollow.proxySize(width: 0, height: 10))
    }

    func testGoingBackIsReadASecondAtATime() {
        let c = SkimFollow.backChunks(from: 2.5, chunk: 1)
        XCTAssertEqual(c.map(\.from), [1.5, 0.5, 0]); XCTAssertEqual(c.map(\.to), [2.5, 1.5, 0.5])
        XCTAssertTrue(SkimFollow.backChunks(from: 0, chunk: 1).isEmpty)
        XCTAssertTrue(SkimFollow.backChunks(from: .nan, chunk: 1).isEmpty)
        XCTAssertTrue(SkimFollow.backChunks(from: 3, chunk: 0).isEmpty)
    }

    func testSureness() {
        typealias F = SkimFollow
        XCTAssertEqual(F.sureness(tracker: 0.9, found: true, area: 0.1, last: 0.1, refound: false), .sure)
        XCTAssertEqual(F.sureness(tracker: nil, found: true, area: 0.3, last: 0.3, refound: false), .sure, "the sky has no tracker")
        XCTAssertEqual(F.sureness(tracker: 0.4, found: true, area: 0.1, last: 0.1, refound: false), .shaky, "the tracker unsure")
        XCTAssertEqual(F.sureness(tracker: 0.9, found: true, area: 0.2, last: 0.1, refound: false), .shaky, "the area doubled")
        XCTAssertEqual(F.sureness(tracker: 0.9, found: true, area: 0.05, last: 0.1, refound: false), .shaky, "the area halved")
        XCTAssertEqual(F.sureness(tracker: 0.9, found: true, area: 0.12, last: 0.1, refound: false), .sure)
        XCTAssertEqual(F.sureness(tracker: nil, found: true, area: 0.1, last: nil, refound: true), .shaky, "found again")
        XCTAssertEqual(F.sureness(tracker: 0.8, found: false, area: nil, last: 0.1, refound: false), .shaky, "only the tracker holds it")
        XCTAssertEqual(F.sureness(tracker: 0.1, found: false, area: nil, last: 0.1, refound: false), .lost)
        XCTAssertEqual(F.sureness(tracker: nil, found: false, area: nil, last: nil, refound: false), .lost)
    }

    func testTheStripJoinsEqualFrames() {
        let s = SkimFollow.strip([(0.0, .sure), (0.04, .sure), (0.12, .lost), (0.08, .shaky), (0.16, .lost), (0.2, .sure)])
        XCTAssertEqual(s, [.init(t0: 0, t1: 0.04, sure: .sure), .init(t0: 0.08, t1: 0.08, sure: .shaky),
                           .init(t0: 0.12, t1: 0.16, sure: .lost), .init(t0: 0.2, t1: 0.2, sure: .sure)])
        XCTAssertEqual(SkimFollow.strip([]), [])
        XCTAssertEqual(s[2].json["sure"] as? String, "lost")
    }

    func testALostShapeIsFoundAgainOnlyAsItsKindAndClose() {
        let c: [(id: String, kind: LookMasks.Kind, distance: Double)] = [("person-1", .person, 0.5), ("person-2", .person, 0.3),
                                                                         ("object-1", .object, 0.1), ("sky", .sky, 0)]
        XCTAssertEqual(SkimFollow.refound(.person, among: c), "person-2", "the nearest person, never the object nearer still")
        XCTAssertEqual(SkimFollow.refound(.object, among: c), "object-1")
        XCTAssertEqual(SkimFollow.refound(.subject, among: c), "object-1")
        XCTAssertNil(SkimFollow.refound(.person, among: [("person-1", .person, SkimFollow.refind + 0.01)]), "too far: someone else")
        XCTAssertNil(SkimFollow.refound(.person, among: [("person-1", .person, .nan)]))
        XCTAssertNil(SkimFollow.refound(.sky, among: c))
        XCTAssertTrue(SkimFollow.refindable(.person, as: .subject))
        XCTAssertFalse(SkimFollow.refindable(.person, as: .background))
    }

    func testTrackedFrameAnswer() {
        let shape = self.shape("person-1", .person, Box(x: 0.1, y: 0.2, w: 0.3, h: 0.4))
        let f = SkimFollow.Tracked(t: 1.234567, step: .init(box: shape.box, held: true, shape: shape), sure: .shaky)
        XCTAssertEqual(f.json["t"] as? Double, 1.2346)
        XCTAssertEqual(f.json["sure"] as? String, "shaky")
        XCTAssertEqual((f.json["outline"] as? [[[Double]]])?.first?.count, 4)
        XCTAssertNil(f.json["shape"])
        XCTAssertEqual(f.area ?? 0, 0.12, accuracy: 1e-9)
        XCTAssertTrue(SkimFollow.Tracked(t: 0, step: .init(box: nil, held: false, shape: nil), sure: .lost).json["outline"] is NSNull)
    }

    func testWhatThePageMaySendForATrack() {
        XCTAssertEqual(SkimFollow.trackID("C0001|1"), "C0001|1")
        XCTAssertNil(SkimFollow.trackID(""))
        XCTAssertNil(SkimFollow.trackID(String(repeating: "x", count: 65)))
        XCTAssertNil(SkimFollow.trackID(42))
        XCTAssertEqual(SkimFollow.time(2.5), 2.5)
        XCTAssertNil(SkimFollow.time(-1)); XCTAssertNil(SkimFollow.time(Double.nan)); XCTAssertNil(SkimFollow.time("2"))
    }

    func testAFixReTracksTheStretchBetweenTheSureOnes() {
        let strip: [SkimFollow.Run] = [.init(t0: 0, t1: 1, sure: .sure), .init(t0: 1.04, t1: 2, sure: .shaky), .init(t0: 2.04, t1: 2.5, sure: .lost),
                                       .init(t0: 2.54, t1: 4, sure: .sure), .init(t0: 4.04, t1: 5, sure: .shaky)]
        let a = SkimFollow.fixSpan(at: 1.5, strip: strip, length: 5)
        XCTAssertEqual(a.from, 1); XCTAssertEqual(a.to, 2.54)
        let b = SkimFollow.fixSpan(at: 4.5, strip: strip, length: 5)
        XCTAssertEqual(b.from, 4); XCTAssertEqual(b.to, 5, "no sure stretch after: to the end")
        let c = SkimFollow.fixSpan(at: 0.5, strip: [.init(t0: 0, t1: 5, sure: .lost)], length: 5)
        XCTAssertEqual(c.from, 0); XCTAssertEqual(c.to, 5)
    }

    func testAFixTakesThePlaceOfItsStretch() {
        func f(_ t: Double, _ s: SkimFollow.Sure) -> SkimFollow.Tracked { .init(t: t, step: .init(box: nil, held: s != .lost, shape: nil), sure: s) }
        let base = [0.0, 0.5, 1.0, 1.5, 2.0].map { f($0, $0 >= 1 && $0 <= 1.5 ? .lost : .sure) }
        let m = SkimFollow.merged(base, patch: [f(1.5, .sure), f(1.0, .sure), f(3, .sure)], from: 1, to: 1.5)
        XCTAssertEqual(m.map(\.t), [0, 0.5, 1, 1.5, 2])
        XCTAssertEqual(m.map(\.sure), [.sure, .sure, .sure, .sure, .sure], "a patch frame outside its stretch is left out")
    }

    // MARK: The edge

    func testTheEdgeThePageMaySend() {
        XCTAssertEqual(SkimFollow.edge(grow: 0.01, soft: 0.02).grow, 0.01)
        XCTAssertEqual(SkimFollow.edge(grow: 1, soft: 1).grow, SkimFollow.maxGrow)
        XCTAssertEqual(SkimFollow.edge(grow: -1, soft: -1).grow, -SkimFollow.maxGrow)
        XCTAssertEqual(SkimFollow.edge(grow: -1, soft: -1).soft, 0)
        XCTAssertEqual(SkimFollow.edge(grow: Double.nan, soft: "x").grow, 0)
        XCTAssertEqual(SkimFollow.edge(grow: nil, soft: nil).soft, 0)
    }

    func testGrowShrinkAndSoften() {
        // a 20 × 20 square in a 60 × 60 frame
        var p = LookMasks.Plane(width: 60, height: 60)
        for y in 20..<40 { for x in 20..<40 { p[x, y] = 1 } }
        func width(_ q: LookMasks.Plane) -> Int { (0..<60).filter { q[$0, 30] > 0.5 }.count }
        XCTAssertEqual(width(SkimFollow.edged(p, grow: 0, soft: 0)), 20)
        let g = width(SkimFollow.edged(p, grow: 4, soft: 0)), s = width(SkimFollow.edged(p, grow: -4, soft: 0))
        XCTAssertTrue((25...29).contains(g), "grown about 4 px a side: \(g)")
        XCTAssertTrue((11...15).contains(s), "shrunk about 4 px a side: \(s)")
        let soft = SkimFollow.edged(p, grow: 0, soft: 6)
        XCTAssertEqual(soft[30, 30], 1, accuracy: 1e-5, "the middle stays")
        XCTAssertTrue(soft[20, 30] > 0.2 && soft[20, 30] < 0.8, "the edge is soft: \(soft[20, 30])")
        XCTAssertEqual(soft[5, 30], 0, accuracy: 1e-5, "far outside stays out")
    }

    func testTheClicksThePageMaySend() {
        let p = SkimFollow.promptPoints([["x": 0.5, "y": 0.4, "in": false], ["x": 0.2, "y": 0.9, "in": false], ["x": 1, "y": 0]])
        XCTAssertEqual(p, [.init(x: 0.5, y: 0.4, include: true), .init(x: 0.2, y: 0.9, include: false), .init(x: 1, y: 0, include: true)],
                       "the first click always adds; a click with no `in` adds")
        XCTAssertNil(SkimFollow.promptPoints([] as [Any]))
        XCTAssertNil(SkimFollow.promptPoints([["x": 1.2, "y": 0.5]]), "outside the frame")
        XCTAssertNil(SkimFollow.promptPoints([["x": Double.nan, "y": 0.5]]))
        XCTAssertNil(SkimFollow.promptPoints([["x": "0.5", "y": 0.5]]))
        XCTAssertNil(SkimFollow.promptPoints("clicks"))
        XCTAssertNil(SkimFollow.promptPoints(Array(repeating: ["x": 0.5, "y": 0.5], count: SkimFollow.promptMax + 1)))
    }

    func testAClickAddsToTheOutlineAndAnUndoStartsAgain() {
        let a = SkimFollow.PromptPoint(x: 0.5, y: 0.5, include: true), b = SkimFollow.PromptPoint(x: 0.7, y: 0.5, include: false)
        let c = SkimFollow.PromptPoint(x: 0.1, y: 0.1, include: true)
        XCTAssertEqual(SkimFollow.promptAdded([a], [a, b]), [b])
        XCTAssertEqual(SkimFollow.promptAdded([a, b], [a, b]), [], "the same clicks again: nothing to add")
        XCTAssertNil(SkimFollow.promptAdded([a, b], [a]), "an undo starts again")
        XCTAssertNil(SkimFollow.promptAdded([a, b], [a, c]), "a different click starts again")
        XCTAssertNil(SkimFollow.promptAdded([], [a]), "nothing yet: start")
    }

    func testTheFollowedBoxIsGrownToPromptTheNextFrame() {
        let g = SkimFollow.grown(LookMasks.Box(x: 0.4, y: 0.4, w: 0.2, h: 0.1), by: 0.15)
        XCTAssertEqual(g.x, 0.37, accuracy: 1e-9); XCTAssertEqual(g.y, 0.385, accuracy: 1e-9)
        XCTAssertEqual(g.w, 0.26, accuracy: 1e-9); XCTAssertEqual(g.h, 0.13, accuracy: 1e-9)
        let edge = SkimFollow.grown(LookMasks.Box(x: 0, y: 0.9, w: 0.5, h: 0.1), by: 0.15)
        XCTAssertEqual(edge.x, 0); XCTAssertEqual(edge.y + edge.h, 1, accuracy: 1e-9, "kept inside the frame")
    }
}
