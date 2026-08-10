import Foundation

/// Wholesale propagation scope — row → scene → shoot concentric rings (hi-fi H6).
struct PropagationState: Equatable, Sendable {
    var ring: PropagationRing = .row
    var referencePhotoID: AssetID
    var referenceGroupID: String
    var referenceFrame: String
    /// Shoot-persisted hand exclusions — survive re-staging and relaunch.
    var excludedIDs: Set<AssetID> = []

    /// Widen exactly one ring. Returns false when already at shoot.
    mutating func widen() -> Bool {
        switch ring {
        case .row: ring = .scene; return true
        case .scene: ring = .shoot; return true
        case .shoot: return false
        }
    }

    /// Narrow exactly one ring. Returns false at row (caller cancels whole stage).
    mutating func narrow() -> Bool {
        switch ring {
        case .shoot: ring = .scene; return true
        case .scene: ring = .row; return true
        case .row: return false
        }
    }
}

/// Resolved wholesale scope at a ring — ONE count source for A1 copy.
struct PropagationScope: Equatable, Sendable {
    /// In-scope recipients after user exclusions and auto-exclusion.
    var memberIDs: [AssetID]
    /// User exclusions + offline/damaged auto-exclusions (banner arithmetic).
    var excludedCount: Int
    /// Faint second-order halo — proposal only until widened.
    var proposalRecipientIDs: Set<AssetID>
}

extension PropagationState {
    func resolvedScope(
        presentation: WorkspacePresentation,
        model: ProjectViewModel
    ) -> PropagationScope {
        Self.resolveScope(
            ring: ring,
            referencePhotoID: referencePhotoID,
            referenceGroupID: referenceGroupID,
            presentation: presentation,
            model: model,
            userExcluded: excludedIDs
        )
    }

    static func resolveScope(
        ring: PropagationRing,
        referencePhotoID: AssetID,
        referenceGroupID: String,
        presentation: WorkspacePresentation,
        model: ProjectViewModel,
        userExcluded: Set<AssetID>
    ) -> PropagationScope {
        let rowIDs = eligibleIDs(in: referenceGroupID, presentation: presentation, model: model, keptOnly: false)
        let sceneIDs = sceneEligibleIDs(
            referenceGroupID: referenceGroupID,
            presentation: presentation,
            model: model
        )
        let shootIDs = shootEligibleIDs(presentation: presentation, model: model)

        let rawPool: [AssetID]
        let proposalPool: [AssetID]
        switch ring {
        case .row:
            rawPool = rowIDs
            proposalPool = sceneIDs
        case .scene:
            rawPool = sceneIDs
            proposalPool = shootIDs
        case .shoot:
            rawPool = shootIDs
            proposalPool = []
        }

        let autoExcluded = Set(rawPool.filter { !isWholesaleEligible(model: model, id: $0) })
        let userExcludedInPool = userExcluded.intersection(Set(rawPool))
        let excludedCount = userExcludedInPool.count + autoExcluded.count

        var members = rawPool.filter { id in
            !userExcluded.contains(id) && !autoExcluded.contains(id)
        }
        var seen = Set<AssetID>()
        members = members.filter { seen.insert($0).inserted }

        let memberSet = Set(members)
        let proposals = Set(proposalPool.filter { !memberSet.contains($0) && !userExcluded.contains($0) })
            .subtracting(autoExcluded)

        return PropagationScope(
            memberIDs: members,
            excludedCount: excludedCount,
            proposalRecipientIDs: proposals
        )
    }

    // MARK: - Eligibility

    private static func isWholesaleEligible(model: ProjectViewModel, id: AssetID) -> Bool {
        guard let photo = model.photo(with: id) else { return false }
        if photo.sourceAvailability == .missing { return false }
        if photo.tier == .reject { return false }
        let rawExists = FileManager.default.fileExists(atPath: photo.rawPath)
        let previewExists = (photo.previewPath ?? photo.thumbPath).map(FileManager.default.fileExists) ?? false
        if !rawExists && !previewExists { return false }
        return true
    }

    private static func eligibleIDs(
        in groupID: String,
        presentation: WorkspacePresentation,
        model: ProjectViewModel,
        keptOnly: Bool
    ) -> [AssetID] {
        guard let group = presentation.groups.first(where: { $0.id == groupID }) else { return [] }
        return group.captureOrderedAssets.compactMap { asset in
            if keptOnly {
                guard asset.decision == .keep else { return nil }
            } else if asset.decision == .cut {
                return nil
            }
            return asset.id
        }
    }

    private static func sceneEligibleIDs(
        referenceGroupID: String,
        presentation: WorkspacePresentation,
        model: ProjectViewModel
    ) -> [AssetID] {
        let units = TableLayout.swimLaneUnits(from: presentation.groups)
        guard let unit = units.first(where: { $0.groups.contains { $0.id == referenceGroupID } }) else {
            return eligibleIDs(in: referenceGroupID, presentation: presentation, model: model, keptOnly: false)
        }
        return unit.groups.flatMap { group in
            eligibleIDs(in: group.id, presentation: presentation, model: model, keptOnly: false)
        }
    }

    private static func shootEligibleIDs(
        presentation: WorkspacePresentation,
        model: ProjectViewModel
    ) -> [AssetID] {
        presentation.groups.flatMap { group in
            eligibleIDs(in: group.id, presentation: presentation, model: model, keptOnly: false)
        }
    }

    /// Kept frames in a lane — used when a docked chip lands on another lane.
    static func keptIDs(
        inLaneContaining groupID: String,
        presentation: WorkspacePresentation
    ) -> [AssetID] {
        let units = TableLayout.swimLaneUnits(from: presentation.groups)
        let groups: [GroupPresentation]
        if let unit = units.first(where: { $0.groups.contains { $0.id == groupID } }) {
            groups = unit.groups
        } else if let group = presentation.groups.first(where: { $0.id == groupID }) {
            groups = [group]
        } else {
            return []
        }
        return groups.flatMap { group in
            group.captureOrderedAssets.compactMap { asset in
                asset.decision == .keep ? asset.id : nil
            }
        }
    }
}
