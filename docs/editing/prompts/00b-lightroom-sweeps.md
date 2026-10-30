# 00b · All Lightroom sweeps in one owner session

Run the agent loop in `docs/editing/prompts/LOOP.md` (setup, checks and finish only: no look change).
Branch `claude/edit-lightroom-sweeps` from origin/main.

**Goal.** One batch of Lightroom CC presets covering every feature prompt, so the owner opens
Lightroom once instead of ten times.

**Build.**
- Add sweeps 4–13 to `Tools/parity/lr_cc_sweep.py` as `presets --sweep N`. Use the same base as
  sweep 1, which already pins Texture, Clarity, Dehaze, Parametric, vignette, grain and lens to 0.
  Each sweep is defined in its feature prompt:
  - 4: Texture / Clarity / Dehaze (02, 03)
  - 5: HSL + B&W mix (04)
  - 6: Colour grading (05)
  - 7: parametric curve (06)
  - 8: sharpening, scored at 100 % (08)
  - 9: noise reduction on an ISO ladder (09). **The ladder is a capture the owner makes**; write its
    shot list.
  - 10: lens CA / distortion (10)
  - 11: vignette (12)
  - 12: grain (13)
  - 13: Adaptive Sky / Subject masks with one local (14)
- Before writing sweep 13, ask the owner to save one masked preset from the Lightroom UI and send the
  `.xmp`. Copy its structure; whether hand-written mask XMP imports is unverified.
- Photo choice per sweep: a script picks photos from the 156 Death Valley pool plus the portraits set
  (hue content for 5, people for 13, architecture for 10, flat frames for 12), and writes the list.
- `ingest` learns every new sweep: naming from embedded XMP, `refs.json` rows. Tests go in
  `Tools/parity/tests`; `make parity-test` must pass.
- Write `docs/editing/prompts/SWEEPS-OWNER.md`, a one-page checklist for the owner:
  - which preset groups to install
  - which photos to apply each group to
  - export settings (full size where a sweep is scored at 100 %, "All metadata")
  - where to put the exports
  - the one command to run afterwards

**Done when.** The presets are written, the checklist exists, and ingest is tested on synthetic XMP.
Then stop and hand the checklist to the owner.
