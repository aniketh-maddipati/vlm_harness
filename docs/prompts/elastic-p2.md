# P2 — Scroll latency to near zero, without giving up resolution or RAW

## Where you are

Repo: `/Users/aniketh/vlm_harness` (Lumina, native macOS photo culling app, Swift/SwiftUI).
Branch: start a new one off **`elastic-v4/fixture-generator`** (`596362a`). Run
`git branch --show-current` before every build and commit.

```
596802c  checkpoint 03 (base)
1b74acc  Elastic surfaces match the prototype's own numbers
34f001d  Fixture cards generator
59d1cf7  Index assets by id; pin the orientation contract
596362a  Plan: the elasticity backlog          ← branch from here
9745c9e  WIP model assist (unmergeable, parked)
```

All three branches are pushed to `origin`. `model-assist` fails `banned_patterns` by design (network egress vs
contract-v6 D4/D36) — not yours to fix.

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

## How these three fit together

Run **P0 alone first**, branched off `elastic-v4/fixture-generator`. It is small, it
unblocks visual verification for the other two, and it carries the user-visible bug.

Once P0 lands, **P1 and P2 can run in parallel** off its tip: P1 is keys, the Esc ladder
and the drawer; P2 is `BrowsePixelService` and `DevelopRenderScheduler`. Their overlap in
the view files is small *only because P0 already took* the wrap-layout caching and the
version thumbnails — do not move those around.

```
fixture-generator (596362a)
        └── P0
              ├── P1
              └── P2
```

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
