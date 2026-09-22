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
    /// A plan is applied to the frames it was **previewed** against, or not at all: if
    /// the focus or the shoot moved between `planAsk` and here so that any scope the
    /// plan uses now resolves to a different number of frames than the summary showed,
    /// the whole plan is refused. "12 frames" on screen must never become 40 on ⏎.
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
        if let expected = plan.expectedCounts {
            for scope in Set(plan.steps.map(\.scope)) {
                let now = AskScopeResolver.frames(for: scope, input: input).count
                guard expected[scope] == now else { return 0 }
            }
        }
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

    // MARK: - Model auto

    /// Model-backed auto over `ids` as **one** undoable move, with bounded concurrency
    /// and a deterministic fallback per frame.
    ///
    /// Every frame is snapshotted at dispatch. When its answer arrives, it becomes a
    /// mark only if the frame still exists and neither its recipe nor its provenance
    /// has moved since. A hand edit, an undo, or a removal that lands while the model
    /// is thinking wins, and the model's answer for that frame is dropped rather than
    /// written over it.
    ///
    /// The batch is all-or-nothing: nothing commits until every frame has answered or
    /// fallen back, and a cancellation before then commits nothing. There is never a
    /// torn batch, and one ⌘Z always covers the whole pass. The cost is that one slow
    /// frame delays the whole batch — bounded by the endpoint's timeout, after which
    /// that frame falls back and the rest commit.
    ///
    /// Same skip rules as `applyAuto`: frames the photographer already spoke for are
    /// left alone unless `force`, and frames with no measurements are never guessed at.
    @discardableResult
    func applyModelAuto(
        to ids: [UUID],
        force: Bool = false,
        client: ChatCompletionsClient? = nil
    ) async -> Int {
        flushPendingEditIfNeeded()
        // Already cancelled: don't fan work out that can never commit.
        guard !Task.isCancelled else { return 0 }
        let client = client ?? ChatCompletionsClient(endpoint: .localVision)

        var dispatches: [ModelAutoBatch.Dispatch] = []
        var seen = Set<UUID>()
        for id in ids where seen.insert(id).inserted {
            guard let asset = assets.first(where: { $0.id == id }) else { continue }
            guard force || asset.recipeSource == .shot else { continue }
            guard let stats = asset.imageStats else { continue }
            dispatches.append(ModelAutoBatch.Dispatch(
                asset: asset,
                stats: stats,
                fingerprintBefore: recipe(for: id).valueFingerprint,
                sourceBefore: asset.recipeSource
            ))
        }
        guard !dispatches.isEmpty else { return 0 }

        let results = await ModelAutoBatch.propose(
            dispatches, client: client, concurrency: ModelAutoBatch.concurrency
        )
        guard !Task.isCancelled else { return 0 }

        var marks: [BatchEditMutationCommand.Mark] = []
        for dispatch in dispatches {
            let id = dispatch.asset.id
            guard let result = results[id],
                  let now = assets.first(where: { $0.id == id }) else { continue }
            let before = recipe(for: id)
            // Stale answer: the frame moved while the model was thinking. Drop it.
            guard before.valueFingerprint == dispatch.fingerprintBefore,
                  now.recipeSource == dispatch.sourceBefore else { continue }
            guard before.valueFingerprint != result.recipe.valueFingerprint else { continue }
            marks.append(BatchEditMutationCommand.Mark(
                assetID: id,
                before: before,
                after: result.recipe,
                sourceBefore: now.recipeSource,
                sourceAfter: result.source
            ))
        }
        return commitBatchEdit(marks: marks, label: "Auto")
    }
}

/// The fan-out behind `applyModelAuto`. Pure of session state: it takes snapshots in
/// and hands results back, and never touches the main actor while frames are in flight.
nonisolated enum ModelAutoBatch {

    /// How many frames are in flight at once. LM Studio serves four in parallel; a
    /// fifth would queue there anyway, so it queues here, where it can be cancelled.
    static let concurrency = 4

    /// What one frame looked like when it was sent. Anything that has changed by the
    /// time the answer arrives makes that answer stale.
    nonisolated struct Dispatch: Sendable {
        var asset: AssetRecord
        var stats: ImageStats
        var fingerprintBefore: String
        var sourceBefore: RecipeSource
    }

    static func propose(
        _ dispatches: [Dispatch],
        client: ChatCompletionsClient,
        concurrency: Int
    ) async -> [UUID: ModelAutoDevelop.Result] {
        await withTaskGroup(of: (UUID, ModelAutoDevelop.Result).self) { group in
            var results: [UUID: ModelAutoDevelop.Result] = [:]
            var next = 0
            let limit = max(1, concurrency)

            func enqueue() {
                guard next < dispatches.count else { return }
                let dispatch = dispatches[next]
                next += 1
                group.addTask {
                    let result = await ModelAutoDevelop.proposal(
                        for: dispatch.asset, stats: dispatch.stats, client: client
                    )
                    return (dispatch.asset.id, result)
                }
            }

            for _ in 0..<min(limit, dispatches.count) { enqueue() }
            while let (id, result) = await group.next() {
                results[id] = result
                enqueue()
            }
            return results
        }
    }
}
