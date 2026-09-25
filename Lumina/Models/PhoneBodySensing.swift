import Foundation
import ImageIO

/// Capture-body sensing for the phone glyph and moment mix line.
///
/// One phone treatment for everyone: a hand mark and a sensed classification
/// both resolve through `AssetRecord.isPhoneBody`. There is no second tag.
nonisolated enum PhoneBodySensing {
    /// Traditional camera RAW containers. Phone ProRAW also uses `.dng`, so
    /// extension alone can never decide phone vs camera.
    static let cameraRawExtensions: Set<String> = [
        "arw", "cr2", "cr3", "nef", "nrw", "orf", "rw2", "raf", "pef",
        "srw", "iiq", "3fr", "fff", "mos", "mrw", "x3f", "raw",
    ]

    /// Containers Apple phones commonly write that cameras rarely use as the
    /// primary delivery. Never sufficient alone — paired with Make/Model.
    static let phoneNativeExtensions: Set<String> = [
        "heic", "heif", "hif",
    ]

    struct Evidence: Equatable, Sendable {
        var make: String?
        var model: String?
        var filename: String
        var path: String?

        init(make: String? = nil, model: String? = nil, filename: String, path: String? = nil) {
            self.make = PhoneBodySensing.normalize(make)
            self.model = PhoneBodySensing.normalize(model)
            self.filename = filename
            self.path = path
        }
    }

    enum Classification: Equatable, Sendable {
        case phone
        case camera
        case unknown
    }

    /// Read TIFF Make/Model from the file when ImageIO can open it.
    static func evidence(atPath path: String, filename: String? = nil) -> Evidence {
        let name = filename ?? URL(fileURLWithPath: path).lastPathComponent
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return Evidence(filename: name, path: path)
        }
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let make = tiff[kCGImagePropertyTIFFMake] as? String
        let model = tiff[kCGImagePropertyTIFFModel] as? String
        return Evidence(make: make, model: model, filename: name, path: path)
    }

    static func classify(_ evidence: Evidence) -> Classification {
        if looksLikePhone(make: evidence.make, model: evidence.model) {
            return .phone
        }
        if looksLikeCameraBody(make: evidence.make, model: evidence.model) {
            return .camera
        }

        let ext = (evidence.filename as NSString).pathExtension.lowercased()
        // Camera RAW without phone Make → camera. DNG alone is ambiguous
        // (ProRAW vs desktop conversion) and stays unknown without Make.
        if cameraRawExtensions.contains(ext), ext != "dng" {
            return .camera
        }
        // HEIC with no Make is still usually a phone delivery in this product's
        // shoots, but a stripped export can land here — prefer unknown so the
        // hand can mark it rather than inventing a false phone.
        if phoneNativeExtensions.contains(ext), evidence.make == nil, evidence.model == nil {
            return .unknown
        }
        // JPEG/PNG/TIFF with no identity: camera out-of-camera JPEG is common;
        // never call that a phone.
        return .unknown
    }

    static func isPhone(_ evidence: Evidence) -> Bool {
        classify(evidence) == .phone
    }

    // MARK: - Make / Model

    /// Apple iPhone (incl. ProRAW DNG), Pixel, Galaxy phone lines, and common
    /// Android phone makers when the model string looks like a handset.
    static func looksLikePhone(make: String?, model: String?) -> Bool {
        let make = normalize(make) ?? ""
        let model = normalize(model) ?? ""
        guard !make.isEmpty || !model.isEmpty else { return false }

        if model.contains("iphone") { return true }
        if make.contains("apple") {
            if model.contains("ipad") { return false }
            // Empty model on an Apple body is treated as phone (ProRAW/HEIC fleet).
            if model.isEmpty || model.contains("iphone") { return true }
            return false
        }

        if make.contains("google"), model.contains("pixel") { return true }
        if model.contains("pixel ") || model.hasPrefix("pixel") { return true }

        if make.contains("samsung") {
            // Galaxy S/Z/Note/A phone lines; exclude NX/camera-ish model codes when obvious.
            if model.contains("galaxy") { return true }
            if model.hasPrefix("sm-s") || model.hasPrefix("sm-g") || model.hasPrefix("sm-f")
                || model.hasPrefix("sm-a") || model.hasPrefix("sm-n") {
                return true
            }
        }

        if make.contains("oneplus") || make.contains("xiaomi") || make.contains("redmi")
            || make.contains("huawei") || make.contains("honor") || make.contains("oppo")
            || make.contains("vivo") || make.contains("realme") || make.contains("motorola")
            || make.contains("nothing") {
            return true
        }

        if make.contains("sony"), model.contains("xperia") { return true }
        return false
    }

    static func looksLikeCameraBody(make: String?, model: String?) -> Bool {
        let make = normalize(make) ?? ""
        let model = normalize(model) ?? ""
        guard !make.isEmpty || !model.isEmpty else { return false }
        if looksLikePhone(make: make.isEmpty ? nil : make, model: model.isEmpty ? nil : model) {
            return false
        }

        let cameraMakes = [
            "sony", "canon", "nikon", "fujifilm", "fuji photo", "olympus", "om digital",
            "panasonic", "leica", "hasselblad", "phase one", "pentax", "ricoh",
            "sigma", "minolta", "konica", "samsung",
        ]
        if cameraMakes.contains(where: { make.contains($0) }) {
            // Samsung makes phones and NX cameras; require camera-ish model cues.
            if make.contains("samsung") {
                return model.contains("nx") || model.contains("ex") || model.contains("wb")
            }
            return true
        }

        // Model-only camera cues when Make was stripped.
        let cameraModels = ["ilce-", "ilme-", "dsc-", "z cam", "eos ", "eos-", "d850", "z6", "z7", "z8", "z9", "x-t", "x-h", "gfx"]
        if cameraModels.contains(where: { model.contains($0) }) { return true }
        return false
    }

    static func normalize(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}
