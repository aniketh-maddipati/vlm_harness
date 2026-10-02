# Lumina: release notes and checklist

Status 2026-10-01. Cull and Edit ship together (ruled 2026-10-01). Matching Lightroom is ongoing
work, not a release gate. Sources: `AGENTS.md`, `Tests/probe/EDGE-CASES.md`,
`design/handoff/DESIGN-ASKS.md`, `design/handoff/lumina-cull/` (GRAMMAR, SAFETY, CHANGES).

## Open before release

| # | What | Where it is fixed |
|---|---|---|
| 1 | **The app has no Edit screen yet.** The shipped page (v5) has three steps: Open · Cull · Save. The Edit engine (look, canvas, JPEG export, RAW 9) is built and tested, but only the probe drives it. | Design: DESIGN-ASKS Prompt 1 + its addendum, then `Scripts/sets_sync_design.sh` |
| 2 | `README.md` describes older keys and steps (R / X on rows, Auto, "edit … then export", RAW + JPEG export). v5: P / R keep, F flag, Save writes sidecars. | README refresh + new screenshots once #1 lands |
| 3 | The app is not sandboxed, signed with a Developer ID or notarised (SAFETY.md 7–8). Fine for a build from source; needed before handing a built app to others. | Xcode project + a signing step |

## What Lumina does

**Cull** (in the app today)
- Opens a folder or a Sony card of ARW files and reads them in place. Nothing is copied or moved.
- Splits the shoot into rows by time, and groups bursts and brackets into stacks.
- Marks the sharpest frame of a stack and names problems: soft, blown, shake, dark, preview missing.
- Keyboard first: P or R keeps, F flags, arrows move, Space large view, Z 100 %, Q undo. `?` lists every key.
- Saves your place by itself; reopening a shoot picks up where you left off.
- Save writes one `.xmp` per keeper next to its RAW, with a star rating (default 3★). An existing
  sidecar only gets its rating changed. Lightroom and Capture One read the rating.
- Skips non-Sony files and says so (import notes: other RAW formats, JPEGs, videos, more than one body).

**Edit** (engine in the app, screen pending: see #1 above)
- One look per photo: exposure, white balance, contrast, highlights, shadows, whites, blacks,
  vibrance, saturation, clarity, sharpening, vignette, noise reduction, black and white, crop.
- A look can apply to one photo or a whole row.
- The Mac renders the picture itself: the preview while a slider moves, and JPEG export with the look.
- A Lightroom-style starting point; we measure against Lightroom and keep closing the gap.

## What it does not do yet / known limits

**Cull**

| Limit | What happens | Status |
|---|---|---|
| Wrong camera clock, time-zone jump | Rows follow the camera's clock. There is no "shift shoot time". | Design ask (Prompt 3 B) |
| Two bodies in one folder | Photos sort by capture time, so the bodies interleave. Lumina warns to check the clocks match; it can't shift one body. | Design ask (Prompt 3 B) |
| Camera bursts | Often not stacked: 15 of 80 real bursts came out as one stack. The camera's drive data isn't read from ARWs yet. Without it, look-alike frames within 2 s are stacked, burst or not. | Design ask (Prompt 2 A, B) |
| Repeated tries at one picture | Shown as separate photos, not a group. | Design ask (Prompt 2 C) |
| Missing or damaged preview | Kept as a grey tile with the file number, counted in the import notes. No reason on the tile, no picture to judge. | Design ask (Prompt 3 A) |
| File that can't be read at all | Left out of the grid. Counted as "N unreadable"; can't be kept or saved. | Design ask (Prompt 3 A) |
| Photo with no capture time | Lands in its own row at 00:00. | Design ask (Prompt 3 A) |
| "blown" | Fires on bright scenes (296 of 509 frames at one bright event; kept as often as the rest). | Design ask (Prompt 2 D) |
| "soft" | Always names the bottom 12 % of a shoot, however sharp the shoot is. | Design ask (Prompt 2 E) |
| "sharpest" | Among near-identical tries it agreed with the photographer 39 % of the time; chance is 37 %. | Open (Prompt 2 G) |
| Save on a USB stick, a non-camera SD card, or after the card is pulled | Save is offered, then every keeper fails "on the card". Nothing is written. | Design ask 9 |
| Slow disk | No word while a folder opens (up to 14 s measured on a just-mounted disk). | Design ask 10 |
| Big cards | Scrolling misses the frame budget slightly (p95 18.0 ms vs 17.5). A 5,000-photo card has not been run. | Open |

Not tested yet: network drives, iCloud files not downloaded, Lightroom writing a sidecar at the same
moment, the same shots on two card slots, the same folder in two windows, sleep / wake, a folder
permission gone stale after a restart, VoiceOver and larger text, lossless / uncompressed /
pixel-shift / APS-C-crop RAWs. Culling was measured on one body (α7 III).

By hand only, not done: how Lightroom and Capture One behave with unsaved edits, custom label
sets, the Capture One XMP preference and rejects; the macOS access-denied prompt; the Quit alert.

**Edit**

- No Edit screen in the app yet (#1 above).
- Not a Lightroom match. Closest on landscapes and moderate edits; people photos and strong
  Shadows are where we're working now.
- Vibrance is too weak on skin tones (2–4× less colour gain than Lightroom) and too strong on greens and blues.
- Edits are not written to XMP. Only ratings travel to Lightroom; an edited picture leaves Lumina as a JPEG.
- Sony ARW only. Apple silicon, macOS 14 or later.
- Apple's newest RAW decoder (RAW 9) needs macOS 27. Older systems use the previous decoder.

## Edit vs Lightroom: the numbers

Colour difference (ΔE2000), median / p95, lower is better. Target for single sliders: 2.0 / 4.0
(`Tools/parity/criteria.json`; a tracked target, not a gate).

| Measured on | Median | p95 |
|---|---:|---:|
| Single sliders (5 photos × 30 Lightroom presets) | 1.45 | 5.05 |
| Three sliders at once + white balance | 1.63 | 4.62 |
| Untouched render, landscapes (156 photos) | 1.05 | 3.13 |
| Untouched render, people (36 photos) | 1.28 | 5.29 |
| Highlights / Shadows, landscapes never used for fitting | 1.70 | 5.82 |
| Highlights / Shadows, people (prototype) | 1.84 | 8.90 |
| The photographer's own real edits (109, never fitted) | 2.31 | 7.81 |

Single sliders: the median is inside the target, the p95 is not. Photos and reports stay out of the repo.

## Trust rules

| Rule | Enforced by |
|---|---|
| Never writes to the card | `probe.sh fault` (`fault-readonly-card`, `fault-card-pull-cull`, `app-xmp-both`, `fault-disk-full`), `fuzz-app-card` (no `.xmp` on the card after 2,000 inputs) |
| Never changes originals | `SetsSidecarTests` (`testWritesNextToTheRaw`, `testOnlyXmpInsideTheFolder`, `testLinkedFolderCannotLeadOut`), `SetsTrustTests.testReadingChangesNothing`, `app-xmp-lightroom` (RAWs byte-identical after two saves) |
| Copies, never moves; every copy checked | `SetsFileOpsTests`, `SetsTrustTests.testACopyThatFailsLeavesNothingBehind`, `fault-native-dest` (copies hash-equal to the originals), `fault-kill-mid-handoff` |
| `.lumina-bak` before replacing a file | `SetsSidecarTests.testExistingSidecarKeptAsLuminaBak`, `SetsFileOpsTests.testReplacingKeepsTheOldBytesAsLuminaBak`, `SetsTrustTests.testSecondExportKeepsTheOriginalBackup`, `app-smoke`, `app-xmp-lightroom` |
| Nothing leaves the Mac | The page loads only from files inside the app (`lumina://`, `SetsSchemeHandler`); `SetsPageBytesTests` pins those files. Not yet blocked by the system: see #3 above |

v5's Save only writes `.xmp` sidecars into the shoot folder; the copy rule covers the Mac's export job.

## Pre-release checklist

In order. Stop at the first failure.

| # | Command | Needs |
|---|---|---|
| 1 | `(cd design/handoff/lumina-cull && node lumina-core-v4.test.mjs)` | any machine |
| 2 | `node Tests/web/plumbing-harness.mjs` then `node Tests/web/parity.mjs` | any machine, Playwright's Chromium |
| 3 | `xvfb-run … python3.12 Tests/web/webkit.py` (full line in AGENTS.md) | Linux, WebKitGTK |
| 4 | `bash Tests/linux-swift/run.sh` | Docker |
| 5 | `make parity-test` and `make culleval-test` | any machine |
| 6 | `xcodebuild … -only-testing:LuminaLogicTests test` (full line in AGENTS.md) | Mac |
| 7 | `bash Scripts/probe.sh contract`, `smoke`, `screens` | Mac, awake display |
| 8 | `LUMINA_FIXTURE_ROOT=~/LuminaEvidence/fixtures bash Scripts/probe.sh fuzz`, `app`, `fault` | Mac, awake display, fixtures |
| 9 | `… bash Scripts/probe.sh edge` and `ingest` | same. Four scenarios fail today: the Cull limits above |
| 10 | `LUMINA_EDIT_DIR=<shoot> bash Scripts/probe.sh edit`, `raw9`, `consistency` | Mac, awake display, a real shoot |
| 11 | `LUMINA_CARD_DIR=<card folder> bash Scripts/probe.sh card` and `stress` | Mac, a real card (only read) |
| 12 | `make parity-check`, then `make parity` | Mac, Lightroom references in `~/LuminaEvidence/parity`. Numbers reported, not gated |
| 13 | By hand: Quit with unsaved keepers, the access-denied prompt, Lightroom reading the saved ratings | Mac, Lightroom |
| 14 | `bash Scripts/install_app.sh` | Mac |

Build the fixtures once with `LUMINA_CARD_DIR=… bash Tests/probe/forge_fixtures.sh` (it only reads the card).
CI runs 1 and 3–6, the plumbing harness of 2, and part of 7, 8 and 10.

## The experimentation phase

- Every Edit change was fitted on development photos and adopted only if a held-out set did not
  get worse. Most candidates were rejected: two tone ideas, a Vibrance refit, a base refit, and a
  slider refit on that base.
- Single sliders against Lightroom: 1.45 median, 5.05 p95. Three sliders at once plus white balance: 1.63 / 4.62.
- The untouched render against Lightroom's default: landscapes 1.05 / 3.13, people 1.28 / 5.29.
  The people gap is mostly fine detail: compared at small size the two agree (0.84 / 2.64 vs 0.81 / 2.07).
- Highlights and Shadows on photos never used for fitting: landscapes 1.70 / 5.82; people are
  noticeably worse at the bad end (prototype 1.84 / 8.90).
- The photographer's own real edits (109, measured, never fitted): 2.31 / 7.81.
- Vibrance gives skin tones 2–4× less colour gain than Lightroom and pushes greens and blues too far.
- Culling was measured against real camera bursts and the photographer's real keeps
  (`Tools/culleval`; one photographer, one body, a small truth set). It found that camera bursts
  are mostly split (15 of 80 whole; 74 of 80 once the camera's drive data is read), that "blown"
  and "soft" fire on photos that were kept, and that "sharpest" is close to a coin toss between
  near-identical tries. All of it went to the design as asks; none of it is fixed in the app yet.
- A second pass through the real app (1,854 photos, 444 finished picks) agreed, and found that
  the quality of faces ranks tries better than sharpness (63 % vs 52 %; a modest signal).

> Lumina started as a question: can a small native Mac app make culling a Sony shoot fast and safe, and get an edit close enough to Lightroom to be a useful starting point? We spent the experimentation phase measuring instead of guessing: rendering the same photos in both, comparing them pixel by pixel, and holding back a set of real edits we never tuned against. Some ideas held up; many didn't, and we kept the record of both. Culling and editing ship together; we keep measuring and improving both.
