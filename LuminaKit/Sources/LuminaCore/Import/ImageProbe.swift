import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// WP-2. One look at a file through ImageIO: does it decode, how big is it once EXIF orientation
// is applied (R-10, R-1D), and what the camera wrote about it (R-16). The file is opened once.

enum ImageProbe {
    struct Result: Sendable {
        var info: ImageInfo
        var exif: EXIF?
    }

    static func probe(_ url: URL) -> Result? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(src) > 0,
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = (p[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let h = (p[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue, w > 0, h > 0
        else { return nil }
        // The header is not proof: the pixels have to come out too. A RAW's embedded preview counts
        // (Cull never develops a RAW); anything else is decoded, small. A strip 2 px wide still has
        // to leave one pixel, so the probe size follows the shape.
        let raw = ImportClassifier.raws.contains(url.pathExtension.lowercased())
            || (CGImageSourceGetType(src) as String?).flatMap { UTType($0) }?.conforms(to: .rawImage) == true
        let side = Int(min(4096, max(16, (max(w, h) / min(w, h)).rounded(.up) * 2)))
        let opts: [CFString: Any] = [kCGImageSourceThumbnailMaxPixelSize: side, kCGImageSourceShouldCache: false,
                                     (raw ? kCGImageSourceCreateThumbnailFromImageIfAbsent : kCGImageSourceCreateThumbnailFromImageAlways): true]
        guard CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) != nil else { return nil }
        let o = (p[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return Result(info: ImageInfo(pixelSize: (5...8).contains(o) ? CGSize(width: h, height: w) : CGSize(width: w, height: h)), exif: exif(p))
    }

    /// The fields Lumina shows, from ImageIO's property dictionaries. Nil when there are none.
    static func exif(_ p: [CFString: Any]) -> EXIF? {
        let x = p[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let aux = p[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]
        func text(_ v: Any?) -> String? {
            guard let s = (v as? String)?.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)), !s.isEmpty else { return nil }
            return s
        }
        func number(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue ?? (v as? [NSNumber])?.first?.doubleValue }
        func positive(_ v: Any?) -> Double? { number(v).flatMap { $0 > 0 && $0.isFinite ? $0 : nil } }

        var e = EXIF()
        e.shot = date(text(x[kCGImagePropertyExifDateTimeOriginal]), subsec: text(x[kCGImagePropertyExifSubsecTimeOriginal]))
            ?? date(text(x[kCGImagePropertyExifDateTimeDigitized]), subsec: text(x[kCGImagePropertyExifSubsecTimeDigitized]))
        e.make = text(tiff[kCGImagePropertyTIFFMake]); e.model = text(tiff[kCGImagePropertyTIFFModel])
        e.lens = text(x[kCGImagePropertyExifLensModel]) ?? text(aux[kCGImagePropertyExifAuxLensModel])
        e.fNumber = positive(x[kCGImagePropertyExifFNumber]); e.exposure = positive(x[kCGImagePropertyExifExposureTime])
        e.focal = positive(x[kCGImagePropertyExifFocalLength])
        e.iso = positive(x[kCGImagePropertyExifISOSpeedRatings]).map { Int($0) }
        e.orientation = (p[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return e == EXIF() ? nil : e
    }

    /// "2026:09:30 09:00:00" as the camera's wall clock, read in this Mac's time zone (EXIF has none).
    static func date(_ s: String?, subsec: String? = nil) -> Date? {
        guard let s else { return nil }
        let n = s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard n.count >= 6, n[0] > 0, (1...12).contains(n[1]), (1...31).contains(n[2]) else { return nil }
        guard let d = Calendar.current.date(from: DateComponents(year: n[0], month: n[1], day: n[2], hour: n[3], minute: n[4], second: n[5])) else { return nil }
        let frac = subsec.flatMap { Double("0." + $0.filter(\.isNumber)) } ?? 0
        return d.addingTimeInterval(frac)
    }
}

public enum EXIFReader {
    /// Capture time, camera, lens, exposure (R-16). Nil when the file has no metadata.
    public static func read(url: URL) -> EXIF? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary), CGImageSourceGetCount(src) > 0,
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }
        return ImageProbe.exif(p)
    }
}
