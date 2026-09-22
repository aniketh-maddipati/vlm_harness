#!/usr/bin/env swift
//
// Reproduce the browse-tier orientation hole.
//
//   xcrun swift Scripts/harness/develop/preview_orientation_repro.swift <folder-of-raws>
//
// For every RAW in the folder it prints what each branch of
// `PreviewExtractor.extract` would put on disk:
//
//   ImageIO  — `extractWithImageIO`, which applies the file's orientation
//   exiftool — `exiftool -b -PreviewImage`, the fallback when ImageIO cannot
//              make a thumbnail, which does not
//
// A frame whose EXIF orientation is not 1 comes out of the exiftool branch in
// sensor space, and the bytes written carry no orientation tag of their own —
// so nothing downstream can put it back up the right way. That is a photograph
// displayed on its side.
//
// Needs exiftool on PATH (`brew install exiftool`).

import CoreGraphics
import Foundation
import ImageIO

let rawExtensions: Set<String> = ["ARW", "CR2", "CR3", "NEF", "RAF", "DNG", "ORF", "RW2"]
let quarterTurns: Set<UInt32> = [5, 6, 7, 8]

struct Shape {
    let width: Int
    let height: Int
    var isPortrait: Bool { height > width }
    var description: String { "\(width)x\(height) \(isPortrait ? "portrait" : "landscape")" }
}

func fileShape(_ url: URL) -> (shape: Shape, orientation: UInt32)? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
        return nil
    }
    let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
    let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
    guard width > 0, height > 0 else { return nil }
    let orientation = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
    let shape = quarterTurns.contains(orientation)
        ? Shape(width: height, height: width)
        : Shape(width: width, height: height)
    return (shape, orientation)
}

func thumbnailWithTransform(_ url: URL, maxPixelSize: Int) -> Shape? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
              kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
              kCGImageSourceCreateThumbnailWithTransform: true,
          ] as CFDictionary) else { return nil }
    return Shape(width: image.width, height: image.height)
}

func exiftoolPath() -> String? {
    ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool", "/usr/bin/exiftool"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
}

func extractedPreview(_ url: URL, using tool: String) -> URL? {
    let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-repro-\(UUID().uuidString).jpg")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = ["-b", "-PreviewImage", url.path]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard !data.isEmpty else { return nil }
        try data.write(to: destination)
        return destination
    } catch {
        return nil
    }
}

let arguments = CommandLine.arguments.dropFirst()
guard let folder = arguments.first else {
    FileHandle.standardError.write(Data("usage: preview_orientation_repro.swift <folder-of-raws>\n".utf8))
    exit(2)
}
guard let tool = exiftoolPath() else {
    FileHandle.standardError.write(Data("exiftool not found — brew install exiftool\n".utf8))
    exit(2)
}

let root = URL(fileURLWithPath: folder, isDirectory: true)
let contents = (try? FileManager.default.contentsOfDirectory(
    at: root,
    includingPropertiesForKeys: nil,
    options: [.skipsHiddenFiles]
)) ?? []
let raws = contents
    .filter { rawExtensions.contains($0.pathExtension.uppercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

var sideways = 0
for url in raws {
    guard let (oriented, orientation) = fileShape(url) else { continue }
    let imageIO = thumbnailWithTransform(url, maxPixelSize: 2048)
    var fallback: Shape?
    if let preview = extractedPreview(url, using: tool) {
        fallback = thumbnailWithTransform(preview, maxPixelSize: 2048)
        try? FileManager.default.removeItem(at: preview)
    }

    let wrong = fallback.map { $0.isPortrait != oriented.isPortrait } ?? false
    if wrong { sideways += 1 }
    print("\(url.lastPathComponent)  exif=\(orientation)  file=\(oriented.description)")
    print("    ImageIO branch : \(imageIO?.description ?? "FAILED — this is when the fallback runs")")
    print("    exiftool branch: \(fallback?.description ?? "no embedded preview")\(wrong ? "   ← ON ITS SIDE" : "")")
}

print("")
print("\(raws.count) frames · \(sideways) would be written on their side by the exiftool fallback")
exit(sideways > 0 ? 1 : 0)
