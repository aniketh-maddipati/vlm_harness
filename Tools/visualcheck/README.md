# Visual check

Flags image pairs with a visible difference (before/after, canvas/export, Lumina/Lightroom) and
writes a contact sheet with the flagged pairs first. Measures only: nothing here changes the look.

```bash
PY=~/LuminaEvidence/venv-parity/bin/python
$PY Tools/visualcheck/check.py --pairs <dir | list.txt> --out ~/LuminaEvidence/visualcheck/<run> --no-model
$PY Tools/visualcheck/test_check.py          # 15 tests, synthetic images, mocked model, no LM Studio
$PY Tools/visualcheck/calibrate.py --sources <img> … --out ~/LuminaEvidence/visualcheck/calib-<date> [--real <pairs dir>]
```

**Pairs.** A directory of `<stem>-before.* / <stem>-after.*` (also `a/b`, `canvas/export`,
`lumina/lightroom`, `render/ref`, `old/new`), sub-directories holding one such pair each, or a list
file of `A<TAB>B[<TAB>name]` lines. B is resized to A when the sizes differ.

**Output** (in `--out`, which must be outside the repo): `index.html` (the contact sheet: A, B and
a ΔE2000 heatmap per pair, flagged first), `report.md`, `report.json`, `heat/`, `thumbs/`.

## Signals

Measured at 1024 px on the long side, in sRGB (16-bit ProPhoto TIFFs from `lumina-render` are read
through `Tools/parity/delta_e.py` and converted):

| signal | flags when | catches |
|---|---|---|
| tone ΔE2000 median / p95 (8 px blocks) | > 0.6 / > 1.25 | exposure, tint, profile |
| worst 32 px block ΔE | > 1.75 | a local change (a mask, a patch) |
| sharpness B/A (Laplacian variance) | < 0.45 or > 1.30 | soft or over-sharp all over |
| worst 128 px block sharpness | < 0.30 | one soft region (a tile not refined) |
| seam z (strongest row/column step in the difference) | > 6 | tile seams |

**The model** (optional, off with `--no-model`): both images sent to a vision model in LM Studio on
loopback (`http://127.0.0.1:1234`; any other host is refused, photos never leave the Mac), asked for
`{"visible_difference", "reason"}`. A model error never hides the numbers.

## Calibration (2026-11-12, 8 photos)

| signal | hits (73 known changes) | false alarms (24: identical, JPEG q90, resize round trip) |
|---|---|---|
| numbers | 72 (99 %) | 0 |
| `qwen2.5-vl-3b-instruct` | 0 of the first 17 | 0 of 3 |

The numbers are the check. The 3B vision model answered "both images are identical" to every pair,
including ±0.3 EV, tints and a whole-frame blur, so it adds nothing at this size: run with
`--no-model`. Measure a larger local model with `calibrate.py` before trusting it. The one miss by
the numbers is a shadows crush on a photo with almost no shadows.

Evidence: `~/LuminaEvidence/visualcheck/calib-numbers`, `calib-qwen2.5-vl-3b`, `calib-qwen.log`.
