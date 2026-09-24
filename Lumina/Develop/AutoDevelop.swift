import Foundation

/// The deterministic first pass the UI calls "auto".
///
/// Pure function of `ImageStats` plus the asset's existing recipe: the same stats
/// always produce the same recipe, on any machine, in any session. It never reads
/// cull, taste, selection, or wall-clock time, and it never decides anything the
/// photographer can't immediately overwrite by hand.
///
/// Only controls the render graph is honest about are touched. Whites, Blacks,
/// Dehaze, Texture and Clarity stay at 0 — they remain inert in the engine
/// (`docs/DEVELOP_ENGINE.md`), so an auto pass that moved them would be claiming
/// a correction the pixels never receive.
nonisolated struct AutoDevelop {
    /// Mid-tone anchor the exposure correction pulls `ImageStats.mean` toward.
    static let meanAnchor = 0.46
    static let exposureGain = 3.0
    static let exposureLimit = 1.5
    static let exposureStep = 0.05
    /// Below this clip fraction a frame counts as "not actually clipping".
    static let clipSignificance = 0.005
    /// Applied when the frame is not clipping at that end — a gentle default curve.
    static let defaultHighlights = -20.0
    static let defaultShadows = 15.0
    static let autoVibrance = 8.0
    /// Beyond this the tilt is assumed intentional and left alone.
    static let horizonCorrectionLimit = 4.0

    /// Auto recipe for one asset. Geometry beyond straighten, crop, profile and
    /// aspect are carried through from whatever the asset already had.
    static func recipe(for asset: AssetRecord, stats: ImageStats) -> EditRecipe {
        let base = asset.recipe ?? .neutral
        return base.updating { recipe in
            recipe.exposure = exposure(mean: stats.mean)
            recipe.highlights = highlights(clipFraction: stats.highlightClipFraction)
            recipe.shadows = shadows(clipFraction: stats.shadowClipFraction)
            recipe.vibrance = autoVibrance
            // Tone Auto preserves the complete starting WB intent. The neutral
            // sentinel resolves camera temperature AND tint in the RAW decoder;
            // adopting only stats.nativeTemperature would create a hybrid pair.
            recipe.straightenDegrees = straightenDegrees(
                base: base.straightenDegrees,
                horizonAngle: stats.horizonAngle
            )
            // Inert in the render graph — an auto pass must not pretend otherwise.
            recipe.whites = 0
            recipe.blacks = 0
            recipe.dehaze = 0
        }
    }

    /// Pull the measured mean toward the mid-tone anchor, bounded and quantized
    /// so two near-identical frames in one burst can't land on different values.
    static func exposure(mean: Double) -> Double {
        let raw = (meanAnchor - mean) * exposureGain
        let bounded = min(max(raw, -exposureLimit), exposureLimit)
        return (bounded / exposureStep).rounded() * exposureStep
    }

    /// Recover only genuinely clipped highlights; otherwise apply the default curve.
    static func highlights(clipFraction: Double) -> Double {
        guard clipFraction > clipSignificance else { return defaultHighlights }
        return -min(80, clipFraction * 3000)
    }

    /// Lift genuinely crushed shadows; otherwise apply the default curve.
    static func shadows(clipFraction: Double) -> Double {
        guard clipFraction > clipSignificance else { return defaultShadows }
        return min(60, clipFraction * 2000)
    }

    /// Straighten replaces only the fine remainder. Any quarter turns the
    /// photographer already applied survive — `straightenDegrees` carries both
    /// (see `docs/ELASTIC_PLAN.md` §4 on deriving orientation rather than forking it).
    static func straightenDegrees(base: Double, horizonAngle: Double?) -> Double {
        let quarterTurns = (base / 90.0).rounded()
        guard let horizonAngle, abs(horizonAngle) < horizonCorrectionLimit else {
            return quarterTurns * 90
        }
        return quarterTurns * 90 + horizonAngle
    }
}
