# Broader masking baselines — status 2026-10-28

## Ready on factory (converted, prompts + labels)

| set | path | clips (prompts) | label PNGs | scored run |
|---|---|---:|---:|---|
| DAVIS 2017 val | `masklab-davis/` | 61 | (in labels/) | **yes** — see `2026-10-28-tracking-baselines.md` |
| DAVIS train | `masklab-davis-train/` | — | — | calibrate / train only |
| VOST | `masklab-vost/` | 162 `.mov` | 10 993 | smoke only (3 clips) |
| LaSOT | `masklab-lasot/` | 82 | 20 532 | **not yet** (clips are long; airplane-1 alone is 2788 frames) |
| VIPSeg / clicks / RORD-50 | `datasets/` | — | — | NoC90 / class IoU not written |

## VOST smoke (2026-10-28)

`MASKLAB_TRACKERS=skim MASKLAB_FRAMES=60` on three tagged hard clips
(`6503_apply_paint_1`, `1207_break_garlic_1`, `7202_clean_car_1`) →
`/Volumes/LuminaFactory/masklab-vost-smoke/runs/20261028-130207/`.

| tracker | clips | J&F | fps | sure share |
|---|---:|---:|---:|---:|
| skim | 3 | **0.200** | 13.7 | 42% |

Per clip IoU: clean_car 0.387, apply_paint 0.183 (lost from box — no shape under prompt),
break_garlic 0.048. VOST's shape-change / occlusion set is much harder than DAVIS; full 162-clip
pass still needed before quoting a VOST number in STATE.

## DAVIS snapshot (already published)

| tracker | J&F | fps |
|---|---:|---:|
| skim | 0.435 | 14.6 |
| skim-prompted | 0.609 | 12.0 |
| edgetam-apple-click | 0.755 | 9.0 |
| edgetam | 0.788 | 8.8 |
| sam2.1-small | 0.820 | 1.9 |

## Next runs (not started 2026-10-28)

```bash
# after masklab-skim / masklab-track build
MASKLAB_EVIDENCE=/Volumes/LuminaFactory/masklab-vost \
  MASKLAB_TRACKERS=skim,skim-prompted \
  MASKLAB_FRAMES=180 \
  bash Tools/masklab/run-tracker-test.sh

MASKLAB_EVIDENCE=/Volumes/LuminaFactory/masklab-lasot \
  MASKLAB_TRACKERS=skim \
  MASKLAB_FRAMES=300 \
  bash Tools/masklab/run-tracker-test.sh
```

Gate each with `Scripts/test_guard.py`. Full LaSOT without `MASKLAB_FRAMES` is a
multi-hour job. VIPSeg class IoU and NoC90 on COCO-MVal / GrabCut / Berkeley remain
open after those.
