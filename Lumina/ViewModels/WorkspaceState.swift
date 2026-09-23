import Foundation

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

    init(
        focusedAssetID: UUID? = nil,
        selectedAssetIDs: [UUID] = [],
        temporarilyExpandedAssetIDs: [UUID] = [],
        comparisonAssetIDs: [UUID] = [],
        currentScope: PropagationRing = .row
    ) {
        self.focusedAssetID = focusedAssetID
        self.selectedAssetIDs = Self.unique(selectedAssetIDs)
        self.temporarilyExpandedAssetIDs = Self.unique(temporarilyExpandedAssetIDs)
        self.comparisonAssetIDs = Self.unique(comparisonAssetIDs)
        self.currentScope = currentScope
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

    mutating func retainAssets(_ validAssetIDs: Set<UUID>) {
        if let focusedAssetID, !validAssetIDs.contains(focusedAssetID) {
            self.focusedAssetID = nil
        }
        selectedAssetIDs.removeAll { !validAssetIDs.contains($0) }
        temporarilyExpandedAssetIDs.removeAll { !validAssetIDs.contains($0) }
        comparisonAssetIDs.removeAll { !validAssetIDs.contains($0) }
    }

    mutating func restore(from durable: WorkspaceRestoreState, availableAssetIDs: Set<UUID>) {
        focusedAssetID = durable.focusedAssetID.flatMap {
            availableAssetIDs.contains($0) ? $0 : nil
        }
        selectedAssetIDs.removeAll()
        temporarilyExpandedAssetIDs.removeAll()
        comparisonAssetIDs.removeAll()
        currentScope = .row
    }

    mutating func clear() {
        focusedAssetID = nil
        selectedAssetIDs.removeAll()
        temporarilyExpandedAssetIDs.removeAll()
        comparisonAssetIDs.removeAll()
        currentScope = .row
    }

    private static func unique(_ assetIDs: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return assetIDs.filter { seen.insert($0).inserted }
    }
}
