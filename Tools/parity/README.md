# Parity harness: Lumina's Edit look vs Lightroom Classic

The roadmap's Prompt 2. Lightroom's basic sliders are the behaviour reference; this folder
measures how far `LookPipeline` (the app's Core Image graph, `Lumina/Sets/Look/`) is from them
in ΔE2000 and drives the fit, stage by stage. The criteria are in `criteria.json` and are edited
only by a human.

```
golden ARWs (~/LuminaEvidence/parity/golden)       golden.json (metadata only, committed)
        │                                                     │
        ▼  Lightroom Classic + lr_sweep.lrdevplugin           │
~/LuminaEvidence/parity/refs/*.tif  ──► import_refs.py ──► refs.json
        │                                                     │
        ▼  parity.py  ──► lumina-render batch (Core Image) ──► ~/LuminaEvidence/parity/render/
        │
        ▼  delta_e.py per pair ──► Tools/parity/report/<date>/report.md (numbers, committed)
                                   ~/LuminaEvidence/parity/report/<date>/ (heatmaps, stays on the Mac)
        │
        ▼  loop.sh: fit.py → rules-v1.json → make parity again → lock or BLOCKED.md
```

## What runs where

| Piece | Linux / CI | The Mac |
|---|---|---|
| `Lumina/Sets/Look` maths and look-string tests (`LookStringTests`, `LookMathTests`) | ✓ CI (macOS job and the Linux Swift sandbox) | ✓ |
| `LookPipelineTests` (the real graph on synthetic ramps) | ✓ CI macOS job | ✓ |
| `lumina-render` build | ✓ CI macOS job | ✓ |
| `delta_e.py`, `lookmath.py`, `import_refs.py`, `parity.py` tests | ✓ CI (ubuntu) | ✓ |
| The Lightroom sweep | ✗ | Lightroom Classic 13+ |
| `make parity` (renders + report) | ✗ (Core Image) | ✓ |
| `loop.sh` | ✗ | ✓ |

## One-time setup on the Mac

```bash
python3 -m pip install -r Tools/parity/requirements.txt
mkdir -p ~/LuminaEvidence/parity/{golden,refs,render,report}
```

### 1. The golden set (50 ARWs)

Copy the photos into `~/LuminaEvidence/parity/golden/` (they never enter the repo) and record
each one's metadata and category:

```bash
python3 Tools/parity/golden.py add ~/LuminaEvidence/parity/golden/DSC01234.ARW --tag backlit
python3 Tools/parity/golden.py check      # coverage of: card backlit blown-sky iso12800 tungsten mixed snow foliage under2 over2 highkey
```

`golden.py add` reads body, ISO, exposure and EV bias from the ARW itself. Commit `golden.json`.

### 2. The Lightroom sweep

1. Lightroom Classic ▸ File ▸ Plug-in Manager ▸ Add ▸ choose `Tools/parity/lr_sweep.lrdevplugin`.
2. Import the golden folder into a catalog (Add, in place), select all 50 photos in Library.
3. Library ▸ Plug-in Extras ▸ **Lumina parity sweep…** ▸ Everything ▸ pick `~/LuminaEvidence/parity/refs`.
4. Wait. About 150 exports per photo; ~4 min per photo on an M1, so start it before bed. It skips
   files that already exist, so it can be stopped and resumed.

What it exports, per photo (`Sweep.lua`):
- `<stem>__base.tif`: profile **Adobe Color**, every basic and detail setting reset, capture
  sharpening **0** (Lightroom's RAW default is 40; the Sharpness sweep starts from nothing and
  the base compares the two RAW developments alone). Colour noise reduction stays at Lightroom's
  default 25.
- `<stem>__asshot.json`: Lightroom's as-shot Temperature/Tint. Apple's RAW pipeline estimates
  Kelvin differently, so `parity.py` applies Lightroom's *mired delta* to Apple's as-shot rather
  than the absolute Kelvin.
- `<stem>__<Slider>__<value>.tif`: one slider at a time, 10 positions each, for Exposure,
  Temperature, Tint, Contrast, Highlights, Shadows, Whites, Blacks, Vibrance, Saturation,
  Clarity, Sharpness (the positions are listed at the top of `Sweep.lua`).
- `<stem>__comboNN.tif` + `.json`: 20 random three-slider combinations, seeded per photo.
- All: 16-bit **ProPhoto RGB** TIFF, uncompressed, 2048 px long edge, no output sharpening.

If the SDK refuses something (an older Lightroom without `applyDevelopSettings`'s third
argument, say): the fallback is a **watched-folder** run. Make a develop preset per slider
position (Develop ▸ Presets ▸ + ▸ tick only that slider), apply each preset to the whole
selection and export with the preset name in the file name (`{{custom_token}}` =
`__Exposure__-2`). Same names, same result; `import_refs.py` doesn't care how the files got there.

Then index them:

```bash
python3 Tools/parity/import_refs.py ~/LuminaEvidence/parity/refs      # → ~/LuminaEvidence/parity/refs.json
```

### 3. Build the renderer and run

```bash
make render                    # swift build -c release --package-path Tools/parity/lumina-render
make parity                    # everything in refs.json → report
make parity STAGE=exposure     # one stage's sliders (plus base)
make parity SLIDER=Highlights  # one slider
make parity LIMIT=5            # first five images, a quick look
make parity-check              # lumina-render ramp + lookmath.py --check: Metal ≡ Swift ≡ numpy
make parity-test               # the Python tests (also run on Linux CI)
```

`make parity` prints the report and leaves `Tools/parity/report/<date>-<label>/report.md` +
`summary.json` (numbers only, commit them) and `~/LuminaEvidence/parity/report/<date>-<label>/`
with the heatmaps of the worst five pairs. `Tools/parity/report/latest.json` points at the last run.

### 4. The refinement loop

```bash
bash Tools/parity/loop.sh                 # every unlocked stage, in rules order
bash Tools/parity/loop.sh tone            # one stage
```

For each stage: `make parity STAGE=<id>`; if the stage's sliders meet the criteria it is marked
`"locked": true` in `rules-v1.json` and committed as `parity/<stage>: locked median X p95 Y`.
Otherwise `fit.py --stage <id>` proposes coefficients (Nelder–Mead over the numpy mirror,
objective = mean ΔE + p95 penalty), the change is verified with a real render, kept only if the
median improved and no locked stage regressed by more than 0.2, and one paragraph is appended to
the report. After 12 iterations without meeting the criteria the loop writes `BLOCKED-<stage>.md`
with the residual pattern and moves on. The loop never edits `criteria.json`, the golden set, or
a locked stage.

The loop is meant to be driven by an agent (or you) reading `report.md` between iterations:
`fit.py` moves coefficients; changing a stage's *form* (its kernel in `LookKernels.swift`, the
matching function in `LookMath.swift` and `lookmath.py`) is a code change with the ramp tests as
the guard.

## Files

| File | What |
|---|---|
| `lumina-render/` | SwiftPM tool around `LookPipeline` (`render`, `batch`, `info`, `ramp`) |
| `delta_e.py` | ΔE2000 per pair, regions, heatmaps; `--selftest` |
| `lookmath.py` | numpy mirror of `LookMath.swift`; `--check ramp.json` |
| `import_refs.py` | sweep TIFFs → `refs.json` |
| `parity.py` | the run: looks, renders, measurements, `report.md`, `summary.json` |
| `fit.py` | fit one stage's coefficients |
| `loop.sh` | the stage-by-stage loop, lock and commit |
| `golden.py`, `golden.json` | the golden set's metadata |
| `criteria.json` | the roadmap's numbers; humans only |
| `lr_sweep.lrdevplugin/` | the Lightroom plug-in |
| `default_ab.md`, `ab.html` | the blind A/B of the default render (Phase E) |
| `tests/` | `python3 -m unittest discover -s Tools/parity/tests` |
| `report/` | committed reports (numbers only) |

## Reading a report

- **Per slider**: pooled ΔE over every pair of that slider (each pair contributes the same
  number of sampled pixels). `pass` is the singles criterion.
- **Regions**: median ΔE where the reference's L* is < 25 / 25–75 / > 75, and inside the skin
  gate (hue 15–55°, chroma 8–45, L* 30–85).
- **By position**: where in the slider's range the error grows.
- **Error by L* decile**: the shape of the residual across the tone scale; error climbing above
  L* 80 says "highlight roll-off", error in the bottom deciles says "black point or toe".
- **Worst five**: open their heatmaps under `~/LuminaEvidence/parity/report/…/heatmaps`.
