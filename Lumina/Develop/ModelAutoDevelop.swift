import Foundation

/// What a vision model suggested, before anything is allowed to reach a recipe.
/// Every field is optional: a key the model omitted means "leave it as the
/// deterministic pass had it", never "set it to zero".
nonisolated struct ModelToneProposal: Equatable, Sendable {
    var exposure: Double?
    var contrast: Double?
    var highlights: Double?
    var shadows: Double?
    var vibrance: Double?
    var saturation: Double?
    /// Kelvin shift relative to the camera's as-shot value, warmer positive.
    var temperatureShift: Double?
    var tintShift: Double?

    init(
        exposure: Double? = nil,
        contrast: Double? = nil,
        highlights: Double? = nil,
        shadows: Double? = nil,
        vibrance: Double? = nil,
        saturation: Double? = nil,
        temperatureShift: Double? = nil,
        tintShift: Double? = nil
    ) {
        self.exposure = exposure
        self.contrast = contrast
        self.highlights = highlights
        self.shadows = shadows
        self.vibrance = vibrance
        self.saturation = saturation
        self.temperatureShift = temperatureShift
        self.tintShift = tintShift
    }

    init?(json: [String: Any]) {
        func number(_ key: String) -> Double? {
            guard let value = (json[key] as? NSNumber)?.doubleValue, value.isFinite else { return nil }
            return value
        }
        self.init(
            exposure: number("exposure"),
            contrast: number("contrast"),
            highlights: number("highlights"),
            shadows: number("shadows"),
            vibrance: number("vibrance"),
            saturation: number("saturation"),
            temperatureShift: number("temperature_shift"),
            tintShift: number("tint_shift")
        )
        let fields = [exposure, contrast, highlights, shadows, vibrance, saturation,
                      temperatureShift, tintShift]
        guard fields.contains(where: { $0 != nil }) else { return nil }
    }
}

/// The auto version, proposed by a local vision model and bounded by the engine.
///
/// The model sees the photograph; the engine decides what it is allowed to do.
/// Its proposal starts from the deterministic `AutoDevelop` recipe — which already
/// carries the camera's native white balance, the horizon straighten and the inert
/// controls pinned at 0 — and each tone value the model suggests is clamped into an
/// *auto band*: far narrower than the sliders, because a first pass should correct
/// a frame, not restyle it. When the model is unreachable, slow, or says nothing
/// usable, the deterministic recipe is the answer, so auto never depends on a server.
nonisolated enum ModelAutoDevelop {

    /// How far auto may move each control. The sliders go much further; auto doesn't.
    enum Band {
        static let exposure: ClosedRange<Double> = -1.0...1.0
        static let contrast: ClosedRange<Double> = -25...25
        static let highlights: ClosedRange<Double> = -60...10
        static let shadows: ClosedRange<Double> = -10...50
        static let vibrance: ClosedRange<Double> = -10...25
        static let saturation: ClosedRange<Double> = -15...15
        static let temperatureShift: ClosedRange<Double> = -800...800
        static let tintShift: ClosedRange<Double> = -15...15
    }

    nonisolated struct Result: Equatable, Sendable {
        var recipe: EditRecipe
        /// `.model` when the model's proposal was used, `.auto` when the pass fell back.
        var source: RecipeSource
        /// Why the model was not used, when it wasn't.
        var fallbackReason: String?
    }

    /// Pure: the same base and proposal always give the same recipe.
    static func bound(_ proposal: ModelToneProposal, onto base: EditRecipe) -> EditRecipe {
        base.updating { recipe in
            if let value = proposal.exposure {
                recipe.exposure = (clamp(value, Band.exposure) / AutoDevelop.exposureStep).rounded()
                    * AutoDevelop.exposureStep
            }
            if let value = proposal.contrast { recipe.contrast = clamp(value, Band.contrast).rounded() }
            if let value = proposal.highlights { recipe.highlights = clamp(value, Band.highlights).rounded() }
            if let value = proposal.shadows { recipe.shadows = clamp(value, Band.shadows).rounded() }
            if let value = proposal.vibrance { recipe.vibrance = clamp(value, Band.vibrance).rounded() }
            if let value = proposal.saturation { recipe.saturation = clamp(value, Band.saturation).rounded() }
            if let value = proposal.temperatureShift {
                recipe.temperature = base.temperature + clamp(value, Band.temperatureShift).rounded()
            }
            if let value = proposal.tintShift {
                recipe.tint = base.tint + clamp(value, Band.tintShift).rounded()
            }
            // Never, whatever the model says: the engine is not honest about these.
            recipe.whites = 0
            recipe.blacks = 0
            recipe.dehaze = 0
        }
    }

    /// Ask the model for one frame; fall back to the deterministic pass on any failure.
    static func proposal(
        for asset: AssetRecord,
        stats: ImageStats,
        client: ChatCompletionsClient
    ) async -> Result {
        let base = AutoDevelop.recipe(for: asset, stats: stats)
        guard let path = asset.thumbPath ?? asset.gridThumbPath ?? asset.proxyPath,
              let jpeg = ModelImage.jpeg(forPreviewAt: path) else {
            return Result(recipe: base, source: .auto, fallbackReason: "no preview to show the model")
        }
        do {
            let json = try await client.completeJSON(
                system: systemPrompt,
                user: userPrompt(stats: stats),
                imageJPEG: jpeg,
                schemaName: "tone_proposal",
                schemaJSON: schemaJSON
            )
            guard let proposal = ModelToneProposal(json: json) else {
                return Result(recipe: base, source: .auto, fallbackReason: "model returned no usable values")
            }
            return Result(recipe: bound(proposal, onto: base), source: .model, fallbackReason: nil)
        } catch {
            return Result(recipe: base, source: .auto, fallbackReason: "model unavailable: \(error)")
        }
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    // MARK: - Prompt

    static let systemPrompt = """
    You are a careful photo editor making a first-pass correction, not a stylistic look. \
    Prefer small moves. Leave a well-exposed, well-balanced photograph close to zero. \
    Answer only with the JSON object requested.
    """

    static func userPrompt(stats: ImageStats) -> String {
        let native = stats.nativeTemperature.map { "\(Int($0.rounded())) K" } ?? "unknown"
        return """
        Propose a global correction for this photograph.
        Measured from the RAW: mean luminance \(format(stats.mean)) (0 black, 1 white), \
        \(format(stats.shadowClipFraction * 100))% of pixels crushed to black, \
        \(format(stats.highlightClipFraction * 100))% clipped to white, camera white balance \(native).
        Fields: exposure in EV; contrast, highlights, shadows, vibrance, saturation from -100 to 100; \
        temperature_shift in Kelvin relative to the camera value (positive warmer); \
        tint_shift from -150 to 150 (positive magenta). Use 0 for anything that needs no change.
        """
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    static let schemaJSON = """
    {"type":"object","additionalProperties":false,
     "required":["exposure","contrast","highlights","shadows","vibrance","saturation","temperature_shift","tint_shift"],
     "properties":{
       "exposure":{"type":"number"},"contrast":{"type":"number"},
       "highlights":{"type":"number"},"shadows":{"type":"number"},
       "vibrance":{"type":"number"},"saturation":{"type":"number"},
       "temperature_shift":{"type":"number"},"tint_shift":{"type":"number"}}}
    """
}
