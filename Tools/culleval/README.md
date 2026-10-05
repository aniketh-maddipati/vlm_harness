# Culling eval

How well do Lumina's rows, stacks and automatic keeps match what was really shot and what the
photographer really kept? This measures it. It changes nothing: the logic under test is the design's
own `lumina-core` (`design/handoff/lumina-cull`, shipped byte for byte), loaded as it is. A problem
it finds goes into `design/handoff/DESIGN-ASKS.md`.

```bash
make culleval          # every shoot in ~/LuminaEvidence/culleval/shoots.json → report (0.2 s once cached)
make culleval-test     # the scoring tests, synthetic data, Linux too (CI runs the node ones)
make culleval-app DUMPS="<run>/dump-decisions/decisions.json …" EXPORTS=exports.csv OUT=report.md   # the keeps question through the app, see below
```

First run: copy `shoots.example.json` to `~/LuminaEvidence/culleval/shoots.json` and point it at your
shoots. The first read of a folder takes about 30 s per 1,000 RAWs (exiftool, then the page's own
measure in headless Chromium, four at a time); both are cached by path, size and mtime. It needs
`exiftool` and Playwright's Chromium (`npm i -g playwright && npx playwright install chromium`, or
`LUMINA_PLAYWRIGHT=<folder of the playwright module>`).

Photos, file names and paths stay out of the repo, which is public. The config, the caches and the
reports live under `~/LuminaEvidence/culleval/`; `report/latest/report.md` is the newest one. Only
its last section ("Worst disagreements") names files.

## What is compared

**Lumina's side.** The files are the ones the page reads: ARW and DNG (`RAW_FILE` in
`lib/measure.mjs`, the one matcher). For every RAW the page's own `parseHead` reads the first 256 KB,
and the page's own `measure` runs on the embedded preview at 360 px in Chromium (`lib/measure.mjs`
repeats the page's `readOne`; the test fails when a design sync changes that method, so the copy gets
reviewed). As in the page, a phone (told by `LuminaCore.phoneOf` from EXIF Make/Model, never from the
extension) gets its 35 mm focal length as `fl`, its short name as `model` and its zoom label
(`1× camera`) as `lens`, so rows and stacks see what the page sees; `make` is kept on every record.
The truth side below still reads the real focal length and lens through exiftool.
`LuminaCore.buildShoot` then gives rows, stacks, flags (soft, blown, shake), the sharpest frame of
each stack (what P keeps on a closed stack) and the core's suggested keeps (`sugKeep`).

**Truth for grouping**, from the camera's own record, read by exiftool (a parser that shares nothing
with the page's). Three levels, each coarser than the one before (`lib/truth.mjs`):

| level | a frame joins the one before when |
|---|---|
| camera bursts | `SequenceImageNumber` goes up by one within 5 s (one press of the shutter in a drive mode) |
| bursts by hand | …or it follows within `--repeat-gap` (2 s) with the same lens, focal length (±5 %) and orientation |
| tries at one picture | …or within `--scene-gap` (10 s) with the same framing |

The first is hard truth. The other two are derived from time and exposure data, not marked by a
person; read them as "frames a photographer would expect to see together". There is no truth for
rows (nobody has marked scenes), so rows are only checked for cutting through a burst or a run of tries.

**Truth for keeps.** One of, per shoot:

- `exports`: kept = the RAW has a finished Lightroom export; rejected = shot in the same shoot and
  never exported. An export names its RAW (`crs:RawFileName`); renamed card copies are matched by
  capture time to the second, then exposure. Frames that can't be told apart are left out.
  **A batch export is not a selection**: the truth table shows how many exports carry edits; a
  folder of unedited exports of consecutive frames says nothing about keeps.
- `keeps`: saved keep lists, read like exports (alone or beside `exports`). Every run writes the
  keep list of each shoot whose exports folders are present to `~/LuminaEvidence/culleval/keeps/<id>.json`
  (export name, its RAW, capture time, exposure, whether it was edited; no pixels). When an exports
  folder is archived or deleted, name that file under `keeps` and the shoot scores as before.
- `sidecars`: kept = `.xmp` next to the RAW with `xmp:Rating` ≥ 1 (what Lumina's Save writes).
- `session`: a saved Lumina `session.json`; kept = its keeps, counted only in rows marked seen.

If a folder the config names is not there (a drive that is not mounted, an exports folder that
moved), the run stops with exit code 3 and lists the paths: nothing is scored, so a short report can't
pass for a full one. `make culleval ALLOW_MISSING=1` scores what is there; a shoot without its RAW
folder is listed as skipped, one without its exports or session is scored for grouping only, and a
missing folder is never read as "nothing kept". The reader skips dot files, so the `._*` AppleDouble
stubs macOS writes on exFAT drives are not counted.

`complete: false` marks a shoot whose frames or keeps are known to be partial; the headline pools
the complete ones and shows the rest beside them. `dates` / `datesExclude` pick days out of a
folder, `from` / `to` (`"2026-02-08 14:00:00"`) a stretch of capture time within them. A frame that appears twice in a folder (a card copy) is counted once, by shutter count.

## Metrics (`lib/score.mjs`)

- **Grouping**: pairwise precision / recall / F1 (a pair counts when two frames share a group),
  per truth level; truth groups Lumina made exactly, over-split (spread over several stacks), whole
  but merged with other frames; stacks that mix truth groups (under-split); by truth group size.
- **What if the drive data were read**: the same run with the sequence numbers exiftool reads
  filled in, to size what a parser fix is worth.
- **Keeps**: precision / recall / F1 of the suggested keeps and of "P on every unit" against the
  real keeps, next to the keep rate (keeping everything scores precision = keep rate, recall 100 %).
  Flags read as "reject": how many flagged frames were really rejected.
- **Best of stack**: in groups where the photographer kept exactly one frame, did Lumina pick it?
  For Lumina's own stacks, and for the truth groups as if they had been stacked by hand (the same
  `cuts` the B key makes, so the core itself answers). Next to chance, and by group size.
- **Where it goes wrong**: suggested-but-rejected and kept-but-not-suggested, split by cause; the
  ten worst per shoot by file name, in the local report only.

## Through the app

`make culleval` reads the photos itself, in headless Chromium. `culleval-app.mjs` asks the keeps
question of what the real app decided: `dump-decisions.json` is a probe scenario in which the page
and the native reader open a folder in WKWebView (read-only) and every photo's row, stack, rank,
flags and suggested keep are dumped. The picks are matched by the same `matchExports` and scored by
the same `picks` and `bestOf` as above (`lib/app.mjs` only adapts the dump), so the two can't drift.

```bash
LUMINA_CULL_DIR=<shoot> Tools/LuminaProbe/.build/release/lumina-probe run Tools/culleval/dump-decisions.json --out <run>
exiftool -csv -FileName -RawFileName -DateTimeOriginal <exports…> > exports.csv
node Tools/culleval/culleval-app.mjs --exports exports.csv --out report.md <run>/dump-decisions/decisions.json …
```

A pick here is a *final select* (a RAW a finished Lightroom export names), stricter than a culling
keep, so precision against it is low by nature. What a culling aid must get right is the other
direction: the report leads with recall on picks, each flag word's false alarms on picks, and, in
bursts with exactly one pick, whether it is the frame ranked first. Only days with at least one
pick are scored: a day never exported from is unlabeled, not "all rejected". Until DESIGN-ASKS
Prompt 2 A lands the page reads no drive data from an ARW, so a dump holds almost no camera bursts
and the burst lines say nothing yet. It reads none from a phone DNG either (its drive data is
read from Sony maker notes only), so a phone's bursts are stacked by time and look alone.

`--out report.md` also writes `report.json` and `labeled.json` (the scored photos, each with its
dump's name and whether it was picked) beside it. Keep them under `~/LuminaEvidence/culling-eval`:
`labeled.json` names files.

## Candidate signals (`signals/`)

Signals the page doesn't have. `signals.swift` measures each RAW's embedded preview on the Mac
(Vision face capture quality, landmarks, saliency, aesthetics; sharpness by region), and
`rank_signals.py` asks of each one, inside a row or a run of retakes: does it put the pick above the
frames passed over? (pair accuracy with a bootstrap interval, top-1 against chance, and a combined
model scored on held-out days). Numbers only.

```bash
swiftc -O Tools/culleval/signals/signals.swift -o signals && ./signals list.txt signals.jsonl
python3 Tools/culleval/signals/rank_signals.py --signals signals.jsonl --out signals-report.md labeled.json
```

## Files

| | |
|---|---|
| `culleval.mjs` | the command: config → metadata → the core → scores → `report.md`, `report.json`, `local-worst.json` |
| `lib/core.mjs` | loads `lumina-core`, runs `buildShoot`, turns truth groups into the page's `cuts` |
| `lib/measure.mjs` | the page's header read, its phone remap (`recordOf`) and preview measures, cached; the file matcher |
| `lib/truth.mjs` | truth groups from camera metadata; exports matched to RAWs |
| `lib/score.mjs` | the metrics (pure) |
| `lib/report.mjs` | the Markdown report |
| `culleval-app.mjs`, `lib/app.mjs`, `dump-decisions.json` | the keeps question through the app: the probe scenario, the dump adapter and its report |
| `signals/` | candidate signals measured on the Mac and how well each ranks the pick; `test_rank_signals.py` |
| `tests/culleval.test.mjs` | scoring, truth, the core adapter, the dump adapter and the `readOne` guard, on synthetic data |
