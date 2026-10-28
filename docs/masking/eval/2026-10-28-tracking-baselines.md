# Tracking baselines (DAVIS 2017 val) — published 2026-10-28

Source runs under `/Volumes/LuminaFactory/masklab-davis/runs/20261023-sam2/`
(`score-all.json`, `score-edgetam.json`, `score-edgetam-apple.json`). M4 Pro.

| tracker | J&F | fps | notes |
|---|---|---|---|
| vision-box | 0.443 | 43.1 | |
| vision-instance | 0.498 | 42.2 | at Vision oracle |
| vision-oracle | 0.497 | 28.5 | ceiling on Vision instances |
| skim (Vision follow) | 0.435 | 14.6 | ships today |
| skim-prompted | 0.609 | 12.0 | ships (#311); sure ~85%, IoU\|sure ~0.67 |
| **edgetam-apple-click** | **0.755** | **9.0** | one click → EdgeTAM (app flow target ≥0.75) |
| edgetam (mask-start) | 0.788 | 8.8 | Apache-2.0, shippable |
| sam2.1-small | 0.820 | 1.9 | too slow for live; refine-on-export candidate |
| sam2.1-large | 0.843 | 1.2 | reference only |

**Gap to live target (≥0.75 J&F @ ≥15 fps):** EdgeTAM already clears J&F on the clicked path
but is at **9 fps**. Next: Core ML conversion keeping video memory (`/Volumes/LuminaFactory/ref/EdgeTAM/coreml/`
has conversion scaffolding), optionally run EdgeTAM only on shaky/lost stretches.

**E2 sureness:** factory `calibrate-*.json` fits that hit ≤20–35% bad-sure also collapse sure share
to ~2–4% (unusable). Still open: a rule that keeps usable sure share with bad-sure ≤5%.

**Broader sets:** VOST / LaSOT prompts+labels exist under
`/Volumes/LuminaFactory/masklab-{vost,lasot}/`; scored runs not yet written. VIPSeg / clicks
archives are in `datasets/`.
