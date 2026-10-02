import Foundation
import CoreGraphics
import ImageIO

// WP-0. The golden screenshots' states as data, and the driver that walks a model to one of them.
//
// `design/handoff/lumina-app/parity/capture/capture-goldens.mjs` renders 28 states × 4 sizes from
// the prototype; `LuminaUITests/Native/GoldenSnapshotTests.swift` (`States`) reaches the same
// states in the real window. This table is those steps once more, as data, so they run headless:
// `lumina-snap --golden <state>` renders a state offscreen and diffs it with its golden, and
// `ParityKitTests` checks every state still lands where it should. Names are the script's, one to
// one, in its order. When the script or `States` changes, change this table with it.
//
// Time is the virtual clock's (`TestScheduler`), except where something really runs off the main
// thread (an import, a save): there the driver lets the run loop turn, in real time, until it is done.

/// One thing a golden state does on the way. Keys use KeyRouter's spelling.
public enum GoldenStep: Equatable, Sendable {
    /// Pressed and released ("r", ".", "]", "shift+/", "cmd+3", "return"), then 50 ms.
    case key(String)
    /// Pressed and held: no release (Variations' V held open the grid).
    case hold(String)
    /// Time passes on the virtual clock.
    case wait(TimeInterval)
    /// ⌘1…4, then `settle` seconds.
    case go(Int, settle: TimeInterval)
    /// ⏎ on Open, the whole card copied, then 300 ms (the UI tests' `startCulling`).
    case startCulling
    /// ⏎ on Open without waiting for the copy.
    case enter
    /// Virtual time passes (at most 5 s) until more than this many photos are copied.
    case copiedMoreThan(Int)
    /// What a click on the element with this accessibility identifier does.
    case click(String)
    /// A drag carrying files enters the window (`shell.dropOverlay`).
    case dragEnter
    /// A fault from now on (the UI tests' `{"injectFault":…}`).
    case fault(String)
    /// A fixture folder dropped on the window; waits until it has been imported.
    case drop(GoldenFixture)
}

/// The folders the import states drop (the UI tests' `Fixtures`, the script's `importFiles`).
public enum GoldenFixture: String, Sendable {
    /// a.jpg and b.jpg, a clip and a text file: "2 added, 2 skipped".
    case cardDump = "Card dump"
    /// Nothing that is a photo: "nothing added".
    case onlyJunk = "Docs"

    /// Writes the folder afresh under `root` and returns it.
    public func write(under root: URL = FileManager.default.temporaryDirectory.appendingPathComponent("lumina-golden-fixtures")) throws -> URL {
        let dir = root.appendingPathComponent(rawValue), fm = FileManager.default
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        switch self {
        case .cardDump:
            try Self.jpeg(dir.appendingPathComponent("a.jpg"), seed: 1)
            try Self.jpeg(dir.appendingPathComponent("b.jpg"), seed: 2)
            try Self.bytes(4).write(to: dir.appendingPathComponent("clip.mp4"))
            try Data("hi".utf8).write(to: dir.appendingPathComponent("notes.txt"))
        case .onlyJunk:
            try Data("x".utf8).write(to: dir.appendingPathComponent("readme.txt"))
            try Self.bytes(900, header: Array("%PDF".utf8)).write(to: dir.appendingPathComponent("invoice.pdf"))
            try Self.bytes(900).write(to: dir.appendingPathComponent("movie.mov"))
        }
        return dir
    }

    /// The same picture as the UI tests' `Fixtures.image`: a flat colour from the seed, a white block.
    static func jpeg(_ url: URL, w: Int = 640, h: Int = 420, seed: Int) throws {
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
        let hue = CGFloat((seed * 47) % 360) / 360
        ctx.setFillColor(CGColor(red: hue, green: 0.5, blue: 1 - hue, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.8)); ctx.fill(CGRect(x: w / 10, y: h / 10, width: max(1, w / 5), height: max(1, h / 5)))
        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyOrientation: 1] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }

    static func bytes(_ n: Int, header: [UInt8] = []) -> Data {
        var d = Data(header); d.append(Data((0..<max(0, n - header.count)).map { UInt8(($0 * 131 + 7) & 255) })); return d
    }
}

/// The capture sizes (`SIZES` in capture-goldens.mjs): points and the device pixel ratio.
public struct GoldenSize: Hashable, Sendable {
    public let id: String
    public let width: Double, height: Double
    public let dpr: Double
    public var size: CGSize { CGSize(width: width, height: height) }

    public static let all: [GoldenSize] = [
        GoldenSize(id: "1100x760", width: 1100, height: 760, dpr: 2),
        GoldenSize(id: "1440x900", width: 1440, height: 900, dpr: 2),
        GoldenSize(id: "2560x1440", width: 2560, height: 1440, dpr: 1),
        GoldenSize(id: "480x800", width: 480, height: 800, dpr: 2),
    ]

    /// "1100x760" → the capture size; any other "WxH" at 2x.
    public static func named(_ id: String) -> GoldenSize? {
        if let s = all.first(where: { $0.id == id }) { return s }
        let p = id.split(separator: "x").compactMap { Double($0) }
        guard p.count == 2, p[0] > 0, p[1] > 0 else { return nil }
        return GoldenSize(id: id, width: p[0], height: p[1], dpr: 2)
    }
}

/// How a shot is compared.
public enum GoldenCompare: String, Sendable {
    /// Pixel for pixel: the native UI should match within the manifest's tolerance (2 % of pixels over 16/255).
    case pixel
    /// The native scale differs from the prototype's at this size (AGENTS.md, ruled 2026-10-02:
    /// S = clamp(1, min(w/1280, h/800), 1.5)): diffed and reported, never gated.
    case scaled
    /// LAYOUT_SIZING overrides the prototype (every Cull state, every 2560×1440 shot): compared by eye.
    case layout

    public static func of(state: String, size: GoldenSize) -> GoldenCompare {
        if size.id == "2560x1440" || state.hasPrefix("cull-") { return .layout }
        // The prototype's chrome is at 1× below 1440×900; ours grows sooner.
        return LayoutScale.scale(for: size.size) == 1 ? .pixel : .scaled
    }
}

/// One golden state: how to reach it and where it must land.
public struct GoldenState: Sendable {
    public let name: String
    public let steps: [GoldenStep]
    /// Faults from launch (the UI tests' `States.faults`).
    public var faults: [String] = []
    /// The first-run intro shows on entering Edit (`LUMINA_INTRO=show`).
    public var intro = false
    /// Real seconds for pictures to load once the view is up (the clock moves with them).
    public var settle: TimeInterval = 0.6
    /// Where it must land: a state that doesn't is reported, not rendered as if it were right.
    public let step: Step
    public var overlay: Overlay?

    public init(_ name: String, _ steps: [GoldenStep], step: Step, overlay: Overlay? = nil, faults: [String] = [], intro: Bool = false, settle: TimeInterval = 0.6) {
        self.name = name; self.steps = steps; self.step = step; self.overlay = overlay
        self.faults = faults; self.intro = intro; self.settle = settle
    }
}

extension Array where Element == GoldenStep {
    /// These steps, then more.
    func then(_ more: GoldenStep...) -> [GoldenStep] { self + more }
}

public enum GoldenStates {
    /// The card copied and ten decisions (the script's `keepSome`, the UI tests' `kept`).
    static let kept: [GoldenStep] = [GoldenStep.startCulling] + ["r", "r", "x", "r", "x", "r", "r", "r", "x", "r"].flatMap { [GoldenStep.key($0), GoldenStep.wait(0.04)] }
    static let toEdit: [GoldenStep] = kept.then(.go(3, settle: 1.4))
    /// Every photo decided: X, R, R, X, R, R…
    static let allDecided: [GoldenStep] = [GoldenStep.startCulling] + (0..<117).map { GoldenStep.key($0 % 3 == 0 ? "x" : "r") }
    static let allOut: [GoldenStep] = [GoldenStep.startCulling] + (0..<117).map { _ in GoldenStep.key("x") }
    static let edited: [GoldenStep] = toEdit + [".", ".", ".", "]", ".", "."].map { GoldenStep.key($0) }

    /// capture-goldens.mjs `STATES`, in its order.
    public static let all: [GoldenState] = [
        GoldenState("open-empty", [], step: .open),
        GoldenState("open-copying", [.enter, .copiedMoreThan(20), .go(1, settle: 0.3)], step: .open),
        GoldenState("open-recent", kept.then(.go(1, settle: 0.6)), step: .open),
        GoldenState("open-startover-armed", kept.then(.go(1, settle: 0.6), .click("open.startOver")), step: .open),
        GoldenState("open-import-message", [.drop(.cardDump), .go(1, settle: 0.6)], step: .open),
        GoldenState("open-import-nothing", [.drop(.onlyJunk)], step: .open),
        GoldenState("drop-overlay", [.startCulling, .dragEnter], step: .cull),
        GoldenState("cull-empty", [.go(2, settle: 0.6)], step: .cull),
        GoldenState("cull-copying", [.enter, .copiedMoreThan(30)], step: .cull),
        GoldenState("cull-mid", kept, step: .cull),
        GoldenState("cull-all-decided", allDecided, step: .cull),
        GoldenState("edit-empty", [.startCulling, .go(3, settle: 1.4)], step: .edit),
        GoldenState("edit-intro", toEdit, step: .edit, overlay: .intro, intro: true, settle: 1.0),
        GoldenState("edit-loaded", toEdit, step: .edit, settle: 1.0),
        GoldenState("edit-edited", edited, step: .edit, settle: 1.0),
        GoldenState("edit-help", toEdit.then(.key("shift+/")), step: .edit, overlay: .help, settle: 1.0),
        GoldenState("edit-variations", toEdit.then(.hold("v"), .wait(0.9)), step: .edit, overlay: .variations, settle: 1.0),
        GoldenState("edit-crop", toEdit.then(.key("c")), step: .edit, overlay: .crop, settle: 1.0),
        GoldenState("edit-zoom-1to1", toEdit.then(.key("z"), .wait(0.9)), step: .edit, settle: 1.2),
        GoldenState("edit-focus", toEdit.then(.key("h")), step: .edit, settle: 1.0),
        GoldenState("edit-colour", toEdit.then(.click("edit.section.colour")), step: .edit, settle: 1.0),
        GoldenState("edit-effects", toEdit.then(.click("edit.section.effects")), step: .edit, settle: 1.0),
        GoldenState("edit-loadfail", kept.then(.go(3, settle: 2.9)), step: .edit, faults: ["imageLoadFail"], settle: 1.5),
        GoldenState("edit-storage-warning", toEdit.then(.fault("storageFull"), .key("."), .key("."), .wait(0.8)), step: .edit, settle: 1.0),
        GoldenState("save-ready", toEdit.then(.key("."), .go(4, settle: 0.6)), step: .save),
        GoldenState("save-saved", kept.then(.go(4, settle: 0.6), .click("save.button")), step: .save),
        GoldenState("save-changed", kept.then(.go(4, settle: 0.6), .click("save.button"), .click("save.format.jpeg")), step: .save),
        GoldenState("save-nothing", allOut.then(.go(4, settle: 1.6)), step: .save),
    ]

    public static func named(_ name: String) -> GoldenState? { all.first { $0.name == name } }
}

/// Walks a fresh model to a golden state on a virtual clock. `pump` is called after every step
/// and through every wait with the real seconds to let pass (0 = one turn of the run loop): the
/// offscreen renderer lays its view out there, so the work views start (picture loads, the
/// canvas's 1:1 factor, the intro) happens on the way, as in the app.
@MainActor
public final class GoldenDriver {
    public let model: AppModel
    public let clock: TestScheduler
    public let state: GoldenState
    public var pump: @MainActor (TimeInterval) -> Void = { GoldenDriver.turnRunLoop($0) }

    /// A fresh window's model for `state`: the demo card at the UI tests' copy rate, memory
    /// storage, a recording exporter, the state's faults (and no others), the intro only when asked.
    public init(_ state: GoldenState, window: CGSize) {
        self.state = state
        Faults.shared.clearAll(); ErrorFunnel.reset()
        for f in state.faults.compactMap(Fault.init) { Faults.shared.inject(f) }
        var config = LaunchConfig(arguments: [], environment: ["LUMINA_CARD": "demo117", "LUMINA_COPY_RATE": "66", "LUMINA_INTRO": state.intro ? "show" : "skip"])
        config.window = window
        clock = TestScheduler()
        model = AppModel.launch(config: config, services: Services(images: DefaultImageProvider(), exporter: RecordingExporter(), persistence: MemoryPersistence()), clock: clock)
        model.windowSize = window
        // Never the user's defaults: "seen" lives in memory, and only the intro state hasn't seen it.
        model.overlays.intro = .memory(seen: !state.intro)
        model.overlays.introForced = state.intro
    }

    /// Runs every step. Returns what went wrong: a step that could not be done, or a landing
    /// somewhere else than the state says. Empty = the state was reached.
    @discardableResult
    public func run() -> [String] {
        var problems: [String] = []
        pump(0)
        for s in state.steps { if let p = perform(s) { problems.append(p) } }
        if model.step != state.step { problems.append("landed on \(model.step.rawValue), not \(state.step.rawValue)") }
        if model.edit.overlay != state.overlay, model.step == .edit || state.overlay != nil {
            problems.append("overlay \(model.edit.overlay?.rawValue ?? "none"), not \(state.overlay?.rawValue ?? "none")")
        }
        return problems
    }

    private func perform(_ step: GoldenStep) -> String? {
        switch step {
        case .key(let spec): press(spec, release: true); advance(0.05)
        case .hold(let spec): press(spec, release: false); advance(0.05)
        case .wait(let s): advance(s)
        case .go(let n, let settle):
            press("cmd+\(n)", release: true)
            advance(settle)
            pump(min(settle, 0.3))
            // The overlay view offers the intro when Edit comes on screen; headless there is no view.
            if model.step == .edit { model.introOpenIfFirstRun() }
        case .startCulling:
            press("return", release: true)
            advance(Double(model.total) / (model.config.copyRate ?? 66) + 1)
            guard model.copied >= model.total else { return "the copy never finished (\(model.copied) of \(model.total))" }
            advance(0.3)
        case .enter: press("return", release: true); advance(0.05)
        case .copiedMoreThan(let n):
            var t = 0.0
            while model.copied <= n, t < 5 { advance(0.05); t += 0.05 }
            guard model.copied > n else { return "only \(model.copied) copied after 5 s" }
        case .click(let id): return click(id)
        case .dragEnter: model.dropHover(true); pump(0)
        case .fault(let name):
            guard let f = Fault(name) else { return "no fault \(name)" }
            Faults.shared.inject(f)
        case .drop(let fixture):
            let url: URL
            do { url = try fixture.write() } catch { return "fixture \(fixture.rawValue): \(error)" }
            model.dropFiles([url])
            guard untilReal(30, { !self.model.imports.busy }) else { return "import of \(fixture.rawValue) still busy after 30 s" }
            advance(0.05)
        }
        return nil
    }

    /// The model calls behind the controls the states click.
    private func click(_ id: String) -> String? {
        if id == "open.startOver" { model.startOverClick() }
        else if id == "save.button" {
            model.saveNow()
            guard untilReal(10, { !self.model.save.saving }) else { return "the save never finished" }
        }
        else if id.hasPrefix("edit.section."), let s = EditSection(rawValue: String(id.dropFirst("edit.section.".count))) { model.setSection(s) }
        else if id.hasPrefix("save.format."), let f = SaveFormat(rawValue: String(id.dropFirst("save.format.".count))) { model.setFormat(f) }
        else { return "no click for \(id)" }
        advance(0.2)
        return nil
    }

    /// "r", "cmd+3", "shift+/", "cmd+shift+z", "+" (the Harness's spelling).
    private func press(_ spec: String, release: Bool) {
        var parts = spec.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        var k = parts.removeLast(); if k.isEmpty { k = "+" }
        var m: KeyModifiers = []
        if parts.contains("cmd") { m.insert(.command) }; if parts.contains("shift") { m.insert(.shift) }; if parts.contains("alt") { m.insert(.option) }
        model.handle(KeyEvent(k, m))
        if release { model.handle(KeyEvent(k, m, phase: .up)) }
    }

    /// Virtual time, in 50 ms slices, the view laid out after each.
    private func advance(_ seconds: TimeInterval) {
        var left = seconds
        while left > 1e-9 { let d = min(0.05, left); clock.advance(d); left -= d; pump(0) }
    }

    /// Real time: the run loop turns until `done` (an import or a save off the main thread).
    private func untilReal(_ timeout: TimeInterval, _ done: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while !done(), Date() < end { pump(0.02) }
        return done()
    }

    /// Lets the main run loop (and with it the main queue) turn for `seconds`; 0 = one short turn.
    nonisolated public static func turnRunLoop(_ seconds: TimeInterval) {
        guard seconds > 0 else { RunLoop.current.run(mode: .default, before: Date()); return }
        let end = Date().addingTimeInterval(seconds)
        repeat { RunLoop.current.run(mode: .default, before: min(end, Date().addingTimeInterval(0.01))) } while Date() < end
    }
}
