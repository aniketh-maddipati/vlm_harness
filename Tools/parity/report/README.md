# Parity reports

`parity.py` writes one folder per run here: `<date>-<label>/report.md` and `summary.json`, numbers
only (heatmaps and anything with photo content go to `~/LuminaEvidence/parity/report/`).
`latest.json` points at the last run; `locked.json` records the median / p95 each stage was locked
at, which `loop.sh` uses to detect a regression of more than 0.2 median.

No run has been recorded yet: the Lightroom sweep and `make parity` need the photographer's Mac
(see `Tools/parity/README.md`).
