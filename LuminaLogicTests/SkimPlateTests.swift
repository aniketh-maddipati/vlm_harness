import XCTest
@testable import Lumina

/// Removing a followed shape from a still-camera clip, the maths (`SkimPlate`): the crop, the frames picked, the clean
/// plate as the median of the frames where the shape is not, how much the camera moved, and when a removal is refused.
final class SkimPlateTests: XCTestCase {
    typealias Box = LookMasks.Box

    /// A `w × h` grey scene with a little grain, the same in every frame (a still camera).
    private func scene(_ w: Int, _ h: Int, seed: Int = 0) -> [UInt8] {
        (0..<(w * h * 3)).map { UInt8(100 + ($0 * 7 + seed) % 5) }
    }

    /// A walker: a black block `bw` wide at column `x`, its mask beside it.
    private func walker(_ base: [UInt8], _ w: Int, _ h: Int, x: Int, bw: Int) -> ([UInt8], LookMasks.Plane) {
        var f = base, m = LookMasks.Plane(width: w, height: h)
        for y in 0..<h { for c in x..<min(w, x + bw) { let i = y * w + c; f[i * 3] = 0; f[i * 3 + 1] = 0; f[i * 3 + 2] = 0; m.values[i] = 1 } }
        return (f, m)
    }

    func testTheCropHoldsEveryBoxAndAMargin() {
        let c = SkimPlate.crop([Box(x: 0.1, y: 0.2, w: 0.1, h: 0.1), Box(x: 0.5, y: 0.25, w: 0.1, h: 0.2)], width: 1000, height: 500, pad: 0.01)
        XCTAssertEqual(c, SkimPlate.Crop(x: 90, y: 90, w: 520, h: 145))
        XCTAssertEqual(SkimPlate.crop([Box(x: 0, y: 0, w: 1, h: 1)], width: 100, height: 50), SkimPlate.Crop(x: 0, y: 0, w: 100, h: 50), "never past the frame")
        XCTAssertNil(SkimPlate.crop([], width: 100, height: 50))
    }

    func testFramesArePickedEvenly() {
        XCTAssertEqual(SkimPlate.picks(frames: 3, n: 5), [0, 1, 2])
        XCTAssertEqual(SkimPlate.picks(frames: 100, n: 4), [12, 37, 62, 87])
        XCTAssertEqual(SkimPlate.picks(frames: 0), [])
    }

    func testAnOutlineInTheCrop() {
        let o = SkimPlate.inCrop([[.init(x: 0.5, y: 0.5)]], crop: .init(x: 400, y: 200, w: 200, h: 100), width: 1000, height: 500)
        XCTAssertEqual(o[0][0].x, 0.5, accuracy: 1e-9); XCTAssertEqual(o[0][0].y, 0.5, accuracy: 1e-9)
    }

    func testThePlateIsTheSceneBehindAWalker() throws {
        let w = 40, h = 10, base = scene(w, h)
        let shots = [0, 10, 20, 30].map { walker(base, w, h, x: $0, bw: 8) }
        let p = try XCTUnwrap(SkimPlate.plate(frames: shots.map(\.0), masks: shots.map(\.1), width: w, height: h))
        XCTAssertEqual(p.rgb, base, "the walker is gone, the scene's own grain is back")
        XCTAssertEqual(p.unseen, 0)
        XCTAssertEqual(p.seen[5], 3, "each place shows in the frames the walker is elsewhere")
        XCTAssertEqual(SkimPlate.shake(frames: shots.map(\.0), masks: shots.map(\.1), plate: p, width: w, height: h), 0, accuracy: 1e-9)
        XCTAssertNil(SkimPlate.refusal(shake: 0, unseen: p.unseen))
    }

    func testSomeoneWhoNeverMovesLeavesAHole() throws {
        let w = 40, h = 10, base = scene(w, h)
        let shots = [0, 2, 4].map { walker(base, w, h, x: 10 + $0, bw: 10) }   // columns 14…19 always covered
        let p = try XCTUnwrap(SkimPlate.plate(frames: shots.map(\.0), masks: shots.map(\.1), width: w, height: h))
        XCTAssertEqual(p.unseen, 6.0 / 14.0, accuracy: 1e-9)
        XCTAssertNotNil(SkimPlate.refusal(shake: 0, unseen: p.unseen)?.range(of: "never seen"))
    }

    func testAMovingCameraIsRefused() throws {
        let w = 40, h = 10
        let frames = (0..<5).map { k in scene(w, h, seed: k * 40).map { UInt8(min(255, Int($0) + k * 12)) } }
        let masks = frames.map { _ in LookMasks.Plane(width: w, height: h) }
        let p = try XCTUnwrap(SkimPlate.plate(frames: frames, masks: masks, width: w, height: h))
        let s = SkimPlate.shake(frames: frames, masks: masks, plate: p, width: w, height: h)
        XCTAssertGreaterThan(s, SkimPlate.steadyMax)
        XCTAssertNotNil(SkimPlate.refusal(shake: s, unseen: 0)?.range(of: "camera moves"))
    }

    func testSizesMustAgree() {
        XCTAssertNil(SkimPlate.plate(frames: [[0, 0, 0]], masks: [LookMasks.Plane(width: 2, height: 1)], width: 2, height: 1))
        XCTAssertNil(SkimPlate.plate(frames: [], masks: [], width: 2, height: 1))
    }

    func testPatchName() {
        XCTAssertEqual(SkimPlate.patchName(clip: "C0042.MP4"), "C0042 patch.mov")
        XCTAssertEqual(SkimPlate.patchName(clip: "../x/C0042.MP4"), "C0042 patch.mov")
    }
}
