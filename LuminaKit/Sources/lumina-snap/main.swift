import AppKit
import SwiftUI
import LuminaCore
import LuminaUI

// Renders the native UI to a PNG without showing a window or taking focus, so a screen can be
// looked at (and compared with the prototype) from a terminal:
//
//   swift run lumina-snap --out /tmp/cull.png [--size 1100x760] [--card demo117] [--scale 2]
//       [--keys "return,wait:2500,r,r,x,cmd+3,wait:300,."] [--settle 0.6] [--fault imageLoadFail] [--state]
//
// Keys are KeyRouter names ("return", "escape", "left", "cmd+3", "shift+.", "down:v", "up:v");
// "wait:<ms>" advances the virtual clock (the card copy finishes in about 1800 ms at the default rate).
// --state prints debug.state after the keys.
//
// Golden parity, headless (the states of parity/capture/capture-goldens.mjs, `GoldenStates`):
//
//   swift run lumina-snap --golden <state|a,b,…|all|list> [--size 1100x760] [--goldens ~/LuminaEvidence/native-ui/goldens]
//       [--out-dir /tmp/goldens/1100x760] [--scale <the golden's dpr>] [--settle <extra seconds>]
//
// renders each state, diffs it with <goldens>/<size>/<state>.png and prints one line per state and
// a summary (see GoldenRun.swift). Bash: Tests/runner/run.sh goldens 1100x760.

var args = Array(CommandLine.arguments.dropFirst())
func opt(_ name: String) -> String? { args.firstIndex(of: name).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
func expand(_ path: String) -> URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)

    if let spec = opt("--golden") {
        let sizeID = opt("--size") ?? "1100x760"
        let outDir = opt("--out-dir").map(expand) ?? FileManager.default.temporaryDirectory.appendingPathComponent("lumina-goldens/\(sizeID)")
        exit(GoldenRun.main(spec: spec, sizeID: sizeID, goldens: opt("--goldens").map(expand) ?? GoldenRun.defaultGoldens, outDir: outDir,
                            scale: opt("--scale").flatMap(Double.init), extraSettle: opt("--settle").flatMap(Double.init) ?? 0))
    }

    let size: CGSize = { let p = (opt("--size") ?? "1100x760").split(separator: "x").compactMap { Double($0) }; return CGSize(width: p[0], height: p[1]) }()
    let out = opt("--out") ?? "lumina-snap.png", scale = Double(opt("--scale") ?? "2") ?? 2, settle = Double(opt("--settle") ?? "0.6") ?? 0.6

    var config = LaunchConfig(arguments: [], environment: ["LUMINA_CARD": opt("--card") ?? "demo117", "LUMINA_INTRO": opt("--intro") ?? "skip"])
    config.window = size
    if let f = opt("--fault").flatMap(Fault.init) { Faults.shared.inject(f) }
    let clock = TestScheduler()
    let services = Services(images: DefaultImageProvider(), exporter: RecordingExporter(), persistence: MemoryPersistence())
    let model = AppModel.launch(config: config, services: services, clock: clock)
    model.windowSize = size

    for token in (opt("--keys") ?? "").split(separator: ",").map(String.init) where !token.isEmpty {
        if token.hasPrefix("wait:") { clock.advance((Double(token.dropFirst(5)) ?? 0) / 1000); continue }
        var parts = token.split(separator: "+").map(String.init), phase = KeyEvent.Phase.down
        var key = parts.removeLast()
        if key.hasPrefix("down:") { key = String(key.dropFirst(5)) } else if key.hasPrefix("up:") { key = String(key.dropFirst(3)); phase = .up }
        var m: KeyModifiers = []
        if parts.contains("cmd") { m.insert(.command) }; if parts.contains("shift") { m.insert(.shift) }; if parts.contains("alt") { m.insert(.option) }
        model.handle(KeyEvent(key, m, phase: phase))
        clock.advance(0.05)
    }
    if args.contains("--state") { print(model.debugStateJSON) }

    let screen = Offscreen(model: model, size: size)
    // Let image decodes and onAppear work land.
    screen.settle(settle, clock: clock)
    guard let image = screen.capture(scale: scale) else { FileHandle.standardError.write(Data("lumina-snap: nothing captured\n".utf8)); exit(1) }
    do { try PNG.write(image, to: URL(fileURLWithPath: out)); print("wrote \(out)") }
    catch { FileHandle.standardError.write(Data("lumina-snap: \(error)\n".utf8)); exit(1) }
}
