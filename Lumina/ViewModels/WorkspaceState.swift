import Foundation

/// The only fields a temporary edit branch may replace.
struct EditVariantOverride: Equatable, Sendable {
    var exposure: Double?
    var temperature: Double?
    var tint: Double?
}

/// Four transient branches over one asset and one shared recipe.
struct EditVariantSession: Equatable, Sendable {
    static let count = 4

    let assetID: UUID
    private(set) var sharedRecipe: EditRecipe
    private(set) var overrides: [EditVariantOverride]

    init(assetID: UUID, sharedRecipe: EditRecipe) {
        self.assetID = assetID
        self.sharedRecipe = sharedRecipe
        overrides = Array(repeating: EditVariantOverride(), count: Self.count)
    }

    var assetIDs: [UUID] {
        Array(repeating: assetID, count: overrides.count)
    }

    mutating func setSharedExposure(_ exposure: Double) {
        sharedRecipe.exposure = exposure
    }

    mutating func setExposure(_ exposure: Double?, forVariantAt index: Int) {
        guard overrides.indices.contains(index) else { return }
        overrides[index].exposure = exposure
    }

    mutating func setWhiteBalance(
        temperature: Double?,
        tint: Double?,
        forVariantAt index: Int
    ) {
        guard overrides.indices.contains(index) else { return }
        overrides[index].temperature = temperature
        overrides[index].tint = tint
    }

    func recipe(forVariantAt index: Int) -> EditRecipe? {
        guard overrides.indices.contains(index) else { return nil }
        let layer = overrides[index]
        return sharedRecipe.updating { recipe in
            if let exposure = layer.exposure {
                recipe.exposure = exposure
            }
            if let temperature = layer.temperature {
                recipe.temperature = temperature
            }
            if let tint = layer.tint {
                recipe.tint = tint
            }
        }
    }
}

/// Session-only visual interaction state.
///
/// Asset data stays in `AssetRecord`; this state refers to assets only by stable ID.
/// Only the focused ID crosses into `WorkspaceRestoreState`.
struct WorkspaceState: Equatable, Sendable {
    private(set) var focusedAssetID: UUID?
    private(set) var selectedAssetIDs: [UUID]
    private(set) var temporarilyExpandedAssetIDs: [UUID]
    private(set) var comparisonAssetIDs: [UUID]
    private(set) var currentScope: PropagationRing
    private(set) var editVariants: EditVariantSession?
    private(set) var editVariantCancellationCount = 0

    /// Branching itself owns no decode or rendering resources.
    var editVariantRawSessionCount: Int { 0 }
    var editVariantRenderCount: Int { 0 }
    var editVariantMemoryDelta: String { "UNMEASURED" }
    var editVariantTimeToShowFour: String { "UNMEASURED" }

    init(
        focusedAssetID: UUID? = nil,
        selectedAssetIDs: [UUID] = [],
        temporarilyExpandedAssetIDs: [UUID] = [],
        comparisonAssetIDs: [UUID] = [],
        currentScope: PropagationRing = .row,
        editVariants: EditVariantSession? = nil
    ) {
        self.focusedAssetID = focusedAssetID
        self.selectedAssetIDs = Self.unique(selectedAssetIDs)
        self.temporarilyExpandedAssetIDs = Self.unique(temporarilyExpandedAssetIDs)
        self.comparisonAssetIDs = Self.unique(comparisonAssetIDs)
        self.currentScope = currentScope
        self.editVariants = editVariants
    }

    mutating func focus(_ assetID: UUID?) {
        focusedAssetID = assetID
    }

    mutating func select(_ assetIDs: [UUID]) {
        selectedAssetIDs = Self.unique(assetIDs)
    }

    mutating func toggleSelection(_ assetID: UUID) {
        if let index = selectedAssetIDs.firstIndex(of: assetID) {
            selectedAssetIDs.remove(at: index)
        } else {
            selectedAssetIDs.append(assetID)
        }
    }

    mutating func expandTemporarily(_ assetIDs: [UUID]) {
        temporarilyExpandedAssetIDs = Self.unique(assetIDs)
    }

    mutating func releaseTemporaryExpansion() {
        temporarilyExpandedAssetIDs.removeAll()
    }

    mutating func compare(_ assetIDs: [UUID]) {
        comparisonAssetIDs = Self.unique(assetIDs)
    }

    mutating func setScope(_ scope: PropagationRing) {
        currentScope = scope
    }

    mutating func beginEditVariants(assetID: UUID, sharedRecipe: EditRecipe) {
        editVariants = EditVariantSession(assetID: assetID, sharedRecipe: sharedRecipe)
    }

    mutating func setSharedVariantExposure(_ exposure: Double) {
        editVariants?.setSharedExposure(exposure)
    }

    mutating func setVariantExposure(_ exposure: Double?, at index: Int) {
        editVariants?.setExposure(exposure, forVariantAt: index)
    }

    mutating func setVariantWhiteBalance(
        temperature: Double?,
        tint: Double?,
        at index: Int
    ) {
        editVariants?.setWhiteBalance(
            temperature: temperature,
            tint: tint,
            forVariantAt: index
        )
    }

    mutating func takeEditVariant(at index: Int) -> (assetID: UUID, recipe: EditRecipe)? {
        guard let session = editVariants,
              let recipe = session.recipe(forVariantAt: index) else { return nil }
        editVariants = nil
        return (session.assetID, recipe)
    }

    mutating func cancelEditVariants() {
        guard editVariants != nil else { return }
        editVariants = nil
        editVariantCancellationCount += 1
    }

    mutating func retainAssets(_ validAssetIDs: Set<UUID>) {
        if let focusedAssetID, !validAssetIDs.contains(focusedAssetID) {
            self.focusedAssetID = nil
        }
        selectedAssetIDs.removeAll { !validAssetIDs.contains($0) }
        temporarilyExpandedAssetIDs.removeAll { !validAssetIDs.contains($0) }
        comparisonAssetIDs.removeAll { !validAssetIDs.contains($0) }
        if let assetID = editVariants?.assetID, !validAssetIDs.contains(assetID) {
            editVariants = nil
        }
    }

    mutating func restore(from durable: WorkspaceRestoreState, availableAssetIDs: Set<UUID>) {
        focusedAssetID = durable.focusedAssetID.flatMap {
            availableAssetIDs.contains($0) ? $0 : nil
        }
        selectedAssetIDs.removeAll()
        temporarilyExpandedAssetIDs.removeAll()
        comparisonAssetIDs.removeAll()
        currentScope = .row
        editVariants = nil
    }

    mutating func clear() {
        focusedAssetID = nil
        selectedAssetIDs.removeAll()
        temporarilyExpandedAssetIDs.removeAll()
        comparisonAssetIDs.removeAll()
        currentScope = .row
        editVariants = nil
    }

    private static func unique(_ assetIDs: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return assetIDs.filter { seen.insert($0).inserted }
    }
}
