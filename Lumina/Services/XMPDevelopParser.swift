import Foundation

/// Parses Adobe Lightroom / Camera Raw `crs:*` develop settings via exiftool JSON.
enum XMPDevelopParser {
    struct TasteLibrary {
        var mean: DevelopRecipe
        var entries: [TasteEntry]
    }

    static func buildTasteLibrary(from jpgFolder: URL) -> TasteLibrary {
        let recipes = batchParse(folder: jpgFolder)
        guard !recipes.isEmpty else {
            return TasteLibrary(mean: .neutral, entries: [])
        }

        var entries: [TasteEntry] = []
        for (path, recipe) in recipes {
            let url = URL(fileURLWithPath: path)
            let embedding = EmbeddingService.embed(url: url)
            entries.append(TasteEntry(
                filename: url.lastPathComponent,
                path: path,
                recipe: recipe,
                embedding: embedding
            ))
        }

        return TasteLibrary(mean: meanRecipe(entries.map(\.recipe)), entries: entries)
    }

    static func batchParse(folder: URL) -> [(String, DevelopRecipe)] {
        guard ExifToolService.isAvailable else { return [] }
        let args = [
            "-json", "-q", "-q",
            "-XMP-crs:Exposure2012",
            "-XMP-crs:ColorTemperature",
            "-XMP-crs:Tint",
            "-XMP-crs:Contrast2012",
            "-XMP-crs:Highlights2012",
            "-XMP-crs:Shadows2012",
            "-XMP-crs:Whites2012",
            "-XMP-crs:Blacks2012",
            "-XMP-crs:Texture",
            "-XMP-crs:Clarity2012",
            "-XMP-crs:Dehaze",
            "-XMP-crs:Vibrance",
            "-XMP-crs:Saturation",
            "-XMP-crs:Sharpness",
            "-XMP-crs:LuminanceSmoothing",
            "-ext", "jpg",
            "-ext", "jpeg",
            "-ext", "heic",
            "-ext", "tif",
            "-ext", "tiff",
            "-ext", "dng",
            folder.path,
        ]
        guard let data = try? ExifToolService.runDataPublic(arguments: args),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return json.compactMap { item in
            guard let source = item["SourceFile"] as? String else { return nil }
            return (source, recipe(from: item))
        }
    }

    static func recipe(from item: [String: Any]) -> DevelopRecipe {
        DevelopRecipe(
            exposure: d(item["Exposure2012"]),
            temperature: d(item["ColorTemperature"], default: 6500),
            tint: d(item["Tint"]),
            contrast: d(item["Contrast2012"]),
            highlights: d(item["Highlights2012"]),
            shadows: d(item["Shadows2012"]),
            whites: d(item["Whites2012"]),
            blacks: d(item["Blacks2012"]),
            texture: d(item["Texture"]),
            clarity: d(item["Clarity2012"]),
            dehaze: d(item["Dehaze"]),
            vibrance: d(item["Vibrance"]),
            saturation: d(item["Saturation"]),
            sharpness: d(item["Sharpness"]),
            luminanceNR: d(item["LuminanceSmoothing"]),
            sourceNeighbors: [],
            confidence: 1
        )
    }

    /// Destructive whole-file overwrite — superseded by
    /// `LightroomHandoffService.mergeSidecar`, which preserves external edits.
    @available(*, deprecated, message: "Use LightroomHandoffService.writeSidecarAndReceipt — this overwrites external sidecar edits.")
    static func writeSidecar(recipe: DevelopRecipe, nextTo rawURL: URL) throws {
        let xmpURL = rawURL.deletingPathExtension().appendingPathExtension("xmp")
        let xml = """
        <?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
            crs:Version="15.0"
            crs:ProcessVersion="11.0"
            crs:HasSettings="True"
            crs:Exposure2012="\(fmt(recipe.exposure))"
            crs:Contrast2012="\(fmt(recipe.contrast))"
            crs:Highlights2012="\(fmt(recipe.highlights))"
            crs:Shadows2012="\(fmt(recipe.shadows))"
            crs:Whites2012="\(fmt(recipe.whites))"
            crs:Blacks2012="\(fmt(recipe.blacks))"
            crs:Texture="\(fmt(recipe.texture))"
            crs:Clarity2012="\(fmt(recipe.clarity))"
            crs:Dehaze="\(fmt(recipe.dehaze))"
            crs:Vibrance="\(fmt(recipe.vibrance))"
            crs:Saturation="\(fmt(recipe.saturation))"
            crs:Sharpness="\(fmt(recipe.sharpness))"
            crs:LuminanceSmoothing="\(fmt(recipe.luminanceNR))"
            crs:Temperature="\(Int(recipe.temperature.rounded()))"
            crs:Tint="\(fmt(recipe.tint))"
            crs:ColorTemperature="\(Int(recipe.temperature.rounded()))"/>
         </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
        try xml.write(to: xmpURL, atomically: true, encoding: .utf8)
    }

    private static func meanRecipe(_ recipes: [DevelopRecipe]) -> DevelopRecipe {
        guard !recipes.isEmpty else { return .neutral }
        let n = Double(recipes.count)
        func avg(_ keyPath: KeyPath<DevelopRecipe, Double>) -> Double {
            recipes.map { $0[keyPath: keyPath] }.reduce(0, +) / n
        }
        return DevelopRecipe(
            exposure: avg(\.exposure),
            temperature: avg(\.temperature),
            tint: avg(\.tint),
            contrast: avg(\.contrast),
            highlights: avg(\.highlights),
            shadows: avg(\.shadows),
            whites: avg(\.whites),
            blacks: avg(\.blacks),
            texture: avg(\.texture),
            clarity: avg(\.clarity),
            dehaze: avg(\.dehaze),
            vibrance: avg(\.vibrance),
            saturation: avg(\.saturation),
            sharpness: avg(\.sharpness),
            luminanceNR: avg(\.luminanceNR),
            sourceNeighbors: ["mean-\(recipes.count)"],
            confidence: 0.7
        )
    }

    private static func d(_ value: Any?, default defaultValue: Double = 0) -> Double {
        guard let value else { return defaultValue }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String {
            return Double(s.replacingOccurrences(of: "+", with: "")) ?? defaultValue
        }
        return defaultValue
    }

    private static func fmt(_ v: Double) -> String {
        String(format: "%.2f", v)
    }
}
