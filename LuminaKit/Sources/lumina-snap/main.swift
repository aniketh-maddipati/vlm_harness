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

var args = Array(CommandLine.arguments.dropFirst())
func opt(_ name: String) -> String? { args.firstIndex(of: name).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
let size: CGSize = { let p = (opt("--size") ?? "1100x760").split(separator: "x").compactMap { Double($0) }; return CGSize(width: p[0], height: p[1]) }()
let out = opt("--out") ?? "lumina-snap.png", scale = Double(opt("--scale") ?? "2") ?? 2, settle = Double(opt("--settle") ?? "0.6") ?? 0.6

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
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

    let host = NSHostingView(rootView: AppShell(model: model).frame(width: size.width, height: size.height))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    // Let image decodes and onAppear work land.
    let end = Date().addingTimeInterval(settle)
    while Date() < end { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)); clock.advance(0.02) }
    host.layoutSubtreeIfNeeded()

    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    host.cacheDisplay(in: host.bounds, to: rep)
    do { try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out)); print("wrote \(out)") }
    catch { FileHandle.standardError.write(Data("lumina-snap: \(error)\n".utf8)); exit(1) }
}
