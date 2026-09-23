import CoreGraphics
import CoreImage
import Foundation

nonisolated struct HarmonizationCandidate: Codable, Equatable, Sendable {
    let id: String
    let exposure: Double
    let temperature: Double?
    let tint: Double
    let contrast: Double
    let highlights: Double
    let shadows: Double
    let saturation: Double
    let vibrance: Double

    static let zero = HarmonizationCandidate(
        id: "zero", exposure: 0, temperature: nil, tint: 0, contrast: 0,
        highlights: 0, shadows: 0, saturation: 0, vibrance: 0
    )

    var isValid: Bool {
        let values = [exposure, temperature ?? 6500, tint, contrast, highlights, shadows, saturation, vibrance]
        return !id.isEmpty && values.allSatisfy(\.isFinite)
            && (-1.0...1.0).contains(exposure)
            && (temperature == nil || (2500...10000).contains(temperature!))
            && (-10...10).contains(tint) && (temperature != nil || tint == 0)
            && (-15...15).contains(contrast) && (-40...0).contains(highlights)
            && (0...30).contains(shadows) && (-10...10).contains(saturation)
            && (-10...10).contains(vibrance)
            && (id != "zero" || self == Self.zero)
    }

    var recipe: EditRecipe? {
        guard isValid else { return nil }
        return EditRecipe(
            exposure: exposure, temperature: temperature ?? EditRecipe.neutralTemperature,
            tint: tint, contrast: contrast, highlights: highlights, shadows: shadows,
            vibrance: vibrance, saturation: saturation
        )
    }
}

nonisolated enum HarmonizationMeasurementBridge {
    static let version = "sony-candidate-measurement-1"

    struct Receipt: Codable, Sendable {
        let candidateID: String
        let recipe: EditRecipe
        let recipeFingerprint: String
        let renderIdentity: String
        let engineVersion: String
        let workingSpaceVersion: String
        let policyVersion: String
        let fidelity: String
        let width: Int
        let height: Int
        let measurementSampling: String
        let mean: Double?
        let highlightClipFraction: Double?
        let shadowClipFraction: Double?
        let failures: [String]
        let elapsedMS: Double
        let rawStageCacheHit: Bool
    }

    static func measure(
        candidate: HarmonizationCandidate, source: URL, photoID: UUID,
        fullResolution: Bool
    ) async -> Receipt? {
        guard let recipe = candidate.recipe, source.pathExtension.lowercased() == "arw" else { return nil }
        return await measureRecipe(recipe, candidateID: candidate.id, source: source,
                                   photoID: photoID, fullResolution: fullResolution)
    }

    @MainActor
    static func measureCurrentAuto(source: URL, photoID: UUID, fullResolution: Bool) async -> Receipt? {
        guard source.pathExtension.lowercased() == "arw" else { return nil }
        let session = await PreparedRawSessionRegistry.shared.session(for: photoID, rawURL: source)
        guard let stats = await session.imageStats() else { return nil }
        let asset = AssetRecord(id: photoID, sourceKey: source.path,
            source: SourceReference(originalPath: source.path, relativePath: source.lastPathComponent,
                                    volumeID: "HARMONIZATION", availability: .available),
            filename: source.lastPathComponent)
        return await measureRecipe(AutoDevelop.recipe(for: asset, stats: stats), candidateID: "current_auto",
                                   source: source, photoID: photoID, fullResolution: fullResolution)
    }

    private static func measureRecipe(
        _ recipe: EditRecipe, candidateID: String, source: URL, photoID: UUID, fullResolution: Bool
    ) async -> Receipt {
        let start = Date()
        let request = RawRenderRequest(
            generation: 0, photoID: photoID, rawURL: source, recipe: recipe,
            quality: fullResolution ? .export : .interactive,
            longEdgeCap: fullResolution ? 0 : 640, forDisplay: false
        )
        let result = await DevelopRenderGraph.render(request)
        var failures: [String] = []
        if result.usedProxyFallback { failures.append("proxy_fallback") }
        if result.cancelled || Task.isCancelled { failures.append("cancelled") }
        if result.extent.isEmpty || result.cgImage == nil { failures.append("missing_pixels") }
        let stats = result.cgImage.flatMap { ImageStats.measure(cgImage: $0, maxSampleEdge: 640) }
        if stats == nil { failures.append("missing_measurements") }
        return Receipt(
            candidateID: candidateID, recipe: recipe,
            recipeFingerprint: [recipe.rawIntent.fingerprint, recipe.lookIntent.fingerprint, recipe.geometryIntent.fingerprint].joined(separator: "#"),
            renderIdentity: request.cacheKey,
            engineVersion: RawDecodeBackendRegistry.mappingVersion,
            workingSpaceVersion: DevelopColorPolicy.workingSpaceVersion,
            policyVersion: version,
            fidelity: fullResolution ? "full_resolution_export_bitmap" : "interactive_640",
            width: result.cgImage?.width ?? 0, height: result.cgImage?.height ?? 0,
            measurementSampling: "640-edge Display-P3 8-bit sampled luma; not full-pixel clipping or Lab",
            mean: stats?.mean, highlightClipFraction: stats?.highlightClipFraction,
            shadowClipFraction: stats?.shadowClipFraction, failures: failures,
            elapsedMS: Date().timeIntervalSince(start) * 1000,
            rawStageCacheHit: result.rawStageCacheHit
        )
    }
}
