import Foundation

/// Ask: a sentence becomes a plan, and a plan becomes one undoable move.
///
/// This layer only orchestrates. The vocabulary lives in `AskCommand`, resolution in
/// `AskScopeResolver`, and what a step does to a recipe in `AskPlanApply` — all three
/// pure, so the rules are provable without building a shoot.
@MainActor
extension P0SessionModel {

    // MARK: - Context

    /// The kept set, in shoot order. The resolver takes this as an input rather than
    /// reading it, so it stays testable and independent of the UI branch.
    var askKeptAssetIDs: [UUID] {
        assets.filter { $0.cull == .keep }.map(\.id)
    }

    /// What the ask is about: the frame being inspected, else the focused one.
    var askFocusedAssetID: UUID? {
        inspectingAssetID ?? focusedAssetID
    }

    func askScopeInput(similarLimit: Int = 12) -> AskScopeResolver.Input {
        AskScopeResolver.Input(
            focusedAssetID: askFocusedAssetID,
            assets: assets,
            keptAssetIDs: askKeptAssetIDs,
            selectedAssetIDs: selectedAssetIDs,
            similarLimit: similarLimit
        )
    }

    /// Everything a planner is allowed to know: counts and relationships. No IDs, no
    /// pixels, and no filenames beyond the one on screen.
    func askContext(route: String = "focus") -> AskContext {
        let input = askScopeInput()
        var counts: [AskScope: Int] = [:]
        for scope in AskScope.allCases {
            counts[scope] = AskScopeResolver.frames(for: scope, input: input).count
        }
        return AskContext(
            route: route,
            focusedFilename: askFocusedAssetID.flatMap { id in
                assets.first { $0.id == id }?.filename
            },
            scopeCounts: counts
        )
    }

    // MARK: - Plan

    /// Local model first, keywords when it can't be reached (D67: loopback only).
    nonisolated static func askPlanner(
        transport: any ModelTransport = URLSessionModelTransport()
    ) -> any AskPlanner {
        FallbackAskPlanner(
            primary: ModelAskPlanner(
                client: ChatCompletionsClient(endpoint: .localText, transport: transport)
            ),
            fallback: KeywordAskPlanner()
        )
    }

    /// Interpret a request. Nothing changes until `applyPlan` — the photographer reads
    /// the summary first.
    ///
    /// Returns nil when nothing was understood; a planner that fails is not a plan that
    /// does something arbitrary.
    func planAsk(
        _ request: String,
        planner: any AskPlanner = P0SessionModel.askPlanner()
    ) async -> AskPlan? {
        let context = askContext()
        return try? await planner.plan(request, context: context)
    }

    // MARK: - Apply

    /// Apply a whole plan as **one** undoable move, and return how many frames changed.
    ///
    /// Steps compose in order: a later step touching a frame an earlier step already
    /// moved builds on that result. The `before` recorded in each mark is always the
    /// recipe the frame had *before the plan started*, so one ⌘Z restores the state the
    /// photographer last saw rather than an intermediate one.
    ///
    /// Frames a step can't act on are skipped, not guessed at, and a step that resolves
    /// to a recipe identical to the one already there writes no mark — an ask that
    /// changes nothing must not cost an undo step.
    ///
    /// Cull and the final-set order are never touched; `commitBatchEdit` restores both
    /// around the mutation.
    @discardableResult
    func applyPlan(_ plan: AskPlan) -> Int {
        flushPendingEditIfNeeded()

        let input = askScopeInput()
        let focusRecipe = askFocusedAssetID.map { recipe(for: $0) }

        struct Pending {
            var before: EditRecipe
            var after: EditRecipe
            var sourceBefore: RecipeSource
            var sourceAfter: RecipeSource
        }
        var pending: [UUID: Pending] = [:]

        for step in plan.steps {
            for id in AskScopeResolver.resolve(step, input: input) {
                guard let asset = assets.first(where: { $0.id == id }) else { continue }
                let existing = pending[id]
                let current = existing?.after ?? recipe(for: id)
                let currentSource = existing?.sourceAfter ?? asset.recipeSource
                guard let outcome = AskPlanApply.outcome(
                    of: step.action,
                    on: asset,
                    current: current,
                    currentSource: currentSource,
                    focusRecipe: focusRecipe
                ) else { continue }

                pending[id] = Pending(
                    before: existing?.before ?? recipe(for: id),
                    after: outcome.recipe,
                    sourceBefore: existing?.sourceBefore ?? asset.recipeSource,
                    sourceAfter: outcome.source
                )
            }
        }

        // Sorted by ID so the command's marks are in a stable order on every run —
        // a dictionary's iteration order is not one.
        let marks = pending
            .filter { $0.value.before.valueFingerprint != $0.value.after.valueFingerprint }
            .map { entry in
                BatchEditMutationCommand.Mark(
                    assetID: entry.key,
                    before: entry.value.before,
                    after: entry.value.after,
                    sourceBefore: entry.value.sourceBefore,
                    sourceAfter: entry.value.sourceAfter
                )
            }
            .sorted { $0.assetID.uuidString < $1.assetID.uuidString }

        return commitBatchEdit(marks: marks, label: "Ask")
    }
}
