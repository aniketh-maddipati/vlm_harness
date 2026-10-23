import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import VideoToolbox

/// Skim's `lumina.video.remove`: a followed shape taken out of a still-camera clip as a **patch** for Final Cut. The
/// patch is a ProRes 4444 movie with alpha, at the clip's own size and length, transparent except where the shape is,
/// which holds the clean plate there (`SkimPlate`: the median of the clip's own frames where the shape is not). The
/// .fcpxml connects it above its clip, so in Final Cut the shape is gone and turning the patch off brings it back.
/// The clip itself is never touched. Written as a new file in the folder Export saves into, next to the .fcpxml and
/// never on a card, then opened again to check it.
nonisolated enum SkimPatch {
    struct Request: Sendable {
        var name: String
        var frames: Int
        var frameLength: (n: Int, d: Int)
        var samples: [SkimFollow.Sample]
        var grow: Double
        var soft: Double
    }

    /// What the page asks for (the clip's name, its length in frames and the length of one, the edge), with the
    /// followed frames of the Mac's track it names.
    static func request(_ body: [String: Any], tracked: [SkimFollow.Sample]) -> Request? {
        guard let clip = body["name"] as? String, let name = SkimPlate.patchName(clip: clip),
              let n = (body["frames"] as? NSNumber)?.intValue, n > 0, n <= SkimFollow.maxFrames,
              let fd = SkimFollow.frameLength(body["fd"]), !tracked.isEmpty else { return nil }
        let e = SkimFollow.edge(grow: body["grow"], soft: body["soft"])
        return Request(name: name, frames: n, frameLength: fd, samples: tracked, grow: e.grow, soft: e.soft)
    }

    private struct Failed: Error { var why: String }

    /// Makes the plate from `clip`, then writes the patch into `dir` under the first free name. A plate that cannot be
    /// made (a moving camera, a scene never seen) writes nothing and says why.
    static func write(_ r: Request, clip: URL, into dir: URL) async -> SkimExport.Saved {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { return .init(ok: false, path: "", why: "The folder is not there any more. Choose another under Save to.") }
        let asset = AVURLAsset(url: clip)
        let size: (w: Int, h: Int), track: AVAssetTrack
        do {
            guard let t = try await asset.loadTracks(withMediaType: .video).first else { return .init(ok: false, path: "", why: "The clip has no picture.") }
            let s = try await t.load(.naturalSize)
            size = (Int(s.width.rounded()), Int(s.height.rounded())); track = t
        } catch { return .init(ok: false, path: "", why: "The clip couldn’t be read.") }
        guard size.w > 1, size.h > 1, size.w <= 8192, size.h <= 8192 else { return .init(ok: false, path: "", why: "The clip couldn’t be read.") }

        // Where the shape ever is, and the hole each frame (grown by the margin and the user's edge).
        let boxes = r.samples.compactMap { s -> LookMasks.Box? in
            let pts = s.outline.flatMap { $0 }
            guard let x0 = pts.map(\.x).min(), let x1 = pts.map(\.x).max(), let y0 = pts.map(\.y).min(), let y1 = pts.map(\.y).max() else { return nil }
            return LookMasks.Box(x: x0, y: y0, w: x1 - x0, h: y1 - y0)
        }
        let long = Double(max(size.w, size.h)), grow = Int((max(0, r.grow) * long).rounded()) + SkimPlate.margin
        guard let crop = SkimPlate.crop(boxes, width: size.w, height: size.h, pad: SkimPlate.pad + Double(grow) / long), crop.w * crop.h <= SkimPlate.maxPixels else {
            return .init(ok: false, path: "", why: boxes.isEmpty ? "The shape is in no frame." : "The shape covers too much of the frame to remove.")
        }
        func hole(_ k: Int) -> LookMasks.Plane {
            let a = SkimFollow.matteFrame(k, frameLength: r.frameLength, in: r.samples)
            let o = a.map { SkimPlate.inCrop(r.samples[$0.before].outline, crop: crop, width: size.w, height: size.h) } ?? []
            return SkimFollow.edged(LookMasks.raster(o, width: crop.w, height: crop.h, samples: 2), grow: grow, soft: 0)
        }

        // The plate, from frames spread over the clip.
        // at most about 400 MB of crops in memory
        let picks = SkimPlate.picks(frames: r.frames, n: max(5, min(SkimPlate.maxFrames, 400_000_000 / max(1, crop.w * crop.h * 3))))
        var frames: [[UInt8]] = [], masks: [LookMasks.Plane] = []
        do {
            try read(asset: asset, track: track, crop: crop, want: Set(picks), frameLength: r.frameLength) { k, rgb in
                frames.append(rgb); masks.append(hole(k))
            }
        } catch { return .init(ok: false, path: "", why: (error as? Failed)?.why ?? "The clip couldn’t be read.") }
        guard frames.count >= 3, let plate = SkimPlate.plate(frames: frames, masks: masks, width: crop.w, height: crop.h) else {
            return .init(ok: false, path: "", why: "Too few frames in the clip to rebuild the scene.")
        }
        let shake = SkimPlate.shake(frames: frames, masks: masks, plate: plate, width: crop.w, height: crop.h)
        frames = []
        if let why = SkimPlate.refusal(shake: shake, unseen: plate.unseen) { return .init(ok: false, path: "", why: why) }

        guard let to = SkimExport.free(in: dir, name: r.name) else { return .init(ok: false, path: "", why: "Too many files with that name in the folder.") }
        do {
            try await encode(r, size: size, crop: crop, plate: plate, to: to) { k in
                SkimFollow.edged(hole(k), grow: 0, soft: Int((r.soft * long).rounded()))
            }
            let back = AVURLAsset(url: to)
            let tracks = try await back.loadTracks(withMediaType: .video), length = try await back.load(.duration)
            let want = Double(r.frames * r.frameLength.n) / Double(r.frameLength.d)
            guard tracks.count == 1, abs(length.seconds - want) <= Double(r.frameLength.n) / Double(r.frameLength.d) * 1.5 else { throw Failed(why: "read back") }
            return .init(ok: true, path: to.path, why: "")
        } catch {
            try? FileManager.default.removeItem(at: to)
            if (error as NSError).code == NSFileWriteOutOfSpaceError { return .init(ok: false, path: "", why: "The drive is full.") }
            return .init(ok: false, path: "", why: "The patch could not be written there.")
        }
    }

    /// Reads the clip at full size and hands over the crop of each frame whose number is in `want`, as RGB.
    private static func read(asset: AVAsset, track: AVAssetTrack, crop c: SkimPlate.Crop, want: Set<Int>, frameLength fl: (n: Int, d: Int),
                             each: (Int, [UInt8]) -> Void) throws {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw Failed(why: "The clip’s picture couldn’t be decoded.") }
        reader.add(output)
        guard reader.startReading() else { throw Failed(why: "The clip couldn’t be read.") }
        defer { reader.cancelReading() }
        let step = Double(fl.n) / Double(fl.d), last = want.max() ?? -1
        while let sample = output.copyNextSampleBuffer() {
            guard let pb = CMSampleBufferGetImageBuffer(sample) else { continue }
            let k = Int((CMSampleBufferGetPresentationTimeStamp(sample).seconds / step).rounded())
            if k > last { break }
            guard want.contains(k) else { continue }
            CVPixelBufferLockBaseAddress(pb, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(pb), CVPixelBufferGetWidth(pb) >= c.x + c.w, CVPixelBufferGetHeight(pb) >= c.y + c.h else { continue }
            let row = CVPixelBufferGetBytesPerRow(pb), px = base.assumingMemoryBound(to: UInt8.self)
            var rgb = [UInt8](repeating: 0, count: c.w * c.h * 3)
            for y in 0..<c.h {
                let line = px + (c.y + y) * row + c.x * 4
                for x in 0..<c.w { let o = (y * c.w + x) * 3; rgb[o] = line[x * 4 + 2]; rgb[o + 1] = line[x * 4 + 1]; rgb[o + 2] = line[x * 4] }
            }
            each(k, rgb)
        }
        if reader.status == .failed { throw Failed(why: "The clip couldn’t be decoded.") }
    }

    /// The patch: each frame transparent, the plate inside the hole with the hole's mask as its alpha (straight).
    private static func encode(_ r: Request, size: (w: Int, h: Int), crop c: SkimPlate.Crop, plate: SkimPlate.Plate, to url: URL,
                               alpha: (Int) -> LookMasks.Plane) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.proRes4444, AVVideoWidthKey: size.w, AVVideoHeightKey: size.h,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.w, kCVPixelBufferHeightKey as String: size.h,
        ])
        guard writer.canAdd(input) else { throw Failed(why: "setup") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? Failed(why: "setup") }
        writer.startSession(atSourceTime: .zero)
        for k in 0..<r.frames {
            let a = alpha(k)
            while !input.isReadyForMoreMediaData {
                if writer.status != .writing { throw writer.error ?? Failed(why: "frame") }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else { throw writer.error ?? Failed(why: "frame") }
            var pb: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess, let buffer = pb else { throw Failed(why: "frame") }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                let row = CVPixelBufferGetBytesPerRow(buffer), px = base.assumingMemoryBound(to: UInt8.self)
                memset(base, 0, row * size.h)
                for y in 0..<c.h {
                    let line = px + (c.y + y) * row + c.x * 4
                    for x in 0..<c.w {
                        let i = y * c.w + x, v = a.values[i]
                        guard v > 0.002 else { continue }
                        line[x * 4] = plate.rgb[i * 3 + 2]; line[x * 4 + 1] = plate.rgb[i * 3 + 1]; line[x * 4 + 2] = plate.rgb[i * 3]
                        line[x * 4 + 3] = UInt8(max(0, min(255, (v * 255).rounded())))
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(k * r.frameLength.n), timescale: CMTimeScale(r.frameLength.d))) else { throw writer.error ?? Failed(why: "frame") }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(r.frames * r.frameLength.n), timescale: CMTimeScale(r.frameLength.d)))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? Failed(why: "finish") }
    }
}
