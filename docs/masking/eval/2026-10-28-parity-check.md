# Edit-look parity-check — 2026-10-28

`make render && make parity-check` inside `/Volumes/LuminaFactory/repo` (branch
`claude/heal-benchmark` @ main tip).

**Result: PASS.** Worst `|numpy − graph|` / `|numpy − swift|` = **0.0021** (Metal ≡ Swift ≡
numpy on the lookmath ramp). Guard exit 0 in 33 s.

No stage was locked: all `rules-v1.json` stages remain `"locked": false`. Tone stage baseline
committed under `Tools/parity/report/20261028-125315-tone-eval-20261028/` (median 1.61 / p95
6.42 on 5 sweep ARWs — `2026-10-28-parity-tone.md`). Next: `loop.sh` only if held-out personal
stays within +0.05 / +0.10.
