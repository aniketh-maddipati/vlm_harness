# Culling eval through the app, and candidate signals

`Tools/culleval` is the culling eval: grouping and keeps against what was shot and kept, offline, in
headless Chromium (`make culleval`). This folder holds two things it does not do:

- **The same question through the real app.** `dump-decisions.json` is a probe scenario: the page and
  the native reader open a folder in WKWebView (read-only) and every photo's row, stack, rank, flags
  and suggested keep are dumped. `score.py` scores that against picks (RAWs a finished Lightroom
  export names, by `crs:RawFileName` + capture second): recall of the suggested keeps, each flag
  word's false alarms on picks, burst rank against chance.
- **Signals the page doesn't have.** `signals.swift` measures each RAW's embedded preview on the Mac
  (Vision face capture quality, landmarks, saliency, aesthetics; sharpness by region), and
  `rank_signals.py` asks of each one, inside a row or a run of retakes: does it put the pick above
  the frames passed over? (pair accuracy with a bootstrap interval, top-1 against chance, and a
  combined model scored on held-out days).

```bash
LUMINA_CULL_DIR=<shoot> Tools/LuminaProbe/.build/release/lumina-probe run Tools/culling-eval/dump-decisions.json --out <out>
exiftool -csv -FileName -RawFileName -DateTimeOriginal <exports…> > exports.csv
python3 Tools/culling-eval/score.py --exports exports.csv --out report.md <out>/dump-decisions/decisions.json
swiftc -O Tools/culling-eval/signals.swift -o signals && ./signals list.txt signals.jsonl
python3 Tools/culling-eval/rank_signals.py --exports exports.csv --signals signals.jsonl <out>/dump-decisions/decisions.json
python3 -m unittest discover -s Tools/culling-eval/tests
```

Until DESIGN-ASKS Prompt 2 A lands, the page reads no drive data from an ARW, so the dump holds
almost no camera bursts: the burst table in `score.py`'s report says nothing yet. Photos, labels
and reports stay out of the repo (`~/LuminaEvidence/culling-eval`); the reports name no files.
