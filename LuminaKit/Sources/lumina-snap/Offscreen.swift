import AppKit
import ImageIO
import SwiftUI
import LuminaCore
import LuminaUI

/// The window's content in a borderless window that is never ordered in: no window on screen,
/// no focus, no keys from the desktop. Laid out on demand and captured with `cacheDisplay`.
@MainActor
final class Offscreen {
    let size: CGSize
    private let host: NSView
    private let window: NSWindow

    init(model: AppModel, size: CGSize) {
        self.size = size
        host = NSHostingView(rootView: AppShell(model: model).frame(width: size.width, height: size.height))
        window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
    }

    /// The run loop turns for `seconds` (0 = one short turn) and the view is laid out again.
    func pump(_ seconds: TimeInterval) {
        GoldenDriver.turnRunLoop(seconds)
        host.layoutSubtreeIfNeeded()
    }

    /// Lets picture decodes and onAppear work land: real time, with the virtual clock moving along.
    func settle(_ seconds: TimeInterval, clock: TestScheduler) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)); clock.advance(0.02) }
        host.layoutSubtreeIfNeeded()
    }

    /// The view at `scale` pixels per point. The pixels are tagged sRGB: the tokens are sRGB
    /// values and the device-RGB bitmap holds them unconverted.
    func capture(scale: Double) -> CGImage? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let cg = rep.cgImage else { return nil }
        return CGColorSpace(name: CGColorSpace.sRGB).flatMap { cg.copy(colorSpace: $0) } ?? cg
    }

    func close() { window.contentView = nil; window.close() }
}

enum PNG {
    static func write(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }

    static func read(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
