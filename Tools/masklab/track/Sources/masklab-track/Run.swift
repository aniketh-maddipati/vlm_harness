#if canImport(Vision) && canImport(AVFoundation)
import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import ImageIO
import MaskLabCore
import UniformTypeIdentifiers
import VideoToolbox

/// One tracker over one clip: frames before the start are decoded and dropped (so frame numbers
/// count from the clip's first frame, the way ffmpeg's `n` does), then every frame is tracked,
/// its mask written, and the clock read around each part.
func run(_ o: Options) async throws {
    let clip = URL(fileURLWithPath: o.clip)
    let out = URL(fileURLWithPath: o.out, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    if o.saveFramesEvery != nil {
        try FileManager.default.createDirectory(at: out.appendingPathComponent("frames"), withIntermediateDirectories: true)
    }

    let reader = try await FrameReader(url: clip, longEdge: o.proxy)
    let tracker: FrameTracker
    switch o.tracker {
    case .visionBox: tracker = VisionBoxTracker()
    case .visionInstance: tracker = VisionInstanceTracker()
    case .sam2: tracker = try await SAM2Tracker(modelDir: URL(fileURLWithPath: o.model!, isDirectory: true))
    }

    var index = 0
    while index < o.start {
        guard try reader.next() != nil else { throw UsageError("\(clip.lastPathComponent) has \(index) frames; --start \(o.start) is past its end") }
        index += 1
    }

    var timing = Timing(tracker: o.tracker, clip: clip.deletingPathExtension().lastPathComponent, startFrame: o.start,
                        prompt: o.prompt, proxy: [reader.size.width, reader.size.height],
                        source: [reader.source.width, reader.source.height],
                        model: o.model.map { URL(fileURLWithPath: $0).lastPathComponent }, device: deviceInfo())
    let started = Date()
    while true {
        let tDecode = Date()
        guard let frame = try reader.next() else { break }
        timing.decodeMs.append(msSince(tDecode))

        let tWork = Date()
        var mask: Mask
        do {
            mask = index == o.start ? try tracker.first(frame, prompt: o.prompt) : try tracker.next(frame)
        } catch {
            // One frame failing (Vision can throw on a lost track) is recorded as lost, not fatal.
            FileHandle.standardError.write(Data("masklab-track: frame \(index): \(error)\n".utf8))
            mask = Mask(width: reader.size.width, height: reader.size.height)
        }
        timing.perFrameMs.append(msSince(tWork))
        if mask.width != reader.size.width || mask.height != reader.size.height {
            mask = mask.resized(width: reader.size.width, height: reader.size.height)
        }
        if mask.isEmpty { timing.lost.append(index) }
        if timing.confidence != nil { timing.confidence!.append(tracker.confidence ?? 0) }

        try writePNG(mask, to: out.appendingPathComponent(frameName(index)))
        if let every = o.saveFramesEvery, (index - o.start) % every == 0 {
            try writeFrame(frame, to: out.appendingPathComponent("frames").appendingPathComponent(frameName(index)))
        }
        timing.frames += 1
        index += 1
        if let max = o.maxFrames, timing.frames >= max { break }
    }
    timing.totalMs = msSince(started)
    try timing.json().write(to: out.appendingPathComponent("timing.json"), options: .atomic)

    let fps = timing.totalMs > 0 ? Double(timing.frames) / (timing.totalMs / 1000) : 0
    print(String(format: "%@ %@: %d frames, %.1f fps, %d lost", o.tracker.rawValue, timing.clip, timing.frames, fps, timing.lost.count))
}

func msSince(_ t: Date) -> Double { Date().timeIntervalSince(t) * 1000 }

/// Decodes a clip's video track as 32BGRA at the proxy size. AVAssetReader scales during decode
/// when the output settings name a width and height, so no full-size 4K frame is kept.
/// The track's preferredTransform is not applied: the clips this was written for are landscape.
final class FrameReader {
    let reader: AVAssetReader
    let output: AVAssetReaderTrackOutput
    let source: (width: Int, height: Int)
    let size: (width: Int, height: Int)

    init(url: URL, longEdge: Int) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw UsageError("no video track in \(url.path)")
        }
        let natural = try await track.load(.naturalSize)
        let src = (width: Int(natural.width.rounded()), height: Int(natural.height.rounded()))
        let proxy = proxySize(width: src.width, height: src.height, longEdge: longEdge)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: proxy.width,
            kCVPixelBufferHeightKey as String: proxy.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw UsageError("can't decode the video track of \(url.lastPathComponent)") }
        reader.add(output)
        self.reader = reader; self.output = output; source = src; size = proxy
        guard reader.startReading() else {
            throw UsageError("can't read \(url.lastPathComponent): \(reader.error?.localizedDescription ?? "unknown error")")
        }
    }

    /// The next decoded frame, nil at the end of the track.
    func next() throws -> CVPixelBuffer? {
        while let sample = output.copyNextSampleBuffer() {
            if let image = CMSampleBufferGetImageBuffer(sample) { return image }
        }
        if reader.status == .failed { throw UsageError("decode failed: \(reader.error?.localizedDescription ?? "unknown error")") }
        return nil
    }
}

// ——— writing

func writePNG(_ m: Mask, to url: URL) throws {
    guard let provider = CGDataProvider(data: Data(m.pixels) as CFData),
          let image = CGImage(width: m.width, height: m.height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: m.width,
                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                              provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { throw UsageError("can't make a mask image") }
    try write(image, to: url)
}

/// A proxy frame as a PNG, the image a label for that frame is drawn on.
func writeFrame(_ frame: CVPixelBuffer, to url: URL) throws {
    var image: CGImage?
    VTCreateCGImageFromCVPixelBuffer(frame, options: nil, imageOut: &image)
    guard let image else { throw UsageError("can't convert frame for \(url.lastPathComponent)") }
    try write(image, to: url)
}

func write(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw UsageError("can't write \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw UsageError("can't write \(url.path)") }
}

func deviceInfo() -> Timing.Device {
    func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
    let chip = sysctl("machdep.cpu.brand_string") ?? "unknown chip"
    let model = sysctl("hw.model") ?? "unknown model"
    let p = ProcessInfo.processInfo
    return Timing.Device(model: "\(chip) (\(model))", os: p.operatingSystemVersionString,
                         cores: p.processorCount, memoryGB: Double(p.physicalMemory) / 1_073_741_824)
}
#endif
