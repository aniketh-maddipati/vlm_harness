# E2 sureness calibration — status 2026-10-28

Factory fits under `/Volumes/LuminaFactory/calibrate-*.json` (DAVIS train cues → val check).

| fit file | target IoU | bad-share cap | fitted sure share | IoU when sure | bad among sure | usable? |
|---|---|---|---|---|---|---|
| calibrate-look-0.6-0.2.json | 0.6 | 0.20 | **1.9%** | 0.69 | 0.20 | no — sure share collapsed |
| calibrate-davis-0.55-0.35.json | 0.55 | 0.35 | **3.6%** | 0.57 | 0.34 | no |
| today's shipped rule (same logs) | — | — | ~71–85% | ~0.48–0.67 | ~0.36–0.50 | sure share OK; bad-sure far above 5% |

**Gap:** no threshold rule yet hits bad-sure ≤5% without collapsing sure share below a usable strip.
Next: add cues (look distance already tried; rivals/start/jump) or a tiny logistic on train only, then change
`SkimFollow.sureness` in a dedicated PR. Do not ship a 2%-sure strip.
