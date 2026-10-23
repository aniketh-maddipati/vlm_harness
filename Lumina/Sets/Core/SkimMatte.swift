import AVFoundation
import CoreVideo
import Foundation

/// Skim's `lumina.video.matte`: a followed shape as a black-and-white movie the length of its clip, frame for frame,
/// for Final Cut (white where the shape is, black elsewhere, its edge feathered), which the .fcpxml then lists beside
/// the clip. In Final Cut it is the mask of an effect (Image Mask, or a Luma Keyer on a connected copy). Written as a
/// new file in the folder Export saves into, never over one, next to the .fcpxml and never on a card; the clip itself
/// is never touched. Each frame of the matte is made from the followed frames on either side of it
/// (`SkimFollow.matteFrame`), each outline rasterised once (`LookMasks.raster`) and the two mixed by time; when every
/// frame was followed (the Mac's own track, `SkimTracker`), from the one nearest alone, never mixed.
nonisolated enum SkimMatte {
    /// What the page asks for: the clip's name and size, its length in frames and the length of one, and the
    /// followed frames.
    struct Request: Sendable {
        var name: String
        var width: Int
        var height: Int
        var frames: Int
        var frameLength: (n: Int, d: Int)
        var samples: [SkimFollow.Sample]
    }

    /// The feather of the matte's edge, as a fraction of its long edge.
    static let feather = 0.003

    /// `tracked`: the followed frames of the Mac's own track the page names (`track`), in place of the page's `samples`.
    static func request(_ body: [String: Any], tracked: [SkimFollow.Sample]? = nil) -> Request? {
        guard let clip = body["name"] as? String, let name = SkimFollow.matteName(clip: clip),
              let w = (body["w"] as? NSNumber)?.intValue, let h = (body["h"] as? NSNumber)?.intValue, let size = SkimFollow.matteSize(width: w, height: h),
              let n = (body["frames"] as? NSNumber)?.intValue, n > 0, n <= SkimFollow.maxFrames,
              let fd = SkimFollow.frameLength(body["fd"]), let s = tracked ?? SkimFollow.samples(body["samples"]), !s.isEmpty else { return nil }
        return Request(name: name, width: size.width, height: size.height, frames: n, frameLength: fd, samples: s)
    }

    /// Writes the matte into `dir` under the first free name, then opens it again: a file that does not open as a
    /// movie of the frames asked for is removed and the save fails.
    static func write(_ r: Request, into dir: URL) async -> SkimExport.Saved {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { return .init(ok: false, path: "", why: "The folder is not there any more. Choose another under Save to.") }
        guard let to = SkimExport.free(in: dir, name: r.name) else { return .init(ok: false, path: "", why: "Too many files with that name in the folder.") }
        do {
            try await encode(r, to: to)
            let asset = AVURLAsset(url: to)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let length = try await asset.load(.duration)
            let want = CMTime(value: CMTimeValue(r.frames * r.frameLength.n), timescale: CMTimeScale(r.frameLength.d))
            guard tracks.count == 1, abs(length.seconds - want.seconds) <= Double(r.frameLength.n) / Double(r.frameLength.d) * 1.5 else { throw Failed.readBack }
            return .init(ok: true, path: to.path, why: "")
        } catch {
            try? FileManager.default.removeItem(at: to)
            if case Failed.readBack = error { return .init(ok: false, path: "", why: "The matte did not read back as written, so it was removed.") }
            if (error as NSError).code == NSFileWriteOutOfSpaceError { return .init(ok: false, path: "", why: "The drive is full.") }
            return .init(ok: false, path: "", why: "The matte could not be written there.")
        }
    }

    private enum Failed: Error { case setup, frame, finish, readBack }

    private static func encode(_ r: Request, to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: r.width, AVVideoHeightKey: r.height,
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2, AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: r.width * r.height * 4, AVVideoExpectedSourceFrameRateKey: max(1, r.frameLength.d / r.frameLength.n)],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: r.width, kCVPixelBufferHeightKey as String: r.height,
        ])
        guard writer.canAdd(input) else { throw Failed.setup }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? Failed.setup }
        writer.startSession(atSourceTime: .zero)

        // the rasters of the followed frames in use, at most the two either side of the frame being made
        var planes: [Int: LookMasks.Plane] = [:]
        func plane(_ i: Int) -> LookMasks.Plane {
            if let p = planes[i] { return p }
            let p = LookMasks.raster(r.samples[i].outline, width: r.width, height: r.height, samples: 2, feather: feather)
            planes[i] = p
            return p
        }
        for k in 0..<r.frames {
            // the followed frames around this one (the nearest alone when every frame was followed)
            guard let a = SkimFollow.matteFrame(k, frameLength: r.frameLength, in: r.samples) else { throw Failed.frame }
            planes = planes.filter { $0.key == a.before || $0.key == a.after }
            let p0 = plane(a.before), p1 = plane(a.after), wt = Float(a.weight)
            while !input.isReadyForMoreMediaData {
                if writer.status != .writing { throw writer.error ?? Failed.frame }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else { throw writer.error ?? Failed.frame }
            var pb: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess, let buffer = pb else { throw Failed.frame }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                let row = CVPixelBufferGetBytesPerRow(buffer), px = base.assumingMemoryBound(to: UInt8.self)
                p0.values.withUnsafeBufferPointer { v0 in
                    p1.values.withUnsafeBufferPointer { v1 in
                        for y in 0..<r.height {
                            let line = px + y * row, o = y * r.width
                            for x in 0..<r.width {
                                let v = v0[o + x] + (v1[o + x] - v0[o + x]) * wt
                                let b = UInt8(max(0, min(255, (v * 255).rounded())))
                                line[x * 4] = b; line[x * 4 + 1] = b; line[x * 4 + 2] = b; line[x * 4 + 3] = 255
                            }
                        }
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(k * r.frameLength.n), timescale: CMTimeScale(r.frameLength.d))) else { throw writer.error ?? Failed.frame }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(r.frames * r.frameLength.n), timescale: CMTimeScale(r.frameLength.d)))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? Failed.finish }
    }
}
