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

### P2 — responsiveness

- `[resp]` A guaranteed-resident floor tier (~256 px for every frame, evicted by
  distance) so scroll never shows a well.
- `[resp]` Prefetch by scroll velocity rather than visibility, ~2 screens ahead,
  cancelling behind. The gates exist; their trigger does not.
- `[resp]` Coalesce the request stream so a flick drops superseded requests
  instead of queueing work that is stale before it lands.
- `[resp]` Render the three version thumbnails through the interactive tier,
  which is what closes the P0 item properly.

#### P2 measurement (2026-09-22, branch `elastic-v4/p2-scroll`)

**Before / after, in one table.** Same card (`card-elastic-v4-stress`, 403
frames, 55 moments, 13 screens at 1280×800), same machine (M4 Pro, 24 GB),
same runner, catalog warm, unfilmed. "Before" is `5181c75` plus only the
exiftool pipe fix that made the card open; "after" is the item 5 build,
run a. Cold is different and is measured separately below: a fresh card's
first open extracts previews for ~1 min (`previews 0/N` meanwhile) and no
scroll number applies until it is done.

| pass | steps before → after | tick p95 before → after | tick p99 after | wells (ticks) before → after | soft (floor) tiles after | decodes in pass before → after |
|---|---|---|---|---|---|---|
| glide, 1 screen/s × 5 | 4 in 19.8 s → 478 in 5.0 s | 1090 ms → 2.9 ms | 15.9 ms | 3/4 → **0**/478 | 0 | 105 → 141, all issued ahead |
| flick, 6 screens/s to end | 2 in 7.2 s → 100 in 1.2 s | 0.04 ms* → 10.2 ms | 10.5 ms | 1/2 → **0**/100 | 0 | 16 → 146, all issued ahead |
| return, 6 screens/s to top | 2 in 6.9 s → 183 in 2.0 s | 0.21 ms* → 9.3 ms | 11.4 ms | 0/2 → 0/183 | 0 | 0 → 0 |
| dart, cold grid over warm floor | — → 68 in 0.7 s | — → 1.6 ms | 1.7 ms | — → **0**/68 | 552 | — → 140 |
| recoil | — → 66 in 0.7 s | — → 1.9 ms | 2.1 ms | — → 0/66 | 0 | — → 19 |

\* The baseline's flick and return managed two steps each; their tick
percentiles are two samples of the step itself while the main thread spent
seconds between steps, and are not comparable. The step counts are.

What moved it, in order: caching the chapter arrangement (item 2 part 1:
steps 4 → 417 on the glide), the plate sampling residency in its own pass
(item 2: wells 20 → 14 ticks, tick p95 2.5 → 0.95 ms), the floor tier (item
3: wells → 0 on every pass), velocity prefetch (item 4: soft tiles 91/148 →
0), one bounded queue (item 5: no change on this disk; bounds decode
concurrency at 4). Full per-item tables follow.

What is left on the scroll path is not scroll's: the flick's and return's
~10 ms tick p95 is the cost of realizing a new row's wrap layout
(`ElasticWrapLayout` sizes every subview twice per pass — P0's item), and a
row-realization step is what the glide's 15.9 ms p99 is. The dart from a
cold grid tier draws ~550 soft tiles at 6 screens/s — the floor doing its
job; a faster grid decode would shrink it, nothing on the scroll path can.

Not changed anywhere in P2: full resolution and true RAW for the focused
frame and for export. Nothing here reaches `PreparedRawSession` or
`DevelopRenderScheduler`; the scroll path samples JPEG tiers only.

Scroll now has its own instrument, `--p0-scroll-live [out] --p0-open <folder>`
(`P0ScrollLiveRunner`). It mounts the shell on the time route in a real
1280×800 window, drives the table's `NSScrollView` through three passes —
`glide` 1 screen/s for 5 screens, `flick` 6 screens/s to the bottom, `return`
6 screens/s back — and reports per pass, in the `rapidScrub` shape:

- `p0.scroll.tick_ms.<pass>` — main-thread cost of one step: offset change,
  SwiftUI layout, AppKit display. A synchronous decode reached from a tile's
  `body` lands here. p50/p95/p99 with the window declared.
- `p0.scroll.frame` — display-link interval while scrolling, via
  `P0RenderInstruments`; catches dropped frames the layout timer cannot see.
- `blankSeen` / `wellTicks` / `wellTiles` — a realized tile with nothing
  resident at the grid tier when the step finished. Realization is reported by
  `ChapterPlateImage` through `ElasticScrollTracker`, injected only under the
  table; residency is read from `BrowsePixelService.isResident`, a lock-guarded
  mirror of the cache that never hops to the actor.
- `LUMINA_SCROLL_FILM=1` writes a PNG per step and a second copy of every step
  that saw a well, so the frames that matter can be found without scrubbing.
  Filmed runs are flagged and are never a baseline.

Card: `elastic_cards.py --stress 400 --name card-elastic-v4-stress` appends
RAW-heavy stress moments (six RAW, two phone, 12 min apart) until the card has
403 frames in 55 moments — about 7 GB, local only.

**Baseline, 27-frame card, warm** (harness proof, not the number that matters —
the card is 2.1 screens tall, so the glide reaches the bottom and there is no
flick to measure):

| pass | steps | tick p50 | tick p95 | tick p99 | max | well ticks | tiles decoded during pass |
|---|---|---|---|---|---|---|---|
| glide | 101 | 0.4 ms | 0.95 ms | 21.3 ms | 21.3 ms | 4 | 10 |
| return | 19 | — | 0.92 ms | 0.92 ms | — | 0 | 0 |

The shape of the problem is already visible: the only steps that cost anything
are the ones that realized a row, and every newly realized row shows a well
for at least one frame even when its pixels are resident, because the tile
asks the actor asynchronously and sets state after the hop.

**Why the 403-frame baseline could not be taken at first.** "Reading dates…"
never finished on any shoot past roughly 250 frames: `ExifToolService.runData`
waited for exiftool to exit before draining its stdout pipe, and `-json` over
that many frames is larger than the 64 KB pipe buffer, so the child blocked on
write and the parent on exit — forever. Every large catalog on this machine
(`card-clean-500`, the stress card) had `capturedAt` on 0 of its frames for
that reason. Fixed by draining before waiting (`captureOutput`, pinned by
`ExifToolProcessTests`). Not a scroll change; it is what made scroll
measurable.

**Baseline, 403-frame card (13.0 screens at 1280×800), warm, unfilmed, at
`5181c75` plus the exiftool fix:**

| pass | duration | steps | steps/s | tick p50 | tick p95 | tick max | well ticks | well tiles | decodes in pass |
|---|---|---|---|---|---|---|---|---|---|
| glide (1 screen/s, 5 screens) | 19.8 s | 4 | 0.2 | 634 ms | 1090 ms | 1752 ms | 3/4 | 47/62 | 105 |
| flick (6 screens/s, to end) | 7.2 s | 2 | 0.3 | 0.04 ms | 0.04 ms | 284 ms | 1/2 | 16/60 | 16 |
| return (6 screens/s, to top) | 6.9 s | 2 | 0.3 | 0.21 ms | 0.21 ms | 552 ms | 0/2 | 0/45 | 0 |

A five-screen glide that should take 5 s took 20 s and managed four steps: the
main thread was busy for seconds between them. An 8 s `sample` of the main
thread during the glide put 86 % of it in the table's row closure, and nearly
all of that in `session.gapInterval(after:)` → `session.chapters` →
`ShootChapterArrangement.arrange(_:)` — the whole arrangement recomputed for
every row and again for every gap — with `CaptureName.parse` compiling an
`NSRegularExpression` per call inside a sort comparator.

**After caching `chapters` with `assets` and compiling the pattern once**
(same card, same conditions):

| pass | duration | steps | steps/s | tick p50 | tick p95 | tick p99 | tick max | frame p95 | well ticks | well tiles | decodes in pass |
|---|---|---|---|---|---|---|---|---|---|---|---|
| glide | 5.0 s | 417 | 83 | 0.48 ms | 2.48 ms | 10.1 ms | 40.9 ms | 8.3 ms | 20/417 | 118/10553 | 91 |
| flick | 1.2 s | 91 | 76 | 0.80 ms | 9.27 ms | 9.4 ms | 9.6 ms | 14.2 ms | 20/91 | 152/2544 | 152 |
| return | 2.0 s | 178 | 88 | 0.56 ms | 8.99 ms | 9.8 ms | 70.7 ms | 8.3 ms | 0/178 | 0/4858 | 0 |

The passes now run at the pace they were asked for. What remains is the scroll
work proper: every decode in a pass is a tile that was realized before its
pixels were asked for (flick: 152 decodes, 152 misses, 4 hits), the flick's
tick p95 sits just over the 8.33 ms frame budget, and one step in twenty shows
a well. Items 2–5 are aimed at exactly those three numbers.

**After the plate samples residency synchronously** (item 2 closed — the tile
draws what is resident in the same pass and only a miss enqueues; the strip's
moment-gap check reads an indexed membership map instead of scanning):

| pass | steps | tick p50 | tick p95 | tick p99 | well ticks | well tiles | decodes in pass |
|---|---|---|---|---|---|---|---|
| glide | 439 | 0.45 ms | 0.95 ms | 8.9 ms | 14/439 | 91/10910 | 91 |
| flick | 93 | 0.78 ms | 9.19 ms | 9.3 ms | 20/93 | 152/2614 | 152 |
| return | 190 | 0.55 ms | 8.53 ms | 9.9 ms | 0/190 | 0/5043 | 0 |

Well tiles now equal decodes exactly: every well is a miss and nothing else.
The "resident but not yet shown" frame is gone (glide well ticks 20 → 14, tick
p95 2.5 → 0.95 ms). The flick is unchanged because its wells are all misses —
that is items 3–5. The flick's tick p95 of ~9 ms is the cost of realizing a
new row's wrap layout, which is P0's `ElasticWrapLayout` item, not this one.
Nothing on the scroll path decodes synchronously: the only sync work reached
from a tile's body is a lock-guarded dictionary read.

**Floor tier (item 3).** `BrowsePixelService.Tier.floor` is a 256 px entry
(`PhotoImageTier.floorLongEdge`) in its own store, outside the LRU. It is
warmed nearest-first from the viewport the moment the shoot's order is known
(`ElasticScrollTracker.shootChanged`, fed once per preparation event from
`P0SessionModel.apply`), two decodes in flight, and evicted by distance from
the viewport centre — never by recency, so a flick to the far end cannot push
out what the reader is about to scroll back to. The centre is the median index
of the realized plates and moves on every appearance.

Cap: **64 MB** (`PhotoImageCacheBudget.floorCeilingBytes`), by bytes rather
than count so squares and mixed aspects stay bounded. A 256 px 3:2 frame is
~175 KB, a square ~262 KB, so the budget holds at least 256 frames and about
380 at 3:2 — six to nine screens either side of the viewport at 1280×800,
past the two screens the velocity prefetch looks ahead. A 94-frame shoot fits
whole (~16 MB); a 2000-frame shoot is a sliding window. On the 403-frame card
369 frames are resident at 63.9 MB, warm 1.5 s after mount. Under memory
pressure the floor halves by distance rather than dropping.

A tile draws grid, else floor, else the well; a floor draw is *soft* and the
grid tier is still requested. The runner now counts soft tiles separately from
wells:

| pass | steps | tick p95 | tick p99 | well ticks | well tiles | soft (floor) tiles | decodes in pass |
|---|---|---|---|---|---|---|---|
| glide | 498 | 1.18 ms | 9.95 ms | **0**/498 | **0**/11839 | 91 | 91 |
| flick | 85 | 11.3 ms | 13.8 ms | **0**/85 | **0**/2372 | 148 | 144 |
| return | 184 | 9.45 ms | 10.4 ms | 0/184 | 0/4941 | 0 | 0 |

(Two runs of this build agree on the wells — 0 — and put glide tick p95 at
0.82 and 1.18 ms, flick at 9.9 and 11.3 ms; the numbers above are the later
run, the one that also carries the nearest-K floor.)

No well on any pass. Every tile that would have been a well is now a soft
draw of the same photograph, sharpened when the grid tier lands. The
remaining numbers to move are the soft count on a flick (items 4 and 5: those
grid decodes should have been issued ahead of the cursor) and the flick's
~9–10 ms tick p95, which is row wrap-layout (P0).

Two things the measurement itself taught: the session's `assets.didSet`
fires once per *element* write, so anything there must be O(1) — a hook that
recomputed the path list per element made the reopen's preview merge
quadratic and starved the main thread; and a warm reopen replays the dates
phase and then replaces `assets` wholesale, so the runner now waits for that
phase to have been seen and the status to hold still before measuring.

**Prefetch by velocity (item 4).** `ElasticScrollTracker` now estimates
velocity from its viewport centre over a 0.25 s horizon (frames/s along the
shoot order, signed) and hands `BrowsePixelService.setGridPrefetchWindow` a
window: still → one screen either side, nearest first; moving → two screens
past the leading edge in the direction of travel, one screen behind the
trailing edge kept, everything further behind cancelled. A cancel that lands
before the decode starts costs nothing (`pixel` checks `Task.isCancelled`
before spawning), which is the point of cancelling behind a flick.

Two rules the first runs forced. The median moves in phases as rows leave
and arrive, so the estimate dips to "still" mid-flick and occasionally flips
sign for one sample; turning the window on either cancelled two screens of
good prefetch and re-issued it (one run: 501 issued, 288 cancelled, 711 soft
tiles). Now a still window keeps the hull of the previous keep range, and a
direction is committed only after it has held for 120 ms.

The runner gained two passes — `dart` (6 screens/s for 4 screens) and
`recoil` (straight back) — and drops the grid tier, keeping the floor, before
the dart: a cold LRU over a warm floor is the state after a memory-pressure
trim and the only way the reversal has anything in flight to cancel.

Two runs of the same build, 403-frame card, warm:

| pass | steps | tick p95 | tick p99 | peak frames/s | prefetch issued | cancelled | soft (floor) tiles | wells | decodes in pass |
|---|---|---|---|---|---|---|---|---|---|
| glide | 499 / 501 | 1.05 / 1.45 ms | 9.7 / 10.0 ms | 92 / 94 | 147 / 147 | 6 / 6 | **0 / 0** | 0 / 0 | 141 / 141 |
| flick | 98 / 92 | 10.6 / 10.9 ms | 10.9 / 14.9 ms | 212 / 212 | 146 / 146 | 0 / 1 | **0 / 0** | 0 / 0 | 146 / 146 |
| return | 175 / 179 | 10.6 / 9.9 ms | 15.6 / 10.8 ms | 166 / 161 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| dart (cold grid) | 67 / 67 | 1.84 / 1.95 ms | 2.0 / 2.2 ms | 153 / 152 | 144 / 144 | 0 / 0 | 534 / 534 | 0 / 0 | 144 / 144 |
| recoil | 67 / 66 | 1.99 / 2.05 ms | 3.2 / 2.2 ms | 196 / 187 | 19 / 19 | 0 / 0 | **0 / 0** | 0 / 0 | 19 / 19 |

Read against item 3's table: the glide's 91 and the flick's 148 soft tiles
are now 0 — every grid decode a pass needed was issued by the window before
the tile was realized (issued = decodes, hits from the plate 0 because the
plate found the pixels resident and never asked). The dart from a cold grid
tier still shows 534 soft draws: at 6 screens/s from nothing, prefetch cannot
outrun realization, and that is what the floor is for — 0 wells. Cancels stay
in single digits because decodes land within the pass; the mechanism is
exercised (the dart's own window is what the recoil would cancel) and cheap.

The flick's ~10 ms tick p95 is unchanged and is row wrap-layout (P0).

**One request queue (item 5).** Until now a realized tile's own miss spawned
a detached decode, and the window spawned one task per path — on a flick,
~150 concurrent decodes competing with layout for cores, most of them for
tiles the cursor had already left. Every grid-tier miss now goes through one
queue in `BrowsePixelService`, `PhotoImageCacheBudget.gridDecodeWidth` (4)
wide, ordered by *anyone waiting first, then distance from the viewport*, and
re-ordered every time a slot frees — the order now, not the order of arrival.
A request that leaves the window with nobody waiting, or loses its last
waiter (the tile's `.task` was cancelled by SwiftUI when it scrolled off), is
dropped before its decode starts and counted as `stale` or `cancelled`, the
develop scheduler's own vocabulary. Concurrent asks for one path share one
decode. Pinned by `BrowsePixelGridQueueTests` at width 1, where seven of ten
window requests are dropped unrun when the window moves on.

Two runs, 403-frame card, warm:

| pass | steps | tick p95 | tick p99 | window issued | decodes started | stale | cancelled | soft (floor) tiles | wells |
|---|---|---|---|---|---|---|---|---|---|
| glide | 478 / 482 | 2.9 / 2.2 ms | 15.9 / 15.9 ms | 147 / 147 | 141 / 141 | 6 / 6 | 0 / 0 | 0 / 0 | 0 / 0 |
| flick | 100 / 101 | 10.2 / 10.3 ms | 10.5 / 10.6 ms | 146 / 146 | 146 / 146 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| return | 183 / 180 | 9.3 / 10.3 ms | 11.4 / 11.4 ms | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| dart (cold grid) | 68 / 68 | 1.6 / 1.9 ms | 1.7 / 2.1 ms | 150 / 150 | 144 / 144 | 6 / 6 | 0 / 0 | 552 / 547 | 0 / 0 |
| recoil | 66 / 66 | 1.9 / 2.3 ms | 2.1 / 2.4 ms | 19 / 19 | 19 / 19 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |

On this disk decodes land inside the pass, so the stale counts stay small
(six per glide, six per dart) and nothing is cancelled: the flick never asks
for a tile the window did not already have in hand. The queue's value shows
where decodes are slower than the flick — the width-1 test — and in what it
bounds: at most four ImageIO decodes alongside layout, whatever the shoot.

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
