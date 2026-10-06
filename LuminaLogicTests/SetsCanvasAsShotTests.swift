import CoreImage
import WebKit
import XCTest
@testable import Lumina

/// N2: the Edit canvas names the photo's as-shot white balance for the page's temperature slider
/// (plumbing's `lookString(L, p, asShot)`). The pair is the decoder's, read off the base the
/// canvas develops anyway: in `canvasEnter`'s answer when that base is already there, else through
/// `onAsShot` (the bridge's `__lumina.editHeader` push) when it lands.
///
/// Holds: the shape (`asShot: {kelvin, tint}`, `asShotRel`), no key without a reading (the JPEG
/// stand-in, an image file, a file that does not develop), a rel outside the opened folders is
/// refused as before, and asking never adds a develop (`LookBases.stats.built`).
///
/// No RAW in the repo: a base "already developed" is put into the cache through `LookBases.adopt`.
/// Temp folders only; the image path (no host view, no window).
@MainActor
final class SetsCanvasAsShotTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!
    private var shoot: URL!
    private let rel = "shoot/DSC00001.ARW"

    @MainActor final class Chooser: SetsChooser {
        var sources: [URL] = []
        func chooseSource(allowsDirectories: Bool) async -> URL? { sources.isEmpty ? nil : sources.removeFirst() }
        func chooseDestination(label: String, suggested: URL?, refusal: String?) async -> URL? { nil }
        func chooseCard(name: String, at: URL, refusal: String?) async -> URL? { nil }
    }

    final class Message: WKScriptMessage {
        private let payload: Any
        init(_ payload: Any) { self.payload = payload; super.init() }
        override var body: Any { payload }
        override var name: String { "lumina" }
    }

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("sets-asshot-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        shoot = root.appendingPathComponent("shoot", isDirectory: true)
        try fm.createDirectory(at: shoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("support"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("outside"), withIntermediateDirectories: true)
        // Not RAWs any decoder reads: a develop of one fails, which is the "no readable value" case.
        for i in 1...2 { try Data(repeating: UInt8(i), count: 4096).write(to: shoot.appendingPathComponent(String(format: "DSC%05d.ARW", i))) }
        try Data(repeating: 9, count: 4096).write(to: root.appendingPathComponent("outside/DSC09999.ARW"))
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    private func bridge() async throws -> SetsBridge {
        let chooser = Chooser()
        let access = SetsAccess(calls: SetsAccess.Calls(start: { _ in true }, stop: { _ in },
                                                        resolve: { data in (URL(fileURLWithPath: String(decoding: data, as: UTF8.self), isDirectory: true), false) },
                                                        bookmark: { Data($0.path.utf8) },
                                                        exists: { u in var d: ObjCBool = false; return FileManager.default.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue }))
        let b = SetsBridge(chooser: chooser, supportDir: root.appendingPathComponent("support"), access: access)
        b.attachCanvas(host: nil)
        chooser.sources = [shoot]
        let (r, e) = await call(b, ["op": "openFolder"])
        XCTAssertNil(e)
        XCTAssertEqual((r as? [String: Any])?["name"] as? String, "shoot")
        _ = await call(b, ["op": "shootOpened", "name": "shoot", "n": 2, "date": "2026:09:08 10:00:00"])
        return b
    }

    private func call(_ b: SetsBridge, _ body: Any) async -> (Any?, String?) {
        await b.userContentController(WKUserContentController(), didReceive: Message(body))
    }

    private func entry(_ wb: Look.WhiteBalance, source: String = "raw") -> LookBases.Entry {
        let px = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        return LookBases.Entry(base: px, small: px, asShot: wb, anchor: .reference, baseSize: CGSize(width: 8, height: 8), smallSize: CGSize(width: 8, height: 8),
                               photoSize: CGSize(width: 8, height: 8), bytes: 512, source: source, decoder: source == "raw" ? 8 : nil, developMs: 0, onGPU: false, textures: [])
    }

    /// The key `enter` asks the cache for on the image path (no view: 1024 × 768).
    private func key(_ rel: String, decoder: Int? = nil) -> LookBases.Key {
        LookBases.Key(rel: rel, decoder: decoder, look: Look(), canvas: CGSize(width: 1024, height: 768))
    }

    // MARK: The shape

    func testHeaderShape() throws {
        let h = LookCanvasController.asShotHeader(rel: rel, Look.WhiteBalance(kelvin: 5234.5, tint: 7))
        XCTAssertEqual(Set(h.keys), ["asShot", "asShotRel"])
        XCTAssertEqual(h["asShotRel"] as? String, rel)
        XCTAssertEqual(h["asShot"] as? [String: Double], ["kelvin": 5234.5, "tint": 7])
        // What the bridge pushes: `__lumina.editHeader(<this>)`.
        let back = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(SetsBridge.json(h).utf8)) as? [String: Any])
        XCTAssertEqual(back["asShotRel"] as? String, rel)
        XCTAssertEqual((back["asShot"] as? [String: Any])?["kelvin"] as? Double, 5234.5)
        XCTAssertEqual((back["asShot"] as? [String: Any])?["tint"] as? Double, 7)
    }

    func testOnlyADevelopedRawHasAPair() {
        let wb = Look.WhiteBalance(kelvin: 4800, tint: -3)
        XCTAssertEqual(LookCanvasController.asShot(of: entry(wb)), wb)
        XCTAssertNil(LookCanvasController.asShot(of: nil), "no base yet")
        XCTAssertNil(LookCanvasController.asShot(of: entry(Look.WhiteBalance(kelvin: 5500, tint: 0), source: "jpeg")), "the embedded JPEG standing in")
        XCTAssertNil(LookCanvasController.asShot(of: entry(Look.WhiteBalance(kelvin: 5500, tint: 0), source: "image")), "an image file")
        for bad in [Look.WhiteBalance(kelvin: 0, tint: 0), Look.WhiteBalance(kelvin: -1, tint: 0), Look.WhiteBalance(kelvin: .nan, tint: 0),
                    Look.WhiteBalance(kelvin: .infinity, tint: 0), Look.WhiteBalance(kelvin: 5000, tint: .nan)] {
            XCTAssertNil(LookCanvasController.asShot(of: entry(bad)), "\(bad)")
        }
    }

    // MARK: canvasEnter's answer

    /// The base is already developed: the pair is in the answer, with its rel, and nothing is developed for it.
    func testReplyNamesThePairWhenTheBaseIsThere() async throws {
        let b = try await bridge()
        let canvas = try XCTUnwrap(b.canvas)
        let wb = Look.WhiteBalance(kelvin: 5234.5, tint: 7)
        canvas.bases.adopt(key(rel), entry(wb))
        var pushed = 0
        for _ in 0..<3 {
            let (r, e) = await call(b, ["op": "canvasEnter", "rel": rel, "look": ""])
            XCTAssertNil(e)
            let out = try XCTUnwrap(r as? [String: Any])
            XCTAssertEqual(out["asShotRel"] as? String, rel)
            XCTAssertEqual(out["asShot"] as? [String: Double], ["kelvin": 5234.5, "tint": 7])
            XCTAssertNotNil(out["canvas"], "the rest of the answer is still there")
            XCTAssertNotNil(out["decoderCanvas"])
            // The bridge installed its push; from here count what the canvas says on its own.
            let was = canvas.onAsShot
            canvas.onAsShot = { rel, wb in pushed += 1; was?(rel, wb) }
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(canvas.bases.stats.built, 0, "asking developed nothing")
        XCTAssertEqual(canvas.bases.stats.failed, 0)
        XCTAssertEqual(pushed, 0, "the answer said it: nothing pushed after it")
        _ = await call(b, ["op": "canvasLeave"])
    }

    /// A file no decoder reads and no embedded JPEG to stand in; then the JPEG stand-in itself: no key at all.
    func testReplyHasNoKeyWithoutAValue() async throws {
        let b = try await bridge()
        let canvas = try XCTUnwrap(b.canvas)
        let (r, e) = await call(b, ["op": "canvasEnter", "rel": rel, "look": ""])
        XCTAssertNil(e)
        let out = try XCTUnwrap(r as? [String: Any])
        XCTAssertNil(out["asShot"]); XCTAssertNil(out["asShotRel"])
        XCTAssertNotNil(out["canvas"])
        var told: [(String, Look.WhiteBalance)] = []
        canvas.onAsShot = { told.append(($0, $1)) }
        try await Task.sleep(nanoseconds: 400_000_000)          // the build fails on its queue
        XCTAssertTrue(told.isEmpty, "a develop that failed names no pair")
        XCTAssertEqual(canvas.bases.stats.built, 0)
        XCTAssertNil(canvas.asShotForReply())

        let two = "shoot/DSC00002.ARW"
        canvas.bases.adopt(key(two), entry(Look.WhiteBalance(kelvin: 5500, tint: 0), source: "jpeg"))
        let (r2, _) = await call(b, ["op": "canvasEnter", "rel": two, "look": ""])
        let out2 = try XCTUnwrap(r2 as? [String: Any])
        XCTAssertNil(out2["asShot"], "the JPEG stand-in's 5500 K is not a reading"); XCTAssertNil(out2["asShotRel"])
        _ = await call(b, ["op": "canvasLeave"])
    }

    /// A rel outside the opened folders: refused as before, the canvas untouched.
    func testARelNotOpenedIsRefusedAsBefore() async throws {
        let b = try await bridge()
        let canvas = try XCTUnwrap(b.canvas)
        for bad in ["../outside/DSC09999.ARW", "shoot/../outside/DSC09999.ARW", root.appendingPathComponent("outside/DSC09999.ARW").path, "/etc/hosts", ""] {
            canvas.bases.adopt(key(bad), entry(Look.WhiteBalance(kelvin: 5000, tint: 1)))
            let (r, e) = await call(b, ["op": "canvasEnter", "rel": bad, "look": ""])
            XCTAssertNil(r, bad)
            XCTAssertEqual(e, "not in an opened folder", bad)
        }
        XCTAssertNil(canvas.asShotForReply(), "no photo went onto the canvas")
        XCTAssertEqual(canvas.bases.stats.built, 0)
    }

    // MARK: The push (the base lands after the answer)

    /// The pair is known only after `enter` answered (here: the decoder map lands and the photo
    /// moves to a base that is there): said once through `onAsShot`, with the photo's rel, and
    /// not again for the same value; a new photo starts over.
    func testPairIsPushedOnceWhenTheBaseLandsLater() async throws {
        let pipe = try LookPipeline(rules: LookRules.bundled())
        let c = LookCanvasController(pipeline: pipe, host: nil)
        var told: [(rel: String, wb: Look.WhiteBalance)] = []
        c.onAsShot = { told.append(($0, $1)) }
        let url = shoot.appendingPathComponent("DSC00001.ARW")
        let wb = Look.WhiteBalance(kelvin: 6100, tint: -4)
        c.bases.adopt(key(rel, decoder: 8), entry(wb))

        c.enter(rel: rel, url: url, look: "", decoder: nil, regionDecoder: nil, preview: nil, neighbours: [])
        XCTAssertNil(c.asShotForReply(), "not known when enter answers")
        XCTAssertTrue(told.isEmpty)

        c.setDecoders(decoder: 8, regionDecoder: 8)
        XCTAssertEqual(told.count, 1)
        XCTAssertEqual(told.first?.rel, rel)
        XCTAssertEqual(told.first?.wb, wb)
        // The same base again (a look change, the decoders named again): nothing more.
        _ = c.look("ev:+0.30", drag: false, key: true, roi: nil, at: nil)
        c.setDecoders(decoder: 8, regionDecoder: 8)
        XCTAssertEqual(told.count, 1)
        // A crop is another base of the same photo with the same pair: still nothing more.
        var cropped = Look(); cropped.crop = try Look.parse("crop:0.1,0.1,0.5,0.5/0").crop
        c.bases.adopt(LookBases.Key(rel: rel, decoder: 8, look: cropped, canvas: CGSize(width: 1024, height: 768)), entry(wb))
        _ = c.look("crop:0.1,0.1,0.5,0.5/0", drag: false, key: true, roi: nil, at: nil)
        XCTAssertEqual(told.count, 1)
        XCTAssertEqual(c.asShotForReply()?.wb, wb)

        // The next photo, already developed: the answer carries it, so no push.
        let two = "shoot/DSC00002.ARW", wb2 = Look.WhiteBalance(kelvin: 3900, tint: 12)
        c.bases.adopt(key(two, decoder: 8), entry(wb2))
        c.enter(rel: two, url: shoot.appendingPathComponent("DSC00002.ARW"), look: "", decoder: 8, regionDecoder: 8, preview: nil, neighbours: [])
        XCTAssertEqual(c.asShotForReply()?.rel, two)
        XCTAssertEqual(c.asShotForReply()?.wb, wb2)
        XCTAssertEqual(told.count, 1)
        XCTAssertEqual(c.bases.stats.built, 0, "nothing was developed to say any of it")
        c.leave()
        XCTAssertNil(c.asShotForReply())
    }
}
