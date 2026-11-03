# Stills editing: parity with RapidRAW (plan, 2026-10-29)

Compared: RapidRAW `a82251f` (fork of CyberTimon's, AGPL) vs this worktree (`main@4279886a`, 5 behind
origin/main; dehaze only on `claude/dehaze-stage`). RapidRAW is AGPL: **ideas only, cited in a
comment, never code** (AGENTS.md). Companion note: `LEARNED-LOOKS.md` (repeating edits across many
photos, learned starting points).

Owner's goal (2026-10-29): people want AI to **repeat their edit across many photos accurately**, plus
hands-on control, **like a physical print you move with your hands**, both by hand and automatically.
The order below follows that goal, not RapidRAW's feature count.

## Where Lumina stands

- **Quality first, features second.**
  - Measured 2026-11-03 (`Tools/parity/report/20261029-baseline/`, table below): only Contrast (1.52 / 3.90,
    5 photos) and the combos (1.55 / 4.52) pass. Every other slider misses p95 ≤ 4.0, worst at the ends of
    the range: Blacks −50 p95 10.9, Highlights −100 9.0, Exposure +2 6.3, Shadows +100 6.8.
  - The held-out set is at **2.38 / 8.10**, past the 8.07 cap on main (7.93 on 2026-10-02). Nothing is locked:
    no stage passes parity and the held-out tolerance together.
  - Clarity, sharpening, the HSL mixer, the curve regions and the vignette strength all run on
    default coefficients (round numbers).
- **UI and native disagree.**
  - Clarity and Vibrance render natively but have no slider.
  - Masks: v23 has a Masks panel since 2026-10-30 (prompt 14): left rail of layers, click to lift,
    hold O, local sliders, invert / opacity / in-out / solo.
- **Profile.** The default render is `prof:camera`, fitted to the camera JPEG. The Lightroom numbers
  apply only to `prof:adobe`. Decide which one parity means.

## Gap table

Effort is rough agent-days per item, including the three copies of the maths (LookMath, LookKernels,
lookmath.py), tests and a Lightroom sweep where one applies.

| Area | RapidRAW | Lumina now | To reach parity | Days |
|---|---|---|---|---|
| Basic tone | exp, brightness, con, hl/sh/wh/bl; AgX tonemap | ✓ fitted; con passes, ev/hl/sh/wh/bl fail p95 (5.2–5.9) | Highlights form rework; refit wh/bl on new base; ev's highlight clipping | 4 |
| Clarity / Texture / Dehaze | clarity, structure, centré, dehaze | clarity native, unfitted, no slider; dehaze unmerged | expose + fit clarity; add texture (small-radius local contrast); merge dehaze | 4 |
| Vibrance / Saturation | ✓ | sat ✓; vib no slider | add slider | 0.5 |
| HSL 8 bands | ✓ | ✓ page + native, unfitted | HSL sweep, fit | 2 |
| Colour grading wheels (3 + global, blend, balance) | ✓ | ✗ | page wheels + stage + fit; full design in `COLOUR-GRADING.md` (~12 d incl. hands-on + agent) | 4 |
| Colour calibration (primaries) | ✓ | ✗ | optional; low demand | 2 |
| B&W mixer | via HSL | chroma → 0 only | luminance-by-hue mixer | 1 |
| Curves | point luma/RGB, parametric | ✓ point RGB+R/G/B, regions (unfitted) | fit regions; luma-only mode | 1 |
| Sharpen (amount, threshold/masking) | ✓ | amount only, unfitted | radius/detail/masking + fit at 100 % crops | 2 |
| Noise reduction | shader luma+chroma; BM3D; NIND AI | luma via decoder (RAW 9 denoise) | colour NR key; measure on an ISO ladder | 2 |
| Lens: distortion, TCA, vignetting | lensfun DB | vignetting from Sony EXIF only | distortion + CA from Sony EXIF (`DistortionCorr`, `ChromaticAberrationCorr`), no lensfun licence question; defringe later | 4 |
| Transform / upright / perspective | sliders + guided lines → homography | crop, straighten, 90° | perspective keys + Vision horizon/rectangles auto-upright; flip | 4 |
| Vignette | amount, mid, round, feather | ✓ + keep highlights; unfitted | fit; **per-corner pull (beyond RR)** | 1 + 2 |
| Grain | amount/size/roughness | ✗ | stage; score by spectrum, not ΔE | 2 |
| Glow / halation / flares | ✓ | ✗ | skip for now (creative extras) | — |
| Masks: AI subject/sky/person | SAM click, U²-Net sky, Depth Anything | ✓ Vision + **Masks panel** (2026-10-30): click a subject to lift it, rail in/out/⇧-solo, O overlay, `inv`/`amt`/`off` per layer; ids by role (`person-1` = most prominent) so a carried look re-finds them; canvas ≡ export with masks median ΔE 0.71–0.78 (gate 1.0, `probe.sh scenarios edit-masks`, 2 ARWs) | sky not found on a Death Valley frame (no sky label); Lightroom Adaptive Sky/Subject shape (sweep 13) not measured: exports pending | 4 |
| Masks: brush, linear, radial | ✓ | ✗ | three mask kinds + feather; stroke storage in look string | 5 |
| Masks: colour / luma range, depth | ✓ | ✗ | range from the pixel under the pointer; depth needs a model (Depth Anything V2 Small, Apache-2.0: verify) | 3 + 3 |
| Local adjustment set | almost everything | ev, con, hl, sh, wh, bl, vib, sat, clr | add wb, curve, HSL, nr, sharpen inside masks | 3 |
| Heal / clone / remove | clone, Poisson heal, LaMa erase, liquify, skin brush | automatic dust only | manual heal/clone reusing LookDust's clone + Poisson; AI remove (LaMa CoreML, Apache-2.0); skip liquify | 6 |
| Presets / LUTs | presets, XMP import, .cube/.3dl/HALD | copy/paste, same-as-last, curve presets | named presets (look strings in a file); `.cube` through CIColorCube; Lightroom XMP import extends `import_lr_edits.py` | 3 |
| Before/after, clipping | clipping view | hold `\`; histogram clip hovers | split view; on-image clipping overlay | 1.5 |
| Export | JPEG/PNG/TIFF/WebP/JXL/AVIF, resize, watermark | sRGB JPEG/TIFF/PNG | P3/ProPhoto + 16-bit; resize; HEIF | 2 |
| Out of scope | panorama, HDR merge, focus stack, negatives, generative replace (network: breaks TRUST) | — | not parity work for Edit | — |

Sum: about **70–80 agent-days**. About a third of it is quality (fits, sweeps, forms), not new features.

## Measured: per stage (2026-11-03)

origin/main f3b95414, `prof:adobe`, ΔE2000 median / p95 vs Lightroom CC; sweeps 1–2 are 5 photos, Death Valley
(DV) the unseen half without the 3 photos whose crop or masks the presets kept. Full numbers:
`Tools/parity/report/20261029-baseline/README.md`. Skim: Skim's display-referred look (`LOOK-BEGIN`) on
Lightroom's base export, same positions (`skim_parity.py`); Temperature / Tint at Skim's best-matching value.

| stage | slider | Lumina (sweep) | Lumina (DV) | Skim (sweep) | pass |
|---|---|---|---|---|:---:|
| exposure | Exposure | 1.31 / 5.18 | – | 3.28 / 12.25 ✗ | ✗ |
| whiteBalance | Temperature | 2.02 / 5.49 | – | 3.67 / 15.75 ✗ (range ends at ±100) | ✗ |
| whiteBalance | Tint | 1.35 / 4.04 | – | 2.16 / 8.78 ✗ | ✗ |
| whitesBlacks | Whites | 1.73 / 4.59 | – | 1.16 / 5.32 ✗ | ✗ |
| whitesBlacks | Blacks | 1.43 / 5.57 | – | 1.49 / 5.08 ✗ | ✗ |
| tone | Highlights | 1.50 / 5.91 | −100: 1.96 / 4.23 | 1.50 / 8.54 ✗ | ✗ |
| tone | Shadows | 1.51 / 5.20 | +100: 2.06 / 5.90 | 1.66 / 7.67 ✗ | ✗ |
| contrast | Contrast | 1.52 / 3.90 | – | 1.24 / 3.57 ✓ | ✓ (5 photos; not locked) |
| colour | Vibrance | 1.65 / 5.55 | – | 1.39 / 4.91 ✗ | ✗ |
| colour | Saturation | 1.24 / 5.01 | – | 1.17 / 4.13 ✗ | ✗ |
| — | combos (3 sliders) | 1.55 / 4.52 | – | 2.10 / 6.65 ✗ | ✓ |
| rawDevelop | base | 1.03 / 3.67 | 1.05 / 3.08 | (input) | – |
| curve, mixer, clarity, sharpen, vignette | | no sweep yet (sweeps 4–12, PR #327) | | | – |

Held-out 2.38 / 8.10 (cap 2.42 / 8.07): ✗ on p95, on main as it stands.

**Better scores, sweep 1** (`better.py`; Lightroom's exports vs Lumina's renders, median over 5 photos):

| slider | isolation LR / Lumina (leak) | hue skin ° LR / Lumina | evenness LR / Lumina | clip before the end % LR / Lumina | halo L* LR / Lumina |
|---|---|---|---|---|---|
| Exposure | – | 1.9 / 2.8 | 0.16 / 0.16 | 5.2 / **20.3** | −0.13 / 0.02 |
| Contrast | – | 1.1 / 0.6 | 0.04 / 0.04 | 1.4 / **6.2** | −0.14 / 0.00 |
| Highlights | 0.66 (0.11) / 0.53 (0.08) | 1.6 / 0.7 | 0.05 / 0.03 | 0.6 / 0.4 | −0.20 / 0.18 |
| Shadows | 0.76 (0.18) / 0.32 (0.09) | 1.0 / 0.3 | 0.15 / 0.16 | 1.9 / 2.2 | 0.23 / 0.23 |
| Whites | 0.85 (0.36) / **1.25 (0.45)** | 1.3 / 0.0 | 0.43 / 0.02 | 1.5 / 1.3 | −0.13 / 0.00 |
| Blacks | 1.53 (0.91) / 1.03 (0.53) | 1.0 / 0.1 | 0.21 / 0.06 | 15.2 / 14.6 | −0.11 / 0.00 |
| Vibrance | – | 2.1 / 0.0 | 0.31 / 0.33 | 0.1 / 0.5 | −0.18 / 0.00 |
| Saturation | – | 2.4 / 0.1 | 0.14 / 0.16 | 0.1 / 0.9 | −0.14 / 0.00 |

Skim (same scorer on its renders): isolation is tighter than both (Highlights 0.05, Whites 0.02: its curves
are narrow bumps), Exposure clips 2.4 % before the end (soft shoulder), but its ΔE to Lightroom is the largest:
Exposure ±2 at 6–7 median (display-referred gain, not scene-referred), Temperature saturates at ±100 short of
Lightroom's 3200 K / 10000 K, Highlights −100 p95 13. Skim's rows are a measure for the video prompts; no Skim
code changed.

Lumina already beats Lightroom on isolation (Highlights, Shadows, Blacks), on hue stability and on step evenness
(Whites, Blacks). It loses on **added clipping** (Exposure clips 20 % of pixels before the slider's end, Lightroom
5 %; Contrast 6 % vs 1 %) and on Whites' isolation. Lightroom's columns carry a floor of about 1° hue and −0.1 to
−0.2 L* halo from its exports alone (8-bit JPEG; base exported at 1968 px, singles at 2048). RapidRAW: no exports
yet.

## Better than Lightroom and RapidRAW: what the sliders are scored on

ΔE to Lightroom can only reach "equal to Lightroom". It is the **floor**: slider names and amounts
carry the same meaning, so a Lightroom user's habits transfer. "Better" needs its own scores, run on
Lumina, Lightroom exports and RapidRAW exports alike. Use RapidRAW as a measuring tool only: render
the same sweep in RapidRAW; reading its output is fine, copying its code is not.

| Score | Meaning | How |
|---|---|---|
| Parity (floor) | same slider ≈ same picture as Lightroom | existing criteria: ≤ 2.0 / 4.0, combos ≤ 3.0 / 5.0 |
| Isolation | Highlights doesn't move shadows; Blacks doesn't move midtones | ΔE outside the slider's own luma band, per region mask |
| Hue stability | exposure, contrast and saturation don't drift hue (skin, sky) | Oklab hue drift on skin / sky / neutral masks |
| Even steps | +10 → +20 looks like the same step as +40 → +50 | ΔE per slider step along the sweep; flatter is better |
| Same meaning on every photo | "Shadows +50" lifts shadows by a predictable amount (Lightroom: +3 to +58 L*) | spread of the effect across 156 photos. A conflict with parity, so offer it as an opt-in mode, never the default |
| No artefacts | no halos (clarity, dehaze, local tone), no posterising, no hidden new clipping | edge overshoot at high-contrast edges; banding on gradients; clipped pixels added before the slider's end |
| Repeat accuracy | an edit carried across a set looks the same on every photo | rendered-stat spread across the set (`LEARNED-LOOKS.md`); PPR10K groups |
| Speed | under a frame while dragging | already gated (`probe.sh edit`) |
| Preference | people pick it | blind A/B with `Tools/parity/ab.html`, Lumina vs Lightroom vs RapidRAW, owner + testers |

Isolation, hue stability and the artefact scores agree with parity. Fix those failures first: they
are where Lightroom can be beaten without leaving its slider meanings.

## Order

1. **Quality floor (~1.5 wk).**
   - Fresh `make parity` on every stage, on origin/main plus dehaze.
   - New Lightroom sweeps, then fit: clarity, texture, HSL, curve regions, vignette, sharpen.
   - Rework the Highlights form.
   - Expose Clarity and Vibrance sliders.
   - Lock what holds.
   - Nothing new ships until the stage under it is measured.
2. **Masks panel + edit repeat (~2 wk).** This is the owner's goal.
   - Masks panel on the existing Vision masks.
   - Outcome-matching repeat across a row (`LEARNED-LOOKS.md`): re-solve ev, wb, hl, sh, wh and bl
     per photo, and re-find masks per photo.
3. **Hands-on layer (~2 wk).** Below. Most of it reuses the existing drag grammar.
4. **Remaining globals (~2.5 wk).** Colour grading, grain, lens distortion/CA, perspective, colour NR,
   presets/LUT, export spaces.
5. **Local tools + retouch (~3 wk).** Brush, linear, radial, range, depth; manual heal/clone/remove.

## Data (owner's end)

- **Lightroom CC sweeps to make** (`lr_cc_sweep.py` already pins these keys to 0 in the base; add rows
  to `SWEEP`). All one slider from base, on 30–50 photos first:
  - Texture / Clarity / Dehaze at ±25 / ±50 / ±100 (~18 presets)
  - Colour grading: each wheel at 4 hues × Sat 25/50, Lum ±50, Blending/Balance, plus 10 combos (~50)
  - HSL: 8 × H/S/L ±50 (48), on photos that contain each hue
  - Vignette: Amount, Midpoint, Feather, Roundness, Highlights (~12, 30 photos)
  - Grain: 12 presets on 10 flat photos, scored by power spectrum
  - Lens: AutoLateralCA, manual distortion ±50, defringe
  - Sharpen and NR: sharpen grid; NR on an ISO 100 → 12800 ladder of one scene; judged at 100 % crops
  - Masks: Adaptive Sky / Subject presets with one local on 50 sky + 50 people photos. Save one from
    the UI first to learn the XMP shape; whether hand-written mask XMP imports is unverified.
  - By hand on ~20 photos: Remove / Heal and AI Denoise (no preset path).
- **For repeating edits:** the owner's own Lightroom CC shoots where settings were synced, then fixed per
  photo. Those fixes are ground truth for what a blind copy gets wrong. Fitting on owner edits needs
  the owner's ruling: the mehendi set stays held out.
- **Public sets (research and measurement only, never shipped weights):**
  - PPR10K: 11k RAW portraits including ARW, 1,681 groups, 3 experts, XMP. The benchmark for repeating
    an edit across a group.
  - FiveK: 5k DNG × 5 experts, Lightroom catalog, scene labels. The per-type prior benchmark.
  - SID (Sony, low light): denoise.
  - LSMI (Sony α9 subset): mixed-light white balance.
  - Not verified: whether the JarvisArt / MMArt data includes masks, INRetouch's release, the RAISE /
    Cube+ licences.

## Hands-on: the photo as a physical print

One rule: **anything a slider does, a hand can do on the photo, with the same drag grammar** (⇧ fine,
⌥ finer, esc cancels, double-click resets, everything lands in the look string, undo works). Already
there: corner crop, straighten line, histogram drag, ⌥-drag on a colour, hold-V variations, the
vignette corner (`vigDown`, which moves the overall amount).

| Gesture | Does | Look keys | Notes |
|---|---|---|---|
| **Pull one vignette corner** | darkens or lightens that corner only; the others stay | new `vigc:tl,tr,br,bl` corner weights (×amount), blended by angle; drag inside the frame moves the centre (`vigx,vigy`) | Kernel change in three copies. Lightroom has none, so it is measured against a radial-mask equivalent, not the parity criteria. Edge midpoints drag feather; ⌥-drag a corner sets roundness |
| Drag up/down on a tone in the photo | moves the curve at that pixel's luma | `curve` point | Targeted curve, the tone twin of today's ⌥-drag on colour |
| Drag across the photo on a neutral | x = temperature, y = tint | `wb`, `tint` | Extends **W** (pick white) into a 2-D pad |
| Drag in from an edge | linear gradient (darken sky, lift foreground) | linear mask + local ev | Two-finger rotate turns it |
| Click a subject | selects it (Vision instance mask); then drag ↕ = light, ↔ = warmth | `mask:` locals | The "lift it off the table" feeling |
| Paint with pressure (Force Touch) | dodge/burn; pressure = strength | brush mask + local ev | Pen-first grammar from the Sort editor ruling |
| Two-finger rotate | straighten | `crop` angle | Trackpad rotation gesture |
| Drag the corners of a grid | keystone / perspective, like tilting a print | perspective keys | Vision rectangles propose a start |
| Drag on one photo with a row selected | same relative move on every photo, re-solved per photo | per-photo looks | Hands plus repeat-across: the owner's goal in one gesture |

**Automatic and manual meet in the handles.** Whatever Auto, masks or repeat-across did shows up as
handles you can grab: the gradient Auto placed, the corner it darkened, the subject it lifted, each
photo's re-solved exposure in the filmstrip. Nothing automatic is a black box; you can pick up all of it.
