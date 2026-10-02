import XCTest

/// Layout, sizing and fill (R-50…R-59), labels and copy (R-52, R-53). Ports "layout", "zoomresize",
/// "labels", "tokens" and "stretch"/"resizeStorm" from the HTML suites, plus the native sizing rules.
final class LayoutAndSizingTests: XCTestCase {
    var l: Lumina!
    override func setUp() { continueAfterFailure = true; l = Lumina().launch(); l.startCulling(); l.keepN(6) }
    override func tearDown() { assertNoErrors(l); l.app.terminate() }

    static let allSizes: [CGSize] = [
        .init(width: 320, height: 480), .init(width: 375, height: 812), .init(width: 600, height: 300),
        .init(width: 480, height: 800), .init(width: 700, height: 560), .init(width: 860, height: 600),
        .init(width: 1100, height: 760), .init(width: 1024, height: 1366), .init(width: 1440, height: 900),
        .init(width: 1920, height: 1080), .init(width: 2560, height: 1440), .init(width: 3000, height: 600),
        .init(width: 400, height: 1600)]
    let steps = ["open", "cull", "edit", "save"]
    let mainAction = ["open": "open.card", "cull": "cull.toSave", "save": "save.button"]

    func expectedScale(_ s: CGSize) -> Double { min(1.5, max(1.0, min(Double(s.width) / 1280, Double(s.height) / 800))) }

    /// R-50, R-51
    func test_R50_everyWindowShape_noSidewaysScroll_tabsAndMainActionVisible() {
        for size in Self.allSizes {
            l.resize(size.width, size.height)
            for (i, step) in steps.enumerated() {
                l.go(i + 1, settle: step == "edit" ? 1.0 : 0.4)
                let tag = "\(Int(size.width))×\(Int(size.height)) \(step)"
                XCTAssertFalse(l.hasHorizontalScroll(), "\(tag): sideways scroll")
                for t in steps { XCTAssertTrue(l.visible(l.el("step.\(t)")), "\(tag): tab \(t) cut off") }
                if let m = mainAction[step] { XCTAssertTrue(l.visible(l.el(m)), "\(tag): main action unreachable") }
                if step == "edit" { let f = l.el("edit.photo").frame; XCTAssertTrue(f.width >= 40 && f.height >= 40, "\(tag): photo \(f.size)") }
                for b in l.app.buttons.allElementsBoundByIndex where b.isHittable {
                    XCTAssertGreaterThanOrEqual(b.frame.minX, l.window.frame.minX - 1, "\(tag): \(b.identifier) off the left edge")
                    XCTAssertLessThanOrEqual(b.frame.maxX, l.window.frame.maxX + 1, "\(tag): \(b.identifier) off the right edge")
                }
            }
        }
    }

    /// R-54: nothing small, and big windows scale chrome up.
    func test_R54_nothingSmall_andChromeScalesOnBigWindows() {
        var tabH: [Double: CGFloat] = [:]
        for size in Self.allSizes {
            l.resize(size.width, size.height)
            for (i, step) in steps.enumerated() {
                l.go(i + 1, settle: step == "edit" ? 1.0 : 0.4)
                let m = l.metrics, S = expectedScale(size), tag = "\(Int(size.width))×\(Int(size.height)) \(step)"
                XCTAssertEqual(m.scale, S, accuracy: 0.01, "\(tag): UI scale")
                XCTAssertGreaterThanOrEqual(m.minFontPt, 11 * S - 0.25, "\(tag): text below 11pt×S")
                XCTAssertGreaterThanOrEqual(m.bodyFontPt, 13 * S - 0.25, "\(tag): body below 13pt×S")
                for b in l.app.buttons.allElementsBoundByIndex where b.isHittable && !b.identifier.hasPrefix("debug.") && !b.identifier.hasPrefix("_XCUI:") {
                    let minH: CGFloat = b.identifier.hasPrefix("step.") || b.identifier.hasPrefix("cull.keepSuggested") ? 24 : 28
                    XCTAssertGreaterThanOrEqual(b.frame.height, minH * CGFloat(S) - 1, "\(tag): \(b.identifier) only \(b.frame.height)pt high")
                }
                for id in ["open.card", "cull.keep", "cull.out", "save.button"] where l.el(id).isHittable {
                    XCTAssertGreaterThanOrEqual(l.el(id).frame.height, 34 * CGFloat(S) - 1, "\(tag): primary \(id) too small")
                }
                if step == "cull" { tabH[S] = l.el("step.cull").frame.height }
            }
        }
        if let a = tabH[1.0], let b = tabH[1.5] { XCTAssertEqual(Double(b / a), 1.5, accuracy: 0.06, "R-54 chrome didn’t scale on a big window") }
    }

    /// R-55: Edit photo fills its canvas.
    func test_R55_editPhotoFillsCanvas() {
        for size in Self.allSizes where size.width >= 480 {
            l.resize(size.width, size.height); l.go(3, settle: 1.2)
            let c = l.el("edit.canvas").frame, p = l.el("edit.photo").frame, tag = "\(Int(size.width))×\(Int(size.height))"
            let gapX = (c.width - p.width) / 2, gapY = (c.height - p.height) / 2
            XCTAssertTrue(min(gapX, gapY) <= 12.5, "\(tag): photo doesn’t reach the canvas on either axis (gaps \(gapX), \(gapY))")
            if size.width >= 1440 && size.height >= 900 {
                let share = (c.width * c.height) / (l.window.frame.width * l.window.frame.height)
                XCTAssertGreaterThanOrEqual(share, 0.70, "\(tag): canvas only \(Int(share * 100))% of the window")
            }
        }
        l.key("h"); l.pause(0.3)
        XCTAssertEqual(l.el("edit.canvas").frame.size.width, l.window.frame.width, accuracy: 2, "focus mode isn’t edge to edge")
    }

    /// R-56: Cull rows are justified and tiles grow with the window.
    func test_R56_cullRowsJustified_tilesScaleWithWindow() {
        for size in Self.allSizes where size.width >= 600 {
            l.resize(size.width, size.height); l.go(2, settle: 0.5)
            let m = l.metrics, grid = l.el("cull.grid").frame, tag = "\(Int(size.width))×\(Int(size.height))"
            for r in m.rows ?? [] where !r.last { XCTAssertEqual(r.width, r.gridWidth, accuracy: 2, "\(tag): scene \(r.scene) row ragged") }
            if let th = m.tileH { XCTAssertGreaterThanOrEqual(th, min(200, 0.10 * Double(grid.height)) - 1, "\(tag): tiles too small (\(th)pt)") }
        }
    }

    /// R-57, R-58: no dead bands on Open/Save; the Cull preview fills its column.
    func test_R57_R58_noDeadBands() {
        for size in Self.allSizes where size.width >= 600 {
            l.resize(size.width, size.height)
            let W = l.window.frame, tag = "\(Int(size.width))×\(Int(size.height))"
            XCTAssertLessThanOrEqual(l.el("step.cull").frame.minY - W.minY, 28, "\(tag): toolbar/title gap above the tabs")
            for (n, first, last) in [(1, "open.card", "open.openFolder"), (4, "save.summary", "save.button")] {
                l.go(n, settle: 0.4)
                let top = l.el(first).frame.minY - l.el("step.cull").frame.maxY, below = W.maxY - l.el(last).frame.maxY
                XCTAssertLessThanOrEqual(top, 72 + 40, "\(tag): \(top)pt dead band above the content")
                if below > 0 { XCTAssertLessThanOrEqual(top, below + 40, "\(tag): more empty space above than below") }
                XCTAssertGreaterThanOrEqual(l.el(first).frame.width, min(0.46 * W.width, 760 * CGFloat(expectedScale(size))) - 40, "\(tag): column too narrow")
            }
            if size.width >= 900 {
                l.go(2, settle: 0.4); l.click("cull.tile.\(l.state.cur ?? "")")
                let col = l.el("cull.preview").frame
                XCTAssertGreaterThanOrEqual(col.width, 300 - 1); XCTAssertLessThanOrEqual(col.width, W.width * 0.5 + 1, "\(tag): preview column too wide")
            }
        }
    }

    /// R-59: scale changes smoothly.
    func test_R59_scaleIsSmooth() {
        var prev: CGFloat?
        for w in stride(from: 1440, through: 2560, by: 20) {
            l.resize(CGFloat(w), CGFloat(w) * 900 / 1440, settle: 0.15)
            let h = l.el("step.cull").frame.height
            if let p = prev { XCTAssertLessThanOrEqual(abs(h - p), 2, "jump at \(w)pt wide") }
            prev = h
        }
    }

    /// R-43
    func test_R43_resizeWhileZoomed_photoStaysVisible() {
        l.go(3, settle: 1.2); l.key("z"); l.pause(0.3)
        for s in [CGSize(width: 800, height: 600), CGSize(width: 1300, height: 820), CGSize(width: 1100, height: 760)] { l.resize(s.width, s.height) }
        let f = l.el("edit.photo").frame
        XCTAssertTrue(f.width >= 40 && f.height >= 40, "photo \(f.size) after resizing while zoomed")
        XCTAssertTrue((0.25...8).contains(l.state.zoom))
    }

    /// Burst of 80 resizes while editing.
    func test_resizeStorm_whileEditing() {
        l.go(3, settle: 1.0)
        for _ in 0..<80 { l.resize(CGFloat(Int.random(in: 360...1960)), CGFloat(Int.random(in: 320...1220)), settle: 0.016) }
        l.resize(1100, 760, settle: 0.4)
        XCTAssertGreaterThanOrEqual(l.el("edit.photo").frame.width, 40)
    }

    /// R-52
    func test_R52_everyControlLabelled() {
        for n in 1...4 {
            l.go(n, settle: n == 3 ? 1.1 : 0.45)
            let q = l.app.descendants(matching: .any).matching(NSPredicate(format: "elementType IN %@", [XCUIElement.ElementType.button, .radioButton, .slider, .checkBox, .tab, .menuItem].map { $0.rawValue }))
            for e in q.allElementsBoundByIndex where e.isHittable && !e.identifier.hasPrefix("debug.") && !e.identifier.hasPrefix("_XCUI:") {
                XCTAssertFalse(e.label.isEmpty && (e.title.isEmpty) && ((e.value as? String) ?? "").isEmpty, "step \(n): unlabelled \(e.identifier)")
            }
        }
    }

    /// R-53
    func test_R53_noBrokenCopy() {
        for n in 1...4 {
            l.go(n, settle: n == 3 ? 1.1 : 0.45)
            let all = l.app.staticTexts.allElementsBoundByIndex.map { $0.label + " " + (($0.value as? String) ?? "") }.joined(separator: " ")
            for bad in ["undefined", "NaN", "{{", "[object", "Optional(", " nil "] { XCTAssertFalse(all.contains(bad), "step \(n) shows “\(bad)”") }
        }
    }
}
