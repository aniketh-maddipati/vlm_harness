import XCTest
import CoreGraphics
import ImageIO

/// Golden snapshot parity. For each entry in goldens/manifest.json: drive the native app to the same state,
/// capture the window, and
///   compare == "pixel":  fail if more than 2% of pixels differ by more than 16/255 in any channel;
///   compare == "layout": no pixel diff (LAYOUT_SIZING.md overrides the prototype there).
///                        Just attach the side-by-side for human review; the R-5x tests guard the rules.
/// Always attaches golden | native | diff, so reviewers can see parity in the Xcode report even when it passes.
/// Copy goldens/ into the UI-test bundle as a folder reference.
final class GoldenSnapshotTests: LuminaTestCase {
    override class var limit: TimeInterval { 600 }
    struct Manifest: Decodable { struct Shot: Decodable { let file: String?; let state: String; let size: String; let viewport: [Int]?; let compare: String?; let error: String? }; let shots: [Shot] }
    lazy var root = Bundle(for: Self.self).url(forResource: "goldens", withExtension: nil)!
    lazy var manifest = try! JSONDecoder().decode(Manifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))

    func test_goldens_1100x760() { run(size: "1100x760") }
    func test_goldens_1440x900() { run(size: "1440x900") }
    func test_goldens_2560x1440() { run(size: "2560x1440") }
    func test_goldens_480x800() { run(size: "480x800") }

    private func run(size: String) {
        continueAfterFailure = true
        for shot in manifest.shots where shot.size == size && shot.error == nil {
            guard let vp = shot.viewport, let file = shot.file, let build = States.all[shot.state] else { XCTFail("no native setup for \(shot.state)"); continue }
            let l = Lumina(window: CGSize(width: vp[0], height: vp[1]), faults: States.faults[shot.state] ?? []).launch()
            build(l); l.pause(0.5)
            let native = l.window.screenshot().image, golden = NSImage(contentsOf: root.appendingPathComponent(file))!
            let (ratio, diff) = Self.diff(golden, native)
            for (n, img) in [("golden", golden), ("native", native), ("diff", diff)] { let a = XCTAttachment(image: img); a.name = "\(size) \(shot.state) · \(n)"; a.lifetime = .keepAlways; add(a) }
            if shot.compare == "pixel" { XCTAssertLessThanOrEqual(ratio, 0.02, "\(size) \(shot.state): \(Int(ratio * 100))% of pixels differ") }
            l.app.terminate()
        }
    }

    /// Fraction of pixels whose max channel delta > 16, after scaling native to the golden's pixel size.
    static func diff(_ a: NSImage, _ b: NSImage) -> (Double, NSImage) {
        let ca = a.cgImage(forProposedRect: nil, context: nil, hints: nil)!, w = ca.width, h = ca.height
        func px(_ img: NSImage) -> [UInt8] {
            var d = [UInt8](repeating: 0, count: w * h * 4)
            let ctx = CGContext(data: &d, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .high; ctx.draw(img.cgImage(forProposedRect: nil, context: nil, hints: nil)!, in: CGRect(x: 0, y: 0, width: w, height: h)); return d
        }
        let pa = px(a), pb = px(b); var out = [UInt8](repeating: 0, count: w * h * 4), bad = 0
        for i in stride(from: 0, to: pa.count, by: 4) {
            let m = max(abs(Int(pa[i]) - Int(pb[i])), abs(Int(pa[i + 1]) - Int(pb[i + 1])), abs(Int(pa[i + 2]) - Int(pb[i + 2])))
            if m > 16 { bad += 1; out[i] = 255; out[i + 3] = 255 } else { out[i] = pa[i] / 4; out[i + 1] = pa[i + 1] / 4; out[i + 2] = pa[i + 2] / 4; out[i + 3] = 255 }
        }
        let ctx = CGContext(data: &out, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return (Double(bad) / Double(w * h), NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: w, height: h)))
    }
}

/// Native equivalents of the states in capture/capture-goldens.mjs. Keep names identical.
enum States {
    static let faults: [String: [String]] = ["edit-loadfail": ["imageLoadFail"]]
    static func kept(_ l: Lumina) { l.startCulling(); for k in ["r", "r", "x", "r", "x", "r", "r", "r", "x", "r"] { l.key(k); l.pause(0.04) } }
    static let all: [String: (Lumina) -> Void] = [
        "open-empty": { _ in },
        "open-copying": { l in l.enter(); _ = l.waitUntil(5) { l.state.copied > 20 }; l.go(1, settle: 0.3) },
        "open-recent": { l in kept(l); l.go(1) },
        "open-startover-armed": { l in kept(l); l.go(1); l.click("open.startOver") },
        "open-import-message": { l in l.importFixture(Fixtures.folder("Card dump") { d in Fixtures.write(d.appendingPathComponent("a.jpg"), seed: 1); Fixtures.write(d.appendingPathComponent("b.jpg"), seed: 2); Fixtures.bytes(d.appendingPathComponent("clip.mp4"), 4); Fixtures.text(d.appendingPathComponent("notes.txt"), "hi") }); l.go(1) },
        "open-import-nothing": { l in l.importFixture(Fixtures.onlyJunk) },
        "drop-overlay": { l in l.startCulling(); l.command("{\"dragEnter\":true}") },
        "cull-empty": { l in l.go(2) },
        "cull-copying": { l in l.enter(); _ = l.waitUntil(5) { l.state.copied > 30 } },
        "cull-mid": { l in kept(l) },
        "cull-all-decided": { l in l.startCulling(); for i in 0..<117 { l.key(i % 3 == 0 ? "x" : "r") } },
        "edit-empty": { l in l.startCulling(); l.go(3, settle: 1.4) },
        "edit-intro": { l in l.app.terminate(); l.app.launchEnvironment["LUMINA_INTRO"] = "show"; l.launch(); kept(l); l.go(3, settle: 1.4) },
        "edit-loaded": { l in kept(l); l.go(3, settle: 1.4) },
        "edit-edited": { l in kept(l); l.go(3, settle: 1.4); for k in [".", ".", ".", "]", ".", "."] { l.key(k) } },
        "edit-help": { l in kept(l); l.go(3, settle: 1.4); l.key("/", .shift) },
        "edit-variations": { l in kept(l); l.go(3, settle: 1.4); l.command("{\"keyDown\":\"v\"}"); l.pause(0.9) },
        "edit-crop": { l in kept(l); l.go(3, settle: 1.4); l.key("c") },
        "edit-zoom-1to1": { l in kept(l); l.go(3, settle: 1.4); l.key("z"); l.pause(0.9) },
        "edit-focus": { l in kept(l); l.go(3, settle: 1.4); l.key("h") },
        "edit-colour": { l in kept(l); l.go(3, settle: 1.4); l.click("edit.section.colour") },
        "edit-effects": { l in kept(l); l.go(3, settle: 1.4); l.click("edit.section.effects") },
        "edit-loadfail": { l in kept(l); l.go(3, settle: 2.9) },
        "edit-storage-warning": { l in kept(l); l.go(3, settle: 1.4); l.command("{\"injectFault\":\"storageFull\"}"); l.key("."); l.key("."); l.pause(0.8) },
        "save-ready": { l in kept(l); l.go(3, settle: 1.4); l.key("."); l.go(4) },
        "save-saved": { l in kept(l); l.go(4); l.click("save.button") },
        "save-changed": { l in kept(l); l.go(4); l.click("save.button"); l.click("save.format.jpeg") },
        "save-nothing": { l in l.startCulling(); for _ in 0..<117 { l.key("x") }; l.go(4, settle: 1.6) },
    ]
}
