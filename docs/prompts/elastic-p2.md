# P2 — Scroll latency to near zero, without giving up resolution or RAW

## Where you are

Repo: `/Users/aniketh/vlm_harness` (Lumina, native macOS photo culling app, Swift/SwiftUI).
Branch: create **`elastic-v4/p2-scroll`** off `elastic-v4/fixture-generator`
(`541119f` or later) and stay on it. Run `git branch --show-current` before every build
and commit.

```
596802c  checkpoint 03 (base)
1b74acc  Elastic surfaces match the prototype's own numbers
34f001d  Fixture cards generator
59d1cf7  Index assets by id; pin the orientation contract
596362a  Plan: the elasticity backlog          ← branch from here
9745c9e  WIP model assist (unmergeable, parked)
```

All three branches are pushed to `origin`.

**`elastic-v4/model-assist` is superseded** — pre-ruling WIP that fails `banned_patterns`.
The question it was parked on was answered by **D67 / R-N.1 (model inference is
loopback-only)**, which landed on `elastic-v4/model-core`. That branch comes off
checkpoint-02 and does not contain the Elastic shell; reconciling the two lineages is a
separate decision. Leave both alone.

Read `AGENTS.md`, `docs/DEVELOP_ENGINE.md`, and `docs/ELASTIC_PLAN.md` ("Elasticity
backlog").

## The goal

Scrolling the time table should never block on a decode, and should never show an empty
well, **while** full resolution and true RAW development are preserved for the focused
frame and for export. Those two are not in tension: nothing on the scroll path needs a
RAW decode.

## What is already right — do not rebuild it

- `BrowsePixelService` with a `grid` / `focused` tier ladder and `pinnedPaths`.
- `DevelopRenderScheduler` with `visibleRenderGate` (limit 1) and `speculativeRenderGate`,
  plus `quality: .interactive` / `.settled`.
- `PreparedRawSession` with `materializeInteractiveStage`, `interactiveCacheLimit = 2`,
  `pinnedInteractiveDecode`.
- `OrientedDisplayImage.stablePresent`, which keeps the oriented browse frame on screen
  when a promotion arrives in the opposite aspect — geometry must not jump.
- The no-remount contract: one permanent Metal leaf per focused photograph.
  `progressive_render_architecture` pins this and it is right; do not weaken it to make
  a measurement look better.

## The work

### 1. Measure first

`LatencyMetrics` already records `p0.edit.open_preview_ms` and the runner reports a
`rapidScrub` window with p50/p95/p99 and a `blankSeen` flag. Get a scroll-specific
number before changing anything, and keep it in the same shape so it can be compared
across runs. A change that is not measured is not a fix.

Generate a large card to measure against — the generator takes a `--name`, so cut one
with far more frames than the default 27 by extending the card plan, or point
`--raw-dir` at a bigger pool.

### 2. Never decode on the scroll path

Scroll should only ever sample an already-resident texture. A miss draws the well and
enqueues; it never blocks and never decodes inline. Audit for anything synchronous
reached from a tile's `body`.

### 3. A guaranteed-resident floor tier

Keep a small entry (~256 px long edge) for every frame in the shoot so scroll always has
something real rather than an empty well. At 94 frames that is roughly 16 MB; at 2000 it
is not, so cap the tier and evict by distance from the viewport rather than by recency.
Decide the cap explicitly and write down the reasoning.

### 4. Prefetch by velocity, not by visibility

The gates exist; their trigger does not. Extrapolate scroll direction and speed, prefetch
roughly two screens ahead, and cancel work behind the cursor. `prewarm(photos:recipe:)`
is the existing entry point.

### 5. Coalesce the request stream

On a fast flick most per-frame requests are stale before they land. Drop superseded
requests instead of queueing them — the scheduler already counts `cancel` and `stale`,
so the effect should be visible in its own numbers.

### 6. Do not redo P0's work

Two things that look like they belong here are **owned by P0** and should already be
done before you branch: caching `ElasticWrapLayout`'s subview sizing, and rendering the
three version thumbnails through the interactive tier. If they are not done, say so and
take P0 first rather than duplicating them here — they touch `ElasticTableView.swift`
and `ElasticFocusView.swift`, which is where a parallel P1 is also working.

`assetIndex(_:)` already exists on `P0SessionModel` (commit `59d1cf7`) and removed the
per-tile linear scans — use it, and do not reintroduce `assets.first(where:)` on any
path a view can reach more than once per frame.

## Test data

```bash
python3 Scripts/harness/fixtures/elastic_cards.py \
  --raw-dir /Users/aniketh/jeevana_mehendi_raws \
  --phone-dir ~/Downloads/lumina_phone_pool \
  --out ~/LuminaFixtures --force
```

Open `<out>/card-elastic-v4/frames`. Note the first open of a fresh card reports
`previews 0/N` while extraction runs; the second reports `N/N`. Measure warm unless you
are deliberately measuring cold.

## Running this in a loop

This prompt is written to be re-entered. Each time you start or wake:

1. `git branch --show-current` — confirm you are on your own branch. If it
   changed under you, stop and say so.
2. `git log --oneline -5` and re-read the **Progress** section at the bottom of
   this file. That is the only record of what you already did; the conversation
   may not survive.
3. Run the gate before changing anything, so you know whether you are starting
   from green.
4. Do the **next unchecked item only**, then commit, then update **Progress**
   in this file in the same commit.
5. When every item is checked and the gate is green, say so and stop. Do not
   invent more work — the other two streams own the rest.

Commit after every item, never in a batch. A loop that dies between items must
lose at most one item's work.

## Working alongside P0, P1 and P2

All three streams run **at the same time**, each on its own branch off
`elastic-v4/fixture-generator` (`541119f` or later). The Elastic views were
split by owner in `541119f` precisely so this works:

| File | Owner |
|---|---|
| `ElasticWrapLayout.swift` | **P0** |
| `ElasticVersionColumn.swift` | **P0** (pixels) and **P1** (hide under drawer) |
| `P0EditLiveRunner.swift`, `OrientedDisplayImage.swift`, `DevelopMetalView.swift` | **P0** |
| `ElasticSetShelf.swift`, `P0KeyRoutingModifier.swift`, `P0EscLadder.swift` | **P1** |
| `ElasticFocusView.swift`, `ElasticTableView.swift` | **P1** |
| `ElasticFilmstrip.swift`, `BrowsePixelService.swift`, `DevelopRenderScheduler.swift`, `PreparedRawSession.swift` | **P2** |
| `ElasticLayout.swift`, `docs/ELASTIC_PLAN.md` | **shared — append only** |

Rules that keep this collision-free:

- **Touch a file you do not own only if you must**, and say so in the commit
  message so the others can find it.
- `ElasticLayout.swift` and `ELASTIC_PLAN.md` are shared. **Append** at the end
  of the relevant section; never reflow or renumber, because that turns a clean
  merge into a conflict.
- Never rename or move a file another stream owns.
- Do not rebase onto another stream's branch. Rebase onto
  `elastic-v4/fixture-generator` only, and only when it moves.
- If you genuinely need something another stream is building, stub it behind
  your own type and leave a `// TODO(Pn):` — do not wait, and do not reach into
  their branch.

## Gate

```bash
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug -derivedDataPath DD -destination 'platform=macOS,arch=arm64' -only-testing:LuminaLogicTests build-for-testing
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug -derivedDataPath DD -destination 'platform=macOS,arch=arm64' -only-testing:LuminaLogicTests test-without-building
python3 Scripts/harness/run.py fast
python3 Scripts/harness/lint/xcode_compile.py --project-root . --derived-data DD
```

Baseline: **285 logic tests, 2 skipped** (one skips unless `TEST_RUNNER_LUMINA_RAW_DIR`
is set — xcodebuild does not forward shell env to the test process). Fast lane **41/41**.

Render-path changes also want the hosted CI lane: `.github/workflows/rendering.yml` runs
`fast` + `compile-logic` on push/PR. A green fast lane alone is not sufficient when
Swift types change.

## Rules that will bite you

- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.** Types on the render/export path must
  be explicitly `nonisolated` — including `nonisolated extension EditRecipe`. Actor
  nested types and actor statics must not be read synchronously from that plane; hoist
  constants to `RawDecodeBackendRegistry`. `CIContext.startTask(toRender:from:to:at:)`
  requires the `at:` argument. `render_data_plane_isolation` enforces this.
- **Magic-number lint** scans `Views`, `Design`, `Shell`; it skips lines mentioning
  `HiFiTokens`/`LuminaTokens` — do not exploit that. Route numbers through `ElasticLayout`.
- **Banned:** `onHover`, `ProgressView` (there are no spinners — softness and facts-chips
  are the loading truth), `.alert`, anything network.
- **Never `pkill -x Lumina`.**
- Motion goldens are keyed to the tokens hash. If you change `design/tokens.yaml`,
  `spring_physics_f07` will fail until re-approved via
  `Scripts/harness/golden/service.py propose/approve spring_trajectory_place_return`.
  Re-approve with the **previous payload** unless motion genuinely changed — passing
  then proves the change was motion-neutral.

## Wrap up

Record the before/after numbers in `docs/ELASTIC_PLAN.md` — not just that it got faster,
but what was measured, on what card, warm or cold. Commit with
`Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`. Ask before pushing.

## Checklist

- [x] 1. A scroll-latency measurement exists and is recorded, before any change
- [x] 2. Nothing on the scroll path decodes synchronously
- [ ] 3. Guaranteed-resident floor tier, with an explicit cap and eviction by distance
- [ ] 4. Prefetch by scroll velocity; cancel behind
- [ ] 5. Superseded requests dropped rather than queued
- [ ] 6. Re-measure; before/after recorded in `docs/ELASTIC_PLAN.md`
- [ ] 7. Gate green, including `xcode_compile.py`

## Progress

_Append one line per completed item: date, item number, commit sha, and anything
the next pass needs to know — especially anything here that turned out to be
wrong._

- 2026-09-22 · item 1 **partial** (checkpoint, sha in `git log`) · The
  measurement exists: `--p0-scroll-live` runner, `ElasticScrollTracker`,
  `BrowsePixelService.isResident`, `elastic_cards.py --stress`, film mode.
  Recorded in `docs/ELASTIC_PLAN.md` § "P2 measurement". **Not done:** the
  baseline on the 403-frame card. Extraction finishes in < 1 min, but the
  runner's readiness wait never fires there (session `assets` stays empty while
  the 27-frame card populates) — debug `P0SessionModel.consume` on the big
  card before anything else. Card lives at
  `~/LuminaFixtures/card-elastic-v4-stress/frames`, catalog already warm.
  Wrong in this prompt: the base branch does **not** carry P0's two items
  (wrap-layout caching, version thumbnails) — P0 is doing them in parallel in
  `~/lumina-wt/p0-render-proof`; do not redo them here. Files touched outside
  P2's row, all minimal: `ChapterPlateImage.swift` (appear/disappear report),
  `ElasticRootView.swift` (tracker environment, one modifier),
  `P0SessionModel.openFolder(_:shootName:)` (cards share a `frames` leaf),
  `LuminaApp.swift` (runner registration), `shipping_fence.py` (new runner).
- 2026-09-22 · item 1 **done** · The readiness bug was not the runner: the
  dates phase hangs on any shoot past ~250 frames because `ExifToolService.
  runData` waited for exit before draining a >64 KB pipe. Fixed
  (`captureOutput` + `ExifToolProcessTests`), outside P2's row but nothing
  large could be measured without it — and it is why every big catalog on
  this Mac had no dates. Runner now waits for the lazy table to grow and
  compares the document against the scroll view's frame (SwiftUI's clip view
  reports bounds as tall as the document). Baseline on the 403-frame card is
  in `docs/ELASTIC_PLAN.md`: 4 steps in 19.8 s, tick p95 1090 ms.
- 2026-09-22 · item 2 **part 1** · `sample` put 86 % of the glide's main
  thread in `session.chapters` recomputed per row and per gap, with a regex
  compiled per filename inside the sort. Cached `chapters` with `assets`
  (`P0SessionModel`, unowned), compiled the pattern once
  (`ShootChapterArrangement`), `gapInterval` reads the list once. Glide went
  from 4 steps / 19.8 s to 417 steps / 5.0 s, tick p95 2.5 ms. Still to do
  for item 2: the tile samples `BrowsePixelService.residentPixel` in its body
  and only enqueues on a miss — today every realized row shows a well for at
  least a frame even when its pixels are resident.
- 2026-09-22 · item 2 **done** · `ChapterPlateImage` draws
  `BrowsePixelService.residentPixel` in the same pass and only a miss awaits;
  `startsNewMoment` reads `chapterID(containing:)` (indexed, cached with
  `assets`) instead of scanning. Well tiles now equal decodes exactly (91/91
  on the glide); glide tick p95 0.95 ms. Audit result: nothing sync on the
  tile path but a lock-guarded dictionary read. Two things seen and left:
  `ShootBurst.preferredCoverID(in:)` builds a 403-entry dictionary per group
  per layout (called from P1's `ElasticTableView`; not in the profile after
  the chapters fix, so not touched), and the flick's ~9 ms tick p95 is row
  wrap-layout, P0's item. Next: item 3, the floor tier.
