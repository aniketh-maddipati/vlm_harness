# TEST-PLAN map: every v0.01 row and trust rule → what checks it today

One line per row of `design/handoff/lumina-cull/TEST-PLAN.md` and per beta trust rule 1–17 in
`design/handoff/lumina-cull/ROADMAP.md`. Model: `Tests/probe/EDGE-CASES.md`. Written 2026-10-05 against
c30ac18 (the v0.01 handoff: Sets v7, Edit v21) by reading the scenario JSON, the harnesses and the
XCTest source; nothing was run for this map.

**Status words.** **covered**: an automated check asserts the row. **partly**: something checks part of it;
what is missing is named. **automatable**: nothing checks it yet, a scenario could (sketched in 3 lines).
**hardware only**: needs a person, a device or a third-party app (steps in order).

**Where checks live.** Probe scenarios: `Tests/probe/scenarios/<name>.json`, cited with step numbers
(0-based, as the runner numbers them). Chromium harness: `Tests/web/plumbing-harness.mjs`, cited by its
`ok(…)` label. WebKitGTK sandbox: `Tests/web/webkit.py`, cited by suite and `t(…)` label. XCTest:
`LuminaLogicTests/<Class>.<test>`. Design fixtures: `design/handoff/lumina-cull/lumina-core-v4.test.mjs`.

**v7 or v5 steps.** Only `smoke`, `keys-open-return`, `selftest`, `app-plumbing-contract`, `app-smoke` and
`app-empty-start` were rewritten for v7 (four steps, ⌘4 = Save, the Save guard's second ⌘⏎, no Flag).
Every other scenario still carries v5 steps or was never re-run on v7. Marked per citation:
- **(v5 steps)**: presses ⌘3 expecting Save, sends one ⌘⏎ with no Save-guard handling, or presses F and
  expects a flag. On v7 ⌘3 is Edit, the first ⌘⏎ with undecided photos only arms (`state.armed === 'save'`),
  and F is the focus overlay (R and X remove). These fail or assert the wrong thing until rewritten:
  `app-session` (⌘3 @28, F @5, flags @10/23/44, one ⌘⏎ @31), `app-reopen-renamed` (F @4, flags @16, one
  ⌘⏎ @19), `app-reopen-twice` (F @4), `app-rename-mid-cull` (⌘3 @21, ⌘⏎ @24), `app-xmp-both` (⌘3 @14),
  `app-xmp-lightroom` (⌘3 @10, ⌘⏎ @14/33), `app-xmp-changed-since-open` (⌘3 @17, ⌘⏎ @20/42),
  `fault-card-pull-cull` (⌘3 @16/40, ⌘⏎ @24/43), `fault-readonly-card` (⌘3 @17 then expects Save's card
  notice, ⌘⏎ @19), `hostile-names` (⌘3 @18), `hostile-xmp` (⌘3 @12), `open-folder-awkward-name` (⌘3 @16),
  `card-stress` (⌘3 @10), `screens-1440/1920` and their `-app` twins (F @15 "05-cull-flagged", ⌘3 @33
  "12-save").
- **(not re-run on v7)**: no ⌘3 / F / single-⌘⏎ step, but outside the six above: `card-sandbox-first`,
  `card-sandbox-again`, `fault-card-pull-read`, `fuzz-app-card`, `edge-*`, `hostile-card-label`,
  `edit-canvas`, `edit-cold`, `raw9`, `scroll-*`, `open-slow-disk`.

**Totals.** TEST-PLAN, 50 checkbox rows: 1 covered, 29 partly, 8 automatable, 12 hardware only (plus G7, the
cable-import spike, hardware only). Trust rules 1–17: 3 covered, 8 partly, 1 automatable, 5 hardware only.

**Latest evidence.** `~/LuminaEvidence/probe/20261005-113437` (run from the `.claude/worktrees/lumina-gallery-redesign-dac647`
checkout): `smoke`, `keys-open-return`, `app-smoke`, `app-empty-start` pass; `selftest` fails 4 of 25 (row A3);
`app-plumbing-contract` fails step 1 (`__lumina.drift()`: "onDir/readOne changed (fnv 2481318810)", the C1 lane's subject).

## The ten scenarios worth writing first

1. **Rewrite the v5-step scenarios for v7** (list above): ⌘4 for Save, then `expect state.armed === 'save'`
   and a second ⌘⏎ (as `app-smoke` steps 24–26 do), drop every F/flags step. It turns trust rules 1, 2 and 6,
   and Save rows V1/V3, back into running checks. Highest value: these are the card and sidecar guarantees.
2. **`app-dng-picks`**: a folder of forged phone DNGs plus ARWs (C4's `Tests/probe/forge_dng.mjs`): opens with
   the phone's model and lens, picks two DNG + one ARW, ⌘4, armed ⌘⏎ → `Picks/` copies hash-equal to the
   sources, originals byte-identical, `.xmp` only for the ARW (O4, V2, R11).
3. **`phoneOf` + DNG fixtures in Node**: the 7 `phoneOf` cases of row A2 and the 5 DNG families of row A1,
   loading `lumina-core-v4.js` as the design test does. C4's `Tests/web/dng-parse.test.mjs` covers iPhone,
   Pixel, Sony ARW and a Sony DNG; Samsung Expert RAW and a Leica/DJI DNG are still missing (A1, A2, G6).
4. **Card writes nothing, any file**: list the card image recursively, dotfiles included, before the read and
   after read / cull / Save / pull / re-insert; the two lists must be equal (catches `.DS_Store`, `._*`,
   anything the app or WebKit makes) (T2, R1).
5. **Zero network in a full session**: in the Chromium harness record every `page.on('request')` whose URL is
   not `lumina.test` and every WebSocket; run the whole flow (open, pick, Edit, Save, Beta panel, FAQ, tour);
   expect none. In the probe, log every request the content rule blocks; expect none (T1, R7).
6. **`selftest` follows v7 + `?selftest&n=1000`**: the design's `lumina-selftest.js` still tests v5 keys
   (DESIGN-ASKS item, see A3), then a `selftest-1000` scenario with `"query": "selftest&n=1000"` that dumps
   the three timing rows (A3).
7. **`edge-phone-mixed`**: forged α7 IV ARWs + iPhone DNGs in one folder, the phone frames split between
   the 1× and 3× lenses: expect the "bodies" note naming both, and a row break where the lens changes (K2).
8. **`phone-page`**: Open → "Add from phone" → `state.phonePage` true and view still `import`; drop synthetic
   `File`s (a DNG and a HEIC) through a constructed `DataTransfer` → RAW tile added, HEIC dimmed "not added";
   "Start shoot with N" → Pick with the name field focused; Back adds nothing (U1, U3, U7).
9. **`first-launch`**: empty page store → tour shows; Esc skips; reload → no tour (`lumina-v4-toured`); `?` sheet
   reopens it; Beta chip lists `Component.ISSUES` and the three links; with `debug: false` no debug link is in
   the DOM (T3, T4, T5, R13).
10. **`seen-before`**: open shoot A, pick two, close; open a copy of the same RAWs in another folder → decisions
    back with a note naming shoot A, "N already here, skipped" when added to A; re-adding A's folder → "nothing
    new" (S2, S7). Needs `SetsSources` wired first (see S1).

## Automated

| # | Row | Covered by | Status |
|---|---|---|---|
| A1 | `node lumina-core-v4.test.mjs`: no FAIL; add iPhone ProRAW (SubIFD strips), Pixel, Samsung Expert RAW, Leica/DJI (not a phone), ARW with Make SONY | The test runs its `eq(…)` checks on `lumina-core-v4.fixtures.json` (keys `sweep, rows, stacks, a7iii, split, afterBurst, moves, stackMerge, peak, dark, twoBody, rowDone, paint`). None is a DNG and none calls `parseHead` or `phoneOf`. | **partly**: the run exists; all five asked-for fixtures are missing. The design owns this file, so the fixtures go into the design (DESIGN-ASKS) or into `Tests/web` (C4's `dng-parse.test.mjs`: iPhone, Pixel, ARW, Sony-make DNG; no Samsung, Leica or DJI). |
| A2 | `phoneOf` unit cases: Apple/iPhone, Google/Pixel, samsung/SM-S918B → phone; samsung/NX500, SONY/ILCE-7M4, empty make → camera; SONY/XQ-DQ54 → phone | Nothing outside the page and `plumbing.js` calls `phoneOf` (grep of Tests, Tools, LuminaLogicTests). | **automatable**: `createRequire('lumina-core-v4.js').phoneOf({make, model})` for the 7 pairs; expect non-null for the 4 phones, null for the 3 cameras; plain `node`, ok/FAIL lines. |
| A3 | `?selftest` in the app: all pass; timing at `?selftest&n=1000` | `selftest` (step 2 expects no failing row), `webkit.py` suite `selftest` ("behaviour checks pass in WebKit"). 2026-10-05 run: 21/25, FAIL "R keeps too", "X changes nothing", "F flags", "⌘3 shows the Save bar with a count" (the design's `lumina-selftest.js` still tests v5 keys; v7 maps R/X to remove and F to the overlay). Timing rows pass: → 16.0 ms, large view 51.0 ms. | **partly**: the selftest file needs a design fix; no scenario runs `?selftest&n=1000` (`selftest.json` query is `selftest`). Note `release_preflight.sh` checks the Release binary has no name for `lumina-selftest` (S4), so "in the app" means a Debug or probe build. |

## Open

| # | Row | Covered by | Status |
|---|---|---|---|
| O1 | Card insert → Card panel. Non-Sony card → quiet line, card not hidden | `card-sandbox-first` (not re-run on v7) steps 2–8: insert noticed (`cardPending` name, no count, sandboxed), panel pick, 12 read with `readingCard`. `SetsCardAccessTests.testFirstInsertIsUnknownAndCullAsksAtDCIM`; `SetsCardDNGTests.testJPEGOnlyCardAndHiddenRAWAreNotCounted`, `testEmptySonyFolderIsNotSupportedRAWCard`, `testVolumeWithoutDCIMIsNotACard` (`sony` false / nil). | **partly**: the native verdict is tested; the page's quiet line for an unsupported card, with the card still shown, is not. Automatable: as `hostile-card-label`, `__lumina.card(true, {sony:false, photos:0, …})` → expect the card shown and its line text; snap. |
| O2 | ⌘O, the "Go straight to" buttons, and drag a folder from Finder → same shoot | ⌘O: the probe's `openFolder` step presses ⌘O with a scripted panel (Runner.swift `case "openFolder"`), so `app-smoke` step 4 opens through ⌘O; harness 'read: lands in Cull'. "Go straight to" was removed in the final pass (README, "Latest changes"). Drag from Finder: no drop handling in `plumbing.js` or `SetsRootView.swift` (grep `drop`, `dataTransfer`). | **partly**: ⌘O covered; the row's "Go straight to" is obsolete; drop is unchecked and nothing app-side swaps the page's drop for a native read. Hardware: 1. drag a shoot folder from Finder onto the Open screen; 2. check it opens as the same shoot as ⌘O on it (one Recent, same decisions). |
| O3 | ARW + JPEG twins skipped silently. JPEG/HEIF with no RAW → note | Harness 'intake: no-ARW note uses non-ARW names from the listing' (exact v7 text "no ARW or DNG found · 2 CR3 · 1 JPEG / HEIF · 1 videos · Lumina reads ARW and DNG"), 'read: import notes from intake + sidecars' (shoot has a `DSC01001.JPG` twin). `edge-junk-in-folder` (not re-run on v7) steps 5–6: n = 2, bad = 0. `SetsIngestDNGTests.testDNGsAreListedLikeARWsWithoutChangingSidecarsOrOtherFiles` (`d.jpg`, `e.heic` in `others`). | **partly**: no check asserts that no note mentions the twin. `webkit.py` flow 'no ARW: the page's note from the native listing' still expects the v5 text ("… only Sony ARW is supported") and will fail on v7. |
| O4 | iPhone export folder (unmodified originals) → DNGs open. HEIC twins skipped | `SetsIngestDNGTests.testDNGsAreListedLikeARWsWithoutChangingSidecarsOrOtherFiles` (listing only: DNGs in `files`, `.heic` in `others`). The harness's synthetic shoot is ARW only. | **partly**: nothing reads a DNG through the page. Automatable (top-ten 2): forge `IMG_0001.DNG` + `IMG_0001.HEIC` …; openFolder; expect `real.length`, `model === 'iPhone 15 Pro'`, lens "1× camera", no HEIC tile. |
| O5 | Access denied → banner → Settings → back → retry works | Harness 'access: luminaAccess(true, name) on denial', 'access: checkAccess → banner cleared'; `webkit.py` flow 'access: denied → luminaAccess banner', 'access: checkAccess → cleared'; `app-plumbing-contract` step 4 (`openSettings`, `checkAccess` exist); `SetsCardAccessTests.testAccessCheckTellsMissingFromReadable`. | **partly**: the page and stand-in sides are covered; a real TCC denial is not. Hardware: 1. System Settings → Privacy → Files and Folders: turn Lumina off for Removable Volumes; 2. open a card folder → banner; 3. banner's Settings button opens that pane; 4. allow, return, Retry → the shoot reads. |

## Pick

| # | Row | Covered by | Status |
|---|---|---|---|
| K1 | Bursts open in place, top frame pinned, rest fade in below. ← → order: top, its row, then the unfurled frames | `selftest` rows "⇧→ opens a stack with a time axis", "→ on a closed stack walks into its frames", "→ past the last frame moves on and closes the stack", "⌥→ skips a closed stack" (all pass 2026-10-05). Design fixtures 'stacks from Sony sequence numbers', 'α7 III whole seconds · 10 stays 10'. | **partly**: key order covered; "top frame pinned, rest fade in" is visual. Hardware: 1. open a shoot with a burst; 2. → into it; 3. watch the first frame stay put and the rest fade in below. |
| K2 | Mixed Sony + iPhone shoot: "bodies" note names both. Phone rows split on 1× ↔ 3× | None. `edge-two-bodies` (not re-run on v7) is two Sony bodies, order only. | **automatable** (top-ten 7): forge ARWs + iPhone DNGs at 1× and 3×; openFolder; expect a note matching both names and a row break at the lens change. |
| K3 | Big view Measured column: edge detail, shutter vs focal (phone 35 mm eq.), highlights recoverable / all channels, focus point vs sharpest | `lumina-measure.js` is only byte-checked (`SetsPageBytesTests.testBundledPageMatchesTheDesign`). No behaviour check. | **hardware only**: 1. open a real α7 shoot and an iPhone shoot; 2. Space on a sharp, a soft, a blown and a long-shutter frame; 3. check each Measured line against the photo (phone shutter warning uses the 35 mm focal). An automatable half: a synthetic preview with known clipped channels → expect "recoverable" vs "all channels". |
| K4 | Hold F/E/M/B overlays. Z 100%. Pinch zoom on trackpad | `screens-*` (v5 steps) step 19 `hold z` → snap "07-zoom-100"; `webkit.py` flow 'menu: Zoom 100% toggles on/off'; `app-plumbing-contract` step 7 (`luminaGesture` exists). | **partly**: Z covered; no check holds F/E/M/B (the screens' step 15 `f` is a v5 flag press that now taps the F overlay). Pinch is hardware: 1. big view; 2. pinch out and in on the trackpad; 3. zoom follows, release returns. |
| K5 | Window widths 900, 1280, 1440, 1920, 2560, full screen: tiles resize until set in Settings; big view columns hide < 980 px; nothing clips | `screens-1440`, `screens-1920` (+ `-app`, v5 steps), `scroll-fast` (1440 × 900), `scroll-fast-2560` (sets `tsz` by `setState`), `smoke` (924 × 540), `edge-*` (1280 × 800). | **partly**: no 900 or full-screen run, no check of the < 980 px column rule or of auto tile size. Automatable: `screens-900`, `-1280`, `-2560` (+ app twins), each with an expect on the big view's column count and a snap per screen. |

## Phone upload page (v0.0.1)

| # | Row | Covered by | Status |
|---|---|---|---|
| U1 | Open → Add from phone opens Phone photos and does not jump into Pick | None. | **automatable** (top-ten 8): click "Add from phone"; expect `state.phonePage === true` and `state.view === 'import'`; snap. |
| U2 | iPhone AirDrop with All Photos Data → Downloads → drop on page → RAW tags with phone and lens | None. | **hardware only**: 1. iPhone ProRAW: Share → Options → All Photos Data → AirDrop to the Mac; 2. drop the files from Downloads on the Phone photos page; 3. each tile tagged RAW, "iPhone 15 Pro", lens. (Drop is unwired natively: see O2.) |
| U3 | AirDrop without All Photos Data → HEIC tile, dimmed, "not added" | None. | **automatable**: the labelling, via a synthetic `DataTransfer` drop (top-ten 8). The AirDrop itself is hardware: 1. AirDrop without All Photos Data; 2. drop; 3. HEIC tile dimmed, "not added". |
| U4 | Photos app Export Unmodified Original → drop the folder → RAWs only | None. | **hardware only**: 1. Photos → File → Export → Export Unmodified Original → Downloads; 2. drop the folder; 3. only the DNGs added, HEIC/JPG dimmed. |
| U5 | Android over cable + OpenMTP → DNGs → drop → RAW tags | None. | **hardware only**: 1. Pixel in File transfer mode; 2. OpenMTP → DCIM/Camera → copy DNGs; 3. drop → RAW tags with "Pixel 8 Pro". |
| U6 | Watch Downloads (Comet/Chrome): AirDrop while the page is open → tiles within about 2 s | `SetsDownloadsWatcherTests.testGrowingDNGReportsAfterOneStableSecondAndOnlyOnce`, `testDownloadSiblingHoldsStableRAWUntilSiblingGoes`, `testDriverWaitsForStableFileAndStopsImmediately`. `SetsDownloadsWatcher` is referenced by no other app file. | **partly**: the native watcher is unit-tested but not wired; the row as written is the browser page. Hardware: 1. page open in Chrome, Watch on; 2. AirDrop a ProRAW; 3. time to tile ≤ ~2 s. |
| U7 | New shoot → Pick with the name field focused. From inside a shoot: Add to <shoot> keeps its decisions. Back returns with nothing added | `app-smoke` step 6 (`document.activeElement` is `INPUT` after a first open; the folder path, not the phone page). | **partly**: the phone page's three exits are unchecked (top-ten 8). |
| U8 | Firefox/Safari: Watch is hidden, drop / Choose files still work | None (the harness launches Chromium only). | **automatable**: `lib.open` with Playwright's Firefox and WebKit on the prototype (no plumbing); expect no Watch control; set files on the Choose files input → tiles. |

## Phone go/no-go (file check)

All need real phones and `Phone Handoff Check.dc.html` in Chrome; the report is saved as `fixtures/phone-<device>.json`.

| # | Row | Covered by | Status |
|---|---|---|---|
| G1 | iPhone 15/16 Pro ProRAW by AirDrop | None. | **hardware only**: 1. shoot ProRAW incl. a portrait; 2. AirDrop with All Photos Data; 3. drop the folder on the check page; 4. Copy report → `fixtures/phone-iphone-airdrop.json`; 5. read the four go criteria. |
| G2 | iPhone, Photos → Export Unmodified Original | None. | **hardware only**: as G1, step 2 = Photos → Export Unmodified Original. |
| G3 | iPhone with Optimise Storage on (0-byte placeholders caught) | None. | **hardware only**: 1. turn Optimise Storage on, let originals offload; 2. export; 3. drop; 4. the 0-byte files are flagged, not read as photos. |
| G4 | Pixel RAW (USB file mode → DCIM) | None. | **hardware only**: 1. USB file mode; 2. copy DCIM DNGs (OpenMTP); 3. drop; 4. report. |
| G5 | Samsung Expert RAW | None. | **hardware only**: as G4 with Expert RAW files. |
| G6 | One Leica or DJI DNG (must read as camera, not phone) | None (no `phoneOf` test: A2). | **hardware only** for the real file (drop, "Read as phone" 0); the Make/Model half is automatable inside A2. |
| G7 | (not a checkbox) Cable import spike, ImageCaptureCore | No ImageCaptureCore code in `Lumina/` (grep `ImageCaptureCore`, `ICDevice`); deferred to v0.1 (ROADMAP, v0.0.1). | **hardware only**, not started: a 1-day spike: list the device, count RAW/HEIC/iCloud-only, download 50 DNGs hash-verified, nothing deleted. |

## Sources

| # | Row | Covered by | Status |
|---|---|---|---|
| S1 | ⌘O, the +, holding ⇧ and drag-drop in Pick add to the open shoot. Name kept. Decisions kept | `SetsSourcesTests.testAddsTwoFoldersInOrder`, `testCodableRoundTripPreservesOrderedSources`. `SetsSources` is referenced by no other app file; `plumbing.js` resets `logic._sources = []` on open. | **partly**: native model only, unwired. Once wired, automatable: open A, pick 1; ⌘O inside the shoot on B → expect both sources, name and the pick kept. |
| S2 | Re-adding the same folder → "nothing new". A copy elsewhere → "N already here, skipped" | `SetsSourcesTests.testAddingSameFolderAndSymlinkReturnsExistingSource` (same folder and a symlink return the existing source). | **partly**: no page check of either message (top-ten 10). |
| S3 | Second body with a wrong clock → merge preview with the offset. Shift lines up the rows. Keep leaves them | `edge-tz-jump` (not re-run on v7) step 6 expects `shiftTime` or "shift" text; `edge-two-bodies` step 5 (order). Both recorded as **gap** in EDGE-CASES (C1, C2). | **partly**: no check of the merge preview, the offset or Shift/Keep. Automatable: forge a second body 1 h off with ≥ 3 look-alike frames; add it; expect the preview's offset; Shift → rows interleave; Keep → unchanged. |
| S4 | "Show only" per source dims the others. A source that disappears shows "Reconnect" | `SetsSourcesTests.testDeletedFolderIsMissing`, `testBookmarkFailureIsMissingWithoutReadingStoredPath`, `testReconnectRenewsStaleBookmarkWithoutChangingIdentity` (unwired, as S1). | **partly**: no page check of "show only" or "Reconnect". |
| S5 | Phone by cable: counts, iCloud-only count, import new, nothing deleted on the phone | None; cable import deferred to v0.1 (ROADMAP v0.0.1, README To do 2). | **hardware only**, not built: 1. connect an iPhone; 2. Sources → Phone shows counts and iCloud-only; 3. import new; 4. the phone's library count is unchanged. |
| S6 | Watched Downloads: new files wait under Pending until pulled in | `SetsDownloadsWatcherTests.testBaselineIsSilent`, `testGrowingDNGReportsAfterOneStableSecondAndOnlyOnce`, `testZeroByteFileIsNeverReported` (unwired). | **partly**: the Pending row and the pull are unchecked. |
| S7 | A photo seen in an earlier shoot brings back its decision; the note names that shoot | `plumbing.js` persists `lumina-v4-seen` through `storeSet` (its `STORED` list); `SetsPageStoreTests.testAllowedKeysRoundTripAcrossStores` round-trips other allowed keys (`lumina-v4-toured`, `lumina-v4-names`), not `-seen`. | **automatable** (top-ten 10): open A, pick 2, close; open a copy in B → expect both picks back and a note naming A. |
| S8 | New shoot: name field focused with a suggestion. ⏎ keeps it. Name in the top bar, on Recent, on Save | `app-smoke` step 6 (focus is an `INPUT`), step 7 blurs it; harness comment at line 22 (the checks leave the field); `SetsPageStoreTests` stores `lumina-v4-names`. | **partly**: suggestion text, ⏎, and the name on Recent and Save are not asserted. Automatable: after open, expect the input's value = folder name; ⏎; expect it in `recents()[0]` and on Save's text. |

## Edit

| # | Row | Covered by | Status |
|---|---|---|---|
| E1 | Phone portrait DNGs keep their shape in the loupe, crop and variations | Harness 'edit v21: the canvas lies on the photo's box (the photo's shape, fitted into the page's canvas element)' (`la.w / la.h` vs the photo's `ar`) and the crop check; `LookPipelineTests.testBasesBuildUprightTexturesAndCacheByKey`, `testCropAndStraighten`. All on ARW or synthetic images. | **partly**: no portrait DNG. Automatable: in `app-dng-picks`, enter Edit on a portrait DNG; expect the canvas aspect = the photo's; crop 1:1 → box square. |
| E2 | Sliders, variations follow the slider, ⇧T tone-mapper compare, edited picks bright and unedited dim | Harness 'edit v21: a single change reaches the canvas once, as a keystroke', 'a slider drag is a drag on the canvas …', 'before (\ held) is the as-shot render …'; `edit-canvas` (not re-run on v7) steps 6–8 (`editDrag` ev and sh, `editParity`); `LookMathTests.testMapperRollsOffSmoothlyOnAGreyRamp` and the other mapper tests. | **partly**: variations, ⇧T and the bright/dim filmstrip are unchecked. ⇧T and dimming are automatable (key, then expect state + snap); judging the look is hardware. |
| E3 | Working-files squares visible bottom right | `webkit.py` flow 'save: working-files row size known on Save'; `app-plumbing-contract` step 4 (`workingFiles`, `removeWorkingFiles` exist). | **partly**: the squares in Edit are unchecked. Automatable: in Edit, expect the working-files element in the bottom-right quadrant; snap. |

## Save

| # | Row | Covered by | Status |
|---|---|---|---|
| V1 | ARW picks → .xmp with the chosen rating. Existing sidecar → rating merged, Lightroom edits kept, `.lumina-bak` | `app-smoke` steps 24–31 (armed, then "2 saved", 2 `.xmp`, no temp) and 43–53 (Lightroom-edited sidecars → 2 `.xmp.lumina-bak`, backup is Lightroom's). Harness 'save: sidecar rated 3★', 'save: .lumina-bak keeps the old sidecar', the 'stale sidecar: …' checks. `SetsSidecarTests.testWritesNextToTheRaw`, `testExistingSidecarKeptAsLuminaBak`, `testSidecarChangedSinceItsBaseIsLeftAlone`. `app-xmp-lightroom` (v5 steps) for real Lightroom 9.3.1 files. | **covered** (rating 3, the default); a non-default rating is not saved by any check. The real-Lightroom scenario needs top-ten 1. |
| V2 | DNG picks → copied to Picks/, checksum verified, originals untouched | `SetsPicksCopyTests.testDNGPicksAndSidecarsLandVerifiedWithoutChangingSources` (SHA-256 and mtime before/after, no temp files, second run makes no `-2`), `testMissingSourceIsReportedAndOtherItemsStillLand`, `testNamesOutsideOneSubfolderAreRefused`. The page → `writeInto` `copy` path (`plumbing.js` lines 504–519) has no check. | **partly**: native job covered, page path not (top-ten 2). |
| V3 | Lightroom Classic: import or Read Metadata shows ratings. Capture One: import shows ratings | `app-xmp-lightroom` (v5 steps) step 23 `xmpMerged` (exiftool reads the stars, per EDGE-CASES F6). | **hardware only**: 1. Save picks; 2. Lightroom Classic → Import → Add (or Metadata → Read Metadata from Files); 3. stars match; 4. Capture One → Import → stars match. |
| V4 | Show in Finder (button and ⌘R) opens Finder at the right file or folder | Harness 'save: ⌘R reveals', 'awkward names: reveal sends the path unchanged'; `webkit.py` flow 'save: ⌘R reveals'; `SetsBridgeOpsTests.testRevealOnlyInsideOpenedFoldersAndTheLastExport`. | **partly**: the call is checked, Finder is not. Hardware: 1. click the Show in Finder button on Save; 2. Finder opens with the shoot folder selected; 3. ⌘R on a big-view photo selects its file. |
| V5 | Tidy up: sizes are real. Remove clears them. "This card's picks" is locked until saved | `webkit.py` flow 'save: working-files row size known on Save'; `SetsWorkingFilesTests.testRemoveAllKeepingSessionLeavesExactlySessionAndReportsFreedBytes`, `testProtectedPickAndSessionNeverEnterPlanAndCapCanRemainUnmet` (`SetsWorkingFiles` is referenced by no other app file); `SetsShootStoreTests.testRemoveCannotTakeTheStoreOrItsParent`. | **partly**: Remove from the page and the locked state are unchecked. Automatable: open, wait for `ex.wf > 0`, Remove → `wf === 0`, session file still there; with unsaved picks the card segment refuses. |

## Trust and release

| # | Row | Covered by | Status |
|---|---|---|---|
| T1 | Zero network requests in a full session | The app's content rule blocks `^https?://` (`SetsBridge.swift:810`; no XCTest asserts it). `webkit.py` compiles the same kind of rule (`offline_filter`), blocking rather than counting. `SetsExternalLinksTests.testOtherSchemesAreRefused`, `testScriptInitiatedExternalLinksAreRefused`, `testWebRefusals`. `release_preflight.sh` entitlement check (`network.client` is WARN D2). | **partly**: nothing counts requests in a session (top-ten 5). Hardware: Little Snitch (or a proxy) on, one full session: open, pick, Edit, Save, Beta, FAQ, tour; zero connections from Lumina and its WebContent process. |
| T2 | Card is read-only throughout: no files created on the volume, including .DS_Store from the app | `card-sandbox-first` (not re-run on v7) steps 18–20 (`*.xmp` 0, `*lumina-*` 0, `*.ARW` 12); `fuzz-app-card` steps 16–18; `fault-readonly-card` (v5 steps) steps 20–21; `fault-card-pull-cull` (v5 steps) step 27 (`*` = 0, but only on the empty mount point with the card out) and 44–46; `SetsTrustTests.testReadingChangesNothing`. | **partly**: every glob is for Lumina's own names; no step lists all files on a mounted card (top-ten 4). |
| T3 | Tour on first launch only. Reopens from ?. Esc skips | `SetsPageStoreTests.testAllowedKeysRoundTripAcrossStores` (`lumina-v4-toured` persists). | **automatable** (top-ten 9). |
| T4 | Beta chip → known issues + bug link | `SetsExternalLinksTests.testTheThreePageDestinationsAreAllowedAndCanonicalized`, `testMailIsRebuiltFromParsedParts`, `testMailRefusals`. | **partly**: the chip, the issues list and the click → hand-off are unchecked (top-ten 9). |
| T5 | `lumina.debug` false: no debug links | `plumbing.js:206` sets `debug: !!cfg.debug`; harness and `webkit.py` configure `debug: false`. No check looks for debug links. | **automatable** (top-ten 9): with `debug:false` expect no element the page's `dbg()` gates; with `?debug` expect them. |
| T6 | Quit with unsaved picks → confirm | Harness 'quit: unsaved keepers counted', 'quit: nothing unsaved after Save'; `webkit.py` flow 'quit: 2 unsaved keepers'; `app-session` (v5 steps) step 26; `SetsPageRecoveryTests.testQuitWaitsTwoSeconds`, `testAnswerFirstThenTimeoutRepliesOnceWithTheAnswer`, `testPageThatNeverAnswersRepliesOnceOnTimeout`. | **partly**: the count and the 2 s timeout are covered; the alert is manual. Hardware: 1. pick 2; 2. ⌘Q; 3. alert names 2 unsaved picks; 4. Cancel stays, Quit quits. |
| T7 | Signed + notarized build | `release_preflight.sh`: "signature verifies (deep, strict)"; with `--notarised` "notarisation ticket stapled" and "Gatekeeper accepts it". | **partly**: the checks exist; notarising needs the Developer ID account. Hardware: 1. `bash Scripts/release.sh dmg` with credentials; 2. `release_preflight.sh <app> dmg --notarised`; 3. open the DMG on a second Mac, no Gatekeeper warning. |

## Beta trust rules (ROADMAP.md 1–17)

| # | Rule | Covered by | Status |
|---|---|---|---|
| R1 | Never write to the card | T2's citations, plus `app-xmp-both` (v5 steps) step 19 ("DSC08186 · on the card"), `fault-disk-full` step 3 (the native write refuses a disk image), `fault-native-dest` step 2 ("isn't on the card"), `SetsFileOpsTests.testDestinationInsideSourceIsRefused`. | **partly**: Lumina's own writes are refused; "nothing at all appears on the card" is unchecked (top-ten 4); several card scenarios need top-ten 1. |
| R2 | Never change originals | `SetsTrustTests.testReadingChangesNothing` (mtime, size after head + preview), `SetsPicksCopyTests` (source SHA-256 + mtime), `SetsBridgeOpsTests.testWriteSidecarsHostileNames` (no new file but `.xmp` / backup); harness 'session: look saved per photo by path' (looks live in the session, not XMP); scenario byte checks in `app-xmp-lightroom` 28–30, `hostile-names` 38–39, `app-rename-mid-cull` 32 (all v5 steps). | **covered** by the XCTests and harness; the scenario half needs top-ten 1. |
| R3 | Copy, never move. Checksum-verify every copy | `SetsFileOpsTests.testCopyNeverOverwritesADifferentFile`, `testNoTempFilesLeftBehind`; `SetsTrustTests.testACopyThatFailsLeavesNothingBehind`; `SetsPicksCopyTests.testDNGPicksAndSidecarsLandVerifiedWithoutChangingSources`; `fault-native-dest` step 7 (hash-equal after disk full), `fault-kill-mid-handoff` step 0 (24 seeded kills). | **covered**. |
| R4 | "Safe to format in camera" only after every file is copied + verified | v7 contains no "safe to format" text (grep of `Lumina Sets v7.dc.html`, `lumina-v4-data.js`): v0.01 never copies from a card. | **automatable**: a page-text check (scenario or `design_audit.py` rule) that the phrase stays absent until a copy flow exists. |
| R5 | One visible library folder (~/Pictures/Lumina) + "Show in Finder" | Show in Finder: V4. No `~/Pictures/Lumina` in `Lumina/` (grep): v0.01 writes sidecars into the shoot folder and DNG copies to `<dest>/Picks/` (README "New in v0.01"). | **partly**: the library-folder half conflicts with the README; a human should rule which holds. |
| R6 | No delete in beta: "out" only hides | `SetsShootStoreTests.testRemoveCannotTakeTheStoreOrItsParent`, `testRemoveWithATraversalLeavesTheSiblingFolder`; `SetsWorkingFilesTests.testRemoveAllRefusesDangerousFilesAndOutsideLinksWithoutDeletingAnything`; `SetsBridgeOpsTests.testWriteIntoHostileFiles`. | **partly**: no check removes a photo (R or X) and then finds its file. Automatable: open, X on two photos, Save; expect every ARW still byte-identical and present. |
| R7 | Nothing leaves the Mac; said on first launch | T1's citations. The tour's first step says "nothing leaves your Mac, no account" (page source). | **partly**: as T1; the tour line is unchecked (top-ten 9). |
| R8 | Crash reports opt-in, no image content or file names | No crash reporter in `Lumina/` (grep); `Config/Release.xcconfig:37` only keeps symbols out of the app. | **hardware only**: 1. confirm no third-party reporter in the bundle (`otool -L`); 2. force a crash in a Debug build; 3. check only macOS's own "Share with app developers" setting governs the report. |
| R9 | No account | No account code; tour copy says "no account". | **hardware only**: one full session, no sign-in prompt anywhere. |
| R10 | Access only to the card/folder the user picks; never Full Disk Access | `SetsAccessTests.testUnresolvableBookmarkReturnsNilWithNoFallback`, `testFolderGoneReturnsNilAndStopsWhatItStarted`; `SetsCardAccessTests.testPickOnAnotherVolumeIsRefusedAndAskedAgain`; `SetsIngestTests.testPathsOutsideAnOpenedFolderAreRefused`; `SetsIngestLinksTests.testALinkedFolderPointingOutsideIsRefused`; `SetsBridgeOpsTests.testReadSidecarsStaysInside`; `card-sandbox-first/-again` (not re-run on v7); `release_preflight.sh` entitlements. | **covered**. |
| R11 | Export keeps as a folder or XMP ratings | XMP: V1 (`app-smoke`, v7). Folder: `SetsPicksCopyTests` (V2). | **partly**: the DNG Picks folder through the page is unchecked (top-ten 2). |
| R12 | Uninstall leaves every photo in place | Shoot records live in the app's support folder, not beside the RAWs (`SetsShootStoreTests`); `app-session` step 49 (no file added by a reopen; v5 steps). | **hardware only**: 1. save a shoot; 2. delete Lumina.app and its container; 3. every RAW and `.xmp` still in the shoot folder, byte-identical. |
| R13 | Clearly labelled beta + known-issues list | As T4. | **partly** (top-ten 9). |
| R14 | Stated scope: Sony ARW (+ phone DNG), Apple silicon, macOS version | `Component.ISSUES` and the FAQ text (`lumina-v4-data.js`) are byte-checked only (`SetsPageBytesTests`). | **hardware only**: read the Beta panel, FAQ and Open disclaimer; each names ARW + DNG, Apple silicon, macOS 14+. |
| R15 | Tell testers: keep your own backup, don't format until checked | None. | **hardware only**: check the tester invite and FAQ say it. |
| R16 | Signed + notarized, never unsigned | As T7. | **partly**. |
| R17 | One bug-report channel + public changelog | Bug channel: `SetsExternalLinksTests` (the mailto). No changelog file in the repo (`find -iname 'CHANGELOG*'`; `docs/` has RELEASE.md and release/ only). | **partly**: the changelog does not exist yet. |
