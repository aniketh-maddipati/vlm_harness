import Foundation

/// What one step does to one frame's recipe.
///
/// Pure and session-free: given a frame, its current recipe and the focused frame's
/// recipe, this decides the next recipe and its provenance. Keeping it out of the
/// session means every rule here is provable without building a shoot.
///
/// Culling is absent by construction — there is no case that reads or writes `cull`.
nonisolated enum AskPlanApply {

    nonisolated struct Outcome: Equatable, Sendable {
        var recipe: EditRecipe
        var source: RecipeSource
    }

    /// Nil when the step has nothing to do to this frame — an empty delta, a version
    /// the frame doesn't have, or an auto pass with no measurements behind it.
    /// A skipped frame writes no mark, so it never enters the undo step.
    static func outcome(
        of action: AskAction,
        on asset: AssetRecord,
        current: EditRecipe,
        currentSource: RecipeSource,
        focusRecipe: EditRecipe?
    ) -> Outcome? {
        switch action {
        case .adjust(let delta):
            guard !delta.isEmpty else { return nil }
            return Outcome(recipe: delta.apply(to: current), source: handSource(after: currentSource))

        case .syncFromFocus(let groups):
            guard let focusRecipe, !groups.isEmpty else { return nil }
            return Outcome(
                recipe: copy(groups, from: focusRecipe, onto: current),
                source: handSource(after: currentSource)
            )

        case .version(let version):
            switch version {
            case 1:
                return Outcome(recipe: asShot(from: current), source: .shot)
            case 2:
                // Same refusal as `applyAuto`: no measurements, no invented correction.
                guard let stats = asset.imageStats else { return nil }
                return Outcome(recipe: AutoDevelop.recipe(for: asset, stats: stats), source: .auto)
            case 3:
                guard let hand = asset.handRecipe else { return nil }
                return Outcome(recipe: hand, source: .hand)
            default:
                return nil
            }

        case .auto:
            guard let stats = asset.imageStats else { return nil }
            return Outcome(recipe: AutoDevelop.recipe(for: asset, stats: stats), source: .auto)
        }
    }

    /// A hand move on top of an engine recipe stays distinguishable from one made from
    /// scratch: `.autoHand` when the engine got there first, `.hand` otherwise. A frame
    /// whose truth came from a sidecar becomes `.hand` — the photographer has now
    /// overridden the receipt, and pretending otherwise would misreport provenance.
    static func handSource(after source: RecipeSource) -> RecipeSource {
        switch source {
        case .auto, .model, .autoHand:
            return .autoHand
        case .shot, .hand, .sidecar:
            return .hand
        }
    }

    /// Copy tone groups from the focused frame.
    ///
    /// Geometry — crop, straighten and retouch — is deliberately never copied. Where a
    /// photograph is cut and what was healed out of it are decisions about *that* frame;
    /// a treatment is not.
    static func copy(
        _ groups: [AskSyncGroup],
        from source: EditRecipe,
        onto target: EditRecipe
    ) -> EditRecipe {
        target.updating { recipe in
            for group in groups {
                switch group {
                case .light:
                    recipe.exposure = source.exposure
                    recipe.contrast = source.contrast
                    recipe.highlights = source.highlights
                    recipe.shadows = source.shadows
                    recipe.whites = source.whites
                    recipe.blacks = source.blacks
                case .color:
                    recipe.temperature = source.temperature
                    recipe.tint = source.tint
                    recipe.vibrance = source.vibrance
                    recipe.saturation = source.saturation
                case .detail:
                    recipe.texture = source.texture
                    recipe.clarity = source.clarity
                    recipe.dehaze = source.dehaze
                    recipe.sharpness = source.sharpness
                    recipe.luminanceNR = source.luminanceNR
                case .profile:
                    recipe.cameraProfile = source.cameraProfile
                }
            }
        }
    }

    /// "As shot" returns the develop parameters to neutral and keeps the framing.
    /// A crop and a straighten are decisions about the photograph, not a treatment,
    /// so version 1 must not silently un-crop a frame.
    ///
    /// Built by mutating `current` rather than starting from `EditRecipe.neutral` so the
    /// recipe keeps its own identity.
    static func asShot(from current: EditRecipe) -> EditRecipe {
        let neutral = EditRecipe.neutral
        return current.updating { recipe in
            recipe.exposure = neutral.exposure
            recipe.temperature = neutral.temperature
            recipe.tint = neutral.tint
            recipe.contrast = neutral.contrast
            recipe.highlights = neutral.highlights
            recipe.shadows = neutral.shadows
            recipe.whites = neutral.whites
            recipe.blacks = neutral.blacks
            recipe.texture = neutral.texture
            recipe.clarity = neutral.clarity
            recipe.dehaze = neutral.dehaze
            recipe.vibrance = neutral.vibrance
            recipe.saturation = neutral.saturation
            recipe.sharpness = neutral.sharpness
            recipe.luminanceNR = neutral.luminanceNR
            recipe.cameraProfile = neutral.cameraProfile
            // crop, cropAspect, straightenDegrees and retouch are deliberately kept.
        }
    }
}
