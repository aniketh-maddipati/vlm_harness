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

- [ ] 1. `elastic-v4/ui-reconcile` created off the base in its own worktree; the three
  branch tips recorded; the conflict surface recomputed and written into Progress
- [ ] 2. P0 merged; conflicts resolved; gate green
- [ ] 3. P1 merged; conflicts resolved; gate green
- [ ] 4. P2 merged; the duplicate `ExifToolService` fix reconciled to one implementation
  that reads before it waits; gate green
- [ ] 5. Semantic checks cleared on the merged tree: tokens hash and motion golden, forbidden
  literal set, `progressive_render_architecture`, probe mirror sites, shipping fence,
  allowlist ratchet, registry staleness
- [ ] 6. Each stream's own proof re-run here and its numbers recorded, including
  `testEveryTierPresentsTheSameWayUp` and the live capture score
- [ ] 7. Reconciliation record appended to `docs/ELASTIC_PLAN.md`; nothing pushed without
  asking

## Progress

_Append one line per completed item: date, item number, commit sha, and anything the next
pass needs to know — especially anything here that turned out to be wrong._
