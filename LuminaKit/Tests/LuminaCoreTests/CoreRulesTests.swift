import XCTest
@testable import LuminaCore

/// Fast, deterministic unit tests for the rules that don't need a UI. These run on every commit (< 5s).
///
/// They assume this `LuminaCore` API (Wave 0 defines it; see WORKSTREAMS.md, WP-0):
///   ImportClassifier.classify(url:) -> ImportKind  // .photo, .raw, .video, .archive, .sidecar, .system, .empty, .other
///   ImportClassifier.decodes(url:) -> ImageInfo?    // pixel size after EXIF orientation, nil if it won't decode
///   ImportSummary(added:skipped:).message -> String
///   EXIFReader.read(url:) -> EXIF?                   // shot: Date?, make, model, lens, fNumber, exposure, iso, focal, orientation
///   SceneGrouper.group(_ items: [ImportItem]) -> Shoot   // scenes by subfolder + 30-min gaps; bursts ≤2s, same aspect, ≤8
///   DecisionStore (keep/out/undo/redo, 200 deep), EditStore (looks keyed by photo or burst)
///   SaveSignature.make(fmt:withEdits:kept:looks:) -> String
///   KeyRouter.route(_ key: KeyEvent, layers: [Layer]) -> Route   // which layer handles it, or .swallowed(reason)
///   LayoutScale.scale(for size: CGSize) -> CGFloat; CullLayout.rows(...); EditLayout.photoRect(...)
final class ImportClassifierTests: XCTestCase {
    func test_R11_systemAndSidecarFilesAreSilent() {
        for n in [".DS_Store", "._a.jpg", "Thumbs.db", "desktop.ini", "a.xmp", "a.THM", "a.lrv", "a.aae"] {
            XCTAssertTrue([.system, .sidecar].contains(ImportClassifier.classify(name: n, size: 100)), n)
        }
    }
    func test_R12_kindsByName() {
        XCTAssertEqual(ImportClassifier.classify(name: "clip.MP4", size: 9), .video)
        XCTAssertEqual(ImportClassifier.classify(name: "x.zip", size: 9), .archive)
        XCTAssertEqual(ImportClassifier.classify(name: "x.CR3", size: 9), .raw)
        XCTAssertEqual(ImportClassifier.classify(name: "zero.jpg", size: 0), .empty)
        XCTAssertEqual(ImportClassifier.classify(name: "noext", size: 9), .photo, "no extension: try decoding")
    }
    func test_R10_extensionIsAHintNotProof() {
        XCTAssertNotNil(ImportClassifier.decodes(url: Fixtures.messy.appendingPathComponent("f-really-png.jpg")))
        XCTAssertNil(ImportClassifier.decodes(url: Fixtures.messy.appendingPathComponent("broken.jpg")))
    }
    func test_R12_summaryMessageCountsEverySkip() {
        let s = ImportSummary(added: 6, folder: "Card dump", skipped: [.video: 1, .archive: 1, .damaged: 2, .empty: 1, .other: 2, .duplicate: 3])
        XCTAssertEqual(s.message, "Added 6 photos from Card dump. Skipped 1 video · 1 zip/archive (unzip it first) · 2 damaged or not really a photo · 1 empty (0 bytes) · 2 not a photo · 3 already in this shoot.")
        XCTAssertEqual(ImportSummary(added: 0, folder: "Docs", skipped: [.other: 2]).message, "No photos added. Skipped 2 not a photo. Lumina opens JPEG, PNG, WebP, HEIC, AVIF and RAW.")
    }
}

final class EXIFAndGroupingTests: XCTestCase {
    func test_R16_readsShotTimeAndCamera() throws {
        let e = try XCTUnwrap(EXIFReader.read(url: Fixtures.exifDay.appendingPathComponent("m1.jpg")))
        XCTAssertEqual(e.model, "Canon EOS R6"); XCTAssertEqual(e.fNumber, 2.8); XCTAssertEqual(e.iso, 800); XCTAssertEqual(e.focal, 85)
        XCTAssertEqual(e.shot, Fixtures.day(9))
    }
    func test_R1D_orientationApplied() throws {
        let i = try XCTUnwrap(ImportClassifier.decodes(url: Fixtures.rotated.appendingPathComponent("portrait.jpg")))
        XCTAssertEqual(i.pixelSize, CGSize(width: 420, height: 640))
    }
    func test_R15_scenesBySubfolderAndGap_burstsCapped() {
        let t = Fixtures.day(9)
        var items = (0..<12).map { ImportItem(rel: "A/\($0).jpg", shot: t.addingTimeInterval(Double($0)), aspect: 1.5) }   // 12 frames 1s apart
        items.append(ImportItem(rel: "A/late.jpg", shot: t.addingTimeInterval(31 * 60), aspect: 1.5))                  // >30 min gap
        items.append(ImportItem(rel: "B/x.jpg", shot: t.addingTimeInterval(32 * 60), aspect: 1.5))                     // new subfolder
        let s = SceneGrouper.group(items)
        XCTAssertEqual(s.scenes.count, 3)
        XCTAssertTrue(s.bursts.allSatisfy { $0.ids.count <= 8 }); XCTAssertEqual(s.bursts.first?.ids.count, 8)
        XCTAssertEqual(s.scenes.last?.title, "B")
    }
    func test_R14_duplicateKey() {
        let a = ImportItem(rel: "A/1.jpg", size: 100, modified: Fixtures.day(9)), b = ImportItem(rel: "A/1.jpg", size: 100, modified: Fixtures.day(9))
        XCTAssertEqual(a.dedupeKey, b.dedupeKey)
    }
}

final class DecisionAndEditTests: XCTestCase {
    func test_R04_undoRedoExact_200Deep() {
        let d = DecisionStore(ids: (0..<300).map { "p\($0)" })
        for i in 0..<10 { d.mark("p\(i)", keep: true) }
        XCTAssertEqual(d.keptCount, 10)
        for _ in 0..<10 { d.undo() }; XCTAssertEqual(d.keptCount, 0)
        for _ in 0..<3 { d.redo() }; XCTAssertEqual(d.keptCount, 3)
        for i in 0..<250 { d.mark("p\(i)", keep: i % 2 == 0) }
        var n = 0; while d.canUndo { d.undo(); n += 1 }
        XCTAssertEqual(n, 200)
    }
    func test_R05_noHalfStates() {
        let d = DecisionStore(ids: ["a"]); d.mark("a", keep: true); d.mark("a", keep: false)
        XCTAssertEqual(d.keep["a"], false)
    }
    func test_burstFramesShareOneEdit() {
        let e = EditStore(shoot: .demo117)
        let g = e.shoot.bursts.first!; let ids = Array(g.ids.prefix(2))
        let dec = DecisionStore(ids: e.shoot.photos.map(\.id)); ids.forEach { dec.mark($0, keep: true) }
        e.set("ev", 0.5, on: ids[0], decisions: dec)
        XCTAssertEqual(e.look(ids[1], decisions: dec)["ev"], 0.5)
    }
    func test_R34_signatureStableAndSensitive() {
        let a = SaveSignature.make(fmt: .xmp, withEdits: true, kept: ["a", "b"], looks: ["a": ["ev": 0.5]])
        XCTAssertEqual(a, SaveSignature.make(fmt: .xmp, withEdits: true, kept: ["a", "b"], looks: ["a": ["ev": 0.5]]))
        XCTAssertNotEqual(a, SaveSignature.make(fmt: .jpeg, withEdits: true, kept: ["a", "b"], looks: ["a": ["ev": 0.5]]))
        XCTAssertNotEqual(a, SaveSignature.make(fmt: .xmp, withEdits: true, kept: ["a", "b"], looks: ["a": ["ev": 0.55]]))
        XCTAssertEqual(SaveSignature.make(fmt: .xmp, withEdits: false, kept: ["a"], looks: ["a": ["ev": 1]]),
                       SaveSignature.make(fmt: .xmp, withEdits: false, kept: ["a"], looks: [:]), "edits ignored when not included")
    }
}

final class KeyRouterTests: XCTestCase {
    func test_layersOwnTheKeyboard() {
        for layer in [Layer.crop, .variations, .help] {
            for k in ["x", "a", "0", ",", "."] {
                let r = KeyRouter.route(.init(k), layers: [.step(.edit), layer])
                XCTAssertNotEqual(r.handler, .step(.edit), "\(k) fell through \(layer) to the photo (R-24)")
            }
        }
        XCTAssertEqual(KeyRouter.route(.init("r"), layers: [.step(.edit)]).action, .explain("R keeps photos in Cull, so it does nothing here. To turn this photo: C, then R."))
        XCTAssertEqual(KeyRouter.route(.init("t"), layers: [.step(.edit)]).action, .none)
        XCTAssertEqual(KeyRouter.route(.init("r"), layers: [.step(.edit), .crop]).action, .rotate(1))
        XCTAssertEqual(KeyRouter.route(.init("x"), layers: [.step(.edit), .textField]).handler, .textField, "R-22")
    }
}

final class LayoutMathTests: XCTestCase {
    func test_R54_scale() {
        XCTAssertEqual(LayoutScale.scale(for: CGSize(width: 1100, height: 760)), 1)
        XCTAssertEqual(LayoutScale.scale(for: CGSize(width: 1280, height: 800)), 1)
        XCTAssertEqual(LayoutScale.scale(for: CGSize(width: 1440, height: 900)), 1.125)
        XCTAssertEqual(LayoutScale.scale(for: CGSize(width: 2560, height: 1440)), 1.5)
        XCTAssertEqual(LayoutScale.scale(for: CGSize(width: 3000, height: 600)), 1, "short and wide: no scale-up")
    }
    func test_R56_justifiedRows() {
        let aspects: [CGFloat] = [1.5, 1.5, 0.667, 1.78, 1, 1.5, 1.5, 2.2, 0.75, 1.5, 1.33]
        let rows = CullLayout.rows(aspects: aspects, width: 900, targetHeight: 110, gap: 6)
        for r in rows.dropLast() { XCTAssertEqual(r.tiles.map(\.width).reduce(0, +) + 6 * CGFloat(r.tiles.count - 1), 900, accuracy: 1) }
        for r in rows { XCTAssertTrue((0.8 * 110...1.25 * 110).contains(r.height)) }
        XCTAssertEqual(CullLayout.tileHeight(gridHeight: 1000), 115); XCTAssertEqual(CullLayout.tileHeight(gridHeight: 400), 80); XCTAssertEqual(CullLayout.tileHeight(gridHeight: 3000), 200)
    }
    func test_R41_R55_photoFitsTrueAspectAndTouches() {
        for (a, canvas) in [(1.5, CGSize(width: 1000, height: 700)), (0.667, CGSize(width: 1000, height: 700)), (40, CGSize(width: 800, height: 600)), (2.0 / 3000, CGSize(width: 800, height: 600))] {
            let r = EditLayout.photoRect(aspect: a, canvas: canvas, padding: 12)
            XCTAssertEqual(r.width / max(r.height, 0.0001), a, accuracy: a * 0.05)
            XCTAssertTrue(abs(r.width - (canvas.width - 24)) < 1 || abs(r.height - (canvas.height - 24)) < 1, "doesn’t touch on either axis")
            XCTAssertGreaterThanOrEqual(min(r.width, r.height), 1)
        }
    }

    /// Edit's frames are the prototype's (`Lumina Edit v19`: `pad`, `colGap`, `stripLbl`,
    /// `thumbH`, `factsOn`, `footH`), measured on the golden capture at 1100 × 760: canvas
    /// 13…835 × 53…642, photo 74…622 touching it across, filmstrip labels above 40pt thumbnails,
    /// no facts line under 860 tall, a 34pt footer across the window.
    func test_R55_editFrames_matchThePrototypeAt1100x760() {
        let f = EditLayout.frames(window: CGSize(width: 1100, height: 760), focus: false, controlsHidden: false, controlsCollapsed: false)
        XCTAssertEqual(f.controls, .side(width: 252))
        XCTAssertEqual(f.canvas.width, 822, accuracy: 1); XCTAssertEqual(f.canvas.height, 589, accuracy: 1)
        XCTAssertEqual(f.padTop, 11); XCTAssertEqual(f.padSide, 13); XCTAssertEqual(f.padBottom, 8); XCTAssertEqual(f.gap, 10)
        XCTAssertTrue(f.stripLabels); XCTAssertEqual(f.stripHeight, 40); XCTAssertEqual(f.stripRow, 66)
        XCTAssertEqual(f.factsRow, 0); XCTAssertEqual(f.footer, 34)
        let photo = EditLayout.photoRect(aspect: 1.5, canvas: f.canvas, padding: EditLayout.padding(canvas: f.canvas))
        XCTAssertEqual(photo.width, f.canvas.width, accuracy: 0.5, "the photo touches its canvas (no inner padding)")
        XCTAssertEqual(photo.height, 548, accuracy: 1)
        // While cropping the frame shrinks under the toolbar: 84 % of the room, centred below 48pt.
        let crop = EditLayout.cropFrameRect(aspect: 1.5, canvas: f.canvas, scale: 1)
        XCTAssertEqual(crop.minX, 78, accuracy: 2); XCTAssertEqual(crop.minY, 96, accuracy: 2)
        XCTAssertEqual(crop.width, 666, accuracy: 2); XCTAssertEqual(crop.height, 444, accuracy: 2)
    }

    func test_editFrames_labelsFactsFooterAndFocus() {
        func f(_ w: CGFloat, _ h: CGFloat) -> EditLayout.Frames {
            EditLayout.frames(window: CGSize(width: w, height: h), focus: false, controlsHidden: false, controlsCollapsed: false)
        }
        XCTAssertFalse(f(1099, 760).stripLabels); XCTAssertFalse(f(1100, 759).stripLabels)
        XCTAssertEqual(f(1100, 759).stripHeight, 32); XCTAssertEqual(f(1100, 759).footer, 26)
        XCTAssertEqual(f(1100, 859).factsRow, 0); XCTAssertGreaterThan(f(1100, 860).factsRow, 0)
        XCTAssertEqual(f(1400, 960).stripHeight, 56); XCTAssertEqual(f(1399, 960).stripHeight, 40)
        XCTAssertEqual(f(559, 800).stripRow, 0); XCTAssertEqual(f(800, 559).stripRow, 0)
        // The canvas keeps its 64pt (R-50) on the smallest shapes, controls under it and expanded.
        for (w, h) in [(320.0, 480.0), (375, 812), (600, 300), (3000, 600)] {
            XCTAssertGreaterThanOrEqual(f(w, h).canvas.height, 64, "\(w)×\(h)")
        }
        let focus = EditLayout.frames(window: CGSize(width: 1100, height: 760), focus: true, controlsHidden: false, controlsCollapsed: false)
        XCTAssertEqual(focus.canvas, CGSize(width: 1100, height: 760)); XCTAssertEqual(focus.footer, 0)
    }
}
