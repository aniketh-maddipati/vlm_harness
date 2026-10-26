# Continuation prompt: finish Lumina's video masking and healing

Written 2026-10-26 for an agent (Gemini Argon) taking over with no access to the earlier chat threads. Everything
you need is in this file, in the repo, and on the T7 drive. Read the whole file before you start.

---

## 1. The goal

**Lumina should do masking and healing as easily as Lightroom Mobile, but for video**, with a clean round trip
into Final Cut Pro. Lightroom Mobile has no video masks and no video Remove; that gap is the product.

In practice that means, inside Skim (Lumina's video step, a WebKit page hosted by a native macOS app):

- **One tap or one brush stroke makes a mask**: Subject, Sky, People, Background chips; a click on the thing; or
  one brush stroke over it.
- **The mask follows through the whole clip by itself**, and the strip under the scrub bar tells the truth about
  which frames are sure, shaky or lost.
- **One-brush Remove**: brush over a distraction and it is gone for the whole clip, on a tripod shot and (still to
  build) on a moving camera.
- **Final Cut round trip**: Export writes an `.fcpxml` plus, next to it, a black-and-white **matte** movie per
  mask and a ProRes 4444 **patch** movie with alpha per Remove. Final Cut imports it; the clip itself is never
  touched; turning the patch off brings the object back.

Yardstick for every step: **taps and seconds to a good result**, as well as accuracy (J&F, PSNR) and speed (fps
on the owner's M4 Pro).

## 2. Rules (the owner's standing rules; do not break them)

1. **Everything goes on the T7 drive** (`/Volumes/T7`), never the Mac's internal disk: installs, venvs, pip and
   Hugging Face caches, model weights, datasets, runs, renders, DerivedData. Set `HF_HOME`, `TORCH_HOME`,
   `PIP_CACHE_DIR`, `XDG_CACHE_HOME`, `TMPDIR` to T7 paths before any run. Every script checks first that
   `/Volumes/T7` is mounted and writable and **stops** if it is not. If the T7 drops mid-run, stop everything,
   tell the owner, and when it is back run a read-only `fsck_apfs` on the sparse bundle before using it.
2. **Clean up temp files after each run** (partial downloads, extracted frames you no longer need, scratch
   renders). Keep only the numbers, reports and contact sheets.
3. **Ask the owner (sam) before any merge** and for the **Final Cut sign-off** (they open the exported
   `.fcpxml` in Final Cut and confirm the matte and patch look right). Everything else you may do yourself: branches,
   pushes, draft PRs, runs, downloads of public datasets, clicks and dialogs on the Mac.
4. **Builds and tests on the Mac use a separate copy of the repo** (the T7 sparse bundle, section 6), never the
   owner's checkout at `~/vlm_harness`, which has uncommitted work of theirs.
5. **The repo is public. Never commit footage, frames, masks, labels or healed frames**, only code, numbers and
   contact-sheet JPEGs under `docs/masking/checkpoints/`.
6. **Licences.** Only Apache-2.0 / MIT / BSD (or Apple's own frameworks) may ship in the app.
   - Shippable: Apple Vision, **EdgeTAM** (Apache-2.0), **SAM 2.1** (Apache-2.0), **LaMa / big-lama** (Apache-2.0),
     **MI-GAN** (MIT).
   - **Reference only, never bundled, never copied into `Lumina/`**: **ProPainter** (S-Lab, non-commercial),
     MiniMax-Remover, ObjectClear, MatAnyone, Adobe Firefly / Lightroom Generative Remove.
   - **RapidRAW (AGPL) and darktable (GPL): ideas only**, cited in a comment, never code.
   - FiveK and PPR10K are research-only: score against them, never ship anything trained on them.
7. **Privacy (TRUST.md, invariant I5): nothing leaves the Mac.** Models run on-device. The one exception the owner
   approved by merging #311 is Apple's own on-demand download of Vision's prompted-segmenter model (~55 MB,
   the same mechanism Photos' Clean Up uses).
8. **Done means measured**: on real T7 clips and on public sets, with the numbers written into the docs.
9. Never skip, disable or loosen a test to get green. `SetsIngestTests` is known to be flaky under heavy load on the
   Mac (see `docs/masking/TRACKING-EXPERIMENTS.md`, Known issues); re-run that class alone rather than touch it.
10. Work style that the owner likes: one objective at a time, one PR per item, small commits, short plain-English
    status reports that lead with the result and the numbers.

## 3. Where things are

- **Repo**: `github.com/aniketh-maddipati/vlm_harness`, default branch `main`. Read `AGENTS.md` at the root first
  (repo conventions, test commands, CI). The macOS app is called Lumina; the video step is "Skim".
- **Owner's Mac**: M4 Pro, macOS 27 (needed for Vision's prompted segmenter). Owner checkout `~/vlm_harness`
  (don't build in it). Hot dev app: `bash Scripts/dev-skim.sh --watch` builds "Lumina Skim"
  (bundle id `com.lumina.app.skim`); a page edit reloads in under a second, a Swift edit rebuilds.
- **RapidRAW fork**: `github.com/aniketh-maddipati/RapidRAW`. No open work there; read-only for ideas (AGPL).

### Key files (all on `main`)

| Area | File | What it is |
|---|---|---|
| Page (UI) | `design/handoff/lumina-skim/Lumina Skim v3.dc.html` → copied to `Lumina/Sets/Web/` | Skim's whole UI: Viewer, outlines, chips, brush, strip, playback, Export. Edit the design copy; `SetsPageBytesTests` holds the two equal |
| Bridge | `Lumina/Sets/Core/SetsBridge.swift` | Page ↔ Swift ops: `skimPrompt`, `skimPromptReady`, `skimTrack` (`prompted`), matte, patch, Export, Open in Final Cut |
| Click / brush to outline | `Lumina/Sets/Core/SkimPrompt.swift` | Vision `GenerateIterativeSegmentationRequest` (macOS 27): `seedPoint`, `seedBox`, `seedScribbleBuffer` (the brush), include/exclude points. One request per page frame so later clicks only add points |
| Follow (tracking) | `Lumina/Sets/Core/SkimTracker.swift`, `SkimFollower.swift`, `Lumina/Sets/Video/SkimFollow.swift` | Every-frame tracking on the Mac. `SkimFollow.sureness(...)` decides sure / shaky / lost; `strip(...)` builds the strip. The clicked-outline path prompts each frame with the box followed from the last frame, grown 15% |
| Still masks | `Lumina/Sets/Core/SetsMasks.swift`, `Lumina/Sets/Look/LookMasks.swift` | Vision subject / sky / people / instance masks, guided-filter edge snap, `LookMasks.raster` |
| Matte for Final Cut | `Lumina/Sets/Core/SkimMatte.swift` | `lumina.video.matte`: B/W movie the clip's length, edge feathered (`feather = 0.003`), written next to the `.fcpxml`, never over a file |
| Remove (tripod) | `Lumina/Sets/Video/SkimPlate.swift` (maths, Foundation-only) and `Lumina/Sets/Core/SkimPatch.swift` (writer) | Clean plate = per-pixel temporal median of the clip's own frames where the shape is not (`maxFrames 48`, `steadyMax 6.0`, `unseenMax 0.02`, `margin 3`). Refuses when the camera moved (`shake`) or the background never shows (`unseen`). Patch = ProRes 4444 + straight (not premultiplied) alpha, connected above the clip in the `.fcpxml` |
| Export / FCPXML | `Lumina/Sets/Video/SkimExport.swift`, `SkimLedger.swift` | Saves `.fcpxml` (≤16 MB), validates against Final Cut's own DTD inside the app bundle (`Interchange.framework/.../FCPXMLv1_xx.dtd`), checks every `media-rep` src exists, records saves in `skim/exports.json` |
| Tests | `LuminaLogicTests/SkimFollowTests.swift`, `SkimPlateTests.swift`, `Tests/web/skim-*.mjs` (`skim-prompt-browser`, `skim-playback-browser`, `skim-follow*`, `skim-track-browser`, `skim-outlines*`), `Tests/linux-swift/` | Swift unit tests (Mac + Linux sandbox), page tests in Chromium and WebKit |
| Mask lab | `Tools/masklab/` (read its `README.md`) | Numbers-only harness: `masklab-track` (vision-box, vision-instance, vision-oracle, sam2-coreml), `masklab-skim` (the app's own tracker, `--prompted`), `masklab-iterative`, `score.py` (J, F, J&F, volumetric J `vj`, drift, flicker, sure share, IoU by state), `calibrate.py`, `strip_stats.py`, `sheet.py` (contact sheets), dataset converters `davis.py`, `vost.py`, `mose.py`, `lasot.py`, `datasets.py` (+ `MANIFEST.json`), healing: `heal_score.py`, `make_holes.py`. Python tests: `python3 -m unittest discover -s Tools/masklab/tests` |
| Plans and results | `docs/masking/BACKLOG.md`, `TRACKING-EXPERIMENTS.md`, `OUTLINING.md`, `checkpoints/` (sheets 01, 05, 06, 08) | Read all three docs; they hold every measured number and the reasoning |
| Ingest precompute design | (not yet in repo; summary in section 7, item 9) | |

### On the T7 (`/Volumes/T7/Lumina/`)

- `factory/mac.sparsebundle`: APFS sparse bundle with the Mac test clone of the repo, the Python venv
  (PyTorch MPS, SAM 2.1, EdgeTAM, LaMa/IOPaint, ProPainter), DerivedData, datasets and runs. Attach with
  `hdiutil attach -nobrowse`; it mounts at `/Volumes/LuminaFactory`. The T7 itself is exFAT: never build directly on
  it, only inside the bundle. **Unpushed work lives here** (section 5).
- `datasets/` (+ `MANIFEST.json`, sha256 per set), and inside the bundle `/Volumes/LuminaFactory/datasets/<set>`:
  DAVIS 2017 trainval 480p, DAVIS-345/585, VOST, VIPSeg val, GrabCut, Berkeley, COCO-MVal, RORD-50 (removal
  before/after), LaSOT and MOSE (partially converted; MOSE download may need restarting, delete partials first).
- `models/sd-20261023/` and `clips/`: **42 gap-filling clips from the owner's SD card** (Grand Teton trip; moving
  camera, sky, a boat `C0069`, SD car clips). Card tags in `Lumina – open me/sd-card-tags.json`, contact sheets
  `sd-sheet-1…5.jpg`. The card itself was only read.
- `/Volumes/T7/Lumina – open me/`: owner-facing folder (sheets, `Lumina Factory (test app)`, `demo-davis` clips).
- Older 4K test clips at the T7 root: `yvid-a7siii-C00*.mp4`; also T7 clips C0054 (4K24) and C0095 (4K30, small subject).
- `DELETE-AFTER-EVALS.md`: what may be deleted and what must **never** be (originals, personal folders). Respect it.
- Mask lab runs: `MASKLAB_EVIDENCE` → `/Volumes/T7/Lumina/masklab` (inside the bundle in practice:
  `masklab/runs/<date-time>/`, `masklab-davis/runs/...`).

## 4. Current state (all merged to `main` as of 2026-10-26)

- **#258** (merged): outlines, Follow, Final Cut matte, the mask lab.
- **#308** (merged): every-frame tracking, the sure/shaky/lost strip, draft gestures, clean-plate Remove + patch.
- **#310** (merged): tracking looks near the box first (window crop): +11% fps on DAVIS, +22% on a small subject, J&F flat.
- **#311** (merged 2026-10-26):
  - **Click to outline** with Vision's prompted segmenter. Click outside adds, inside removes, Esc undoes, ⏎ follows.
    First click ~150 ms, later clicks 10–20 ms.
  - **Brush select**: one stroke → `seedScribbleBuffer`. On merged objects a stroke reaches 0.92 IoU vs 0.86 for a click
    and 0.89 for a box.
  - **One-tap chips**: Subject, Sky, People, Background.
  - **Live-wire hand drawing**: a drag on the outline snaps to the strongest edges (Sobel + shortest path in a band).
  - **Auto-follow**: following starts by itself a moment after the outline settles.
  - **Sure-strip fix**: a clicked outline that jumps or runs away is still followed but marked shaky. Wrong-but-"sure"
    frames dropped from **75% to 36%** at no J&F cost.
  - **Mask playback**: in the Viewer, **L** or ▶ plays the clip with the mask on every frame; pause keeps it on the frame shown.
  - **Mask readout**: a graph in the scrub bar (mask size over time, jumps in red, sure/shaky/lost shading) and a
    summary line like "88% sure · 2 jumps · size ±40%".
  - Mask lab: look cue, dataset converters, `heal_score.py`, `make_holes.py`, volumetric J.
  - Note: #311 broke CI's Mac build (CI uses Xcode 16.4, which lacks `GenerateIterativeSegmentationRequest`). PR #313
    guards that code with `#if compiler(>=6.4)` (the macOS 27 SDK's Swift). Make sure #313 is merged and main is green,
    then run the full `LuminaLogicTests` on the owner's Mac (macOS 27 SDK), since CI never compiles the click-to-outline path.

### Numbers (DAVIS 2017 val, 61 objects, M4 Pro)

| Tracker | J&F | fps | Licence / ship? |
|---|---|---|---|
| Skim, Vision only (before click-to-outline) | 0.44 | 15–17 | ships |
| Vision oracle (best Vision instance per frame, ceiling) | 0.50 | – | – |
| **Skim with clicks** (prompted segmenter, followed box) | **0.61** | ~12 (9.6 on the clicked path) | ships |
| **One click + EdgeTAM** (the real app flow) | **0.76** | 9 | Apache-2.0, can ship |
| **EdgeTAM** (standard mask-start protocol) | **0.79** | **8.8** | Apache-2.0, can ship |
| **SAM 2.1 small** | **0.82** | **1.9** | Apache-2.0, but too slow for live |
| SAM 2.1 large | 0.84 | 1.2 | reference |

Targets (TRACKING-EXPERIMENTS.md): J&F with fallback ≥ 0.75 (one click + EdgeTAM already reaches 0.76), IoU on "sure"
frames ≥ 0.85, bad frames called sure ≤ 5% (now 36%), full track ≥ 15 fps.

Why Vision alone can't get there: on 13 of the 15 worst objects Vision never produces a mask for the object (it merges
the lab coats, the goldfish, the pigs, rider + bike). The mask must come from a SAM-class model where Vision's doesn't
fit, not only where the track is lost.

## 5. Healing: in progress, results not yet pushed

The healing benchmark is running on the Mac, inside the sparse bundle (started 2026-10-24 by the "factory" session).
Its results and the `masklab-heal` CLI will arrive as **a new PR** (with `docs/masking/HEALING.md`). First look on
GitHub for that PR. If it exists, review it, make its checks pass, and ask the owner before merging. If it does not
exist and nothing is running anymore, check `/Volumes/LuminaFactory` (the test clone's `git status`/`git log`, and
`masklab/` runs) for the CLI, healed-frame runs and partial reports. Push what's there to a new branch, re-run what's
missing, and open the PR yourself. The plan it is following:

- **Healers** (each writes healed frames per clip):
  a. **skim-plate**: Skim's own Remove. A small `masklab-heal` CLI that takes a frames folder and a holes folder and
     compiles against `SkimPlate.swift` (reuse its functions; change app code only for a real bug).
  b. **LaMa per frame** (big-lama, Apache-2.0).
  c. **MI-GAN per frame** (MIT), if quick.
  d. **ProPainter**: reference only, never bundled.
  e. **Flow fill + LaMa**: propagate known pixels along RAFT (or Farneback) flow from neighbouring frames, LaMa for the rest.
- **Sets**: DAVIS 2017 val 30 clips with `make_holes.py` holes, both moving and `--still`, truth = the original
  frames; **RORD-50** real before/after; and, no truth, the 8 SD car clips + `C0069` boat with holes from
  skim-prompted masks grown 8 px (flicker, seam, leak only).
- **Report**: healer × set table of PSNR, SSIM, flicker, seam (with p10/p90) and fps, plus contact sheet **09** per set
  (hole, each healer, truth; 3 frames × 4 clips) into a new `docs/masking/HEALING.md`. Numbers and sheets only.

## 6. Mac test factory (how to build and run safely)

1. Check `/Volumes/T7` is mounted. `hdiutil attach -nobrowse /Volumes/T7/Lumina/factory/mac.sparsebundle`.
2. In the clone inside it: `git fetch origin && git checkout <branch>`; DerivedData inside the bundle.
3. Run the `-only-testing` classes `Scripts/ci_changes.py` picks, or the full `LuminaLogicTests` before a merge.
4. Mask lab runs go through `Scripts/test_guard.py` (one at a time, time limit, refused while
   `~/LuminaEvidence/.tests-off` exists).
5. Detach the bundle and delete temp frames when done.

## 7. Remaining work, in order

1. **Verify `main`**: build the app and run `LuminaLogicTests` + the Skim page tests on the merged `main` in the
   factory. Fix anything #311 broke. Get the app screenshots of click / brush / chips / playback / readout.
2. **Finish the healing benchmark** (section 5): land its PR with `docs/masking/HEALING.md` (owner merges).
3. **Ship EdgeTAM as the follow model.** Convert EdgeTAM to Core ML (image encoder + memory attention + mask
   decoder; keep the video memory, unlike Apple's SAM 2.1 conversion which is per-frame only). Run it per frame on
   the Mac, seeded from the clicked/brushed outline. Measure J&F, vj and fps on DAVIS val; target ≥ 0.75 at ≥ 15 fps
   on the clicked path (use Vision's box tracking for the box and EdgeTAM for the mask; run EdgeTAM only on
   shaky/lost stretches if full-clip speed is short). Then wire it into `SkimTracker` behind the existing strip.
   SAM 2.1 small stays an optional slower "refine on export" pass.
4. **Make "sure" mean right** (E2 in TRACKING-EXPERIMENTS.md): fit the sureness rule on train splits with
   `calibrate.py` (cues: tracker figure, box/shape agreement, area change, look distance, refound, Vision score,
   rivals) so bad-but-sure frames go from 36% to ≤ 5%, then change `SkimFollow.sureness`.
5. **Remove on a moving camera**: the winner of the healing benchmark among shippable healers (likely flow fill +
   LaMa or MI-GAN in Core ML), written as the same ProRes 4444 patch layer as the tripod Remove, so the Final Cut round
   trip is unchanged. Keep `SkimPlate` for tripod shots (it keeps the real grain).
6. **One-brush Remove end to end**: brush → outline → auto-follow → Remove → patch, with the taps and seconds counted.
7. **Final Cut round trip check (owner sign-off)**: export a clip with a matte and a patch, open the `.fcpxml` in
   Final Cut (File ▸ Import ▸ XML), confirm the matte works as an Image Mask / Luma Keyer source and the patch hides the
   object and toggles off. Also wire the Final Cut matte directly as a mask (open item from #258).
8. **Broader masking baselines**: skim, skim-prompted, EdgeTAM, SAM 2.1 small on VOST, MOSE, LaSOT (box IoU) and
   VIPSeg (sky / person / background classes) with vj; NoC90 (taps to 90% IoU) on COCO-MVal, GrabCut, Berkeley for
   Apple point vs Apple scribble vs SAM 2.1 small; E5 on the owner's T7 clips against SAM 2.1 large pseudo-labels.
9. **Ingest-time precompute** so entering the Viewer has zero lag: at ingest, on the 720p proxy at `.utility` QoS,
   cache Vision masks (`[LookMasks.Found]`, a few KB) and feature prints on keyframes plus a static-camera score per
   clip; key by SHA-256 of the preview bytes + orientation + version + tracker mode. Do **not** precompute EdgeTAM
   features (several MB per frame).
10. **Lightroom side-by-side** (once the owner starts the Lightroom monthly trial): 200 stills (50 each people, objects,
    sky, removals), our masks/Remove vs Lightroom's Select Subject/Sky/People and Generative Remove, by taps, time and accuracy.
11. Later: matching a mask across clips (⇧⏎), video dust removal, color harmonization across bodies (see the strategy
    page the owner has: "Lumina Mask, Heal and Grade Stack").

## 8. Waiting on the owner (ask once, then carry on)

- Sign-ins for **YouTube-VOS**, the **full RORD** and **VSPW** (form/sign-in downloads).
- 5–10 clips with **people and crowds** (the SD card is thin there).
- **Final Cut sign-off** (item 7) and **every merge**.
- Starting the Lightroom trial (item 10).

## 9. How to report

Lead with the result and the numbers, in plain words, in a few lines. Then what's next and anything you need from
the owner. Put long tables in `docs/masking/*.md`, not in the message.
