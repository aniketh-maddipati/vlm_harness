# Healing benchmark (video Remove)

Numbers only. Footage and healed frames stay on the T7
(`/Volumes/LuminaFactory/heal/`). Shippable healers may enter the app later; ProPainter is
reference-only (non-commercial) and is never bundled.

## Method

- **Holes**: `Tools/masklab/make_holes.py` on DAVIS 2017 val (30 clips), both `moving` (object
  track as the hole) and `--still` (fixed box). Truth = the original DAVIS frames.
- **Healers**:
  - `skim-plate` — Skim's own tripod Remove (`SkimPlate` median clean plate) via
    `Tools/masklab/heal/masklab-heal` (compiles against `SkimPlate.swift`).
  - `lama` — big-lama per frame through IOPaint (Apache-2.0, shippable).
  - `migan` — MI-GAN per frame through IOPaint (MIT, shippable).
  - `flow-lama` — Farneback flow fill from neighbours (`Tools/masklab/flow_fill.py`), then LaMa
    on what's left (shippable parts only).
  - ProPainter — run for reference only; not in the table below as a shipping candidate.
- **Scores**: `Tools/masklab/heal_score.py` → PSNR / SSIM inside the hole, flicker, seam; fps from
  wall time. Table built with `Tools/masklab/heal_table.py`.

## DAVIS 2017 val (30 clips) — 2026-10-23/26 factory run

| healer | holes | clips | PSNR | p10 | SSIM | p10 | flicker | p90 | seam | p90 | fps |
|---|---|---|---|---|---|---|---|---|---|---|---|
| flow-lama | moving | 30 | 20.17 | 14.14 | 0.848 | 0.770 | 1.28 | 1.73 | 1.03 | 1.14 | 0.9 |
| lama | moving | 30 | 21.56 | 15.77 | 0.850 | 0.758 | 1.24 | 2.11 | 1.02 | 1.09 | 1.2 |
| migan | moving | 30 | 19.57 | 14.62 | 0.821 | 0.715 | 1.48 | 2.53 | 0.97 | 1.02 | 1.8 |
| skim-plate | moving | 30 | 14.64 | 10.96 | 0.739 | 0.615 | 0.00 | 0.00 | 0.48 | 0.61 | 23.9 |
| lama | still | 30 | 21.49 | 15.76 | 0.854 | 0.759 | 1.03 | 1.18 | 1.02 | 1.11 | 1.3 |
| migan | still | 30 | 19.66 | 13.92 | 0.827 | 0.716 | 1.16 | 1.42 | 0.97 | 1.02 | 2.7 |
| skim-plate | still | 30 | 12.65 | 10.70 | 0.744 | 0.641 | 0.00 | 0.00 | 0.00 | 0.00 | 27.0 |

Contact sheet: [`checkpoints/09-healing-davis.jpg`](checkpoints/09-healing-davis.jpg)
(hole · skim-plate · lama · migan · flow-lama · truth; 3 frames × 4 clips).

### Reading the table

- **LaMa** wins PSNR/SSIM on both moving and still holes among shippable healers (~21.5 dB, SSIM ~0.85).
- **flow-lama** is close on moving (20.2 dB) but slower (~0.9 fps) — useful when real background
  pixels are visible in neighbours; still loses to plain LaMa on this synthetic-hole set.
- **MI-GAN** is faster (~1.8–2.7 fps) but ~2 dB behind LaMa and flickers more.
- **skim-plate** is an order of magnitude faster (~24–27 fps) and has essentially zero flicker
  (it reuses the clip's own grain), but PSNR is low on these holes because the synthetic mask often
  covers background the plate never sees, and on `moving` the camera/subject motion trips
  `SkimPlate.refusal`. Keep it for **tripod** Remove; do not use it as the moving-camera healer.

## Other sets (status 2026-10-28)

| set | status |
|---|---|
| RORD-50 (real before/after) | Frames / masks / gts staged under `/Volumes/LuminaFactory/heal/rord/`; healer scores not yet written |
| SD car clips + C0069 (no truth) | Frames / holes / track under `/Volumes/LuminaFactory/heal/sd/`; flicker/seam/leak scoring pending |

## Shipping choice (for moving-camera Remove)

**LaMa (big-lama) in Core ML**, same ProRes 4444 straight-alpha patch path as tripod Remove.
Keep `SkimPlate` when `SkimPlate.refusal` is nil (steady camera, background visible). flow-lama stays
a lab option if neighbour fill proves better on real SD removals once those scores land.

## How to re-run (factory image)

```bash
source /Volumes/LuminaFactory/env.sh
# skim-plate binary
swiftc -O -o /Volumes/LuminaFactory/build/heal/masklab-heal \
  Lumina/Sets/Look/LookMasks.swift Lumina/Sets/Video/SkimPlate.swift \
  Tools/masklab/heal/Stub.swift Tools/masklab/heal/main.swift
bash /Volumes/LuminaFactory/scripts/heal-run.sh davis lama moving
python3 Tools/masklab/heal_table.py /Volumes/LuminaFactory/heal/davis/scores \
  --out /Volumes/LuminaFactory/heal/davis/out --md
```
