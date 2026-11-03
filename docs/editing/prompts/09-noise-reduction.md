# 09 · Noise reduction: luminance and colour

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-noise-reduction` from origin/main.

**Goal.** Luminance and colour NR measured against Lightroom, with colour NR added.

**Now.** `nr` drives the decoder's `luminanceNoiseReductionAmount` (RAW 9 denoise when present); never compared with Lightroom. No colour NR key (AGENTS mentions hiding colour NR under RAW 9; v23 has no such keys).

**Build.**
- **Data:** an ISO ladder (100 → 12800, one static scene, tripod) from the owner, plus Lightroom exports at LuminanceSmoothing 25/50/75 and ColorNR 0/50. This is the sweep 9 request; stop for it. Also score on SID (Sony low light, research only) if available locally.
- **Keys:** `nrc` (colour NR) via `colorNoiseReductionAmount` on the decoder, or a chroma-only bilateral in Oklab if the decoder lacks it on a version.
- **Scores:** noise σ in flat patches vs detail kept (MTF on an edge); colour blotch area.
- **UI:**
  - Effects ▸ Detail: Noise, Colour noise.
  - Under RAW 9, hide the controls that do nothing (`lumina.edit.facts().raw9`) and say why in the row's hover text.
  - Judged in the loupe.

**Done when.** At matched noise σ, detail ≥ Lightroom's on the ladder; colour blotches gone at ISO 6400 at the default.

**Depends on:** none.
