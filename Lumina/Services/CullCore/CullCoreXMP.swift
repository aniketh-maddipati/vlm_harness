import Foundation

/// Port of `mergeXmp`, `freshXmp` and `hasDevelop` from `design/handoff/lumina-cull/lumina-core.js`.
/// Output is diffed byte-for-byte against the prototype, so the regexes spell out JS's ASCII
/// `\w` and JS `\s` rather than relying on ICU's Unicode classes.
nonisolated enum CullCoreXMP {
    /// Lumina develop settings written into a fresh sidecar (`crs:` 2012 process).
    struct Develop: Equatable {
        var exposure: Double?
        var contrast: Double?
        var highlights: Double?
        var shadows: Double?
        var temperature: Double?
    }

    private static let jsWord = "[A-Za-z0-9_]"
    private static let jsSpace = "[\\t\\n\\u000B\\f\\r \\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000\\uFEFF]"
    // JS `\b` after `n` (a word char): the next char is not a word char, or end of input.
    private static let descriptionTag = "<rdf:Description(?!\(jsWord))"

    /// Set rating + label in an existing XMP; everything else (Lightroom edits) untouched.
    static func merge(_ source: String, rating: Int, label: String?) -> String {
        var x = source
        if firstMatch("\(descriptionTag)[^>]*>", in: x) != nil, firstMatch("xmlns:xmp\(jsSpace)*=", in: x) == nil {
            x = insertAfterDescriptionTag(x, " xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\"")
        }
        x = setAttribute(x, "xmp:Rating", String(rating))
        if let label, !label.isEmpty { x = setAttribute(x, "xmp:Label", label) }
        return x
    }

    /// New sidecar. `develop == nil` writes ratings only.
    static func fresh(rating: Int, label: String?, develop: Develop?) -> String {
        var a = "xmp:Rating=\"\(rating)\"" + ((label?.isEmpty ?? true) ? "" : " xmp:Label=\"\(label!)\"")
        if let dev = develop {
            func f(_ v: Double?, _ digits: Int = 2) -> String {
                let v = CullCoreJSNumber.truthy(v) ? v! : 0
                return (v >= 0 ? "+" : "") + CullCoreJSNumber.toFixed(v, digits)
            }
            a += " crs:Version=\"15.0\" crs:ProcessVersion=\"11.0\" crs:HasSettings=\"True\""
                + " crs:Exposure2012=\"\(f(dev.exposure))\" crs:Contrast2012=\"\(f(dev.contrast, 0))\""
                + " crs:Highlights2012=\"\(f(dev.highlights, 0))\" crs:Shadows2012=\"\(f(dev.shadows, 0))\""
            if CullCoreJSNumber.truthy(dev.temperature) {
                let kelvin = CullCoreJSNumber.numberString(CullCoreJSNumber.round(dev.temperature!))
                a += " crs:WhiteBalance=\"Custom\" crs:Temperature=\"\(kelvin)\" crs:Tint=\"+0\""
            }
        }
        return "<?xpacket begin=\"\u{FEFF}\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\n<x:xmpmeta xmlns:x=\"adobe:ns:meta/\">\n"
            + " <rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">\n"
            + "  <rdf:Description rdf:about=\"\" xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\" xmlns:crs=\"http://ns.adobe.com/camera-raw-settings/1.0/\" \(a)/>\n"
            + " </rdf:RDF>\n</x:xmpmeta>\n<?xpacket end=\"w\"?>\n"
    }

    /// Existing sidecar already has develop settings (edited in Lightroom / Camera Raw)?
    static func hasDevelop(_ x: String?) -> Bool {
        guard let x, !x.isEmpty else { return false }
        let hasSettings = asciiCaseless("crs:HasSettings"), trueWord = asciiCaseless("True")
        return firstMatch("\(hasSettings)\(jsSpace)*=\(jsSpace)*\"\(trueWord)\"", in: x) != nil
            || firstMatch("<\(hasSettings)>\(trueWord)<", in: x) != nil
            || firstMatch("crs:(Exposure2012|Temperature|Contrast2012|Highlights2012|Shadows2012)", in: x) != nil
    }

    // MARK: - JS `setA`

    private static func setAttribute(_ x: String, _ name: String, _ value: String) -> String {
        let ns = x as NSString
        if let attr = firstMatch("\(NSRegularExpression.escapedPattern(for: name))\(jsSpace)*=\(jsSpace)*\"[^\"]*\"", in: x) {
            return ns.replacingCharacters(in: attr.range, with: "\(name)=\"\(value)\"")
        }
        let element = "(<(?:(?:\(jsWord)|-)+:)?\(NSRegularExpression.escapedPattern(for: name))>)[^<]*(</)"
        if let el = firstMatch(element, in: x) {
            let open = ns.substring(with: el.range(at: 1)), close = ns.substring(with: el.range(at: 2))
            return ns.replacingCharacters(in: el.range, with: open + value + close)
        }
        return insertAfterDescriptionTag(x, " \(name)=\"\(value)\"")
    }

    private static func insertAfterDescriptionTag(_ x: String, _ text: String) -> String {
        guard let tag = firstMatch(descriptionTag, in: x) else { return x }
        return (x as NSString).replacingCharacters(in: NSRange(location: NSMaxRange(tag.range), length: 0), with: text)
    }

    /// JS `/i` without the u flag folds ASCII letters only; ICU's `.caseInsensitive` would also
    /// match `ſ` and the Kelvin sign, so spell the classes out.
    private static func asciiCaseless(_ literal: String) -> String {
        literal.map { c in
            c.isASCII && c.isLetter ? "[\(c.lowercased())\(c.uppercased())]" : NSRegularExpression.escapedPattern(for: String(c))
        }.joined()
    }

    private static func firstMatch(_ pattern: String, in x: String) -> NSTextCheckingResult? {
        // Patterns are fixed literals above; a failure here is a programming error.
        let regex = try! NSRegularExpression(pattern: pattern)
        return regex.firstMatch(in: x, range: NSRange(location: 0, length: (x as NSString).length))
    }
}

/// Port of `exportPlan` from `design/handoff/lumina-cull/lumina-core.js`.
nonisolated enum CullCoreExportPlan {
    enum Target: String, CaseIterable {
        case lightroom = "lr", captureOne = "c1", raw, jpeg = "jpg", both
    }

    struct Item: Equatable {
        /// RAW file name, e.g. `DSC01234.ARW`.
        var file: String
        /// Sidecar name with the existing file's case kept, e.g. `DSC01234.XMP`.
        var xmp: String
        /// Sidecar path relative to the opened folder, when it sits in a subfolder.
        var rel: String?
    }

    struct Entry: Equatable {
        enum Kind: String { case raw, xmp, jpg }
        var path: String
        var kind: Kind
    }

    static func plan(_ target: Target, shoot: String, items: [Item]) -> [Entry] {
        if target == .lightroom || target == .captureOne {
            return items.map { Entry(path: ($0.rel?.isEmpty ?? true) ? $0.xmp : $0.rel!, kind: .xmp) }
        }
        var out: [Entry] = []
        let raw = target == .both ? shoot + "/RAW/" : shoot + "/"
        let jpg = target == .both ? shoot + "/JPEG/" : shoot + "/"
        if target == .raw || target == .both {
            for it in items {
                out.append(Entry(path: raw + it.file, kind: .raw))
                out.append(Entry(path: raw + it.xmp, kind: .xmp))
            }
        }
        if target == .jpeg || target == .both {
            for it in items { out.append(Entry(path: jpg + replacingExtension(it.file) + ".jpg", kind: .jpg)) }
        }
        return out
    }

    /// `file.replace(/\.[^.]+$/, '')` — JS `$` without the m flag is end of input only (ICU `\z`).
    private static func replacingExtension(_ file: String) -> String {
        let regex = try! NSRegularExpression(pattern: "\\.[^.]+\\z")
        let ns = file as NSString
        guard let m = regex.firstMatch(in: file, range: NSRange(location: 0, length: ns.length)) else { return file }
        return ns.replacingCharacters(in: m.range, with: "")
    }
}
