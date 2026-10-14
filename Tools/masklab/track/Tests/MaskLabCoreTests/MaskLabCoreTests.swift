import MaskLabCore
import XCTest

// The Foundation-only half of masklab-track, on Linux too:
//   swift test --package-path Tools/masklab/track
final class MaskLabCoreTests: XCTestCase {
    func testParsesABoxRun() throws {
        let o = try Options.parse(["clip.mp4", "--start", "12", "--box", "0.1,0.2,0.3,0.4", "--tracker", "vision-box",
                                   "--out", "/tmp/x", "--frames", "90", "--save-frames", "30"])
        XCTAssertEqual(o.clip, "clip.mp4")
        XCTAssertEqual(o.start, 12)
        XCTAssertEqual(o.proxy, 720)
        XCTAssertEqual(o.prompt, .box(Box(x: 0.1, y: 0.2, w: 0.3, h: 0.4)))
        XCTAssertEqual(o.tracker, .visionBox)
        XCTAssertEqual(o.maxFrames, 90)
        XCTAssertEqual(o.saveFramesEvery, 30)
    }

    func testParsesAPointRun() throws {
        let o = try Options.parse(["--point", "0.5,0.25", "--tracker", "vision-instance", "c.mov", "--out", "o", "--proxy", "1080"])
        XCTAssertEqual(o.prompt, .point(Point(x: 0.5, y: 0.25)))
        XCTAssertEqual(o.proxy, 1080)
        XCTAssertEqual(o.start, 0)
    }

    func testRefusesBadArguments() {
        let base = ["c.mp4", "--tracker", "vision-box", "--out", "o"]
        XCTAssertThrowsError(try Options.parse(base))                                  // no prompt
        XCTAssertThrowsError(try Options.parse(base + ["--box", "0.5,0.5,0.6,0.1"]))   // leaves the frame
        XCTAssertThrowsError(try Options.parse(base + ["--box", "0.1,0.1,0,0.1"]))     // empty
        XCTAssertThrowsError(try Options.parse(base + ["--point", "1.5,0.1"]))
        XCTAssertThrowsError(try Options.parse(["c.mp4", "--point", "0.1,0.1", "--tracker", "nope", "--out", "o"]))
        XCTAssertThrowsError(try Options.parse(base + ["--point", "0.1,0.1", "--start", "-1"]))
        XCTAssertThrowsError(try Options.parse(base + ["--point", "0.1,0.1", "--wat"]))
        // SAM without a model folder says where to put one; nothing is downloaded.
        XCTAssertThrowsError(try Options.parse(["c.mp4", "--point", "0.1,0.1", "--tracker", "sam2-coreml", "--out", "o"])) { e in
            XCTAssertTrue("\(e)".contains("--model"))
        }
        XCTAssertNoThrow(try Options.parse(["c.mp4", "--point", "0.1,0.1", "--tracker", "sam2-coreml", "--out", "o", "--model", "m"]))
    }

    func testProxySize() {
        XCTAssertEqual(proxySize(width: 3840, height: 2160, longEdge: 720).width, 720)
        XCTAssertEqual(proxySize(width: 3840, height: 2160, longEdge: 720).height, 406)   // 405 rounded to even
        XCTAssertEqual(proxySize(width: 2160, height: 3840, longEdge: 720).height, 720)
        XCTAssertEqual(proxySize(width: 640, height: 360, longEdge: 720).width, 640)      // never upscaled
        XCTAssertEqual(frameName(42), "000042.png")
    }

    func testBoxes() {
        let a = Box(x: 0, y: 0, w: 0.5, h: 0.5), b = Box(x: 0.25, y: 0.25, w: 0.5, h: 0.5)
        XCTAssertEqual(a.iou(a), 1, accuracy: 1e-12)
        XCTAssertEqual(a.iou(b), 0.0625 / 0.4375, accuracy: 1e-12)
        XCTAssertEqual(Box(x: 0.1, y: 0.2, w: 0.3, h: 0.4).flippedY.y, 0.4, accuracy: 1e-12)
        XCTAssertEqual(Box(x: 0.1, y: 0.2, w: 0.3, h: 0.4).flippedY.flippedY.y, 0.2, accuracy: 1e-12)
        let c = Box(x: -0.1, y: 0.9, w: 0.5, h: 0.5).clamped()
        XCTAssertEqual(c.x, 0); XCTAssertEqual(c.maxY, 1, accuracy: 1e-12)
    }

    func testMasks() {
        let m = Mask.box(Box(x: 0.25, y: 0.5, w: 0.5, h: 0.25), width: 8, height: 8)
        XCTAssertEqual(m.area, 8)
        XCTAssertEqual(m.boundingBox, Box(x: 0.25, y: 0.5, w: 0.5, h: 0.25))
        XCTAssertTrue(m.contains(Point(x: 0.5, y: 0.6)))
        XCTAssertFalse(m.contains(Point(x: 0.1, y: 0.1)))
        XCTAssertEqual(m.iou(m.resized(width: 16, height: 16)), 1, accuracy: 1e-12)
        XCTAssertEqual(m.resized(width: 16, height: 16).area, 32)
        XCTAssertNil(Mask(width: 4, height: 4).boundingBox)
        XCTAssertEqual(Mask(width: 4, height: 4).iou(Mask(width: 4, height: 4)), 0)
        // A 2 × 2 soft map sampled up to 4 × 4.
        let t = Mask.threshold(width: 2, height: 2, outWidth: 4, outHeight: 4, above: 0.5) { x, y in x == 1 && y == 0 ? 0.9 : 0.1 }
        XCTAssertEqual(t.area, 4)
        XCTAssertEqual(t.boundingBox, Box(x: 0.5, y: 0, w: 0.5, h: 0.5))
    }

    /// Two people side by side (1 left, 2 right) and a small object (3) at the bottom right.
    func scene() -> LabelMap {
        let w = 10, h = 10
        var labels = [UInt8](repeating: 0, count: w * h)
        for y in 1..<8 { for x in 1..<4 { labels[y * w + x] = 1 }; for x in 5..<8 { labels[y * w + x] = 2 } }
        labels[9 * w + 9] = 3
        return LabelMap(width: w, height: h, labels: labels)
    }

    func testPicksTheInstanceTheBoxCovers() {
        let map = scene()
        XCTAssertEqual(map.ids, [1, 2, 3])
        XCTAssertEqual(Pick.byBox(map, box: Box(x: 0.5, y: 0.1, w: 0.3, h: 0.7)), 2)
        XCTAssertEqual(Pick.byBox(map, box: Box(x: 0.05, y: 0.05, w: 0.4, h: 0.8)), 1)
        XCTAssertNil(Pick.byBox(map, box: Box(x: 0, y: 0.85, w: 0.3, h: 0.1)), "nothing there: lost, not the nearest")
    }

    func testPicksByPointAndByPreviousMask() {
        let map = scene()
        XCTAssertEqual(Pick.byPoint(map, point: Point(x: 0.65, y: 0.5)), 2)
        XCTAssertNil(Pick.byPoint(map, point: Point(x: 0.45, y: 0.5)))
        XCTAssertEqual(Pick.byPrompt(map, prompt: .point(Point(x: 0.2, y: 0.2))), 1)
        // The previous frame's mask at another size, shifted a little: still person 2.
        let prev = Mask.box(Box(x: 0.55, y: 0.15, w: 0.3, h: 0.7), width: 40, height: 40)
        XCTAssertEqual(Pick.byPrevious(map, previous: prev), 2)
        XCTAssertNil(Pick.byPrevious(map, previous: Mask(width: 40, height: 40)))
    }

    func testSAMPrompts() {
        let (xy, labels) = SAMPrompt.points(.box(Box(x: 0.25, y: 0.5, w: 0.5, h: 0.25)), side: 1024)
        XCTAssertEqual(xy, [256, 512, 768, 768])
        XCTAssertEqual(labels, [2, 3])
        XCTAssertEqual(SAMPrompt.points(.point(Point(x: 0.5, y: 0.5)), side: 1024).labels, [1])
        let m = Mask.box(Box(x: 0.25, y: 0.25, w: 0.5, h: 0.5), width: 20, height: 20)
        guard case .box(let b)? = SAMPrompt.follow(m) else { return XCTFail("a mask gives a box") }
        XCTAssertEqual(b.x, 0.2, accuracy: 1e-9)
        XCTAssertEqual(b.w, 0.6, accuracy: 1e-9)
        XCTAssertNil(SAMPrompt.follow(Mask(width: 4, height: 4)))
        XCTAssertEqual(SAMPrompt.best([0.2, 0.9, 0.5]), 1)
    }

    func testTimingJSONIsWhatScorePyReads() throws {
        var t = Timing(tracker: .visionBox, clip: "C001", startFrame: 5, prompt: .box(Box(x: 0, y: 0, w: 1, h: 1)),
                       proxy: [720, 406], source: [3840, 2160], model: nil,
                       device: .init(model: "test", os: "test", cores: 8, memoryGB: 16))
        t.frames = 2; t.totalMs = 100; t.perFrameMs = [20, 30]; t.decodeMs = [5, 5]; t.lost = [6]; t.confidence = [1, 0.4]
        let obj = try JSONSerialization.jsonObject(with: try t.json()) as! [String: Any]
        XCTAssertEqual(obj["start_frame"] as? Int, 5)
        XCTAssertEqual(obj["frames"] as? Int, 2)
        XCTAssertEqual(obj["total_ms"] as? Double, 100)
        XCTAssertEqual(obj["per_frame_ms"] as? [Double], [20, 30])
        XCTAssertEqual(obj["tracker"] as? String, "vision-box")
        XCTAssertNotNil(obj["device"] as? [String: Any])
    }
}
