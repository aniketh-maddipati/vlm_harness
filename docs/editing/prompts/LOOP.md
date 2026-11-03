# The agent loop every feature prompt runs

One agent, one feature, one branch, one PR. The feature prompt says *what*; this file says *how*.
Read it in full before starting.

## 0. Read first
- `AGENTS.md`: especially "The rule", "Parity", "Rules that bite", "Running tests without
  disturbing the Mac"
- `docs/editing/RAPIDRAW-PARITY.md`: gap table, the "better" scores, the hands-on rule
- `Tools/parity/README.md` if the feature touches the look
- the feature's own design doc, if the prompt names one (e.g. `COLOUR-GRADING.md`)

## 1. Set up
- New worktree and branch from **origin/main** (`git fetch` first): `claude/edit-<feature>`.
- Run the baseline before changing anything, and keep the numbers:
  - `make parity-test`
  - `node Tests/web/plumbing-harness.mjs`
  - the stage's `make parity STAGE=<id>` if it has a stage and the data exists
- RapidRAW (`https://github.com/aniketh-maddipati/RapidRAW`, AGPL): **ideas only, cited in a
  comment, never code.**

## 2. The loop (repeat until "Done when" holds; at most 5 rounds of form/fit changes)

1. **Maths.**
   - One form, in all three copies: `Lumina/Sets/Look/LookMath.swift` (reference),
     `LookKernels.swift` (Metal), `Tools/parity/lookmath.py` (numpy).
   - Wire it in `LookPipeline.swift`; keys in `LookString.swift`.
   - Forms in code, numbers in `rules-v1.json`.
   - Key at rest = identity; the stage stays out of the graph at reset (`Look.runs`).
   - Grey ramps stay monotonic and grey (white balance and intentional tints excepted, and
     tested as such).
2. **Tests.**
   - Ramp, identity and range tests in `LookMathTests`, `LookPipelineTests` (Metal ≡ LookMath),
     `LookStringTests` (strings the page writes).
   - Run `bash Tests/linux-swift/run.sh` and `make parity-check`.
3. **Page UI.**
   - Edit `design/handoff/lumina-cull/Lumina Edit v23.dc.html` (and `lumina-core-v4.js` if the core
     writes the key). Never edit `Lumina/Sets/Web` directly.
   - Sync with `bash Scripts/sets_sync_ui.sh`; `python3 Scripts/page_bytes.py` must print 12 / 12.
   - The project agent `page-ui-editor` knows the page; use it for the UI part if that helps.
   - **Hands-on rule:** every new slider gets its on-photo gesture where one makes sense, with the
     existing grammar (drag; ⇧ fine; ⌥ finer; esc cancels; double-click resets; click the number to
     type; `dragStart` / `dragEnd` emitted like `vigDown` / `histDown`).
   - **Keys:** before taking a key, grep the page's key handler (`c==='Key…'`) and `static HELP`. Taken now: A C H N Q R S T V W X Y Z, 0, 2, \\, `,` `.` `[` `]` `=`. The feature prompts reserve J (heal), K (clipping), B (split), U (upright), O (mask overlay), L (outcome tiles), F (flip in Crop). If one clashes, pick another and say so.
   - The help sheet (`static HELP`) lists every new key and gesture.
   - Section reset, the `•` changed dot, ⌘C/⌘V and "same as last" all carry the new keys.
   - **`plumbing.js` supplies data and behaviour, never UI.** New keys reach the Mac through the
     look string. If plumbing must translate a key (as with `wbref`, `shp:40`), add it to `macLook`
     and test it in `Tests/web/plumbing-harness.mjs`.
4. **Check** (the checks CI will run):
   - `(cd design/handoff/lumina-cull && node lumina-core-v4.test.mjs)`
   - `node Tests/web/plumbing-harness.mjs`
   - `node Tests/web/parity.mjs`
   - `python3 Scripts/trust_check.py`
   - On the Mac: `python3 Scripts/ci_changes.py $(git diff --name-only origin/main...)` →
     `xcodebuild … -only-testing:LuminaLogicTests/<the classes it names> test`, then
     `bash Scripts/probe.sh smoke`.
   - A screen that changes on purpose shows up in `probe.sh screens`. **Do not re-record
     references**: that waits for the owner's approval.
5. **Measure.**
   - Parity vs Lightroom, for stages that have a Lightroom twin: per-slider median ≤ 2.0 and p95 ≤ 4.0
     (combos 3.0 / 5.0), `Tools/parity/criteria.json`.
   - Held-out set (`make parity-personal`): at most +0.05 median / +0.10 p95 per change, and never
     more than +0.10 / +0.25 above 2.32 / 7.82. A change outside that is rejected, not argued.
   - The "better" scores from `RAPIDRAW-PARITY.md` that apply to the feature: isolation, hue
     stability, even steps, no artefacts, repeat accuracy. Report them for Lumina and, where the
     owner has exports, for Lightroom and RapidRAW too.
   - `LUMINA_EDIT_DIR=… bash Scripts/probe.sh edit` if the stage runs on the canvas: p95 ≤ 16 ms,
     0 dropped, canvas vs export ΔE ≤ 0.5. A screen-owning run: one at a time, never looped.
6. **Show the owner.**
   - Push the page into the running builds with the project agent `hot-build-pusher` (Lumina Dev /
     Safari :8765). Don't start new servers.
   - Send a before/after screenshot or a short recording with `SendUserFile`.
7. **Decide.** Pass → step 3 of "Finish". Fail → change one thing (form *or* coefficients, never
   both at once), go back to 1.
   - Coefficients: `bash Tools/parity/loop.sh <id>` / `fit.py`.
   - A locked stage is not touched to compensate for another.

## 3. When to stop and ask (end the turn with one question)
- **Lightroom data is missing.**
  - Add the sweep to `Tools/parity/lr_cc_sweep.py` as a new `presets --sweep N` (rows in its tables,
    same base), write the presets, and tell the owner exactly what to apply and export:
    group name, number of photos, export settings with "All metadata".
  - Then stop. Resume with `lr_cc_sweep.py ingest <exports>`.
- **A ruling is needed:** fitting on the owner's own edits, a new entitlement, a bridge op or a model
  file (each also needs a row in `docs/release/TRUST.md`), a key name the page and Skim would share,
  a parity-vs-better conflict.
- **After 5 rounds without "Done when":** report the best numbers and what limits them; don't keep going.
- **The kill switch:** `~/LuminaEvidence/.tests-off` exists → say what you wanted to run, and stop.

## 4. Finish
1. Update the docs:
   - `docs/editing/RAPIDRAW-PARITY.md`: the feature's row, with the measured numbers and the date.
   - `AGENTS.md`: only if a rule changed.
   - A `Log` line in `docs/editing/LEARNED-LOOKS.md` only if the feature touches repeat or learned
     looks.
2. `rules-v1.json`: lock the stage only if it passes, and only through `loop.sh`.
3. Hand off to the project agent `pr-shepherd`: local checks, one push, one PR into main, CI
   reported. **Never merge** unless the owner says so.
4. Final report, terse: what landed, numbers before → after, what is not done, PR link.
