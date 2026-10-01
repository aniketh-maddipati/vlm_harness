# AGENTS.md

Guidance for AI agents and developers working on **Lumina**, a native macOS photo culling app for
Sony ARW shooters.

## The rule

**The design is the product.** Lumina's UI is the Claude Design page in `design/handoff/lumina-cull/`
(`Lumina Sets v5.dc.html` + `support.js` + `lumina-core-v4.js` + `lumina-v4-data.js` + `lumina-selftest.js`;
the names live in `Scripts/page_files.sh`). The app ships those files **byte for byte** inside a native
window. Nobody edits the UI in this repo.

- Something visible is wrong or missing (layout, copy, keys, empty states)? It goes into
  `design/handoff/DESIGN-ASKS.md` as a ready-to-paste Claude Design prompt. It never gets patched here.
- A new handoff arrives as a zip. Sync it with `bash Scripts/sets_sync_design.sh "<zip>"`. That runs the
  fixtures, audits the wording and demo layer, installs the files, checks the plumbing contract,
  compares every screen pixel for pixel, and runs the robustness suites. It never commits. Add
  `--record` once the new look is approved.
- Authority order: `design/handoff/lumina-cull` (its `PROMPT.md` sets the order inside it: ADDENDUM-1 →
  PARITY → GRAMMAR → the page → CHANGES / SAFETY / MENUS) → `Lumina/Sets` (plumbing) → tests.
  The handoff's own `plumbing.js` is an older reference; the app's is `Lumina/Sets/Web/plumbing.js`.

## The native rebuild (in progress, behind a switch)

A second handoff, `design/handoff/lumina-app/` (README, LAYOUT_SIZING, KEYMAP, BEHAVIOR_SPEC,
ACCESSIBILITY_CONTRACT, WORKSTREAMS, TEST_PLAN, the prototypes, and `parity/`: tokens.json, recorded
traces, the demo shoot, the golden capture script), asks for the UI to be **rebuilt natively** in
SwiftUI. That work lives in `LuminaKit/` (a local Swift package: `LuminaCore` + `LuminaUI`) and
`Lumina/Native/`, and it is the one place UI is written in this repo. `LuminaKit/README.md` has the
file ownership per work package, the contract, and the headless checks (`swift test`,
`swift run lumina-snap`). For that code the authority is `design/handoff/lumina-app`, and its
prototypes are a reference, not shipped files.

Until the native UI passes its gates (TEST_PLAN.md), the app's default is still the Claude Design
page below, and every rule in this file still holds for `design/handoff/lumina-cull`, `Lumina/Sets`
and the probe. The native UI shows only with `-LuminaUITest YES`, `-LuminaNative YES` or
`LUMINA_NATIVE=1`. The design's XCUITests are in `LuminaUITests/Native`; they take over the screen,
so run them one at a time and never from parallel agents.

**The native Save writes edits to XMP** (ruled 2026-10-01, the handoff's README §4): a sidecar carries
the keepers' 3★ and the edit as Lightroom develop settings (`LuminaCore/Export/XMPSidecar.swift`),
merged into an existing sidecar, never clobbering it. "Looks are never written to XMP" under Parity
below describes the Sets page's handoff only. The trust rules are unchanged: sidecars only, into the
shoot folder, `.lumina-bak` first, atomic, read back, refused on a card.

```bash
(cd LuminaKit && swift build && swift test)          # contracts, rules, parity traces, headless
python3 Scripts/gen_tokens.py --check                # Tokens.generated.swift matches parity/tokens.json
```

## What the app is

| Path | What it does |
|---|---|
| `Lumina/LuminaApp.swift` | One window and the menu bar from MENUS.md: every item calls `window.luminaCommand(name)`; Quit asks about unsaved keepers |
| `Lumina/Sets/SetsRootView.swift` | The WKWebView, the native folder pickers, downloads, and the Edit canvas overlay laid above the web view |
| `Lumina/Sets/Web/` | The design's files, copied unchanged by `Scripts/sets_sync_ui.sh`, plus `plumbing.js` |
| `Lumina/Sets/Web/plumbing.js` | **The only app-side difference.** It swaps the page's browser I/O (`openFolder` + `onDir`/`readOne`, `writeInto`, `impStart`, `libOpen`) for native calls, provides `window.lumina` (the data contract: `card`, `readingCard`, `reveal`, `setPrefs`, `openSettings`, `checkAccess`, …, and the Edit step's `preview` / `canvasRect` / `drag` / `roi` from DESIGN-ASKS Prompt 1 §3, plus `edit`, the superset the probe drives), persists sessions (writes debounce 500 ms after the last Edit change), makes the grid thumbnails (720 × 480; measures stay on the page's 360 px bitmap) and decodes them ahead of a scroll (design ask 7), keeps the reader's place and decisions when a read they culled during ends (design ask 8), and drives the page's hooks (`luminaCardGone`, `luminaAccess`, `luminaCommand`, `luminaPresented`, `luminaHistogram`, `luminaFacts`, `luminaEditStats`) |
| `Lumina/Sets/Core/` | The native bridge: `SetsIngest` (reads opened folders: listing, 256 KB heads, byte-range previews that reuse the part the head already holds, prefetch, stops when the card goes), `SetsFileOps` (`writeSidecar`: v5's Save, one `.xmp` into the shoot folder with `.lumina-bak`, atomic, read back, refused on a card; SHA-256 copies), `SetsExport` (+ crash journal; RAW copies, v3's CSS-look JPEGs, and the Edit step's `look` renders through `SetsLookExport`, which names the RAW decoder used and falls back per file), `SetsEditLook` (v3's Edit look, unused by v5), `SetsCardWatcher`, `SetsShootStore` (per-shoot sessions and the `Lumina.json` header), `SetsSchemeHandler` (`lumina://`, no network; `lumina://render/<rel>?look=&px=&seq=[&tier=small]` is the Edit preview on the image fallback path), `SetsBridge` (the page's ops, the canvas ops `canvasEnter/Layout/Look/Drag/Loupe/Stats`, the decoder map) |
| `Lumina/Sets/Look/` | The Edit look pipeline (roadmap Prompt 2): `LookString` (the look string, the Edit step's only state), `LookRules` + `rules-v1.json` (stage order, working space, fitted coefficients, `locked` flags), `LookMath` (every stage's maths in scalar form), `LookKernels` (the same maths as Metal, compiled at first use), `LookPipeline` (the one Core Image graph previews, export and `lumina-render` share; `develop` takes the decoder version and `nr`), `LookRenderer` (developed RAW cached per (rel, px, decoder) under a byte cap, sequence numbers drop stale requests). The Edit canvas (addendum): `LookCanvasSchedule` (two tiers, latest wins, sequence numbers; Foundation only), `LookWarmPlan` (which stage graphs to compile ahead of a drag; Foundation only), `LookByteCache` (byte-capped LRU), `LookBases` (`base` + `small` rgba16Float textures per photo, prefetch), `LookRegionTiles` (RAW 9 512 px tiles for the loupe), `LookCanvas` (the MTKView overlay, CIRenderDestination, display link), `LookRawPolicy` + `LookDecoderProbe` (the RAW tiers, the pin rule, the capability map). Also compiled into the probe and `Tools/parity/lumina-render` through symlinks |
| `Tools/parity/` | The Lightroom parity harness: the sweep plug-in, `import_refs.py`, `lumina-render`, `delta_e.py`, `parity.py` (`make parity`), `fit.py`, `loop.sh`, `criteria.json`, `golden.json`. See its README and "Parity" below |
| `Tools/culleval/` | The culling eval: the page's own `lumina-core` run on real shoots, scored against camera bursts and the photographer's keeps (`make culleval`, report in `~/LuminaEvidence/culleval`; `make culleval-test` on Linux), the same keeps question through the app (`culleval-app.mjs` on a probe dump, one matcher and one set of scores for both), and candidate ranking signals (`signals/`). Measures only. See its README |
| `design/handoff/vendor/` | React / Babel pinned to the SRI hashes in `support.js` (see `VENDOR.md`) |

**The Edit canvas is the one place native draws pixels over the page.** `LookCanvasView` (an
MTKView, `Lumina/Sets/Look/LookCanvas.swift`) sits above the web view exactly on the rect the
page reports for its Edit canvas; the look stages render straight into its drawable, so a slider
move never goes through a JPEG, a readback or the web view's image decode. It is pixels only: it
takes no input, draws nothing of its own (no chrome, no text), and is hidden whenever Edit isn't
the active step. The page keeps drawing the filmstrip, sliders and facts. Without a Metal device
the same schedule runs on `lumina://render` images the page shows itself (`canvas: image` in the
facts line). Everything else the app shows is the page's.

Trust rules, from the ROADMAP; the tests enforce them:
- never write to the card or change originals (v5 writes only `.xmp` sidecars, into the shoot folder);
- copy, never move, and verify every copy;
- keep a `.lumina-bak` before replacing any file;
- nothing leaves the Mac, and the page has no network access.

## Checks

```bash
# Design logic fixtures
(cd design/handoff/lumina-cull && node lumina-core-v4.test.mjs)

# Linux too: the real page in headless Chromium with plumbing.js and a Node stand-in for SetsBridge
node Tests/web/plumbing-harness.mjs          # contract, native read, sessions, sidecars, card, access
node Tests/web/parity.mjs                    # screens-* in prototype vs app parity mode, every snapshot diffed
# WebKit sandbox (WebKitGTK + JavaScriptCore, real script-message handler): contract, selftest, app flow, screens
xvfb-run -a -s "-screen 0 2000x1300x24" /usr/bin/python3.12 Tests/web/webkit.py   # apt: gir1.2-webkit2-4.1 python3-gi python3-gi-cairo xvfb
# Fast scrolling over 400 synthetic ARWs at a Retina pixel ratio (numbers reported, not gated)
GDK_SCALE=2 xvfb-run -a -s "-screen 0 5200x3000x24" /usr/bin/python3.12 Tests/web/webkit.py scroll
# The Foundation-only Swift (SetsFileOps, SetsShootStore, SetsExport, SetsIngest, LookString/LookRules/LookMath) + its tests, Swift 6.1 in Docker
bash Tests/linux-swift/run.sh
# The parity tools' own tests (ΔE2000, the numpy mirror of LookMath, refs indexing, the report), Linux too
make parity-test
# The culling eval's scoring tests (synthetic data) + the guard on the page's readOne, Linux too
make culleval-test

# Build + logic tests (SetsFileOpsTests, SetsSidecarTests, SetsPageBytesTests, LookStringTests, LookMathTests,
# LookPipelineTests: every stage monotonic + grey-preserving on synthetic ramps, the Metal graph equal to LookMath,
# the bases upright on GPU textures; LookCanvasTests: the canvas schedule, byte cache, RAW tiers; SetsLookExportTests)
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug -derivedDataPath DD \
  -destination 'platform=macOS,arch=arm64' -only-testing:LuminaLogicTests test

# Lightroom parity (Tools/parity/README.md): renders + ΔE report, the three copies of the stage maths agree
make parity                # needs refs.json from the Lightroom sweep and the golden ARWs in ~/LuminaEvidence/parity
make parity-check          # lumina-render ramp → lookmath.py --check (Metal ≡ Swift ≡ numpy on flat patches)

# Culling eval (Tools/culleval/README.md): grouping + auto keeps vs real bursts and real keeps, numbers only
make culleval              # needs ~/LuminaEvidence/culleval/shoots.json, exiftool, Playwright's Chromium

# Probe: drives the real page + bridge in WKWebView (Tools/LuminaProbe). Evidence → ~/LuminaEvidence/probe
bash Scripts/probe.sh reference     # every screen, prototype and app, byte-compared to Tests/probe/reference/manifest.json
bash Scripts/probe.sh screens       # every screen rendered once, the app twins equal to the prototype (what CI runs)
bash Scripts/probe.sh scenarios fuzz-sample-2 scroll-read   # just these scenarios
bash Scripts/probe.sh contract      # plumbing.js still fits the page
bash Scripts/probe.sh smoke         # page runs, ?selftest passes, app reads / keeps / saves sidecars / reopens, the empty app
bash Scripts/probe.sh selftest      # the design's own ?selftest (25 checks + timing)
bash Scripts/probe.sh fuzz          # seeded key + mouse storms (with LUMINA_FIXTURE_ROOT: also over a card image pulled at random)
LUMINA_FIXTURE_ROOT=~/LuminaEvidence/fixtures bash Scripts/probe.sh scroll  # fast Cull scrolling: frames, blank tiles, thumbnail upscale, memory
LUMINA_FIXTURE_ROOT=~/LuminaEvidence/fixtures bash Scripts/probe.sh app     # contract + the app on folders: sidecars, .lumina-bak, Lightroom's sidecars merged, sessions across a relaunch, keepers renamed mid-cull, the empty app
LUMINA_FIXTURE_ROOT=~/LuminaEvidence/fixtures bash Scripts/probe.sh fault   # disk images: kill -9 mid-write, disk full mid-copy and for a sidecar, read-only card, card pulled mid-read and on Save, .xmp + .XMP on a case-sensitive disk
LUMINA_READ_DIR=~/Pictures/shoot-3000 bash Scripts/probe.sh slowdisk        # a disk whose first directory read takes 12 s (LUMINA_SLOW_DIR_MS): the app still answers the page while the folder is listed
LUMINA_FIXTURE_ROOT=~/LuminaEvidence/fixtures bash Scripts/probe.sh edge    # camera-data cases (design gaps show as FAIL)
LUMINA_FIXTURE_ROOT=~/LuminaEvidence/fixtures bash Scripts/probe.sh ingest  # the same cases through the native reader
LUMINA_CARD_DIR=/Volumes/…/DCIM/101MSDCF bash Scripts/probe.sh card         # golden card + page vs native read
LUMINA_CARD_DIR=/Volumes/…/DCIM/101MSDCF bash Scripts/probe.sh stress       # a whole card: scroll frame budget, 3,000-input storm, memory; page read, then native read
LUMINA_EDIT_DIR=~/Pictures/shoot-3000 bash Scripts/probe.sh edit           # Edit canvas: 2 s drags, latency p95 ≤ 16 ms (LUMINA_EDIT_P95), 0 dropped, rest ≤ 120 ms, ≤ 3 photos / 300 MB, canvas vs export ΔE; then with nothing compiled (edit-cold); then the image path
LUMINA_EDIT_DIR=~/Pictures/shoot-3000 bash Scripts/probe.sh edit-cold      # the first launch after a kernel change (LUMINA_KERNEL_SALT, new per run): first drags on stages the canvas has not rendered, gated like edit + first render of a new set of stages ≤ 8 ms on the main thread; LUMINA_CANVAS_WARM=0 = no warm-up (fails, the "before" measure)
LUMINA_READ_DIR=~/Pictures/shoot-3000 bash Scripts/probe.sh readspeed       # read speed: Open → first rows, first thumbnail, 100 / 500 / 1000 / 2000 photos, done; photos per second (reported, not gated)
LUMINA_EDIT_DIR=~/Pictures/shoot-3000 bash Scripts/probe.sh raw9           # RAW 9: decoder map, first tile / full region, export time + memory per version, forced fallback, tiles vs export ΔE
LUMINA_EDIT_DIR=~/Pictures/shoot-3000 bash Scripts/probe.sh consistency    # canvas vs full-size export per stage of the look on 12 distinct ARWs: median ΔE ≤ 1.0 for every photo and look (p95 reported); also a canvas one decoder behind the export, and the drag preview
LUMINA_REMOTE=user@m1.local bash Scripts/probe_remote.sh edit               # the same on the M1 8 GB over ssh (p95 ≤ 33 ms), evidence pulled back
```

Day-to-day app: `bash Scripts/install_app.sh` builds this checkout (Release) into `/Applications/Lumina.app`,
the copy the Dock and Spotlight open, and removes older builds from Launch Services.

Build fixtures once with `LUMINA_CARD_DIR=… bash Tests/probe/forge_fixtures.sh`. It only reads the card.
`Tests/probe/EDGE-CASES.md` maps the beta checklist to scenarios and their status.

CI (`.github/workflows/lumina.yml`) runs the fixtures, the byte-for-byte page check, the wording
audit, the Chromium plumbing harness, the WebKitGTK sandbox, the Linux Swift tests, the build + logic tests, and the
probe in four parallel macOS shards (smoke + screens, fuzz, fuzz + scroll, scroll 2560 + edit + raw9).

## Rules that bite

- **Don't edit `Lumina/Sets/Web/*.html|support.js|lumina-core-v4.js|lumina-v4-data.js|lumina-selftest.js|vendor`.** Change the design, then sync. `SetsPageBytesTests` and CI fail on drift.
- **`plumbing.js` supplies behaviour and data, never UI.** If the page can't show something, that's a design ask.
- **The native read repeats the page's `onDir` and `readOne`.** `probe.sh contract` fails (`__lumina.drift()`) when a sync changes either: review the read in `plumbing.js`, then update `ONDIR` (`node Tests/web/plumbing-harness.mjs --hash` prints it). Parity with the page's own read is checked with `card-clock.json` in both modes.
- **Pixel parity is 0 px.** App-mode screens (`screens-*-app`, plumbing's test-only parity mode: the design's sample shoot and card) must match the prototype reference byte for byte. Both twins run with `"storageWrites": false`, because the page's "saved" label is browser-only. CSS tricks that change anti-aliasing are out; content-visibility was tried and rejected.
- **The probe never touches a real card.** Fault tests use disk images, and the probe's card watcher only accepts its own images.
- **A disk image is a card to the app** (`volumeIsRemovable`), with or without DCIM: Save on one is refused "on the card". A scenario that needs the write itself on an image (case-sensitive, full) uses the probe's `nativeSidecar` step with `"guard": false`.
- **The probe refuses the page's `dragstart`.** A synthetic drag over a tile would start a real system drag: a drag image on the user's screen and a session that follows the real pointer.
- **ExFAT volume labels are at most 11 characters.** `hdiutil` reports a longer one as "Operation not permitted".
- **Probe runs need an awake display.** The probe holds the display awake itself. If runs stall for minutes, macOS is throttling the page process.
- **Personal data stays out of the repo:** golden data, fixtures and evidence live in `~/LuminaEvidence`.
- **macOS only** (Xcode 16.4+, Apple silicon, macOS 14+). Linux agents can run the node fixtures, `design_audit.py`, `Tests/web` (Chromium and the WebKitGTK sandbox: plumbing.js against the real page, not Cocoa or WKWebView) and `Tests/linux-swift` (the Foundation-only Swift; on Linux `FileManager.replaceItemAt` is broken, so the sandbox copy uses `rename(2)`).

## Parity (the Edit look vs Lightroom Classic)

The Edit step ships behind the `friends` flag until `Tools/parity/criteria.json` holds on the golden
set (singles: per-slider median ΔE2000 ≤ 2.0, p95 ≤ 4.0; combos ≤ 3.0 / 5.0). The full procedure is
`Tools/parity/README.md`; the rules that bite:

- **The look string is the only Edit state** (`ev:+0.70 wb:5200/+3 con:+12 … crop:x,y,w,h/r`,
  `Lumina/Sets/Look/LookString.swift`). Previews are `lumina://render/<rel>?look=&px=&seq=`, exports
  go through `SetsExport` `.look` items, sessions keep `look` per photo and `rowLook` per row. Looks
  are **never written to XMP**; handoff stays ratings only.
- **One maths, three copies.** A stage's transfer function lives in `LookMath.swift` (reference),
  `LookKernels.swift` (Metal, what renders) and `Tools/parity/lookmath.py` (numpy, what `fit.py`
  optimises). Change all three together; `LookPipelineTests` and `make parity-check` fail otherwise.
  Every stage stays monotonic on a grey ramp and keeps grey grey (white balance excepted); the ramp
  tests enforce it, so a coefficient the fit proposes can't break it silently.
- **Coefficients live in `rules-v1.json`, forms live in code.** `loop.sh` / `fit.py` edit only
  `coefficients` and `locked`. A locked stage is not touched to compensate for another.
- **Two kinds of Lightroom data, two uses.** The *sweep* (one slider from a neutral base) is the
  development set the fit may use. Lightroom Classic's plug-in makes it; Lightroom CC has none, so
  `Tools/parity/lr_cc_sweep.py presets` writes click-to-apply presets and `… ingest <exports>`
  names the JPEG exports from their embedded XMP (`presets --sweep 2` adds ten seeded three-slider
  combos, `--sweep 3` white balance per photo, because Lightroom CC ignores a preset that sets only
  Temperature or only Tint; the ingest also writes `<stem>__asshot.json` and the combos' JSON).
  Someone's *own edits* (`make parity-personal`,
  JPEG exports with "All metadata" + their RAWs) are a held-out acceptance set: measured, never
  fitted (ruled 2026-09-30). Both live in `~/LuminaEvidence`, never in the repo.
- **rawDevelop undoes lens shading with the camera's own numbers** (`LookLensShading`: Sony's
  `VignettingCorrParams`, applied in the decoder's linear space; coefficient `lensShading`).
  Lightroom's lens profile does the same from Adobe's tables; Core Image's decoder leaves it in.
- **rawDevelop ends with the base match** (`LookMath.baseMatch`, kernel `lookBase`): a two-number
  midtone curve on luma and a colour mix whose rows sum to 1 (a grey stays grey), fitted on base
  exports so the untouched render is Lightroom's Adobe Color. Every slider stage sits on this base:
  when it changes, refit the stages, and adopt a stage's refit only if the held-out set agrees
  (a fit that helps the sweep and hurts the held-out set overfitted; that has happened twice).
- **White balance uses the same curve**: per-channel scene gains (Temperature moves red and blue and
  holds green, as Lightroom does; Tint has its own red and blue strengths), each channel through the
  tone curve, so a cast is full strength in the shadows and fades toward white.
- **Highlights and Shadows are relative to the photo.** Tone is a local exposure through the same
  curve, with masks and strengths read from the photo's anchor (`LookMath.ToneAnchor`: log-mean
  luma, spread of log2 luma, share of pixels above L* 80; measured once per file on a 256 px
  develop by `LookPipeline.toneAnchor`, pushed through exposure, and carried by every `Developed`,
  base, tile region and export so the tiers stay identical). On 156 photos Lightroom moves the
  same pixel value by +3 to +58 L* at Shadows +100 depending on the photo; those three numbers
  explain most of it. A synthetic image or flat patch gets `ToneAnchor.reference`.
- **Exposure is a scene gain seen through a sigmoid tone curve** (`LookMath.exposure`: per channel
  G·y / (1 + (G − 1)·y/white), G = 2^(ev · stopsPerUnit)), the form Lightroom's sweep shows:
  shadows and midtones move ~1.6 stops per unit, highlights roll off and lose saturation.
- **Criteria are edited only by a human.** `criteria.json` and `golden.json` never change inside the
  loop. Changing the golden set means a new sweep and every stage unlocked.
- **Add a golden image:** copy the ARW to `~/LuminaEvidence/parity/golden/`, run
  `python3 Tools/parity/golden.py add <arw> --tag <category>`, re-run the Lightroom sweep for it (the
  plug-in skips files that exist), `python3 Tools/parity/import_refs.py ~/LuminaEvidence/parity/refs`.
- **Re-run a stage:** `make parity STAGE=<id>` (report in `Tools/parity/report/<date>-<id>/`, heatmaps
  in `~/LuminaEvidence/parity/report/`); `bash Tools/parity/loop.sh <id>` to fit, verify and lock.
- **Photos stay out of the repo:** references, renders and heatmaps live in `~/LuminaEvidence/parity`;
  only `golden.json` (metadata), `rules-v1.json` and the numbers-only reports are committed.
- **Structure only from RapidRAW / darktable** (AGPL/GPL): ideas, cited in a comment, never code.
- **The Edit canvas schedule is `LookCanvasSchedule`** (Foundation only, tested on Linux): two tiers
  (`small`, a quarter of the canvas on each edge, while a slider is dragged; `base` at full quality on
  drag end, a keystroke, or 120 ms idle), latest wins (one render in flight, the next display refresh
  takes the newest value), and a sequence number per render (presented only if newer than the last
  presented). Histogram and clipping are computed on rest renders only. Session writes debounce at
  500 ms after the last change. Bases are keyed by (rel, decoder version, crop, rotation, canvas size,
  `nr`), pinned for the photo on the canvas, at most 3 photos and 300 MB resident, LRU-evicted.
  Bases, prefetch, region tiles and the rest histogram render on their own CIContext (same Metal
  device), never on the drawable's; the neighbours' prefetch waits until the current photo's base
  is on screen and holds during a drag or a loupe refinement. "Dropped" in `probe.sh edit` counts
  missed presents: refreshes that passed while a look had been waiting since before them, i.e.
  vsyncs skipped between display-link ticks (≥ 1.75 frames apart) with a look waiting, plus ticks
  where a waiting look sat behind a render still in flight. A ProMotion panel stretching a frame
  with nothing new to show is its cadence, not a miss (traced as an idle gap). A look the page
  emitted before a skipped refresh but that arrived only after the gap (the main thread was held,
  so its message waited too) counts the refreshes after it was emitted. `lumina.edit.stats().trace` (`LookTrace`) ties a miss to what ran then.
  Region requests take their numbers from `LookRegionTiles.nextSeq()`, so callers can't starve
  each other.

- **Stage programs are compiled before the drag that needs them (`LookWarmPlan`).** `LookPipeline.apply`
  leaves a stage at reset out of the graph (`Look.runs`), and Core Image fuses the stages that run
  into one Metal program per *set* of stages, compiled on the rendering thread the first time the set
  renders: 11 to 47 ms on the main thread with Metal's on-disk cache cold (the first launch after an
  update that changed a kernel, or a set never rendered on this Mac), about 1 ms after. Measured: the
  cost is per set of stages, not per kernel or slider value; compiled programs are shared by every
  CIContext on the device; a 16 px corner of the graph does not warm the blur stages; an intermediate
  between stages does not make programs independent of the set and costs 1 to 3 ms per `base` frame.
  So once the photo's base is on screen and the canvas is idle (the prefetch's condition), the
  controller renders, on its own queue and its own CIContext, into an offscreen texture of the
  drawable's size and format, the look on the canvas and that look with each stage switched (on if
  at reset, off if it runs): every set one slider can reach, both tiers, `small` first. It repeats
  when the look at rest runs another set, holds during a drag, and never touches the drawable's
  context. The canvas's graph is built in one place (`LookCanvasController.compose`) for both. A look
  two stages away (a pasted look) compiles on its first frame as before. `stats().warm` and
  `stats().firstRenders` (the main-thread time of the drawable's first render of each set) report it;
  `LUMINA_CANVAS_WARM=0` turns it off and `LUMINA_KERNEL_SALT=<word>` compiles every kernel under a
  salted name so nothing is cached (both for `probe.sh edit-cold`, never set in the app).

## RAW 9

Apple's RAW decoder version 9 (`CIRAWFilter`, macOS 27: a tiled Core ML demosaic + denoise, per
body, on the Neural Engine) is the best development Lumina can run for Sony files and the only
model besides Vision and the fitted slider stages. It is used wherever it improves the picture and
never where the user is waiting. The rules live in `LookRawPolicy` (tiers, gating, memory) and
`LookDecoderProbe` (the capability map); the tests hold them:

- **Capability map.** On each shoot open, `plumbing.js` names one RAW per body; the bridge measures
  `supportedDecoderVersions`, whether 9 is present and the fastest version (a 512 px proof per
  version, at `.utility`) and keeps it in the shoot's `Lumina.json` header (`LookShootHeader`, next
  to `session.json`). The facts line shows `raw 9: yes/no`. RAW 9 is found by number, so the app
  builds against the macOS 15 SDK and simply reports `no` there.
- **Tiers, by what the user is doing.** Cull: the embedded JPEG only, never a RAW decode. Edit
  canvas: the fastest version (RAW 8) at canvas size for `base` and `small`, so sliders stay under a
  frame. Loupe (100 % with G held): the pinned version (RAW 9 when present) on the visible region
  only, as 512 × 512 tiles covering the region plus one tile of margin, cached per (rel, region,
  look-independent) so panning reuses them; `raw 9 · region` in the facts line, `refining…` only if
  the first tile takes more than 150 ms. Export: the pinned version at full size, `cacheIntermediates`
  off, a 512 MB memory target on 8 GB, serial; the result block names the decoder used.
- **Fallback per file, not per shoot.** A RAW 9 error, or more than 8 s at export size, re-renders
  that file once with the previous version, silently, and logs it (`SetsLookExport.Outcome`,
  `LookCanvasController.onDecoderFallback`).
- **Facts from the model.** When a RAW 9 region exists, its sharpness (Laplacian variance) and
  clipping come from the tiles, not the JPEG: `facts.source: "raw9-region" | "jpeg"` through
  `luminaEditStats`; the page updates the tile's flag words (DESIGN-ASKS, the addendum to Prompt 1).
- **Thermal and battery.** Region tiles run at `.userInitiated`, export at `.utility`. At
  `thermalState == .serious` or in Low Power Mode, region refinement waits 400 ms of stillness and
  export adds the footer fact `raw 9 · slowed by thermal state`. Never disabled, only deferred.
- **Memory.** Region tiles have their own 150 MB cache, evicted before any base texture. Under memory
  pressure: tiles first, then the neighbours' bases, never the current photo's base.
- **Denoise.** One look key, `nr` (Detail ▸ luminance noise reduction, 0 … 100 →
  `luminanceNoiseReductionAmount`), applied identically to `base`, region tiles and export. The
  page hides colour NR, detail and moiré while RAW 9 is active (they have no effect) and shows them
  when it isn't (`lumina.edit.facts().raw9`).
- **The pin rule.** The decoder version is pinned per shoot in `Lumina.json` on first open (the newest
  any body offers). Reopening renders with the pinned version even after a macOS update adds a newer
  one; the facts line offers `decoder N pinned · update shoot` (`luminaFacts.note`) and
  `lumina.edit.updateDecoder()` moves the pin on purpose. The parity run happens once per decoder version present
  (`make parity DECODER=9`, labels `-raw9`), and `probe.sh raw9` reports region tiles vs the export
  at the same region per version (median ΔE ≤ 0.5).

## History

Everything before the Sets rebuild (the P0/Elastic SwiftUI UI, its harness and lints, the Swift
`CullCore` port, AutoDevelop) was removed in the Phase 6 cleanup and lives in git history before it.
Auto for the beta is `lumina-core`'s own; the Swift AutoDevelop is parked, to be revisited after beta.
