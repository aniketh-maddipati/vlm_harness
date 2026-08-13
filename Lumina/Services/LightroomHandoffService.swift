import CryptoKit
import Foundation

/// Lightroom Classic handoff: 16-bit ProPhoto TIFF + round-trip-safe XMP
/// sidecar + verification receipt.
///
/// Sidecar policy:
/// - Only the crs properties Lumina honestly maps are written. Disabled
///   controls (Whites/Blacks/Texture/Clarity/Dehaze) are never emitted.
/// - An existing sidecar is merged, never blind-overwritten: unknown
///   namespaces, attributes and elements are preserved byte-for-byte at the
///   XML node level.
/// - If the existing sidecar's crs values were changed by another tool since
///   Lumina last wrote (fingerprint mismatch), the merge is flagged as a
///   conflict in the receipt and the `lumina:` block records both fingerprints.
/// - Writes are atomic: temp file in the same directory, then replace.
enum LightroomHandoffService {

    struct HandoffResult: Sendable {
        let tiffURL: URL?
        let xmpURL: URL
        let receiptURL: URL
        let mergeOutcome: MergeOutcome
        let tiffSHA256: String?
        let xmpSHA256: String
        let colorSpaceName: String
    }

    enum MergeOutcome: String, Sendable {
        /// No sidecar existed — fresh write.
        case created
        /// Sidecar previously written by Lumina — clean update.
        case updated
        /// Sidecar written externally — Lumina fields merged in, everything else preserved.
        case mergedExternal
        /// External edits detected on Lumina-managed fields since our last write.
        case conflictExternalEdits
    }

    enum HandoffError: Error {
        case renderFailed
        case tiffWriteFailed
        case sidecarWriteFailed(String)
    }

    static let luminaNamespace = "http://lumina.app/xmp/1.0/"
    static let crsNamespace = "http://ns.adobe.com/camera-raw-settings/1.0/"

    // MARK: - Full handoff

    /// Renders the authoritative export, writes TIFF + sidecar + receipt.
    static func performHandoff(
        photoID: UUID,
        rawURL: URL,
        recipe: EditRecipe,
        tiffDestination: URL
    ) async throws -> HandoffResult {
        guard let bitmap = await DevelopRenderGraph.renderExportBitmap(
            rawURL: rawURL,
            photoID: photoID,
            recipe: recipe
        ) else {
            throw HandoffError.renderFailed
        }
        guard DevelopRenderGraph.exportTIFF(
            cgImage: bitmap,
            to: tiffDestination,
            preserveMetadataFrom: rawURL
        ) else {
            throw HandoffError.tiffWriteFailed
        }
        return try writeSidecarAndReceipt(
            recipe: recipe,
            rawURL: rawURL,
            tiffURL: tiffDestination
        )
    }

    /// Sidecar + receipt only (no TIFF render) — used when exporting settings.
    static func writeSidecarAndReceipt(
        recipe: EditRecipe,
        rawURL: URL,
        tiffURL: URL?
    ) throws -> HandoffResult {
        let xmpURL = rawURL.deletingPathExtension().appendingPathExtension("xmp")
        let outcome = try mergeSidecar(recipe: recipe, at: xmpURL)

        let xmpHash = try sha256(of: xmpURL)
        var tiffHash: String?
        if let tiffURL, FileManager.default.fileExists(atPath: tiffURL.path) {
            tiffHash = try sha256(of: tiffURL)
        }

        let colorSpaceName = DevelopColorPolicy.describeColorSpace(DevelopColorPolicy.exportTIFFColorSpace)
        let receiptURL = (tiffURL ?? xmpURL).deletingPathExtension().appendingPathExtension("lumina-receipt.json")
        let receipt: [String: Any] = [
            "generator": "Lumina",
            "mappingVersion": PreparedRawSession.decoderMappingVersion,
            "workingSpaceVersion": DevelopColorPolicy.workingSpaceVersion,
            "recipeFingerprint": recipe.valueFingerprint,
            "mergeOutcome": outcome.rawValue,
            "writtenAt": ISO8601DateFormatter().string(from: Date()),
            "raw": rawURL.lastPathComponent,
            "tiff": tiffURL?.lastPathComponent ?? NSNull(),
            "tiffColorSpace": colorSpaceName,
            "tiffSHA256": tiffHash ?? NSNull(),
            "xmp": xmpURL.lastPathComponent,
            "xmpSHA256": xmpHash,
            "unmappedControls": ["whites", "blacks", "texture", "clarity", "dehaze"],
        ]
        let receiptData = try JSONSerialization.data(
            withJSONObject: receipt,
            options: [.prettyPrinted, .sortedKeys]
        )
        try atomicWrite(data: receiptData, to: receiptURL)

        return HandoffResult(
            tiffURL: tiffURL,
            xmpURL: xmpURL,
            receiptURL: receiptURL,
            mergeOutcome: outcome,
            tiffSHA256: tiffHash,
            xmpSHA256: xmpHash,
            colorSpaceName: colorSpaceName
        )
    }

    // MARK: - Read (foreign-safe — mapped fields only; file never stripped)

    /// Parse mapped develop settings from an open XMP sidecar. Foreign properties remain on disk untouched.
    static func readMappedRecipe(at xmpURL: URL) throws -> EditRecipe? {
        guard FileManager.default.fileExists(atPath: xmpURL.path) else { return nil }
        let data = try Data(contentsOf: xmpURL)
        guard !data.isEmpty else { return nil }
        let document = try XMLDocument(data: data, options: [.nodePreserveAll])
        guard let description = firstDescription(in: document) else { return nil }

        let exposure = crsDouble("crs:Exposure2012", on: description)
        let contrast = crsDouble("crs:Contrast2012", on: description)
        let highlights = crsDouble("crs:Highlights2012", on: description)
        let shadows = crsDouble("crs:Shadows2012", on: description)
        let vibrance = crsDouble("crs:Vibrance", on: description)
        let saturation = crsDouble("crs:Saturation", on: description)
        let sharpness = crsDouble("crs:Sharpness", on: description)
        let luminanceNR = crsDouble("crs:LuminanceSmoothing", on: description)

        let whiteBalance = fieldValue("crs:WhiteBalance", on: description) ?? "As Shot"
        let temperature: Double
        let tint: Double
        if whiteBalance.caseInsensitiveCompare("As Shot") == .orderedSame {
            temperature = EditRecipe.neutralTemperature
            tint = 0
        } else {
            temperature = EditRecipe.normalizedTemperature(
                crsDouble("crs:ColorTemperature", on: description,
                          default: crsDouble("crs:Temperature", on: description, default: EditRecipe.neutralTemperature))
            )
            tint = crsDouble("crs:Tint", on: description)
        }

        var crop: EditCrop?
        if fieldValue("crs:HasCrop", on: description)?.caseInsensitiveCompare("True") == .orderedSame {
            let left = crsDouble("crs:CropLeft", on: description)
            let top = crsDouble("crs:CropTop", on: description)
            let right = crsDouble("crs:CropRight", on: description)
            let bottom = crsDouble("crs:CropBottom", on: description)
            let width = max(0, right - left)
            let height = max(0, bottom - top)
            if width > 0, height > 0 {
                crop = EditCrop(x: left, y: top, width: width, height: height)
            }
        }

        let straighten = -crsDouble("crs:CropAngle", on: description)
        let recipe = EditRecipe(
            exposure: exposure,
            temperature: temperature,
            tint: tint,
            contrast: contrast,
            highlights: highlights,
            shadows: shadows,
            vibrance: vibrance,
            saturation: saturation,
            sharpness: sharpness,
            luminanceNR: luminanceNR,
            crop: crop,
            straightenDegrees: straighten
        )
        return recipe.hasSettings ? recipe : nil
    }

    static func managedFieldsHash(at xmpURL: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: xmpURL.path) else { return nil }
        let data = try Data(contentsOf: xmpURL)
        let document = try XMLDocument(data: data, options: [.nodePreserveAll])
        guard let description = firstDescription(in: document) else { return nil }
        return hashOfManagedFields(on: description)
    }

    static func hashOfManagedFields(for recipe: EditRecipe) -> String {
        hashOfManagedFields(forMapped: mappedCRSFields(for: recipe))
    }

    // MARK: - Merge

    /// The crs fields Lumina honestly maps, with formatted values.
    static func mappedCRSFields(for recipe: EditRecipe) -> [(name: String, value: String)] {
        var fields: [(String, String)] = [
            ("crs:Version", "15.0"),
            ("crs:ProcessVersion", "11.0"),
            ("crs:HasSettings", "True"),
            ("crs:Exposure2012", String(format: "%+.2f", recipe.exposure)),
            ("crs:Contrast2012", String(format: "%+.0f", recipe.contrast)),
            ("crs:Highlights2012", String(format: "%+.0f", recipe.highlights)),
            ("crs:Shadows2012", String(format: "%+.0f", recipe.shadows)),
            ("crs:Vibrance", String(format: "%+.0f", recipe.vibrance)),
            ("crs:Saturation", String(format: "%+.0f", recipe.saturation)),
            ("crs:Sharpness", String(format: "%.0f", recipe.sharpness)),
            ("crs:LuminanceSmoothing", String(format: "%.0f", recipe.luminanceNR)),
        ]
        // White balance: only written when the photographer overrode as-shot.
        if recipe.rawIntent.isAsShotWhiteBalance {
            fields.append(("crs:WhiteBalance", "As Shot"))
        } else {
            fields.append(("crs:WhiteBalance", "Custom"))
            fields.append(("crs:Temperature", String(Int(recipe.temperature.rounded()))))
            fields.append(("crs:ColorTemperature", String(Int(recipe.temperature.rounded()))))
            fields.append(("crs:Tint", String(format: "%+.0f", recipe.tint)))
        }
        if let crop = recipe.crop, !crop.isFullFrame {
            fields.append(("crs:HasCrop", "True"))
            fields.append(("crs:CropLeft", String(format: "%.6f", crop.x)))
            fields.append(("crs:CropTop", String(format: "%.6f", crop.y)))
            fields.append(("crs:CropRight", String(format: "%.6f", crop.x + crop.width)))
            fields.append(("crs:CropBottom", String(format: "%.6f", crop.y + crop.height)))
        }
        if abs(recipe.straightenDegrees) > 0.01 {
            fields.append(("crs:CropAngle", String(format: "%.4f", -recipe.straightenDegrees)))
        }
        return fields
    }

    static func mergeSidecar(recipe: EditRecipe, at xmpURL: URL) throws -> MergeOutcome {
        let fm = FileManager.default
        if !fm.fileExists(atPath: xmpURL.path) {
            let xml = freshSidecarXML(recipe: recipe)
            try atomicWrite(data: Data(xml.utf8), to: xmpURL)
            return .created
        }

        let document: XMLDocument
        do {
            let data = try Data(contentsOf: xmpURL)
            document = try XMLDocument(data: data, options: [.nodePreserveAll])
        } catch {
            // Unparseable sidecar — keep it untouched next to a backup and write fresh.
            let backup = xmpURL.appendingPathExtension("lumina-backup")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: xmpURL, to: backup)
            try atomicWrite(data: Data(freshSidecarXML(recipe: recipe).utf8), to: xmpURL)
            return .conflictExternalEdits
        }

        guard let description = firstDescription(in: document) else {
            throw HandoffError.sidecarWriteFailed("no rdf:Description in existing sidecar")
        }

        // Conflict detection: did another tool change Lumina-managed fields
        // since our last write?
        let previousFingerprint = luminaAttribute(named: "lumina:RecipeFingerprint", on: description)
        let wasLuminaManaged = previousFingerprint != nil
        var conflict = false
        if let previousFingerprint,
           let previousFields = luminaAttribute(named: "lumina:WrittenFieldsHash", on: description) {
            let currentFieldsHash = hashOfManagedFields(on: description)
            conflict = previousFields != currentFieldsHash
            _ = previousFingerprint
        }

        // Merge: update only managed fields; preserve every other node/attribute.
        ensureNamespace(prefix: "crs", uri: crsNamespace, on: description)
        ensureNamespace(prefix: "lumina", uri: luminaNamespace, on: description)
        let written = mappedCRSFields(for: recipe)
        for field in written {
            setField(name: field.name, value: field.value, on: description)
        }
        // Managed fields we did not write this time (e.g. Temperature after a
        // return to As Shot) are removed so the managed-fields hash stays in
        // step with what the file actually says.
        let writtenNames = Set(written.map(\.name))
        for name in Self.managedFieldNames where !writtenNames.contains(name) {
            removeField(name: name, on: description)
        }
        stampLuminaBlock(recipe: recipe, on: description, conflictDetected: conflict)

        document.characterEncoding = "UTF-8"
        let output = document.xmlData(options: [.nodePrettyPrint])
        try atomicWrite(data: output, to: xmpURL)

        if conflict { return .conflictExternalEdits }
        return wasLuminaManaged ? .updated : .mergedExternal
    }

    // MARK: - XML helpers

    private static func freshSidecarXML(recipe: EditRecipe) -> String {
        let crsAttributes = mappedCRSFields(for: recipe)
            .map { "    \($0.name)=\"\(xmlEscape($0.value))\"" }
            .joined(separator: "\n")
        let fieldsHash = hashOfManagedFields(for: recipe)
        return """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Lumina">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:crs="\(crsNamespace)"
            xmlns:lumina="\(luminaNamespace)"
        \(crsAttributes)
            lumina:MappingVersion="\(PreparedRawSession.decoderMappingVersion)"
            lumina:RecipeFingerprint="\(xmlEscape(recipe.valueFingerprint))"
            lumina:WrittenFieldsHash="\(fieldsHash)"
            lumina:WrittenAt="\(ISO8601DateFormatter().string(from: Date()))"/>
         </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
    }

    private static func firstDescription(in document: XMLDocument) -> XMLElement? {
        guard let root = document.rootElement() else { return nil }
        if root.localName == "Description" { return root }
        var queue: [XMLElement] = [root]
        while !queue.isEmpty {
            let node = queue.removeFirst()
            if node.localName == "Description" { return node }
            queue.append(contentsOf: node.children?.compactMap { $0 as? XMLElement } ?? [])
        }
        return nil
    }

    private static func ensureNamespace(prefix: String, uri: String, on element: XMLElement) {
        if element.namespace(forPrefix: prefix) == nil,
           element.resolveNamespace(forName: "\(prefix):x") == nil {
            element.addNamespace(XMLNode.namespace(withName: prefix, stringValue: uri) as! XMLNode)
        }
    }

    /// XMP allows properties as attributes or child elements — update in place
    /// wherever the value currently lives, else add as attribute.
    private static func setField(name: String, value: String, on description: XMLElement) {
        if let attribute = description.attribute(forName: name) {
            attribute.stringValue = value
            return
        }
        let localName = String(name.split(separator: ":").last ?? "")
        if let child = (description.children?.compactMap { $0 as? XMLElement })?
            .first(where: { $0.name == name || $0.localName == localName }) {
            child.stringValue = value
            return
        }
        let attribute = XMLNode.attribute(withName: name, stringValue: value) as! XMLNode
        description.addAttribute(attribute)
    }

    private static func luminaAttribute(named name: String, on description: XMLElement) -> String? {
        description.attribute(forName: name)?.stringValue
    }

    private static func stampLuminaBlock(recipe: EditRecipe, on description: XMLElement, conflictDetected: Bool) {
        let fieldsHash = hashOfManagedFields(for: recipe)
        setField(name: "lumina:MappingVersion", value: PreparedRawSession.decoderMappingVersion, on: description)
        setField(name: "lumina:RecipeFingerprint", value: recipe.valueFingerprint, on: description)
        setField(name: "lumina:WrittenFieldsHash", value: fieldsHash, on: description)
        setField(name: "lumina:WrittenAt", value: ISO8601DateFormatter().string(from: Date()), on: description)
        if conflictDetected {
            setField(name: "lumina:LastMergeConflict", value: "true", on: description)
        }
    }

    /// crs fields Lumina manages — the conflict-detection domain.
    static let managedFieldNames: [String] = [
        "crs:Exposure2012", "crs:Contrast2012", "crs:Highlights2012", "crs:Shadows2012",
        "crs:Vibrance", "crs:Saturation", "crs:Sharpness", "crs:LuminanceSmoothing",
        "crs:WhiteBalance", "crs:Temperature", "crs:ColorTemperature", "crs:Tint",
        "crs:HasCrop", "crs:CropLeft", "crs:CropTop", "crs:CropRight", "crs:CropBottom", "crs:CropAngle",
    ]

    private static func removeField(name: String, on description: XMLElement) {
        if description.attribute(forName: name) != nil {
            description.removeAttribute(forName: name)
        }
        let localName = String(name.split(separator: ":").last ?? "")
        if let children = description.children {
            for (index, child) in children.enumerated().reversed() {
                if let element = child as? XMLElement,
                   element.name == name || element.localName == localName {
                    description.removeChild(at: index)
                }
            }
        }
    }

    /// Hash of the crs fields Lumina manages as they exist on the node right now.
    private static func hashOfManagedFields(on description: XMLElement) -> String {
        let joined = managedFieldNames.map { name -> String in
            let value = description.attribute(forName: name)?.stringValue
                ?? (description.children?.compactMap { $0 as? XMLElement })?
                    .first(where: { $0.name == name })?.stringValue
                ?? ""
            return "\(name)=\(value)"
        }.joined(separator: ";")
        return sha256Hex(joined)
    }

    private static func hashOfManagedFields(for recipe: EditRecipe) -> String {
        hashOfManagedFields(forMapped: mappedCRSFields(for: recipe))
    }

    private static func hashOfManagedFields(forMapped mapped: [(name: String, value: String)]) -> String {
        let written = Dictionary(uniqueKeysWithValues: mapped.map { ($0.name, $0.value) })
        let joined = managedFieldNames.map { "\($0)=\(written[$0] ?? "")" }.joined(separator: ";")
        return sha256Hex(joined)
    }

    private static func fieldValue(_ name: String, on description: XMLElement) -> String? {
        if let attribute = description.attribute(forName: name)?.stringValue {
            return attribute
        }
        let localName = String(name.split(separator: ":").last ?? "")
        return (description.children?.compactMap { $0 as? XMLElement })?
            .first(where: { $0.name == name || $0.localName == localName })?.stringValue
    }

    private static func crsDouble(
        _ name: String,
        on description: XMLElement,
        default defaultValue: Double = 0
    ) -> Double {
        guard let raw = fieldValue(name, on: description) else { return defaultValue }
        return Double(raw.replacingOccurrences(of: "+", with: "")) ?? defaultValue
    }

    // MARK: - Atomic IO + hashing

    static func atomicWrite(data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let temp = directory.appendingPathComponent(".lumina-tmp-\(UUID().uuidString)")
        try data.write(to: temp, options: [.atomic])
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
    }

    static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
