# P1 — Finish the grammar the design specifies

## Where you are

Repo: `/Users/aniketh/vlm_harness` (Lumina, native macOS photo culling app, Swift/SwiftUI).
Branch: create **`elastic-v4/p1-grammar`** off `elastic-v4/fixture-generator`
(`541119f` or later) and stay on it. Run `git branch --show-current` before every build
and commit.

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

**You run alongside P0 and P2, not after them.** P0 is building the photo-pixel proof;
until it lands you cannot verify a photograph visually, so lean on the logic tests and
the chrome captures, and do not block on it.

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

## Checklist

- [x] 1. Hold-`⇥` peek: related → set → flags, release returns, short tap pins, `Esc` closes
- [x] 2. `G` inside the flags peek takes the inferred picks
- [ ] 3. Hold-`␣` is before; 1:1 zoom moves off Space
- [ ] 4. `P0EscLadder` rewritten to peek → drawer → selection → route
- [ ] 5. Hold-V remnants retired (`EditVariantSession`, `WorkspaceState` fields, `V` binding, probe fields); `EditVariantTests` deleted or rewritten
- [ ] 6. Set shelf is a drop target
- [ ] 7. `⇧`-click range, `⌘`-click toggle; the `P0_CULLING.md` ruling closed
- [ ] 8. Develop drawer on `E`, with sliders, ratios, `R` rotate, straighten, profile
- [ ] 9. Version column hides while the drawer or a hold is active
- [ ] 10. `docs/ELASTIC_PLAN.md` P1 section updated, gate green
- [ ] 11. Stress pass (asked for 2026-09-22): every landed item driven in the live
  Debug app by real key events, with a guard that aborts unless Lumina is verified
  frontmost before any key is sent; screenshots in `~/lumina-wt/p1-grammar-proof/<item>/`,
  findings appended to Progress. Per item: 1 ✔ (17 shots) · 2 ✔ with one live re-check
  pending · 3–9 as they land. Spam cases each time: 30 rapid ⇥ taps, held ⇥ + 40 arrows,
  ⌘⇥ away mid-hold, 10× Esc, P/X bursts.

## Progress

_Append one line per completed item: date, item number, commit sha, and anything
the next pass needs to know — especially anything here that turned out to be wrong._

- 2026-09-22 · item 1 · branch lives in its own worktree `~/lumina-wt/p1-grammar`
  (three sessions share `/Users/aniketh/vlm_harness`, so the branch was never checked
  out there). Peek state is `P0SessionModel.peek/peekPinned/peekOpenedAt` with the
  grammar in `P0SessionModel+Peek.swift`; views in `ElasticPeek.swift`. Two tokens added
  (`peek_cursor_tile_width` 220, `peek_related_badge_height` 24) → tokens hash moved to
  `35159b56…` and the F07 golden was re-approved with the previous payload. Touched
  P2's `ElasticFilmstrip.swift` (label / ids / fill read off the session — ~10 lines).
  `toggleKeptRailWalk` is gone; the set walk now follows `finalSetAssetIDs` through
  `setFocus`. Not built: `⇧←→` reorders the set (no set-reorder command exists — copy
  omits it), the flags peek's focus-check overlay, and the inferred-groups band (item 2).
  Wheel gestures untouched. Proof: 17 live-window screenshots driven by System Events
  in `~/lumina-wt/p1-grammar-proof/item1/` (tap-to-pin must be sent as one osascript;
  two invocations exceed the 220 ms window). Gate: 301 logic tests / 2 skipped, FAST 41/41.
  `--p0-edit-live` on the 27-frame card: 3 render-path failures (fidelity monotonic,
  geometry stable, drawable target) — not measured against the base commit, so unverified
  whether pre-existing; none touch peek code.
- 2026-09-22 · item 1 follow-up · Tab is now guarded by `route != .open` (it opened a
  phantom peek on the Open surface and ate the next Esc), and the app-resign release
  also drops the Space loupe. Known and deliberate: the peek bar overlays the last table
  rows with no bottom inset, exactly as the prototype's `position:absolute` does — needs
  a ruling, not a fix. Legacy `P0ChapterTableView.focusKeptAsset` can still arm the set
  walk without a peek; it is unreachable from the Elastic shell and goes with item 5.
- 2026-09-22 · item 2 · `ElasticInferredGroups` (Models, pure) + `takeInferredPicks` in
  the session (one `ChapterKeepCommand`, label `Take the picks`, one ⌘Z). Sharpness is
  never populated on P0 assets (all 27 read 0), so the flags peek measures it itself off
  grid thumbs with `BlurScorer` (now `nonisolated`) and embeds one frame per burst with
  `EmbeddingService.embed`, in a detached task; groups redraw when it lands (~3 s for
  27). Same-burst / same-scene / same-subject only — the prototype's "same exposure
  problem" group writes recipes, which is develop territory, and is not built; no
  `eyes` flag either. Five tokens added (210 · 0.14 · 0.2 · 0.5 · 10); tokens hash is
  now `1eac1762…`, golden moved. `P0Command.swift` gained a `label` on ChapterKeepCommand.
  Live stress found and fixed one bug: the subject representative followed
  `preferredCoverID`, so G's own marks regrouped the shoot (10 → 9 groups); pinned to
  the burst's first frame, regression test added. Cosmetic, left: the band's head line
  truncates at 1280 wide. Live re-check of the fix is PENDING — since ~14:08 the Debug
  app launches into an idle run loop with no window (3 tries, exec and `open`), which
  started when a second Lumina from Xcode DerivedData (pid 64132, not mine) appeared;
  retry when it is gone. Incident: the first stress script resolved an empty pid and
  sent ~60 keystrokes to the frontmost app, which was the Claude window — hence the
  guard. Handed P0 a repro: LUM0012 renders 180° inverted in focus while its version
  thumbnails are upright (shot in `item2/D1-focus-set-walk.png`, message sent to the
  P0 session). Gate: 313 logic tests / 2 skipped, FAST 41/41.
