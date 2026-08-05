import Foundation

/// Keyboard auto-repeat must never stage or commit.
enum BatchKeyFilter {
    /// Returns true when this key-down should be ignored (system auto-repeat).
    static func shouldIgnore(isARepeat: Bool) -> Bool {
        isARepeat
    }
}

enum BatchTreatmentError: Error, Equatable, Sendable {
    case emptySelection
    case nothingStaged
    case alreadyStaged
    case notAwaitingConfirm
}

/// Lifecycle of a multi-photo treatment apply.
enum BatchTreatmentPhase: String, Codable, Hashable, Sendable {
    case idle
    /// Leader recipe previewed on every selected RAW independently.
    case staged
    case committed
}

/// Snapshot used for single-transaction Undo of a batch commit.
struct BatchUndoSnapshot: Codable, Hashable, Sendable {
    let photoIDs: [UUID]
    let priorBindings: [UUID: PhotoEditBinding]
    let priorSharedRecipes: [UUID: EditRecipe]
}

/// Stages a leader recipe across a 2–3 photo selection, then commits on a distinct second Return.
///
/// Grammar (held Command):
/// - ⌘Return → stage
/// - Release Return, keep Command, press Return again → commit
/// - Esc → cancel staged
/// - ⌘Z → undo last committed batch as one transaction
///
/// Empty selections cannot stage or commit. Auto-repeat is rejected.
struct BatchTreatmentSession: Codable, Hashable, Sendable {
    private(set) var phase: BatchTreatmentPhase = .idle
    private(set) var selectedPhotoIDs: [UUID] = []
    private(set) var leaderPhotoID: UUID?
    private(set) var stagedRecipe: EditRecipe?
    /// True after stage until Return is released — blocks commit on the same key-down.
    private(set) var awaitingReturnRelease: Bool = false
    /// True after Return released while staged — next Return (non-repeat) commits.
    private(set) var awaitingConfirmReturn: Bool = false
    private(set) var undoStack: [BatchUndoSnapshot] = []

    var canStage: Bool { !selectedPhotoIDs.isEmpty && phase != .staged }
    var canCommit: Bool { phase == .staged && awaitingConfirmReturn && stagedRecipe != nil }
    var canCancel: Bool { phase == .staged }
    var canUndo: Bool { !undoStack.isEmpty }

    mutating func setSelection(_ ids: [UUID], leader: UUID?) {
        // Preserve staged preview only if selection still contains the same leader set intent.
        selectedPhotoIDs = Array(ids.prefix(3))
        leaderPhotoID = leader ?? selectedPhotoIDs.first
        if selectedPhotoIDs.isEmpty {
            cancelStaging()
        }
    }

    /// ⌘-click add/remove. Does not clear selection on Command release (caller simply stops showing shelf).
    mutating func toggleSelection(photoID: UUID, maxCount: Int = 3) {
        if let idx = selectedPhotoIDs.firstIndex(of: photoID) {
            selectedPhotoIDs.remove(at: idx)
            if leaderPhotoID == photoID {
                leaderPhotoID = selectedPhotoIDs.first
            }
        } else if selectedPhotoIDs.count < maxCount {
            selectedPhotoIDs.append(photoID)
            if leaderPhotoID == nil {
                leaderPhotoID = photoID
            }
        }
        if selectedPhotoIDs.isEmpty {
            cancelStaging()
        }
    }

    /// Stage the leader recipe across the selection. Ignores auto-repeat.
    @discardableResult
    mutating func stage(
        leaderRecipe: EditRecipe,
        isARepeat: Bool
    ) throws -> EditRecipe {
        if BatchKeyFilter.shouldIgnore(isARepeat: isARepeat) {
            throw BatchTreatmentError.nothingStaged
        }
        guard !selectedPhotoIDs.isEmpty else { throw BatchTreatmentError.emptySelection }
        guard phase != .staged else { throw BatchTreatmentError.alreadyStaged }
        stagedRecipe = leaderRecipe
        phase = .staged
        awaitingReturnRelease = true
        awaitingConfirmReturn = false
        return leaderRecipe
    }

    /// Call on Return key-up while Command held.
    mutating func noteReturnReleased() {
        guard phase == .staged, awaitingReturnRelease else { return }
        awaitingReturnRelease = false
        awaitingConfirmReturn = true
    }

    /// Second distinct Return key-down after release — commits into the store.
    @discardableResult
    mutating func confirmCommit(
        into store: inout EditRecipeStore,
        isARepeat: Bool
    ) throws -> BatchUndoSnapshot {
        if BatchKeyFilter.shouldIgnore(isARepeat: isARepeat) {
            throw BatchTreatmentError.nothingStaged
        }
        guard phase == .staged, awaitingConfirmReturn, let recipe = stagedRecipe else {
            throw BatchTreatmentError.notAwaitingConfirm
        }
        guard !selectedPhotoIDs.isEmpty else { throw BatchTreatmentError.emptySelection }

        var priorBindings: [UUID: PhotoEditBinding] = [:]
        var priorShared: [UUID: EditRecipe] = [:]
        for id in selectedPhotoIDs {
            priorBindings[id] = store.binding(for: id)
            if let sharedID = store.binding(for: id).sharedRecipeID, let r = store.recipes[sharedID] {
                priorShared[sharedID] = r
            }
        }

        // Shared recipe — all selected photos link to it (overwrites prior links for this batch).
        let shared = recipe.forked()
        store.upsertShared(shared)
        for id in selectedPhotoIDs {
            store.bindLinked(photoID: id, recipeID: shared.id)
        }

        let snapshot = BatchUndoSnapshot(
            photoIDs: selectedPhotoIDs,
            priorBindings: priorBindings,
            priorSharedRecipes: priorShared
        )
        undoStack.append(snapshot)
        phase = .committed
        stagedRecipe = nil
        awaitingReturnRelease = false
        awaitingConfirmReturn = false
        return snapshot
    }

    mutating func cancelStaging() {
        phase = .idle
        stagedRecipe = nil
        awaitingReturnRelease = false
        awaitingConfirmReturn = false
    }

    /// Undo the complete last batch as one transaction.
    @discardableResult
    mutating func undoLastCommit(into store: inout EditRecipeStore) -> BatchUndoSnapshot? {
        guard let snapshot = undoStack.popLast() else { return nil }
        store.restoreBindings(snapshot.priorBindings)
        for (_, recipe) in snapshot.priorSharedRecipes {
            store.upsertShared(recipe)
        }
        phase = .idle
        return snapshot
    }
}
