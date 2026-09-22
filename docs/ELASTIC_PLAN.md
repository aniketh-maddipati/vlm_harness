# Elastic v4 — orientation plan (checkpoint 00)

Read-only pass per `design_handoff_elastic_v4/PROMPTS.md` checkpoint 00. No code changed in this
checkpoint. Produced against `main` at commit `603f95d` (2026-09-21).

## Headline finding

`PROMPTS.md` and `README.md` were written without visibility into a meaningful amount of code that
already exists on `main` — some of it landed in the last five commits (#92–#96). The design's "time"
route, filmstrip elasticity, and one similarity-ordering peek all have working ancestors already.
Treat checkpoint 03 as **adapt existing views**, not **build from a blank canvas** — see §3.

Also: `PROMPTS.md` checkpoint 00's own file list has two wrong paths. `EditRecipe` lives in
`Lumina/Develop/EditRecipe.swift`, not `Lumina/Models/PhotoRecord.swift`. The type that carries a
recipe (`AssetRecord`) lives in `Lumina/Models/P0State.swift`. `PhotoRecord.swift` holds only the
legacy `DevelopRecipe` (taste/XMP bridge, kept per `P0_CANONICAL_STATE.md`) and the unreachable
`PhotoRecord`/`LuminaProject` island — it is not where canonical state lives.

## 1. README state → existing Swift type

| README field | Owner today | Status |
|---|---|---|
| `route` | `P0SessionModel.route: P0Route` (`.open .contactSheet .grouping`) | **Replace enum cases** with `.time .focus` per README. Note: today's "single photo" is *not* a route case — it's `P0ContactSheetView` conditionally showing `P0SinglePhotoEditor` when `session.inspectingAssetID != nil`. Promoting `.focus` to a real route is a structural change, not a rename. |
| `focus` | `P0SessionModel.focusedAssetID` (contact-sheet cursor) + `P0SessionModel.inspectingAssetID` (open photo) — **two separate properties**, not one | **Existing, but split.** Elastic's single `focus` concept should probably collapse these two into one, or the plan needs to say explicitly which one survives. Flagging, not resolving — see §2. |
| `strip(chrono\|set)` | New | `WorkspaceState.currentScope: PropagationRing` is unrelated (batch-edit ripple scope, not filmstrip mode). Genuinely new. |
| `hold(nil\|related\|set\|flags)` | New, but `holdingLoupe`, `holdingClipping`, `lookGlancing`, `leanedBurstID` on `P0SessionModel` are four *existing* single-purpose hold states covering adjacent ideas (magnifier, clip overlay, similarity glance, burst lean). New unified `hold` should likely replace/absorb `lookGlancing` and `leanedBurstID`; `holdingLoupe`/`holdingClipping` are orthogonal dev/inspection aids, not obviously peeks — needs a call (§2). |
| `peekPinned` | New | — |
| `before` | **Already implemented**, just on the wrong key. `P0SessionModel.setShowingBefore(_:)` / `session.showingBefore`, wired to hold-**`B`** (not modified) in `P0KeyRoutingModifier`, already does "identity recipe while held, never mutates." README wants it on hold-`␣`. Space is currently `holdingLoupe` (1:1 zoom toggle during inspection). Direct key conflict — see §2. |
| `marks` | `CullDecision` on `AssetRecord` (`.undecided/.keep/.reject/.hold`) | Matches already; README's own doc-comment in the state line says as much. |
| `set[]` | `FinalSetOrder` on `ShootRecord` | Matches. |
| `selection[]` | `WorkspaceState.selectedAssetIDs` | Matches. |
| `anchor` | New | Needed for `⇧`-click range select, which `docs/P0_CULLING.md` already lists as **"RULING NEEDED — no contract key"** — Elastic's README is the first place this actually gets ruled on. |
| `develop` (drawer open bool) | New bool, but `P0SessionModel.expandedAdjustmentSection: P0AdjustmentSection?` is the existing analogue — today's rail is an always-visible accordion (light/color/detail/crop sections toggle open one at a time), not a hide/show drawer | Reuse `P0AdjustmentSection` for the drawer's internal sections; add the drawer-visible bool fresh. |
| `recipe{}` | `EditRecipe` on `AssetRecord.recipe` | Matches. |
| `source{}` | New — `AssetRecord` has no provenance tag today; `recipe == nil` currently just means "camera/neutral decode" | New `RecipeSource` enum per checkpoint 01. |
| `hand{}` | New — no cached "last hand recipe" field exists | New `handRecipe: EditRecipe?` per checkpoint 01. |
| `geo{}` | **Not new** — already unified into `EditRecipe.crop` + `.straightenDegrees`, not a separate struct. The README/prototype models geometry separately for its own reasons; the Swift side should *not* mirror that split. |
| `profile{}` (camera profile: Camera Standard / Neutral / Portrait / Adobe Color) | New | ⚠️ Naming collision: `ShootRecord.profile: EditRecipe` **already exists** and means "taste baseline for auto-tone learning" — a completely different concept. Do not name the new field `profile`; `EditRecipe.cameraProfile: String` (as checkpoint 01 already specifies) avoids the collision. Flagging so nobody greps for "profile" and edits the wrong thing. |
| `sync{}` (checkbox state) | New | Session-only, no existing analogue. |
| `hist{}` | New | `DevelopHistogramView` exists and presumably computes a histogram for display already — checkpoint 05's implementer should reuse its computation rather than adding a second one, but the *state* slot is new. |
| `undo[]` | `P0UndoCoordinator` | Matches — and it already merges cull + edit into one stack (`session.undoCoordinator.stack` holds a `.edit(EditMutationCommand)` case alongside cull cases per `EditVariantTests.swift`), which is exactly README's "⌘Z undo anything ... one shared stack." Nothing to build here. |

## 2. Grammar conflicts with existing key bindings / contract tests

All routing lives in `Lumina/Views/P0/P0KeyRoutingModifier.swift` (sole owner, confirmed). Current
bindings pulled directly from that file:

| README input | Current binding | Conflict | Proposed resolution |
|---|---|---|---|
| hold `⇥` → peek related→set→flags | `Tab` = `toggleKeptRailWalk()`, a **toggle** (press once to start walking the kept rail, press again to stop) | Same key, incompatible gesture model (toggle vs. hold-then-cycle) | Retire `toggleKeptRailWalk`'s toggle semantics for `.set` peek's hold-⇥ walk. The *concept* (`walkingKeptRail`) survives as the backing state for the `.set` peek, just re-triggered by hold instead of toggle. |
| hold `␣` → before (never mutates) | `Space` = `holdingLoupe` (1:1 zoom / magnifier during inspection) | Same key, two different existing/wanted hold gestures | `showingBefore` already exists correctly on the wrong key (`B`, unmodified). Move it to `Space`; move 1:1 zoom off hold-Space onto its existing alternate trigger (double-click / the "1:1" button already in `P0SinglePhotoEditor`'s header — both already exist independently of the hold gesture, so nothing is lost). |
| `G` (inside flags peek) → take inferred picks | `⇧G` = `enterGrouping()` (route change), `⌘G` = `beginLookGlance()` (hold, similarity reorder) | Both existing G-chords belong to `.grouping`/look-glance, which checkpoint 03 already retires | Once `.grouping` route and its look-glance UI are gone, plain `G` is free. Keep `ChapterLookGlance`'s embedding-similarity ordering as the algorithm behind the new peek's "take inferred picks," just re-entered from the flags peek instead of a standalone hold. |
| `1` `2` `3` → version | Unbound | None | Free. |
| `E` → develop drawer | Unbound (only `⌘E` = export exists) | None, but the *rail* today is always visible, not a drawer | Checkpoint 05 converts the always-on `P0AdjustmentRail` accordion into a hide/show drawer; the accordion's per-section expand/collapse (`P0AdjustmentSection`) is reusable inside it. |
| `M` → sync | Unbound | None | Free. |
| `R` → rotate 90° | No bare-key binding (`P0CropControls` only exposes rotate as toolbar buttons) | None | Additive. |
| — (README has no hold-`V` gesture) | `V` hold = `beginEditVariants()` — an existing, working 4-way transient recipe comparison (`EditVariantSession`) with its own render-pinning path (`PreparedRawSessionRegistry`, `DevelopRenderGraph.branchInteractiveVariant`) | Not a key conflict, a **feature overlap**: hold-V variants and README's 3-tagged-version system are two different answers to "compare recipes on one photo" | Recommend retiring hold-V/`EditVariantSession`/the variant tray as superseded — see §3. Keep the render-pinning primitives; they're the right mechanism for rendering the 3 version thumbnails cheaply. |
| Esc ladder: peek → drawer → selection → route | `P0EscLadder.handle` today: loupe/clipping → lookGlancing → leanedBurstID → walkingKeptRail → grouping route → close inspection | Same *shape* (deepest transient first), different concrete steps, several of which are being retired | Rewrite `P0EscLadder.handle` for the new step list rather than patching; don't try to preserve the old branches. |
| `⇧`-click range / `⌘`-click toggle | `docs/P0_CULLING.md` flags shift-click range as **"RULING NEEDED — no contract key"** (pre-existing, unresolved) | Elastic's README is the first spec to actually answer this | Adopt README's ruling (⇧-click = range, ⌘-click = toggle) as the resolution to that long-open item. |
| (none in README) | `CullGrammarMachine`'s shift-`⏎` **staging** grammar (`returnKeyDown(shift:)` arms, physical key-release commits — `CullGrammarTests.testD11D13_*`) | README's grammar has no staging concept anywhere — silent, not explicit | **Open question for the user, not resolved here**: does Elastic drop staged commits entirely (nothing in `⏎`/`Esc`/`P`/`X` implies it), or does staging move somewhere? `CullGrammarMachine` is a pure, separately-tested state machine (F02.1) — deleting/changing it is a deliberate product call, not a mechanical rename. |
| (contract tests, not grammar per se) | `EditVariantTests.testKeyRoutingAndMinimalTrayPreserveDecisionBoundary`, `testPersistenceRemainsSerializedThroughShootStore`, `testVariantRenderPathStaysOnExistingOwners` assert **exact substrings** of `P0KeyRoutingModifier.swift` / `P0SinglePhotoEditor.swift` / `P0SessionModel.swift` source text | These will fail the instant those files are rewritten — by construction, not as a regression | Delete/rewrite `EditVariantTests.swift` in the same PR that retires hold-V (checkpoint 03). Do not chase these failures as bugs. |

No item above changes a **persisted** schema in a way that contradicts the README, so nothing here
needs a stop-and-ask under checkpoint 00's own gate. Two callouts were raised to the user directly
and resolved 2026-09-21:
- **Retire hold-V / `EditVariantSession`** as superseded by the version system (checkpoint 03).
- **Drop `CullGrammarMachine`'s shift-⏎ staging grammar** (checkpoint 03/04).
- **Straighten/orientation split (checkpoint 01):** derive, don't fork — `straightenDegrees` stays
  the only render-facing stored value; `crs:Orientation`/`crs:StraightenAngle` are computed at XMP
  export time only. Implemented — see §4.

## 3. Views/types to delete, retire+replace, or keep

**Delete outright** (already legacy per `docs/P0_CANONICAL_STATE.md`, zero live references):
- `Lumina/Views/Workspace/*` (16 files, ~4,710 lines) — confirmed unreferenced from any `P0*` file except one mirroring comment in `P0EscLadder.swift`.
- `Lumina/Views/P0/P0GroupingView.swift` + `P0SessionModel.enterGrouping/leaveGrouping` + the `.grouping` route case (the route dies; keep `ChapterLookGlance`'s similarity algorithm, drop its route/UI).

**Retire the surface, salvage the mechanism:**
- `P0SinglePhotoEditor.swift` → replaced by `ElasticFocusView`. Salvage: 1:1 zoom/pan math, `loadStableFallback`'s pinned-fallback-image pattern, the header layout conventions.
- `P0AdjustmentRail.swift` + `P0CropControls.swift` → salvage `P0EditSlider` usage and the crop-handle drag math wholesale into `ElasticDevelopDrawer` (checkpoint 05); the always-open accordion shell itself doesn't survive.
- `EditVariantSession` / `WorkspaceState.editVariants` / hold-`V` routing / the variant tray in `P0SinglePhotoEditor` → retire as superseded by the shot/auto/yours version system. Keep `DevelopRenderGraph.branchInteractiveVariant` and `PreparedRawSessionRegistry` pinning — reuse for the 3 version thumbnails.
- `P0ContactSheetView.swift` → its whole job (host the chapter table, conditionally overlay the single-photo editor via `inspectingAssetID`) is exactly what `ElasticRootView`'s `.time`/`.focus` switch replaces.

**Keep and extend — do not rebuild:**
- `Lumina/Models/ShootChapterArrangement.swift` (`ShootChapter`, `ShootBurst`, `CaptureName`, `ChapterPack`, gap-based chapter arrangement) — this **is** README's "moments as rows, bursts stacked" model already. Reuse `ShootChapterArrangement.arrange` directly for the time route; do not reinvent moment/burst grouping.
- `Lumina/Views/P0/P0ChapterTableView.swift` (600 lines) — very likely the direct ancestor of `ElasticTableView`. Whoever implements checkpoint 03 should audit this file first and adapt it rather than starting from a blank view.
- `Lumina/Design/ElasticCanvasLayout.swift` (D26/D28 quantized periphery sizing, already named "elastic") — reuse for the filmstrip; update the pixel steps to README's 92 px / 96×64 / 72×48 / 20 px-at-moment-boundary numbers, since today's steps serve a different (inspect-strip) layout.
- `Lumina/Models/P0State.swift` (`AssetRecord`, `ShootRecord`, `CullDecision`, `FinalSetOrder`, `BatchEditCommand`) — extend additively (checkpoint 01), never replace.
- `Lumina/Develop/EditRecipe.swift` — extend additively; crop/straighten already unified here (see `geo{}` row above).
- `P0UndoCoordinator`, `EditMutationCommand`, `CullMutationCommand` — unchanged; already the shared-stack model README wants.
- `ShootStore`, `ShootSidecarStore`, `ShootDecisionJournal`, and all seven `SidecarAuthorityTests` relaunch-authority cases — untouched except additive XMP fields in checkpoint 01. Tolerant decode is the established pattern to follow for any new field.
- `P0KeyRoutingModifier.swift`, `P0EscLadder.swift` — rewritten **in place**, same "sole owner" / "ordered ladder" architecture retained, not replaced by a new mechanism.

**Still genuinely undecided:**
- Exactly which of `focusedAssetID` vs. `inspectingAssetID` becomes README's single `focus` — see the `focus` row in §1. Not blocking for checkpoint 01; needs an answer before checkpoint 03.

## 4. Checkpoint 01 — done (2026-09-21)

Implemented on `main` (no branch/PR yet):
- `RecipeSource` enum (`Lumina/Models/P0State.swift`) — named `RecipeSource`/`AssetRecord.recipeSource`,
  **not** `AssetRecord.source`, since that name was already taken by `SourceReference` (the file/volume
  reference). This is the naming collision the original prompt text didn't anticipate.
- `AssetRecord.handRecipe: EditRecipe?`, both new fields tolerant-decoded (default `.shot` / `nil`)
  via a hand-written `init(from decoder:)` — `AssetRecord` had no custom decoder before, so one was
  added; every pre-existing field decodes as `required` (safe, since synthesis already required them
  on every on-disk catalog) and only the two new fields fall back to defaults.
- `EditRecipe.cameraProfile: String` (default `"Camera Standard"`) and `EditRecipe.cropAspect:
  EditCropAspect` (enum `original/threeByTwo/fourByFive/oneByOne/sixteenByNine/custom` — no
  associated ratio value; a custom ratio is already fully recoverable from `EditCrop`'s own
  width/height, so it isn't duplicated). Both participate in `valueFingerprint`, both preserved
  verbatim through `withTasteStrength`/`lrCalibrated`, both tolerant-decoded.
- **Orientation/straighten kept as one stored field** per the resolved decision: `crs:Orientation`
  and `crs:StraightenAngle` are written to XMP as a computed decomposition of `straightenDegrees`
  (same turns/remainder split as `P0CropControls.fineStraighten`) — informational only, not read back.
  `crs:CropAngle` remains the one value Lumina reads to reconstruct `straightenDegrees`.
- XMP: added `crs:CameraProfile` (always written, like `crs:WhiteBalance`), `crs:CropAspect` (written
  alongside the other crop fields, only when cropped), `crs:Orientation`/`crs:StraightenAngle` (written
  alongside `crs:CropAngle`, only when rotated), `lumina:Source`. `crs:HasCrop` and
  `lumina:RecipeFingerprint` already existed.
- **Deliberately not added to `LightroomHandoffService.managedFieldNames`** (the external-conflict
  drift-detection domain): all five new fields. Reasoning: `managedFieldNames` is hashed and compared
  against a hash stamped by whatever code version last wrote the file. Adding a field to that list
  retroactively would make every pre-existing sidecar in the wild fail the hash comparison on its very
  next edit — a false-positive "external edit conflict" for every user upgrading, not because anything
  external changed. The new fields still round-trip correctly; they just don't participate in drift
  detection yet. Worth a real design pass if per-field drift detection on these becomes wanted later.
- `ShootStore.commitEdit` now looks up the asset's current `recipeSource` from the shoot and threads
  it through to the sidecar write; `applyOpenReconciliation` sets `recipeSource = .sidecar` when the
  sidecar wins relaunch authority. No other call site changed — checkpoint 01 does not wire
  `recipeSource` transitions for hand edits/auto (that's checkpoint 02/05).
- Tests: `P0SidecarIntegrationTests.testCameraProfileCropAspectAndSourceRoundTripThroughSidecar` and
  `.testOldRecipeAndAssetJSONWithoutNewFieldsDecodeWithDefaults`.

Verified on this Mac: `xcodebuild ... -only-testing:LuminaLogicTests` — 249/249 pass, including all
11 `SidecarAuthorityTests` cases unchanged; `python3 Scripts/harness/run.py fast` — 41/41 OK. No view
file was touched.

## 5. Checkpoint 02 — done (2026-09-21)

- **Name collision resolved.** `AutoDevelop` already existed (`Lumina/Services/AutoDevelop.swift`),
  a percentile-based auto-tone whose only consumers are the retired shell (`LuminaShellModel`) and
  `Views/Workspace/TreatmentStageView` — both already slated for deletion here. Swift is one module,
  so the two cannot coexist: the legacy type was renamed **`HistogramAutoTone`** and the spec'd name
  given to the new engine. Its `render_data_plane_isolation` manifest entry moved with it.
- `ImageStats` (`Lumina/Develop`): 32-bin Rec.709 luminance histogram, clip fractions at 6/255 and
  249/255, mean, plus optional native Kelvin and Vision horizon angle. Cached on
  `AssetRecord.imageStats` (tolerant-decoded, like checkpoint 01's fields) and treated as derived
  state — safe to drop and recompute.
- `AutoDevelop.recipe(for:stats:)`: pure, deterministic, rules exactly as specified. Whites/Blacks/
  Dehaze forced to 0 because the engine is not honest about them.
- Measured from the **interactive tier decoded at `RawIntent.neutral`**, not the live recipe —
  otherwise a second auto pass would read its own previous output.
- `BatchEditMutationCommand` + `P0UndoEntry.batchEdit`: the first multi-asset single-undo *edit*
  command (modeled on `ChapterKeepCommand`, the existing template). It carries `RecipeSource` per
  mark, so one ⌘Z restores provenance as well as recipes.
- `P0SessionModel.applyAuto(to:force:)` and `ensureImageStats(for:)`. Skips non-`.shot` frames unless
  forced, and skips unmeasured frames entirely rather than guessing.
- Probe: added `focusedRecipeSource` (checkpoint 04 wanted a `versionSource` field anyway). This is
  the five-site probe mirror — app probe, UI-test mirror, robot, logic round-trip — surfaced two
  lints at a time by `probe_growth` then `probe_mirror`.

**Two honest findings, both documented in `docs/DEVELOP_ENGINE.md` rather than papered over:**
1. The exposure clamp is **asymmetric in practice**: `(0.46 − mean) × 3` spans −1.62…+1.38, so only
   the darkening side reaches ±1.5. A pure-black frame tops out at +1.40 — the formula binds before
   the clamp does. Left as-is; tuning coefficients is the L4 loop's job, not a silent edit here.
2. Auto on a non-clipping frame is **not a no-op** — it still applies the default −20/+15 curve.

**Gate status:**
- Logic tests 264/264 (1 skipped by design), fast lane 41/41 — green.
- `--p0-edit-harness` across "8 fixtures" **could not be run as written**: the `raw-correctness-v1`
  bundle is external and env-var-gated (`design/fixture-manifest.md`), unset here, and the committed
  `.ARW` fixture is a 4-byte placeholder. Instead, `AutoDevelopRawFixtureTests` verifies the same
  claim directly against 8 real Sony ARW frames — decode → measure → auto → assert non-identity,
  deterministic, and not collapsed onto one recipe. It skips rather than passing vacuously when no
  RAW folder is supplied. This proves auto changes pixels; it does not replace the harness runner.

## 6. Checkpoint 03 — first UI (2026-09-22)

**The `focus`-field question from §3 is resolved:** `focusedAssetID` is the single cursor and
`inspectingAssetID` is now *derived* (`route == .focus ? focusedAssetID : nil`), not stored. Verified
first that the two never diverge — every site that opened inspection already set both to the same id.
101 call sites keep working unchanged through the derived accessor.

- `P0Route` is now `.open / .time / .focus`. `.grouping`, `P0GroupingView`, `P0ContactSheetView` and
  `P0SinglePhotoEditor` are deleted.
- `ElasticRootView` / `ElasticTableView` / `ElasticFocusView` / `ElasticSetShelf`, with
  `P0SessionModel+Elastic` supplying the header line, moment copy, version picking and set state.
- `ElasticLayout` is the single definition site for the design's numbers; where an existing token
  already carries the meaning (reject dim, thumb radius, scene gap, focus ring) it defers to it.
- Palette: `LuminaTokens.Elastic` — the README's warmer shell, no inlined hex.

**The table stays mounted under focus.** Commit #93's probe contract ("inspect must latch on the same
table") says the surface is never rebuilt, and the Elastic design says the same thing in its own words
("one continuous surface"). So focus does not replace the table — the table compresses to the
filmstrip. That kept `chapterTableMounted` honest instead of adapting the test away.

**Gate:** logic tests 274/274 (1 skipped by design), fast lane 41/41.

Three lints fired and were each fixed at the cause rather than loosened:
1. `magic_numbers` — first attempt put the Elastic numbers in `tokens.yaml`, which retroactively made
   common values (14, 72, 168) token-owned and broke ~30 unrelated pre-existing files. Reverted;
   tokenized **only** values already owned elsewhere, so no new literal entered the forbidden set.
2. `allowlist_ratchet` — correctly refused the shortcut of allowlisting instead (250 → 255).
3. `spring_physics_f07` — the motion golden is keyed to the tokens hash. Re-approved under the new
   digest using the *previous* payload, which passing then proves the change is motion-neutral.

**What the capture shows and what it does not.** `artifacts/elastic-proof/table-1280x800.png` renders
the real table over a 94-frame shoot: the exact header line, moment rows with times/light words,
a `+ 18 min` gap label, focus ring, keep chip, set shelf. Photo pixels are **not** verified — SwiftUI
`.task` does not run for a view hosted offscreen and captured via `cacheDisplay` (the same limitation
`DEVELOP_ENGINE.md` already records for Metal layers), so every tile shows its empty well. The two
`--p0-edit-live` failures ("blank canvas") were measured on `main` as well — 29/31 there too, so they
are pre-existing, not from this work.

### Visual accuracy pass (2026-09-22)

Checkpoint 03's surfaces built the right structure with approximate numbers. This pass makes them
match the prototype's inline styles, which is where every value in the visual spec comes from. No
behaviour moved; the keys, peeks and thumbnails in "Known gaps" below are all still open.

- **`design/tokens.yaml` `elastic:`** gained tokens only for spec values that were *already* forbidden
  literals, so the forbidden set is unchanged before and after (95 either way). `set_shelf_height`
  dropped 96 → 64. `LuminaTokens.Elastic` gained `paper`, `groupsBar`, `shelfThumbFill`, `shadowInk`.
- **`ElasticLayout`** is now the sole home for every Elastic number, deferring to an existing token
  wherever one already carries the meaning. `versionColumnWidth` is 144; `gapHeight` returns 14 for
  every moment after the first (the prototype's `gapPx` is `null → 0`, else 14 / 40 / 64 at the 25
  and 60 minute thresholds), while the gap *label* still starts at 10 minutes.
- **`ElasticStyle`** holds the type stacks, the cursor ring (`0 0 0 3px ink, 0 0 0 4.5px #EFECE6`,
  drawn outside the frame with the radius grown by each spread), the in-set outline, the fade-only
  `born`, and the one button costume that does nothing on press or hover.
- **`ElasticFocusView` rewritten.** The photograph is sized to its own aspect-fit box rather than
  filling the band, so radius 4 and the `0 20px 40px rgba(20,19,18,0.35)` shadow trace the picture
  and not the well it sits in. Version column 144 with 22-high badges (number in ink, word in
  inkSoft, `yours` at 0.35 with no hand recipe). Status bar is time · camera · exposure · file stem ·
  — · histogram · readout · state, with the state turning cream while `before` is held. The
  histogram draws the design's 64×20 user space into 96×30 and carries salmon clip ticks past 2%.
  Camera and exposure are read off the original with ImageIO on a background task.
- **Histogram shift lives in the view model, not the view.** The bins are measured off the neutral
  decode and never re-measured per recipe; `histogramBinShift` slides them by
  `round(ev × 4 + shadows × 0.02)` instead. That also keeps `0.02` — a forbidden literal — out of the
  linted view layer rather than dodging the lint with a `LuminaTokens` mention on the line.
- **The filmstrip was being squeezed to nothing.** `ElasticTableView` had only a `maxHeight` under
  focus, and the focus view's `layoutPriority(1)` with `maxHeight: .infinity` legitimately consumed
  the whole stack. It is now pinned `minHeight == maxHeight == 92`. Neither committed capture would
  have shown this: `captureTable` forces `route = .time` and `captureEditor` hosts `ElasticFocusView`
  alone, so the root view is never captured in the focus route. Verified with a throwaway capture of
  the root under focus, reverted afterwards.

Three gate failures, each fixed at the cause:

1. `progressive_render_architecture` wants `value: session.route` in `ElasticRootView`. The earlier
   draft had removed the whole route animation along with its `.scale(0.985)` transition. The scale
   was the part the design does not have — `born` is fade-only — so the transition is now a plain
   fade and the `.animation(…, value: session.route)` is back. It is what makes "the table compresses
   to the strip" true rather than a hard cut, and it is invisible in a still capture either way.
2. `orphan_symbols` flagged `ElasticMarkedTile` as self-only. Registering it would have been a lie —
   it is live in three views through `elasticMarked`. It was a named `ViewModifier` it never needed
   to be, so the type is gone and the extension does the work directly.
3. `spring_physics_f07` is keyed to the tokens hash. Re-approved under the new digest using the
   *previous* payload byte-for-byte, so the test passing is itself the proof that the token change is
   motion-neutral.

**Gate:** logic tests 274/274 (1 skipped by design), fast lane 41/41, `--p0-edit-live` 30/31.

**What the capture shows and what it does not.** Photo pixels are still unverifiable: SwiftUI `.task`
does not run for a view hosted offscreen, and Metal layers do not composite through `cacheDisplay`.
The thumbnail wells were filled for this pass by temporarily seeding `ChapterPlateImage`
synchronously — reverted, because a synchronous full-file decode on the main thread across 94 tiles
is exactly what the progressive-rendering contract forbids. With them filled, the table, the version
column and the strip were confirmed against the prototype. The photograph itself was not.
`--p0-edit-live` now scores **30/31**, up from the 29/31 that `main` also scores: "RAW preview
presents without blank canvas" passes now that the photograph is sized to its fitted box. "Quality
promotion keeps geometry stable" still fails, as it does on `main`.

Honest gaps in the copy this pass introduced:

- The export receipt has no XMP sample line; the prototype shows one.
- The receipt persists until the next export rather than fading.
- The camera string is the real EXIF model, so it reads e.g. `ilce-7m3`, not the prototype's `a7 iii`.
- The session date format is `mmm d` (`may 19`), not the prototype's `sept 14`.

### P1 — the grammar (2026-09-22, branch `elastic-v4/p1-grammar`)

Checkpoints 04 and 05 as the prototype specifies them, built alongside P0 and P2 on
their own branch off `a4792c5`. Every item shipped as its own commit with its logic
tests; the gate finished at **335 logic tests / 2 skipped, FAST 41/41**.

- **Hold-⇥ is the one peek.** Similar → set → flags; `↑↓` or `⇥` cycles; release
  returns; a tap inside 220 ms pins; `Esc` or `⇥` past the end closes. The set peek
  keeps `walkingKeptRail` as backing state but the walk follows `finalSetAssetIDs`
  in both routes. Surfaces: the bottom-pinned bar on the table (150 / 170 / 220
  tiles), the similar row in focus (cursor at 1.6×), the strip in set order with
  `set / release ⇥`. The flags peek unfolds every burst and shows the inferred
  groups band; `G` takes the picks as one command.
- **Inference is measured, not assumed.** P0 assets never carry sharpness, so the
  flags peek measures it off grid thumbnails (`BlurScorer`, now `nonisolated`) and
  embeds one frame per burst (`EmbeddingService`) in a detached task. Same burst,
  same scene, same subject; the prototype's "same exposure problem" group writes
  recipes and is not built.
- **Hold-␣ is before**, in both routes, with press-and-hold-the-photograph parity
  (200 ms). Nothing moved off Space: the 1:1 zoom the prompt cites died with
  `P0SinglePhotoEditor`, so `holdingLoupe` was key-less and is gone.
- **Esc ladder** is peek → drawer → selection → route and nothing else; an open burst
  folds by its badge. Probe field `escTransientHoldActive` mirrors steps 1–3.
- **Hold-V is retired** — `EditVariantSession`, the `WorkspaceState` fields, the V
  paths, five probe fields at all five mirror sites, `EditVariantTests`.
  `branchInteractiveVariant` and the registry pinning stay for the version thumbnails.
- **Shelf is a drop target**; table tiles and group frames are draggable with the
  prototype's comma-joined id payload; a drop keeps through the same keep-many
  command `G` uses and spends the selection.
- **⇧-click range · ⌘-click toggle** with an anchor; the `P0_CULLING.md` ruling closed.
- **Develop drawer on `E`**: nine sliders (Whites / Blacks / Dehaze deliberately
  absent), ratios, `R`, straighten, profile, match chips, auto · match · reset. Every
  drawer edit is one `BatchEditMutationCommand` so provenance moves with the recipe;
  a slider release ripples its delta to the selection or the burst. `M` matches the
  checked groups to the selection › set › moment. The surface says *match* because
  the prototype's word is banned copy.
- **Version column hides** while the drawer or a peek is up.

Honest gaps, in the order someone would hit them:

- Live pixel verification of items 3–9 is pending. Since ~14:08 the Debug app
  launches into an idle run loop with no window on this host whenever a Lumina from
  Xcode's own DerivedData (pid 64132, not any stream's) is running; items 1–2 were
  verified live by real key events before that (34 screenshots in
  `~/lumina-wt/p1-grammar-proof/`), the rest by logic tests and the offscreen runner.
- `⇧←→` reorders the set inside the set peek — no set-reorder command exists; the
  peek's copy omits the clause.
- The flags peek has no focus-check overlay and no `eyes` flag; the groups band's
  head line truncates at 1280 wide.
- The crop-handle overlay on the photograph is not wired to the drawer; the
  photograph's gestures are P0's. `P0CropControls.centeredCrop` was not salvaged: it
  ignored the frame's own aspect (1:1 was a no-op on a 3:2 frame).
- Sharpness runs 0…100 in the drawer against the engine's 0…150.
- The peek bar overlays the last table rows with no bottom inset, as the prototype's
  `position: absolute` does — a ruling, not a bug.
- `lookGlancing` / `beginLookGlance` and the legacy `P0ChapterTableView` remain; the
  ⌘G binding is gone. They go when the legacy table does.
- Twenty tokens were added along the way, every one for a value already forbidden;
  the tokens hash is `4a917285…` and the F07 golden was carried forward each time
  with the previous payload byte-for-byte.
- P0 fixed the upside-down interactive tier at d2b2824 on their branch from a repro
  this stream handed over (LUM0012); not cherry-picked here by the stream rule.

## Elasticity backlog (2026-09-22)

Ordered by what blocks what, not by size. `[dbg]` debugging · `[edge]` edge
conditions · `[resp]` responsiveness.

### P0 — blocks this stack

- `[dbg]` **The reported upside-down flip is unreproduced.** The first theory —
  that `OrientedDisplayImage.aligning` drops orientations 2/3/4 — was wrong:
  `CIRAWFilter` applies the file orientation itself, so the no-op is correct for
  all eight values. Needs a repro naming the frame and whether it flips on open,
  on scroll, or at promotion.
- `[dbg]` **Nothing proves the photograph renders.** `.task` does not run for a
  view hosted offscreen and Metal does not composite through `cacheDisplay`, so
  every capture shows an empty well. The one thing the captures cannot check is
  the thing a reader looks at. Fixing this first makes the flip cheaper to find.
- `[resp]` **`ElasticWrapLayout` sizes every subview twice per pass**, uncached,
  in both `sizeThatFits` and `placeSubviews`. Tiles are fixed-width.
- **Version thumbnails all read `gridThumbPath`**, so shot / auto / yours render
  identically — the column asserts a difference that is not on screen.
- **Keys are not migrated**: `1/2/3`, `A`, `⌘A`, `?`-hold, pinch. `pickVersion`
  is reachable only by clicking a version.
- `[edge]` **A cold catalog reports `previews 0/N`** while extraction runs; the
  second open reports `N/N`. Either surface it honestly or make it not say that.

### P1 — the grammar the design specifies

- Checkpoint 04: hold-`⇥` cycling related → set → flags, and hold-`␣` before.
- Rewrite `P0EscLadder` to peek → drawer → selection → route.
- Finish retiring hold-V: `EditVariantSession`, its `WorkspaceState` fields, the
  `V` binding, its probe fields.
- The set shelf as a drop target.
- `⇧`-click range and `⌘`-click toggle — the ruling `docs/P0_CULLING.md` has had
  open since before Elastic.
- Checkpoint 05: develop drawer (`E`), sync (`M`), rotate (`R`), profile picker,
  crop ratios, straighten.

**Status (2026-09-22):** every item above landed on `elastic-v4/p1-grammar`; see §6
"P1 — the grammar" for what shipped and the honest gaps.

### P2 — responsiveness

- `[resp]` A guaranteed-resident floor tier (~256 px for every frame, evicted by
  distance) so scroll never shows a well.
- `[resp]` Prefetch by scroll velocity rather than visibility, ~2 screens ahead,
  cancelling behind. The gates exist; their trigger does not.
- `[resp]` Coalesce the request stream so a flick drops superseded requests
  instead of queueing work that is stale before it lands.
- `[resp]` Render the three version thumbnails through the interactive tier,
  which is what closes the P0 item properly.

### P3 — hardening

- `[edge]` Orientation 2/3/4 and square images — latent, now guarded by
  `OrientationContractTests`, reachable only by a non-orienting backend.
- `[edge]` Offline originals · damaged file mid-card · disk full · two-card
  eject mid-copy.
- `[edge]` Duplicate basenames across volumes · byte-identical duplicates ·
  filenames containing spaces.
- `[edge]` Sidecar date divergence reading as an external edit · `crs:CameraProfile`
  values Lumina never writes (`Adobe Standard` is in the sample sidecars).
- `[edge]` Boundaries: clip at exactly 2% and 0.5%, burst gap at exactly 2 s, and
  the median-dependent chapter threshold.
- `[dbg]` Races: stale promotion after the cursor moves · aspect flip on
  promotion · scroll outrunning decode · eviction of a pinned tier mid-render ·
  `⌘Z` during an in-flight auto pass · Lightroom rewriting a sidecar while the
  shoot is open.

### Fixture coverage against this list

`Scripts/harness/fixtures/elastic_cards.py` cuts a card that exercises the
moment, gap, light-word, burst, mix, clipping and tone conditions from real
frames. It does not cover the P0 render proof, the P1 grammar, or the P2 work —
those need code, not data.

## Known gaps in checkpoint 03

- Version thumbnails all read the same `gridThumbPath`, so shot/auto/yours look identical. The prompt
  allows rendering them through the scheduler's interactive tier; that is not wired yet.
- Keys are not migrated: `1/2/3`, `A`, `⌘A`, `?` hold, and pinch in/out are still unbound. `pickVersion`
  exists and is reachable by clicking a version.
- `P0EscLadder` still has its old step list minus grouping; the peek → drawer → selection → route order
  lands with checkpoint 04's peeks.
- The hold-V variant system is only partly retired: the tray died with `P0SinglePhotoEditor`, but
  `EditVariantSession`, its `WorkspaceState` fields, the V key binding and its probe fields remain.
- The set shelf is not yet a drop target.

## Next

Checkpoint 04 (hold-key peeks and before), plus the key bindings deferred above.
