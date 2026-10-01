import Foundation

// WP-7. The .xmp sidecar Save writes for Lightroom / Capture One (README §4): keepers as 3★,
// edits as develop settings where a Look key has a `crs:` equivalent. An existing sidecar is
// merged, never clobbered: everything in it stays, only the properties Lumina sets change.
// `lumina:Wrote` remembers which those were and `lumina:Replaced` what they replaced, so a later
// save can take back a setting the user reset and put Lightroom's own value back.

public enum XMPSidecar {
    public struct Unreadable: Error, CustomStringConvertible, Equatable {
        public let description = "the existing .xmp can’t be read"
        public init() {}
    }

    public enum Value: Equatable, Sendable { case text(String), seq([String]) }

    public struct Property: Equatable, Sendable {
        public enum Rule: Equatable, Sendable {
            /// Replace whatever is there.
            case set
            /// Leave a value the sidecar already has (process version).
            case ifAbsent
            /// Leave a number that is already at least this (a 5★ from Lightroom stays 5★).
            case atLeast
        }
        /// Canonical prefix ("xmp", "crs", "tiff") and local name ("Rating").
        public var prefix: String, name: String, value: Value, rule: Rule
        public init(_ prefix: String, _ name: String, _ value: Value, rule: Rule = .set) { self.prefix = prefix; self.name = name; self.value = value; self.rule = rule }
        public var key: String { "\(prefix):\(name)" }
    }

    public static let keeperRating = 3
    static let rdfURI = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    static let uris: [String: String] = [
        "xmp": "http://ns.adobe.com/xap/1.0/", "crs": "http://ns.adobe.com/camera-raw-settings/1.0/",
        "tiff": "http://ns.adobe.com/tiff/1.0/", "lumina": "http://ns.lumina.app/sidecar/1.0/",
    ]

    // MARK: Look → develop settings

    /// The Lightroom develop settings for a look. Only the settings the look holds are written;
    /// a missing key is "as shot" and leaves whatever the sidecar says alone.
    /// `orientation` is the file's own EXIF orientation (quarter turns are relative to it).
    public static func develop(_ look: Look, orientation: Int = 1) -> [Property] {
        var p: [Property] = []
        func crs(_ n: String, _ v: String) { p.append(Property("crs", n, .text(v))) }
        func signed(_ v: Double) -> String { let i = Int(v.rounded()); return i > 0 ? "+\(i)" : "\(i)" }
        func plain(_ v: Double) -> String { String(Int(v.rounded())) }
        func num(_ v: Double) -> String {
            var s = String(format: "%.6f", v)
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
            return s == "-0" ? "0" : s
        }

        if let v = look["ev"] { crs("Exposure2012", abs(v) < 0.005 ? "0.00" : String(format: "%+.2f", v)) }
        // Lightroom honours Temperature and Tint only as a pair under "Custom".
        if look["wb"] != nil || look["tint"] != nil {
            crs("WhiteBalance", "Custom")
            crs("Temperature", plain(look["wb"] ?? EditSetting.asShotKelvin))
            crs("Tint", signed(look["tint"] ?? 0))
        }
        for (k, n) in [("hl", "Highlights2012"), ("sh", "Shadows2012"), ("con", "Contrast2012"), ("sat", "Saturation")] {
            if let v = look[k] { crs(n, signed(v)) }
        }
        // The curve: Lumina's three values move the points at ¼, ½ and ¾ by value / 200
        // (prototype `cPts`); Lightroom's point curve is the same points on 0…255.
        if look["cDark"] != nil || look["cMid"] != nil || look["cLight"] != nil {
            func pt(_ x: Double, _ k: String) -> String {
                let y = min(1, max(0, x + (look[k] ?? 0) / 200))
                return "\(Int((x * 255).rounded())), \(Int((y * 255).rounded()))"
            }
            crs("ToneCurveName2012", "Custom")
            p.append(Property("crs", "ToneCurvePV2012", .seq(["0, 0", pt(0.25, "cDark"), pt(0.5, "cMid"), pt(0.75, "cLight"), "255, 255"])))
        }
        for (axis, n) in [("hue", "HueAdjustment"), ("sat", "SaturationAdjustment"), ("lum", "LuminanceAdjustment")] {
            for c in EditSetting.colours { if let v = look["\(axis)_\(c)"] { crs(n + c.prefix(1).uppercased() + c.dropFirst(), signed(v)) } }
        }
        if let v = look["vig"] {
            crs("PostCropVignetteAmount", signed(v))
            crs("PostCropVignetteMidpoint", plain(look["vMid"] ?? 50))
            crs("PostCropVignetteFeather", plain(look["vFeather"] ?? 50))
            crs("PostCropVignetteRoundness", signed(look["vRound"] ?? 0))
            crs("PostCropVignetteStyle", "1")
            crs("PostCropVignetteHighlightContrast", plain(look["vHl"] ?? 0))
        }
        if let v = look["shp"] { crs("Sharpness", plain(v)) }
        if let v = look["nr"] { crs("LuminanceSmoothing", plain(v)) }
        if [CropKey.x, CropKey.y, CropKey.w, CropKey.h, CropKey.angle].contains(where: { look[$0] != nil }) {
            let x = look[CropKey.x] ?? 0, y = look[CropKey.y] ?? 0, w = look[CropKey.w] ?? 1, h = look[CropKey.h] ?? 1
            func unit(_ v: Double) -> String { num(min(1, max(0, v))) }
            crs("HasCrop", "True")
            crs("CropLeft", unit(x)); crs("CropTop", unit(y)); crs("CropRight", unit(x + w)); crs("CropBottom", unit(y + h))
            crs("CropAngle", num(look[CropKey.angle] ?? 0))
            crs("CropConstrainToWarp", "0")
        }
        if let t = look[CropKey.turns], Int(t.rounded()) % 4 != 0 {
            p.append(Property("tiff", "Orientation", .text(String(turned(orientation, by: Int(t.rounded()))))))
        }
        return p
    }

    /// EXIF orientation after `turns` quarter turns to the right.
    public static func turned(_ orientation: Int, by turns: Int) -> Int {
        let right = [1: 6, 6: 3, 3: 8, 8: 1, 2: 7, 7: 4, 4: 5, 5: 2]
        var o = right[orientation] == nil ? 1 : orientation
        for _ in 0..<(((turns % 4) + 4) % 4) { o = right[o] ?? o }
        return o
    }

    /// What a kept photo's sidecar gets: 3★, and the look as develop settings when there is one.
    public static func properties(look: Look?, orientation: Int = 1) -> [Property] {
        var p = [Property("xmp", "Rating", .text(String(keeperRating)), rule: .atLeast)]
        let d = look.map { develop($0, orientation: orientation) } ?? []
        if d.contains(where: { $0.prefix == "crs" }) {
            p += [Property("crs", "Version", .text("15.0"), rule: .ifAbsent), Property("crs", "ProcessVersion", .text("11.0"), rule: .ifAbsent),
                  Property("crs", "HasSettings", .text("True"))]
        }
        return p + d
    }

    // MARK: Merge

    /// The sidecar bytes: `existing` with `properties` applied, or a new sidecar. Throws
    /// `Unreadable` when the existing file isn't XMP (it is then left alone).
    public static func merge(existing: Data?, properties: [Property]) throws -> Data {
        let doc: XMLDocument
        if let existing, !existing.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) {
            guard let d = try? XMLDocument(data: existing, options: []) else { throw Unreadable() }
            doc = d
        } else {
            let blank = "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\" x:xmptk=\"Lumina\"><rdf:RDF xmlns:rdf=\"\(rdfURI)\"><rdf:Description rdf:about=\"\"/></rdf:RDF></x:xmpmeta>"
            doc = try XMLDocument(xmlString: blank, options: [])
        }
        guard let root = doc.rootElement(), let rdf = rdfElement(root) else { throw Unreadable() }
        var descriptions = self.descriptions(rdf)
        if descriptions.isEmpty {
            let d = XMLElement(name: "\(prefix(for: rdfURI, preferred: "rdf", in: rdf)):Description")
            rdf.addChild(d); descriptions = [d]
        }
        let target = descriptions[0]

        // Take back what Lumina wrote last time (putting back what it replaced); what is still
        // wanted is written again below.
        let marker = uris["lumina"]!
        let replaced = (text(marker, "Replaced", in: descriptions)?.data(using: .utf8)).flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
        for key in (text(marker, "Wrote", in: descriptions) ?? "").split(separator: " ").map(String.init) {
            let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let u = uris[parts[0]] else { continue }
            remove(u, parts[1], in: descriptions)
            if let was = replaced[key], let kind = was.first { add(kind == "seq" ? .seq(Array(was.dropFirst())) : .text(was.dropFirst().first ?? ""), u, parts[0], parts[1], to: target) }
        }
        remove(marker, "Wrote", in: descriptions); remove(marker, "Replaced", in: descriptions)

        var wrote: [String] = [], nowReplaced: [String: [String]] = [:]
        for p in properties {
            guard let u = uris[p.prefix] else { continue }
            let old = value(u, p.name, in: descriptions)
            switch p.rule {
            case .ifAbsent: if old != nil { continue }
            case .atLeast: if case .text(let new) = p.value, case .text(let o)? = old, let a = Double(o), let b = Double(new), a >= b { continue }
            case .set: break
            }
            switch old {
            case .text(let v)?: nowReplaced[p.key] = ["text", v]
            case .seq(let items)?: nowReplaced[p.key] = ["seq"] + items
            case nil: break
            }
            remove(u, p.name, in: descriptions)
            add(p.value, u, p.prefix, p.name, to: target)
            wrote.append(p.key)
        }
        func note(_ name: String, _ v: String) {
            target.addAttribute(XMLNode.attribute(withName: "\(prefix(for: marker, preferred: "lumina", in: target)):\(name)", stringValue: v) as! XMLNode)
        }
        if !wrote.isEmpty { note("Wrote", wrote.joined(separator: " ")) }
        if !nowReplaced.isEmpty {
            let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
            note("Replaced", String(decoding: (try? enc.encode(nowReplaced)) ?? Data("{}".utf8), as: UTF8.self))
        }
        let body = root.xmlString(options: [.nodePrettyPrint])
        return Data("<?xpacket begin=\"\u{FEFF}\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\n\(body)\n<?xpacket end=\"w\"?>\n".utf8)
    }

    /// The simple properties of a sidecar by canonical name ("xmp:Rating" → "3"; a sequence's
    /// items are joined with "|"). Properties in namespaces Lumina doesn't write keep the file's
    /// own prefix. Nil when the data isn't XMP.
    public static func read(_ data: Data) -> [String: String]? {
        guard let doc = try? XMLDocument(data: data, options: []), let root = doc.rootElement(), let rdf = rdfElement(root) else { return nil }
        let canonical = Dictionary(uniqueKeysWithValues: uris.map { ($1, $0) })
        var out: [String: String] = [:]
        for d in descriptions(rdf) {
            for a in d.attributes ?? [] {
                guard let n = a.name, let local = a.localName, let u = d.resolveNamespace(forName: n)?.stringValue, u != rdfURI, a.prefix != "xmlns" else { continue }
                out["\(canonical[u] ?? a.prefix ?? ""):\(local)"] = a.stringValue ?? ""
            }
            for c in (d.children ?? []).compactMap({ $0 as? XMLElement }) {
                guard let n = c.name, let local = c.localName, let u = c.resolveNamespace(forName: n)?.stringValue else { continue }
                let items = c.children?.compactMap { $0 as? XMLElement }.first?.children?.compactMap { ($0 as? XMLElement)?.stringValue }
                out["\(canonical[u] ?? c.prefix ?? ""):\(local)"] = items.map { $0.joined(separator: "|") } ?? (c.stringValue ?? "")
            }
        }
        return out
    }

    // MARK: XML helpers

    private static func rdfElement(_ root: XMLElement) -> XMLElement? {
        if root.localName == "RDF" { return root }
        return (root.children ?? []).compactMap { $0 as? XMLElement }.first { $0.localName == "RDF" }
    }
    private static func descriptions(_ rdf: XMLElement) -> [XMLElement] {
        (rdf.children ?? []).compactMap { $0 as? XMLElement }.filter { $0.localName == "Description" }
    }

    /// The prefix bound to `uri` where `el` is, declaring one on `el` when there is none.
    private static func prefix(for uri: String, preferred: String, in el: XMLElement) -> String {
        if let p = el.resolvePrefix(forNamespaceURI: uri), !p.isEmpty { return p }
        var p = preferred, n = 1
        while let bound = el.resolveNamespace(forName: "\(p):x")?.stringValue, bound != uri { p = "\(preferred)\(n)"; n += 1 }
        el.addNamespace(XMLNode.namespace(withName: p, stringValue: uri) as! XMLNode)
        return p
    }

    private static func matches(_ node: XMLNode, _ uri: String, _ name: String, scope: XMLElement) -> Bool {
        guard node.localName == name, let n = node.name else { return false }
        return scope.resolveNamespace(forName: n)?.stringValue == uri
    }

    /// A property as it stands: an attribute or a plain element is text, an element holding an
    /// rdf:Seq (or Bag) is its items.
    private static func value(_ uri: String, _ name: String, in descriptions: [XMLElement]) -> Value? {
        for d in descriptions {
            if let a = (d.attributes ?? []).first(where: { matches($0, uri, name, scope: d) }) { return .text(a.stringValue ?? "") }
            if let c = (d.children ?? []).compactMap({ $0 as? XMLElement }).first(where: { matches($0, uri, name, scope: $0) }) {
                if let list = (c.children ?? []).compactMap({ $0 as? XMLElement }).first { return .seq((list.children ?? []).compactMap { ($0 as? XMLElement)?.stringValue }) }
                return .text(c.stringValue ?? "")
            }
        }
        return nil
    }
    private static func text(_ uri: String, _ name: String, in descriptions: [XMLElement]) -> String? {
        if case .text(let v)? = value(uri, name, in: descriptions) { return v } else { return nil }
    }

    private static func add(_ value: Value, _ uri: String, _ preferred: String, _ name: String, to target: XMLElement) {
        let q = "\(prefix(for: uri, preferred: preferred, in: target)):\(name)"
        switch value {
        case .text(let v): target.addAttribute(XMLNode.attribute(withName: q, stringValue: v) as! XMLNode)
        case .seq(let items):
            let r = prefix(for: rdfURI, preferred: "rdf", in: target)
            let e = XMLElement(name: q), seq = XMLElement(name: "\(r):Seq")
            for i in items { seq.addChild(XMLElement(name: "\(r):li", stringValue: i)) }
            e.addChild(seq); target.addChild(e)
        }
    }

    private static func remove(_ uri: String, _ name: String, in descriptions: [XMLElement]) {
        for d in descriptions {
            for a in (d.attributes ?? []) where matches(a, uri, name, scope: d) { if let n = a.name { d.removeAttribute(forName: n) } }
            for c in (d.children ?? []).compactMap({ $0 as? XMLElement }).reversed() where matches(c, uri, name, scope: c) { d.removeChild(at: c.index) }
        }
    }
}
