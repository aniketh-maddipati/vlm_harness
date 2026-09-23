# Reconcile — land the three UI streams as one tree

## Where you are

Repo: `/Users/aniketh/vlm_harness` (Lumina, native macOS photo culling app, Swift/SwiftUI).

Three streams ran in parallel off `elastic-v4/fixture-generator` (`a4792c5`), each in its
own worktree, each with its own prompt and its own Progress log:

| Branch | Worktree | Prompt | Theme |
|---|---|---|---|
| `elastic-v4/p0-render-proof` | `~/lumina-wt/p0-render-proof` | `docs/prompts/elastic-p0.md` | photo-pixel proof, the flip, three cheap P0s |
| `elastic-v4/p1-grammar` | `~/lumina-wt/p1-grammar` | `docs/prompts/elastic-p1.md` | keys, peeks, before, inferred groups |
| `elastic-v4/p2-scroll` | `~/lumina-wt/p2-scroll` or the main checkout | `docs/prompts/elastic-p2.md` | scroll latency |

Your job is to produce **one branch that contains all three and is green**, without
rewriting any of them. Create **`elastic-v4/ui-reconcile`** off
`elastic-v4/fixture-generator`, in its own worktree (`~/lumina-wt/ui-reconcile`), and
merge the three into it. Run `git branch --show-current` before every build and commit.

**Do not rebase the stream branches.** They are pushed, other sessions hold worktrees on
them, and their prompts tell them to rebase onto `elastic-v4/fixture-generator` only. You
merge *from* them; you never rewrite them. If a stream needs a change to merge cleanly,
make it on the integration branch and tell that stream.

Read `AGENTS.md` and the three prompts — including their **Progress** sections, which are
where each stream recorded what it touched outside its own row.

## Before you start: the streams may still be moving

Two of the three were still committing when this was written. Reconciling a moving branch
is fine; reconciling one and pretending it is final is not.

1. Record the exact tip of each branch you are merging, and put those three shas in the
   merge commit messages and in Progress. "Merged P1" is worthless six hours later.
2. If a stream moves after you merge it, merge the new commits again rather than starting
   over.
3. If a stream is mid-item — its Progress says "partial" or an item is ticked with work
   still open — say so in Progress and merge what exists. Do not wait, and do not finish
   another stream's item for it.

## The conflict surface

Recompute it; do not trust the table below, which was measured at
`p0-render-proof d2b2824` / `p1-grammar ba70ece` / `p2-scroll 5181c75`:

```bash
B=elastic-v4/fixture-generator
for s in p0-render-proof p1-grammar p2-scroll; do
  git diff --name-only $B..elastic-v4/$s > /tmp/$s.files
done
comm -12 /tmp/p0-render-proof.files /tmp/p1-grammar.files
comm -12 /tmp/p0-render-proof.files /tmp/p2-scroll.files
comm -12 /tmp/p1-grammar.files /tmp/p2-scroll.files
```

As measured, the overlap is small and the whole risk is in four files:

- **P0 ∩ P1 — nothing.** They share no file at all.
- **P0 ∩ P2 — `Lumina/Services/ExifToolService.swift` and `docs/ELASTIC_PLAN.md`.**
- **P1 ∩ P2 — `Lumina/ViewModels/P0SessionModel.swift` and
  `Lumina/ViewModels/P0SessionModel+Elastic.swift`.**

### `ExifToolService.swift` — the same bug, fixed twice

Both P0 and P2 hit it and both fixed it: `runData` called `process.waitUntilExit()` before
draining the pipe, so any output past a pipe buffer deadlocked — which an embedded preview
(~600 KB) always is, and which a `-json` capture-date listing becomes at a few hundred
frames. P2 also added `LuminaLogicTests/ExifToolProcessTests.swift`.

Do not take both. **Keep one implementation**, and check the merged result actually has
the property: the pipe is read *before* the wait, and stderr goes to `FileHandle.nullDevice`
rather than into an unread `Pipe` that can fill and block the writer. Keep both test files
only if they assert different things; if they assert the same thing, keep the better one
and say which you dropped.

### `P0SessionModel.swift` / `+Elastic.swift` — two streams, different regions

P1 added peek state and the inferred-groups path; P2 added scroll instrumentation and
touched `openFolder(_:shootName:)` because cards share a `frames` leaf. These are
different regions of the same files and should merge mechanically, but the result must be
read, not just compiled: two streams adding state to one model is exactly where a resolved
conflict compiles and behaves wrongly.

### `docs/ELASTIC_PLAN.md` — append-only, so expect a tail conflict

P0 and P2 both appended. Keep both appends, in either order, and do not reflow the
surrounding lists.

## Semantic conflicts — the ones git will not show you

A clean merge is not a green tree. Check each of these on the merged result:

- **Tokens hash and the motion golden.** P1 changed `design/tokens.yaml` twice, moved
  `artifacts/harness/tokens.hash`, and re-approved `spring_trajectory_place_return` under
  each new digest. If the merged tree's hash does not match an approved golden directory,
  `spring_physics_f07` fails. Re-approve with the **previous payload** — passing then
  proves the token change was motion-neutral. Never approve a payload you have not compared.
- **The forbidden literal set.** P1 added tokens, and every added token makes its value a
  forbidden literal everywhere `magic_numbers` scans (`Views`, `Design`, `Shell`). P0 added
  and rewrote code in that scope. The merged tree can fail where neither branch did.
- **`progressive_render_architecture`.** P0 added REQUIREMENTS for
  `ElasticVersionColumn.swift` (`previewPath(for:)`, `guard index == 1`) and a FORBIDDEN
  entry for `DevelopMetalView.swift`. P1's unfinished item 9 hides the version column under
  the drawer — if that landed, its edit must keep `previewPath` intact.
- **Probe mirror sites.** P1 touched `UITestStateProbe.swift`, `ProbeSnapshot.swift`,
  `LuminaRobot.swift` and `P0LogicTests.swift`. A probe field must exist at all of its
  sites; `probe_mirror` and `probe_growth` fail if a merge drops one.
- **`shipping_fence`.** P2 registered a new runner (`P0ScrollLiveRunner`). Every
  shipping-fenced source must carry `#if !LUMINA_SHIPPING_APP` and end with `#endif`.
- **`allowlist_ratchet` and `registry_staleness`.** Both are counted against a stored
  baseline that each branch may have moved independently. The ratchet may shrink, never grow.
- **The flip fix lives in P2's file.** P0 changed one line and its comment in
  `PreparedRawSession.materializeInteractiveStage` (`destination.isFlipped = false`),
  because `CIImage(mtlTexture:)` does not flip back and every photograph was arriving
  upside down on the interactive tier. If P2 edited that function, keep P0's value and its
  comment, and confirm with the test named below.

## Merge order

Merge the branch with the smallest conflict surface first so that each conflict you do hit
has only one plausible owner:

1. **P0** — shares nothing with P1, and only `ExifToolService.swift` plus the plan with P2.
2. **P1** — shares nothing with P0.
3. **P2** — the only branch that conflicts with both.

Gate after each merge, not once at the end. A merge that breaks the gate should be
attributable to one merge, and the only way to get that is to run the gate three times.

## Gate

```bash
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug -derivedDataPath DD -destination 'platform=macOS,arch=arm64' -only-testing:LuminaLogicTests build-for-testing
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug -derivedDataPath DD -destination 'platform=macOS,arch=arm64' -only-testing:LuminaLogicTests test-without-building
python3 Scripts/harness/run.py fast
python3 Scripts/harness/lint/xcode_compile.py --project-root . --derived-data DD
```

Each stream's own last-recorded numbers are in its Progress section; read them and expect
the merged total to be at least the sum of the new tests, minus any duplicate test file you
deliberately dropped. Baselines drift, so measure the base branch yourself before you start
rather than quoting a number from a prompt.

## Re-prove each stream's claim on the merged tree

Separately green is not together green. Each stream proved something; re-run that proof
here, and record the numbers in Progress:

- **P0** — `PhotoRenderProofTests`, `PreviewOrientationTests`, `ColdOpenStatusTests`. In
  particular `testEveryTierPresentsTheSameWayUp`, which is what catches the interactive-tier
  inversion returning through a bad merge. Also the live capture:
  `--p0-edit-live <out> --p0-open ~/LuminaFixtures/card-elastic-v4/frames`, which scored
  29/31 on P0's branch against 27/31 on the base, measured on the same card.
- **P1** — its live key-driven stress pass in the real Debug app, with screenshots. P1's
  Progress explains the launch trap: while a foreign Lumina Debug instance is running, a
  second one can come up windowless. Check for other instances before concluding a failure
  is yours. **Never `pkill -x Lumina`** — find out whose it is.
- **P2** — its scroll measurement on the stress card, in the same shape as the number it
  recorded, so the two are comparable.

## Running this in a loop

This prompt is written to be re-entered. Each time you start or wake:

1. `git branch --show-current` — confirm you are on your own branch. If it changed under
   you, stop and say so.
2. `git log --oneline -5` and re-read the **Progress** section at the bottom of this file.
   That is the only record of what you already did; the conversation may not survive.
3. Run the gate before changing anything, so you know whether you are starting from green.
4. Do the **next unchecked item only**, then commit, then update **Progress** in this file
   in the same commit.
5. When every item is checked and the gate is green, say so and stop.

Commit after every item, never in a batch. A loop that dies between items must lose at most
one item's work.

## Rules that will bite you

- **The repo squash-merges.** Every `main` commit has one parent, so a stacked branch moves
  with `git rebase --onto origin/main <old-base-sha> <branch>`, never a plain rebase. This
  matters when the integration branch is retargeted at `main`.
- **Authority order:** contract-v6 → `tokens.yaml` → copy-contract → code → tests. A lint
  and the code disagreeing means the code is wrong, not the lint. Resolving a merge is not
  a licence to loosen a check so the tree goes green.
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.** Render/export-path types are explicitly
  `nonisolated`, UI/session helpers explicitly `@MainActor`. A merge that moves a type
  across that line compiles on one branch and not the other.
- **Banned:** `onHover`, `ProgressView`, `.alert`, anything network, and the word "sync" in
  copy. A conflict resolution that reintroduces one of these fails `banned_patterns`.
- Several Claude sessions share `/Users/aniketh/vlm_harness`. Never switch its branch; work
  in `~/lumina-wt/ui-reconcile`.
- Project uses synchronized folders — new files are picked up automatically.

## Wrap up

Append one **Reconciliation** record to `docs/ELASTIC_PLAN.md`: the three shas merged, every
conflict and how it was resolved, every duplicate dropped, and the merged gate numbers. Do
not reflow the surrounding sections.

Commit with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`. **Ask before pushing**
and before opening a pull request; the integration branch is the single PR for the round, so
its description is what the reviewer reads instead of three.

## Checklist

- [x] 1. `elastic-v4/ui-reconcile` created off the base in its own worktree; the three
  branch tips recorded; the conflict surface recomputed and written into Progress
- [x] 2. P0 merged; conflicts resolved; gate green
- [x] 3. P1 merged; conflicts resolved; gate green
- [x] 4. P2 merged; the duplicate `ExifToolService` fix reconciled to one implementation
  that reads before it waits; gate green
- [x] 5. Semantic checks cleared on the merged tree: tokens hash and motion golden, forbidden
  literal set, `progressive_render_architecture`, probe mirror sites, shipping fence,
  allowlist ratchet, registry staleness
- [x] 6. Each stream's own proof re-run here and its numbers recorded, including
  `testEveryTierPresentsTheSameWayUp` and the live capture score
- [x] 7. Reconciliation record appended to `docs/ELASTIC_PLAN.md`; nothing pushed without
  asking

## Progress

_Append one line per completed item: date, item number, commit sha, and anything the next
pass needs to know — especially anything here that turned out to be wrong._

- 2026-09-22 · item 1 · `elastic-v4/ui-reconcile` created off `elastic-v4/fixture-generator`
  `a4792c5` in `~/lumina-wt/ui-reconcile`; this prompt file taken from `4d46a8a` on
  `elastic-v4/next-round` so Progress has somewhere to live. **Tips to merge, recorded at
  creation:** P0 `elastic-v4/p0-render-proof` **d2b2824** (8 commits, 17 files, Progress
  through item 7 + item 3 reopened; nothing partial) · P1 `elastic-v4/p1-grammar`
  **84aa136** (8 commits, 45 files, Progress through item 7; every live check since item 2
  is PENDING behind the no-window launch trap; items 8–9 not started, so the version
  column is untouched) · P2 `elastic-v4/p2-scroll` **1b9f751** (4 commits, 17 files,
  items 1–2 done, item 3 in flight uncommitted in `/Users/aniketh/vlm_harness`, which is
  P2's live checkout — not merged, not touched). All three merge-base at `a4792c5`.
  **Conflict surface, recomputed at those tips:** P0∩P1 = ∅ · P0∩P2 =
  `Lumina/Services/ExifToolService.swift`, `docs/ELASTIC_PLAN.md` · P1∩P2 =
  `Lumina/ViewModels/P0SessionModel.swift`, `Lumina/ViewModels/P0SessionModel+Elastic.swift`.
  Unchanged from the prompt's table, but P1 moved from `ba70ece` to `84aa136` without
  widening it. Both session-model diffs read: P1's regions (peek/drawer/anchor state,
  `keepFrames`, `measureForInference`, variant removal) and P2's (`chaptersCache`,
  `chapterID(containing:)`, `openFolder(_:shootName:)`, `gapInterval`, `startsNewMoment`)
  do not overlap by hunk. P2 does not touch `PreparedRawSession.swift`, so P0's
  `isFlipped = false` has no competitor. Base gate measured before any merge — numbers in
  the item 2 line. Foreign Lumina instances up while this ran: pid 3599 (model-core's
  DD), pid 64132 (Xcode DerivedData `--workbench`, the one P1 hit), pid 8257 (P2's own
  `--p0-scroll-live` on the stress card). None are mine; none killed.
- 2026-09-22 · item 2 · P0 `d2b2824` merged as `a08c050` (item 1 was `0a30416`). No
  conflicts. **Base gate, measured on `a4792c5` before the merge: 285 logic tests / 2
  skipped / 0 failures · FAST 41/41 · xcode_compile OK.** After P0: **304 / 2 skipped / 0
  failures · FAST 41/41 · xcode_compile OK** — +19, matching P0's own last-recorded 304.
  Dry-runs with `git merge-tree` before touching the tree: P1 onto this commit merges
  clean; P2 onto (P0+P1) conflicts only in `ExifToolService.swift`, and the auto-merged
  `ELASTIC_PLAN.md` keeps both appends with zero deleted lines (P0's block at the old
  line 304, P2's at 393). Both session-model files auto-merge with every P1 and P2 hunk
  line present and no line from neither.
- 2026-09-22 · item 3 · P1 `84aa136` merged as `7f3a659` (item 2 was `e3eccdc`). No
  conflicts. Gate: **343 / 2 skipped / 0 failures · FAST 41/41 · xcode_compile OK** —
  285 base + 19 (P0) + 39 (P1), and P1's own last number was 324 = 285 + 39, so nothing
  was lost or double-counted. Tokens hash on the tree is now `de232d00…` with its golden
  directory present; `spring_physics_f07` passed without re-approval.
- 2026-09-22 · item 4 · P2 merged as `d92bcb3` (item 3 was the commit before `7f3a659`'s
  successor; see `git log`). **The tip moved under the merge:** item 1 recorded P2 at
  `1b9f751`, but P2 committed item 3 (`33782bc`, the floor tier) before `git merge` ran,
  so the merge took **33782bc** and the merge message was amended to say so. The
  extra commit overlaps P1 only in `P0SessionModel.swift` (`defer { publishScrollOrder() }`
  at the top of `apply(_:)`, in the same cases P1 stripped `dropVariantPinIfInactive()`
  from — auto-merged, read, coherent) and P0 only in `ELASTIC_PLAN.md`. One conflict,
  `ExifToolService.swift`: resolved to P2's `captureOutput` shape (it is what
  `ExifToolProcessTests` calls) with P0's stderr choice, `FileHandle.nullDevice`, so the
  drain thread is gone. Property checked on the result: stdout `readDataToEndOfFile()`
  on line 115, `waitUntilExit()` on 116, no second `Pipe`. No test file dropped: P0 added
  none for ExifTool, and `PreviewOrientationTests` asserts orientation, not the process
  contract; all three `ExifToolProcessTests` still pass with stderr on the null device
  (200 KB to `/dev/null` cannot block). Gate: **359 / 2 skipped / 0 failures · FAST
  41/41 · xcode_compile OK** — 343 + 16 (P2). The gate log header reads `58aced3`, the
  pre-amend sha of the same tree. P2 is now on item 4 (velocity prefetch), uncommitted.
- 2026-09-22 · item 5 · Semantic checks, all on the merged tree at `d92bcb3`/`411c1d5`,
  from the item-4 gate logs plus direct reads: **tokens hash** `de232d00…` with
  `approved.json` present under it, `spring_physics_f07` OK with no re-approval (P0 and
  P2 never touch `tokens.yaml`, so P1's last digest is the tree's digest) · **forbidden
  literals** `magic_numbers` OK — P0's rewritten `ElasticWrapLayout` / `ElasticVersionColumn`
  and P1's seven added tokens coexist · **`progressive_render_architecture`** OK;
  `ElasticVersionColumn.previewPath(for:)` and `guard index == 1` intact at lines 35–36
  (P1's item 9 has not landed, so nothing hid the column) · **probe mirror** OK; P1's
  `escTransientHoldActive` is at all four sites and the five removed variant fields are
  at none · **`shipping_fence`** OK; `P0ScrollLiveRunner.swift` opens with
  `#if !LUMINA_SHIPPING_APP` and ends with `#endif` · **`allowlist_ratchet`** OK and the
  three allowlists are byte-identical to the base · **`registry_staleness`** OK with P1's
  regenerated coverage artifacts (the one registry change is P1's removal of
  `testVariantPointerTravelDoesNotCullOrSelect`) · **`banned_patterns`** and
  `render_data_plane_isolation` OK, so the resolution reintroduced nothing and moved no
  type across the actor line · **the flip:** `PreparedRawSession.swift:374` reads
  `destination.isFlipped = false` with P0's comment, and `testEveryTierPresentsTheSameWayUp`
  passed in the merged gate (3.48 s, real RAW fixtures). Nothing needed changing.
- 2026-09-22 · item 6 · Each stream's proof re-run on the merged tree (`2e80788`, tree of
  `d92bcb3`); artifacts in `~/lumina-wt/ui-reconcile-proof/` (outside the repo).
  **P0:** `PhotoRenderProofTests` 8/8, `PreviewOrientationTests` 7/7, `ColdOpenStatusTests`
  4/4 in the merged gate, `testEveryTierPresentsTheSameWayUp` passed in 3.48 s on real RAW
  fixtures. Live capture `--p0-edit-live` on `card-elastic-v4/frames`: **30/32** — the same
  two failures as P0's branch and the base (`Quality promotion keeps geometry stable`,
  `Authoritative preview reaches drawable target` 2212/2560), and the denominator is 32
  not 31 because P1's `Peek cycles similar → set` check now runs there and passes. So this
  is P0's 29/31 plus one. Two foreign Lumina instances were up during the run.
  **P2:** `--p0-scroll-live` on the 403-frame stress card, warm, unfilmed, run only after
  P2's own concurrent run had exited: glide 469 steps / 5.0 s, tick p95 **2.90 ms** (P2's
  item-3 record: 0.82–1.18), flick 90 steps tick p95 **10.13 ms** (P2: 9.9–11.3), return
  185 steps p95 **9.03 ms** (P2: 9.45); **wells 0/469, 0/90, 0/185** on every pass, soft
  (floor) tiles 91 / 144 / 0 (P2: 91 / 148 / 0), floor 369 resident at 63.9 MB 1.5 s after
  mount. The runner exits 1 on the flick and return frame-budget checks (8.33 ms), exactly
  as P2's own record does; that residue is row wrap-layout, P0's item, not a merge effect.
  **P1:** the live key-driven pass, 27 screenshots, real key events through System Events in
  the real Debug app: hold-⇥ similar → ↓ set (17 frames, cursor) → ↓ flags (10 groups
  inferred, sharpness measured live), G and ⌘Z inside flags, release, tap-to-pin, ⇥ cycles
  set → flags → past the end closes, Esc, Return opens the photograph (upright, version
  column showing `1 shot` only), hold-⇥ in focus, set strip `1 of 17 in the set`, hold-␣
  before (`everything as shot`), Esc home, 30 ⇥ taps, held-⇥ arrow spam, Esc ×3 → clean
  table. `G` took 0 picks because every candidate was already in the set from P0's capture
  on the same catalog, which is the "proposes, never overrules" rule, not a miss.
  **The launch trap, measured:** while pid 64132 (`com.lumina.app`, Xcode DerivedData
  `--workbench`, launched 14:08:40 by launchd, not any stream's) is up, every second
  instance of that bundle id comes up with only menu-bar windows. A copy of the merged
  build re-signed ad hoc as `com.lumina.app.reconcile` gets its main window — but only on
  about one launch in three, whatever the launch mode, so the driver retries its own
  launch until a window exists. Every key press is guarded by a frontmost-pid check and
  the driver aborts otherwise; it fired zero times. The user stopped an earlier unguarded
  run; nothing foreign was touched or killed at any point. **P1 items 8–9 (f280b9e) are not
  in this tree yet**, so the E drawer shot shows nothing; re-merge follows.
- 2026-09-22 · re-merge (rule 2: a stream that moves is merged again) · Both streams
  closed out after the first round. **P1** `f280b9e` merged as `228b590` (items 8–9: the
  develop drawer on E, `versionColumnVisible` hides the column in `ElasticFocusView` —
  `ElasticVersionColumn.swift` itself untouched, `previewPath(for:)` intact; tokens hash →
  `4a917285…` with its golden; gate **370 / 2 skipped · FAST 41/41 · xcode_compile OK**),
  then `68ccbc1` merged as `aa254ac` (docs only: plan record + Progress close-out, items
  1–10 checked, item 11 open for live re-checks). **P2** `4ca6d2e` merged as `41d0942`
  (items 4–7: velocity prefetch, one bounded request queue, before/after table, close-out;
  P2's own final gate 312). Every merge conflict-free; `ELASTIC_PLAN.md` gained P1's `### P1`
  section and P2's later tables with **zero deleted lines vs the base**. Final gate on
  `41d0942`: **381 logic tests / 2 skipped / 0 failures · FAST 41/41 · xcode_compile OK**
  = 285 + 19 (P0) + 50 (P1, 335−285) + 27 (P2, 312−285), exactly. Item-5 checks re-read on
  this tree: golden dir for `4a917285…` present, `spring_physics_f07` OK, runner fenced,
  flip at line 374 = `false`, allowlists byte-identical to base, all eight lints OK.
  **Final tips: P0 d2b2824 · P1 68ccbc1 · P2 4ca6d2e**; all three unchanged on origin at
  the time of writing. P0's capture and P2's scroll run re-executed on this tree — numbers
  in the item-7 line. P1's guarded key pass was run on the pre-re-merge tree (item 6);
  the E drawer and item 9 were not in it, so those two remain proven by
  `ElasticDevelopTests` (11) and the runner's `editor-drawer` capture only.
- 2026-09-22 · item 7 · Reconciliation record appended at the end of `docs/ELASTIC_PLAN.md`
  (after `## Next`; nothing above it reflowed). Proofs re-run on the final tree `41d0942`:
  **P0 `--p0-edit-live` 31/33** — same two failures as always, denominator up one more for
  P1's `Develop drawer opens on E` check; **P2 `--p0-scroll-live`** wells 0 on all five
  passes, soft tiles glide 0 / flick 0 / dart 547, tick p95 3.37 / 8.84 / 9.70 / 1.74 / 1.90
  ms, floor 369 resident. Artifacts in `~/lumina-wt/ui-reconcile-proof/*-final/`. Every
  checklist item is ticked; gate on the final tree is green (381 / 2 skipped / 0 failures ·
  FAST 41/41 · xcode_compile OK). **Nothing pushed, no PR opened** — both wait for the user.
- 2026-09-22 · pushed and PR opened, both at the user's word: `origin/elastic-v4/ui-reconcile`
  at `8b939bb`, PR **#101** against `elastic-v4/fixture-generator`, description = the
  Reconciliation record. P2's #100 is superseded by it. Anything a stream commits after
  its final tip (P0 d2b2824 · P1 68ccbc1 · P2 4ca6d2e) is a new merge onto this branch.
- 2026-09-22 · second guarded key pass, on the final tree's build re-signed as
  `com.lumina.app.reconcile`, at the user's go: items 8–9 seen under real keys (column hides
  on hold-⇥ and on E, stays on hold-␣). Window on the first launch this time. Screenshots in
  `~/lumina-wt/ui-reconcile-proof/p1-live-final/`; addendum in the plan's Reconciliation
  record. ⌘Z with nothing to undo in the peek undid P0's last journaled keep (17 → 16 in the
  set) — journal behaviour, noted, not fixed here.
- 2026-09-22 · landing order, at the user's "merge in order" · #100 closed as superseded.
  The shell (fixture-generator `a4792c5` + main, branch `elastic-v4/shell-to-main`) landed on
  main as **#102 → f79ac8f** (gate 285 / 41/41). Then `origin/main` merged into this branch
  as `54851fb`: the squash re-added fixture-generator's tree, so 25 files conflicted, and in
  every one main's copy was byte-identical to `a4792c5`, so the round's version won;
  `EditVariantTests.swift` stays deleted. Net change vs the round: #99's three files only.
  Gate after: **381 / 2 skipped / 0 failures · FAST 41/41 · xcode_compile OK**. #101 now
  targets `main`. Next: model-core (#TBD) after this lands, with its five known overlaps.
