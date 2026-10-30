# 00 · Parity baseline: measure everything, lock what holds

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-parity-baseline` from origin/main.

**Goal.** A current, trusted parity report for every look stage, so every later prompt starts from real numbers. Nothing on main has one today: no stage is `locked`, `Tools/parity/report/` has no run, and Whites/Blacks/Saturation numbers predate the base-match refit.

**Build.**
- Run `make parity` for every stage on origin/main (sweep 1–3 refs, golden set), plus `make parity-personal` (held-out) and the Death Valley tone roots (`parity_personal.py --root parity-dv-tone|parity-dv-unseen`).
- Write `Tools/parity/report/<date>-baseline/` (numbers only) and a table in `RAPIDRAW-PARITY.md`: per slider and position, median/p95, pass/fail vs `criteria.json`.
- Add a "better" scorer to `Tools/parity` (numpy, Linux-testable, tests in `Tools/parity/tests`). It covers isolation (ΔE outside the slider's luma band), hue drift on skin/sky/neutral masks, step evenness (ΔE per slider step), added clipping, and halo (edge overshoot). It runs on any set of renders: Lumina, Lightroom exports, RapidRAW exports.
- Lock (through `loop.sh`) only stages that pass both parity and the held-out tolerance.
- **UI:** none, except one developer-only line. If the facts line or `?debug=1` can show the rules version and the locked stages, add it; otherwise skip.

**Done when.** The report exists, the scorer has tests, every stage is marked pass/fail with numbers, and the gap table cites them.

**Out of scope:** changing any form or coefficient.
