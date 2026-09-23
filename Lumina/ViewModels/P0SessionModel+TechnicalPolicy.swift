import Foundation

@MainActor
extension P0SessionModel {
    /// Explicit opt-in deterministic starting points. Geometry and WB survive;
    /// hand/sidecar edits never enter the batch. One undo restores all proposals.
    @discardableResult
    func applyTechnicalPolicy(to ids: [UUID]) -> Int {
        flushPendingEditIfNeeded()
        var marks: [BatchEditMutationCommand.Mark] = []
        for id in Set(ids).sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let asset = assets.first(where: { $0.id == id }), asset.recipeSource == .shot,
                  let stats = asset.imageStats, TechnicalAssist.valid(stats) else { continue }
            let before = recipe(for: id)
            let action = TechnicalAssist.deterministicAction(stats)
            guard let after = TechnicalAssist.recipe(action, base: before, stats: stats),
                  after.valueFingerprint != before.valueFingerprint else { continue }
            marks.append(BatchEditMutationCommand.Mark(assetID: id, before: before, after: after,
                sourceBefore: asset.recipeSource, sourceAfter: .auto))
        }
        return commitBatchEdit(marks: marks, label: "Technical starting points")
    }
}
