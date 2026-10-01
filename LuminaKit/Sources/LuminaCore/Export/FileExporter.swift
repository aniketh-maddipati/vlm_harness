import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// WP-7. The real writers behind `Exporter` (README §4), for file-backed photos:
//   Lightroom: a .xmp next to each photo (3★, edits as develop settings), merged into an existing one;
//   Folder:    verified copies of the keepers (size + SHA-256), with a .xmp for edited ones;
//   JPEG:      full-size sRGB JPEGs rendered through `ImageProvider`, the look baked in.
// Every write goes through `ExportFiles` (backup first, atomic, read back, never onto a card).
// A photo without a file (the demo card) has nothing to write and counts as written.
// Failures come back per photo in `ExportResult.failed` (photo id → reason); nothing is thrown away.

public final class FileExporter: Exporter, @unchecked Sendable {
    private let images: any ImageProvider
    private let isCard: @Sendable (URL) -> Bool
    private let jpegQuality: Double

    /// `isCard` answers whether a path is on a camera card (tests pass their own).
    public init(images: any ImageProvider = DefaultImageProvider(), jpegQuality: Double = 0.92, isCard: (@Sendable (URL) -> Bool)? = nil) {
        self.images = images; self.jpegQuality = jpegQuality; self.isCard = isCard ?? { ExportFiles.isCard($0) }
    }

    public static let onCard = "on the card"

    public func export(_ job: ExportJob) async -> ExportResult {
        var r = ExportResult(written: 0, reveal: job.destination)
        switch job.format {
        case .xmp: exportSidecars(job, &r)
        case .folder: exportCopies(job, &r)
        case .jpeg: await exportJPEGs(job, &r)
        }
        return r
    }

    // MARK: Lightroom

    private func exportSidecars(_ job: ExportJob, _ r: inout ExportResult) {
        var first: URL?
        for item in job.items {
            guard case .file(let src) = item.photo.source else { r.written += 1; continue }
            let sidecar = Self.sidecarURL(for: src)
            if upToDate(item, at: sidecar, job) { r.written += 1; first = first ?? sidecar; continue }
            do {
                guard FileManager.default.fileExists(atPath: src.path) else { throw ExportFiles.Failure("missing") }
                try writeSidecar(sidecar, look: item.look, photo: src)
                r.written += 1; first = first ?? sidecar
            } catch { r.failed[item.photo.id] = ExportFiles.reason(error) }
        }
        r.reveal = first ?? job.destination
    }

    /// `<name>.xmp` beside `photo`; an existing sidecar in either case of the extension is the one.
    static func sidecarURL(for photo: URL) -> URL {
        let base = photo.deletingPathExtension(), upper = base.appendingPathExtension("XMP"), lower = base.appendingPathExtension("xmp")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: photo.deletingLastPathComponent().path)) ?? []
        return !names.contains(lower.lastPathComponent) && names.contains(upper.lastPathComponent) ? upper : lower
    }

    private func writeSidecar(_ url: URL, look: Look?, photo: URL) throws {
        if isCard(url) { throw ExportFiles.Failure(Self.onCard) }
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { throw ExportFiles.Failure("refused") }
        let old = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        let turns = Int((look?[CropKey.turns] ?? 0).rounded()) % 4 != 0
        let data = try XMPSidecar.merge(existing: old, properties: XMPSidecar.properties(look: look, orientation: turns ? Self.orientation(of: photo) : 1))
        try ExportFiles.write(data, to: url)
    }

    static func orientation(of url: URL) -> Int {
        guard let s = CGImageSourceCreateWithURL(url as CFURL, nil), let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any] else { return 1 }
        return (p[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    }

    // MARK: Folder

    private func exportCopies(_ job: ExportJob, _ r: inout ExportResult) {
        guard let dest = destination(job, &r) else { return }
        let files = job.items.compactMap { i -> (ExportJob.Item, URL)? in if case .file(let u) = i.photo.source { return (i, u) } else { return nil } }
        r.written += job.items.count - files.count
        let todo = files.filter { !upToDate($0.0, at: dest.appendingPathComponent($0.1.lastPathComponent), job) }
        r.written += files.count - todo.count
        let needed = todo.reduce(Int64(0)) { $0 + Int64((try? $1.1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        if let free = ExportFiles.freeBytes(at: dest), free < needed + max(1 << 20, needed / 20) {
            for (item, _) in todo { r.failed[item.photo.id] = "not enough space" }
            return
        }
        for (item, src) in todo {
            do {
                guard FileManager.default.fileExists(atPath: src.path) else { throw ExportFiles.Failure("missing") }
                let copy = try ExportFiles.copyVerified(src, to: dest.appendingPathComponent(src.lastPathComponent)).url
                let sidecar = Self.sidecarURL(for: copy), edited = !(item.look ?? [:]).isEmpty
                // "with an .xmp for edited ones"; one written earlier follows the look when the edit is taken back.
                if edited || FileManager.default.fileExists(atPath: sidecar.path) { try writeSidecar(sidecar, look: item.look, photo: src) }
                r.written += 1
            } catch { r.failed[item.photo.id] = ExportFiles.reason(error) }
        }
    }

    // MARK: JPEG

    private func exportJPEGs(_ job: ExportJob, _ r: inout ExportResult) async {
        guard let dest = destination(job, &r) else { return }
        for item in job.items {
            guard case .file(let src) = item.photo.source else { r.written += 1; continue }
            let target = dest.appendingPathComponent(src.deletingPathExtension().lastPathComponent + ".jpg")
            if upToDate(item, at: target, job) { r.written += 1; continue }
            do {
                guard FileManager.default.fileExists(atPath: src.path) else { throw ExportFiles.Failure("missing") }
                let look = (item.look ?? [:]).isEmpty ? nil : item.look
                let image: CGImage
                do { image = try await images.image(for: item.photo, maxPixel: Self.longEdge(of: src), look: look) }
                catch { throw ExportFiles.Failure("can’t be opened") }
                let data = try Self.jpeg(image, quality: jpegQuality)
                try ExportFiles.write(data, to: target)
                r.written += 1
            } catch { r.failed[item.photo.id] = ExportFiles.reason(error) }
        }
    }

    static func longEdge(of url: URL) -> Int {
        guard let s = CGImageSourceCreateWithURL(url as CFURL, nil), let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any],
              let w = (p[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, let h = (p[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else { return 8192 }
        return max(w, h, 1)
    }

    /// sRGB JPEG bytes, decoded once before they count (a JPEG that doesn't open is not a save).
    static func jpeg(_ image: CGImage, quality: Double) throws -> Data {
        let out = NSMutableData()
        guard let d = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { throw ExportFiles.Failure("failed") }
        let opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality, kCGImageDestinationOptimizeColorForSharing: true]
        CGImageDestinationAddImage(d, image, opts as CFDictionary)
        guard CGImageDestinationFinalize(d) else { throw ExportFiles.Failure("failed") }
        let data = out as Data
        guard let s = CGImageSourceCreateWithData(data as CFData, nil), let back = CGImageSourceCreateImageAtIndex(s, 0, nil),
              back.width == image.width, back.height == image.height else { throw ExportFiles.Failure("verify failed") }
        return data
    }

    // MARK: shared

    /// The folder copies and JPEGs go to, made if needed. Refused on a card: then every photo fails.
    private func destination(_ job: ExportJob, _ r: inout ExportResult) -> URL? {
        func failAll(_ why: String) { for i in job.items { if case .file = i.photo.source { r.failed[i.photo.id] = why } else { r.written += 1 } } }
        guard let dest = job.destination else { failAll("no folder chosen"); return nil }
        if isCard(dest) { failAll(Self.onCard); return nil }
        do { try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true) } catch { failAll(ExportFiles.reason(error)); return nil }
        return dest
    }

    /// "Only what changed is rewritten": a photo outside `changedOnly` whose output is still there.
    private func upToDate(_ item: ExportJob.Item, at url: URL, _ job: ExportJob) -> Bool {
        guard let changed = job.changedOnly, !changed.contains(item.photo.id) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}
