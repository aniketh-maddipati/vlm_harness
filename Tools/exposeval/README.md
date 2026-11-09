# exposeval: Skim's ⇧E against a human's per-shot brightness

Measures only. How close is Skim's per-clip auto exposure (⇧E, LOCAL-CHANGES 322) to one human's per-shot
choices? Ground truth is the one annotator in the HDRVS adaptive colour grading subset (Canham, Punnappurath,
Brown, "Adaptive Color Grading", CIC 2026, arXiv 2609.21169; HF `trevorcanham/hdrvs_adaCGsubset`; code
github.com/SamsungLabs/adaptive-color-grading). Licences differ: the HF card says MIT, hdrvs.github.io CC BY 4.0,
the paper CC BY 4.0, and the code has a copyright line and no licence. So nothing is trained on this data, and
no data, images or labels are committed. Only numbers-only reports go in `report/`.

```bash
~/LuminaEvidence/venv-parity/bin/python -I Tools/exposeval/run.py \
  --pkl /Volumes/T7/Lumina/datasets/hdrvs-adacg/trainDemo8b.pkl.UNTRUSTED-do-not-unpickle \
  --tiffs /Volumes/T7/Lumina/datasets/hdrvs-adacg/adaCG \
  --out ~/LuminaEvidence/exposeval --report Tools/exposeval/report/$(date +%F).md
make exposeval-test        # unittest on synthetic data, Linux too (numpy; Pillow for the end-to-end case)
```

It takes about 5 s. Evidence goes to `~/LuminaEvidence/exposeval/`: `results-<date>.json` holds every number and
`shots-<date>.json` holds the per-shot values.

## The label file is a pickle

`adacg.py` reads `trainDemo8b.pkl` with a whitelist `pickle.Unpickler`. Its `find_class` resolves only the four
globals the file names, which were checked with `pickletools` (protocol 4): numpy's `_reconstruct`, `ndarray`,
`dtype`, and `datetime.datetime`. Anything else raises `RefusedGlobal` before it runs. The tests feed it an
`os.system` payload and a `__reduce__` payload. Run it under `python3 -I`, from outside the data folder.

## What the labels are (and aren't)

Per still there are four region thresholds (`reg`: darkest / dark / light / lightest, each `[pivot, falloff]`), CIELAB
a\*/b\* offsets per region (`set`), a histogram and a 102 × 54 JPEG thumbnail. In `adaCG.py`, `colorEngine.apply`
works in the still's own encoding (Display P3, γ2.4). A pivot is a level of mean(R, G, B) where a region's mask
reaches 1. The falloff is the mask's slope, and it sits at the tool's default (−10, −5, 5, 10) on every still. The
grade changes a\* and b\* only. **There is no exposure, gain or brightness field.** The annotator chose where each
still's dark and light regions begin, not how bright it should be.

So the target here is a proxy:

- **The annotator's middle** is halfway between where "dark" ends and "light" begins, `(pivot_dark + pivot_light) / 2`,
  taken to linear light with γ2.4. The tool's default pivots (0.4, 0.5) put it at 0.147 linear, close to 18 % grey.
- **Relative target** (⇧E's frame): the stops that bring a shot's middle to its shoot's median middle. A shot is the
  two stills of one video (numbered 2k, 2k + 1). A shoot is the location label (utah, alaska, seattle, nyc, toronto,
  london). A second run uses the full label set (17 sessions such as urban+night+london).
- **Absolute target**: the stops that bring the middle to 18 % grey.

What this assumes: the annotator puts the dark/light boundary at the brightness they see as the middle of that
picture. If so, a gain that brings every shot's middle to the same level is the per-shot balance they would accept.
That is a reading of the labels, not something they record. The report also scores the light pivot alone and the
dark pivot alone, so the conclusions can be checked against the choice of proxy.

## ⇧E, reimplemented (`rule.py`)

The code follows `design/handoff/lumina-skim/Lumina Skim v3.dc.html` line for line:

- `sceneSl(img, c)` → `rule.scene_sl`. It reads every 8th pixel of the 8-bit frame (`i += 32` over RGBA). Each
  level goes through a 256-entry table to scene-linear: S-Log3 decoded after the calibration, or sRGB's curve undone
  for anything else (these stills are P3 γ2.4, so Skim undoes sRGB's curve). Luminance uses Rec.709 weights, and the
  frame's value is the upper median (`v[v.length >> 1]`).
- `evAutoMap()` → `rule.clip_value` + `rule.ev_auto_map`. A clip's value is the upper median of its frames; with two
  frames that is the brighter one. The shoot's middle is the upper median of its clips. A clip's Exposure is
  `Math.round(clamp(log2(mid / clip), ±1) · 100) / 100`, rounded halves-up as JavaScript does.

Frames are the label thumbnails, since they are what the tool stored with each label. Only 12 full TIFFs are on hand,
and they read ~0.5 stop brighter than the thumbnails (thumbnail ≈ 0.905 · TIFF^1.07, fitted on those 12). That
factor cancels in ⇧E's frame, and the report also shows a corrected column. The label histograms match the TIFF's
linear Y on some stills and its encoded Y on others, so they appear only as a diagnostic.

## What's scored

For each shot the report gives the median and p90 of |predicted − target| stops, the bias, the share within ⅓ stop,
Pearson and Spearman r, and sign agreement on shots whose target moves at least ⅓ stop. Predictors:

- no change;
- ⇧E as shipped;
- ⇧E unclamped;
- k × ⇧E, with k fitted leaving the scored shoot out;
- the image median to 18 % grey;
- a sweep of the statistic ⇧E matches (median, log-mean, p10 … p90).

The report also gives a regression of the annotator's middle on the image statistic (slope 1 = full match), the
residual by tag (night, sunset, indoor, day outdoor), and the annotator's own spread between the two stills of one
video.

## Trevor's zips

`/Volumes/T7/Lumina/datasets/hdrvs-trevor/` holds two Dropbox zips from the dataset's author (see the README there).
`20240629.zip` (26.3 GB) contains 8 Atomos ProRes RAW HQ clips: 4128 × 2192 Bayer, 59.94p, about 8 to 17 s each.
It has no labels, no stills and no mapping to the annotated `choice*.tif` stills, so it cannot be scored against the
annotator yet. `20240805.zip` (39.1 GB) was still downloading when this report was written. If either zip, or the
author, maps clips to stills, ⇧E can be measured on the source frames in scene-linear instead of on display-referred
thumbnails.
