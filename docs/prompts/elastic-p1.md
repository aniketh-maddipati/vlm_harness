# P1 — Finish the grammar the design specifies

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
9745c9e  WIP model assist (unmergeable, parked) ← elastic-v4/model-assist
```

All three branches are pushed to `origin`.

**`elastic-v4/model-assist` is superseded** — pre-ruling WIP that fails `banned_patterns`.
The question it was parked on was answered by **D67 / R-N.1 (model inference is
loopback-only)**, which landed on `elastic-v4/model-core`. That branch comes off
checkpoint-02 and does not contain the Elastic shell; reconciling the two lineages is a
separate decision. Leave both alone.

**Do P0 first if it is not done.** The surfaces you are about to build cannot be verified
visually until the photograph is provable — see `PROMPT_P0.md`.

Read `AGENTS.md`, `docs/ELASTIC_PLAN.md` (§2 grammar conflicts, §6, "Elasticity
backlog"), and `docs/P0_CULLING.md`.

## Sources of truth

- **Prototype**: `/Users/aniketh/Downloads/Lumina Elastic v4.html`. It is a bundle —
  parse `<script type="__bundler/template">…</script>` with `json.loads` and write the
  result out as HTML. Markup is roughly lines 1–240; logic starts near 245; `renderVals()`
  near the end holds all the copy and numbers. Divs are content-box (no global
  `box-sizing`); buttons are border-box.
- Every layout number already lives in `Lumina/Design/ElasticLayout.swift`. Add there, do
  not hand-write sizes in views.

## The task

### Checkpoint 04 — the one peek, and before

The prototype's `peekPatch(mode:)` is the spec. Hold `⇥` cycles **related → set →
flags**; `↑↓` or `⇥` moves through them; release returns; a short tap pins; `Esc` or
tabbing past the end closes. `G` inside the flags peek takes the inferred picks.

- `Tab` is currently `toggleKeptRailWalk()` — a *toggle*. Retire the toggle semantics;
  keep `walkingKeptRail` as the backing state for the `.set` peek.
- Hold `␣` is **before**. `showingBefore` already exists and works correctly, just on the
  wrong key (`B`). Move it. 1:1 zoom vacates Space — it already has a double-click and a
  header button, so nothing is lost.
- `ChapterLookGlance`'s embedding-similarity ordering is the algorithm behind "take the
  inferred picks" — reuse it, do not reinvent it.
- The peek surface in the prototype is `data-screen-label="Peek"`: a bar pinned to the
  bottom at `rgba(46,46,44,0.94)`, padding `12px 28px 16px`, tiles 150 wide for the set
  peek and 170/220 for related.

### The Esc ladder

`P0EscLadder.handle` still carries its old step list minus grouping. Rewrite it in place
— same "sole owner, ordered ladder" architecture — to **peek → drawer → selection →
route**. Do not patch the old branches; several of the things they unwind no longer
exist.

### Finish retiring hold-V

The tray died with `P0SinglePhotoEditor`, but `EditVariantSession`, its `WorkspaceState`
fields, the `V` binding and its probe fields remain. Retire them. **Keep**
`DevelopRenderGraph.branchInteractiveVariant` and `PreparedRawSessionRegistry` pinning —
they are the right mechanism for rendering the three version thumbnails cheaply, which is
a P0/P2 item.

`EditVariantTests` asserts exact source substrings and will fail by construction when
those files change. Delete or rewrite it in the same commit; do not chase it as a
regression.

### Set shelf as a drop target

`ElasticSetShelf` in `Lumina/Views/P0/ElasticTableView.swift`. The prototype uses
`dragOver`/`dropShelf` with `outline: {{ shelfDropRing }}` and `outline-offset: -2px`,
and the shelf background changes to `#EFECE6` while the set strip is held.

### ⇧-click range, ⌘-click toggle

`docs/P0_CULLING.md` has flagged shift-click range as **"RULING NEEDED — no contract
key"** since before Elastic. The design's README is the first thing to actually rule on
it. Adopt that ruling and close the open item in the doc.

### Checkpoint 05 — the develop drawer

`E` opens it. 256 wide, `rgba(46,46,44,0.35)`, radius 8, padding `12px 14px`, gap 6.
Sliders are a `78px 1fr 44px` grid at 11px. Then crop ratios, `R` rotate 90°, straighten
(−10…10, step 0.1), profile select, the sync chips (`M`), and auto/match/reset.

Salvage rather than rebuild: `P0EditSlider` usage and the crop-handle drag math from
`P0AdjustmentRail` / `P0CropControls`; `P0AdjustmentSection` for the drawer's internal
sections. The always-open accordion shell itself does not survive.

**`variantsCol` is `none` when the drawer or a hold is active** — the version column
hides while developing.

Note the exposed-controls list is deliberately short: `Whites`, `Blacks` and `Dehaze`
stay in the schema and the XMP but are **not shown**, because the engine renders them
inert. Do not surface them to be helpful.

## Test data

```bash
python3 Scripts/harness/fixtures/elastic_cards.py \
  --raw-dir /Users/aniketh/jeevana_mehendi_raws \
  --phone-dir ~/Downloads/lumina_phone_pool \
  --out ~/LuminaFixtures --force
```

Open `<out>/card-elastic-v4/frames`. 27 frames, 8 moments, a five-frame burst for the
open/fold path, a camera+phone moment, a crop/straighten A/B pair with real Lightroom
18.5.1 sidecars, and a byte-identical duplicate pair. The generator verifies its own
output against Lumina's rules and fails if they disagree.

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
```

Baseline: **285 logic tests, 2 skipped** (one skips unless `TEST_RUNNER_LUMINA_RAW_DIR`
is set — xcodebuild does not forward shell env to the test process). Fast lane **41/41**.

## Rules that will bite you

- **Authority order:** contract-v6 → tokens.yaml → copy-contract → code → tests. Keys and
  copy you add may need a copy-contract entry — check `Scripts/harness/lint/copy_contract_diff.sh`.
- **Magic-number lint** scans `Views`, `Design`, `Shell`; it skips lines mentioning
  `HiFiTokens`/`LuminaTokens` — do not exploit that. Route numbers through `ElasticLayout`.
  Only tokenize a value already forbidden; never grow the allowlist.
- **Costume lint:** every `Button` needs a `Lumina*Style` (`LuminaElasticButtonStyle`
  exists and does nothing on press or hover, which is correct for this design); no bare
  `Text`/`Image` gets `.onTapGesture`.
- **Probe fields are a five-site mirror.** Adding one means five files; `probe_growth`
  then `probe_mirror` will reveal them two at a time.
- **Banned:** `onHover`, `ProgressView`, `.alert`, anything network, and the word "sync"
  in copy — note the drawer's sync feature must be *labelled* something else.
- `P0KeyRoutingModifier` is the sole owner of key routing. Keep it that way.
- **Never `pkill -x Lumina`.**

## Wrap up

Update `docs/ELASTIC_PLAN.md` §6 and the backlog with what landed and the honest gaps.
One commit per checkpoint is fine; end each message with
`Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`. Ask before pushing.
