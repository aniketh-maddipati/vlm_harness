import Foundation

/// What a rendered export (Edit's JPEG, TIFF or PNG) says about the photo (docs/release/TRUST.md I7).
/// The look stages are Metal kernels, which keep none of the RAW's metadata, so an export carries
/// only what is chosen here, by allowlist: the capture time, the camera and lens, the exposure, and
/// the photographer's own credit (artist, copyright, IPTC creator and caption). Never written:
/// location (GPS, and IPTC's city, region and country), camera and lens serial numbers, maker notes,
/// and the orientation (the pixels are already upright). A field nobody listed stays out, so a new
/// camera's fields can't leak by default.
///
/// Foundation only (tested on Linux): keys are ImageIO's property names as strings; SetsLookExport
/// writes the result with ImageIO.
nonisolated enum SetsExportMetadata {
    static let keep: [String: Set<String>] = [
        "{TIFF}": ["Make", "Model", "Artist", "Copyright", "DateTime", "ImageDescription"],
        "{Exif}": ["DateTimeOriginal", "DateTimeDigitized", "OffsetTime", "OffsetTimeOriginal", "OffsetTimeDigitized",
                   "SubsecTime", "SubsecTimeOriginal", "SubsecTimeDigitized",
                   "ExposureTime", "FNumber", "ExposureProgram", "ISOSpeedRatings", "PhotographicSensitivity", "SensitivityType",
                   "RecommendedExposureIndex", "ExposureBiasValue", "MeteringMode", "LightSource", "Flash",
                   "FocalLength", "FocalLenIn35mmFilm", "ExposureMode", "WhiteBalance", "SceneCaptureType",
                   "LensMake", "LensModel", "LensSpecification"],
        "{IPTC}": ["Byline", "BylineTitle", "CopyrightNotice", "Credit", "Source", "CaptionAbstract", "Headline",
                   "Keywords", "ObjectName", "WriterEditor", "RightsUsageTerms"],
    ]

    /// Never written, whatever `keep` says (a test holds that the two don't meet).
    static let never: Set<String> = [
        "{GPS}", "{ExifAux}", "{MakerApple}", "{MakerCanon}", "{MakerNikon}", "{MakerMinolta}", "{MakerFuji}", "{MakerOlympus}", "{MakerPentax}",
        "{TIFF}.Orientation", "{TIFF}.HostComputer", "{TIFF}.Software",
        "{Exif}.BodySerialNumber", "{Exif}.LensSerialNumber", "{Exif}.CameraOwnerName", "{Exif}.MakerNote", "{Exif}.UserComment", "{Exif}.ImageUniqueID",
        "{IPTC}.City", "{IPTC}.SubLocation", "{IPTC}.Province/State", "{IPTC}.Country/PrimaryLocationCode", "{IPTC}.Country/PrimaryLocationName",
        "{IPTC}.ContactInfo",
    ]

    /// The source's properties (CGImageSourceCopyPropertiesAtIndex) → (dictionary, key, value) to write.
    static func fields(from properties: [String: Any]) -> [(dictionary: String, key: String, value: Any)] {
        var out: [(String, String, Any)] = []
        for (dict, keys) in keep.sorted(by: { $0.key < $1.key }) {
            guard !never.contains(dict), let d = properties[dict] as? [String: Any] else { continue }
            for k in keys.sorted() where !never.contains("\(dict).\(k)") {
                guard let v = d[k], usable(v) else { continue }
                out.append((dict, k, v))
            }
        }
        return out
    }

    /// The refused fields an image's properties hold: whole dictionaries in `never` and
    /// "<dictionary>.<key>" for single fields. Empty for a clean file.
    static func refused(in properties: [String: Any]) -> [String] {
        var out: [String] = []
        for (dict, v) in properties {
            if never.contains(dict) { out.append(dict); continue }
            guard let d = v as? [String: Any] else { continue }
            for (k, value) in d where never.contains("\(dict).\(k)") {
                // Upright pixels may say so: orientation 1 is the one value that changes nothing.
                if dict == "{TIFF}", k == "Orientation", "\(value)" == "1" { continue }
                out.append("\(dict).\(k)")
            }
        }
        return out.sorted()
    }

    /// A value ImageIO writes as it is: text (at most 2,000 characters), a number, or a short list
    /// of those. Anything else (a nested dictionary, data) is left out.
    static func usable(_ v: Any) -> Bool {
        switch v {
        case let s as String: return s.utf8.count <= 2_000 && !s.utf8.contains(0)
        case is NSNumber, is Int, is Double: return true
        case let a as [Any]: return a.count <= 64 && a.allSatisfy { !($0 is [Any]) && usable($0) }
        default: return false
        }
    }
}
