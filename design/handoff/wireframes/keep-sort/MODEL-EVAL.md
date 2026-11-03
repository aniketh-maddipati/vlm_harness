# Model / eval assessment (Import → Sort track)

Honest status for product claims that touch Rec.709 / Log preview on this spine.
Wireframes under this folder are **UI grammar only** — they do not run the Skim transform,
Vision masks, or cull models.

## What was measured vs wireframe-only

| Work | Measured? | Where |
|---|---|---|
| Import / Sort / Export wireframes | No (layout + interaction mock) | `import-wf.html`, `keep-wf.html` |
| Multi-device research notes | Qualitative only | `research_notes/Creator multi device problems/` |
| Skim S-Log3 → Rec.709 vs Final Cut stills | Yes | `~/LuminaEvidence/skim-rec709/` (not in-repo) |
| Cull Auto / near / dust / masks on this PR | No | Unrelated; not changed here |
| SetsPrecompute WIP | No — left stashed, not shipping | `stash@{0}` on this worktree |

## Rec.709 numbers (evidence under `~/LuminaEvidence/skim-rec709/`)

**2026-10-27 large FCP stills eval** (`2026-10-27-fcp-stills-large/`): shipped SL3T table vs FCP Sony S-Log3/S-Gamut3.Cine stills, 15 frames / 5 friend clips at 960×540.

- Overall ΔE2000: **mean 1.44 · p95 2.97 · p99 4.03** (target mean &lt; 2 → meets on this set)
- Per-clip means ~1.27–1.66; worst p95 ~3.5 (C4832)
- Shipped SL3T == 2026-10-09 5-clip refit: **true**

**Held-out caveat (critical):** the 2026-10-27 run scores the **same five clips the table was fitted on**. Leave-one-clip-out was **not** re-run on that pass (“eval only”). The earlier 2026-10-09 refit JSON does record per-clip leave-one-out style `held_out` means ~1.32–1.71 / p95 ~2.33–3.68 — still the same small friend set, not a new shoot corpus.

**Safari canvas check** (`2026-10-09-safari-check/`): Safari-captured preview vs FCP was worse than the Python/table path — about **mean 2.28 / mean-of-p95 ~4.7** (max p95 ~6.3 on C4832). Engine/`calibrate()` gap is still open; do not treat FCP-table ΔE as what the user sees in Safari.

**Not measured on these runs:** other log profiles (S-Log2, HLG, S-Gamut3 non-Cine), full 4K, Chromium canvas pixels, clips beyond the five friend files.

Canonical method notes: `design/handoff/lumina-skim/REC709.md`.

## Safe to claim in UI vs not

**Safe (wireframe / product copy):**

- Log / HDR material gets a **Rec.709 preview** path (default on in Sort).
- Import copy like “Rec.709 for Log”, progressive Ready, keep-only skim — as **intent**, not a measured guarantee.
- “Display-ready · Rec.709” for files already tagged Rec.709/SDR/Normal — labelling, not ΔE.

**Not safe without stronger evidence:**

- “Matches Final Cut” / “colour-accurate” / a single ΔE number in shipping UI.
- Implying Safari/WebKit preview == FCP (Safari check is above the mean&lt;2 target).
- Masks / near / dust / Auto keep quality — **not evaluated on this PR**.
- Phone / drone / HLG / D-Log / etc. parity with Sony S-Log3.Cine results.

## Gaps / next eval

1. **Leave-one-clip-out** (or held-out sixth clip) on the current shipped SL3T; publish mean/p95 with the caveat removed or restated.
2. Re-run **Safari (and Chromium) canvas** ΔE after any `calibrate()` work; gate UI claims on engine pixels, not Python alone.
3. One **new shoot** (different body/lighting) before any App Store / friend-demo accuracy line.
4. Sort DnD / gesture checklist is wired in the wireframe (`keep-wf.html`) — still orthogonal to colour eval; not a measured product claim.

## Wireframe lock-ins (do not re-litigate)

- Import = sensed designation cards up top (click to enable) + hero Drop + **Input dock** — **no Cards & volumes / `sd*` chip strip under Drop**.
- AirDrop / Android / OS drops land in the Input dock; Sort opens a **union chron axis** for every docked input.
- Files not Phone; Kept dock always present; progressive Ready N/M (not a gate); no Match; no vague Memory footer; Rec.709 default for Log.
