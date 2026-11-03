# Colour grading from first principles (stills, shared with Skim)

2026-10-29. Goal: rebuild colour grading so it is more accurate than Lightroom's and RapidRAW's, easier to
use, works with your hands on the photo, and can be driven by an agent. Companions:
- `RAPIDRAW-PARITY.md`: what "better" is scored on
- `LEARNED-LOOKS.md`: repeating an edit across many photos

## 1. What grading is

A grade is a **colour shift that depends on how bright the pixel is**:

out = in + Σ_regions w_r(tone) · shift_r

There are four parts:
1. a **tone coordinate** (what "shadows" means)
2. **region weights** w_r over it (how shadows, midtones and highlights overlap)
3. a **shift** per region: a hue direction, an amount, a lightness move
4. the **space** the shift is added in

Every grading tool is one choice of each.

| Tool | Tone coordinate | Regions | Shift | Space |
|---|---|---|---|---|
| Lift / Gamma / Gain (telecine, Resolve) | the channel value itself | implicit: lift ∝ (1−x), gain ∝ x, gamma on mids | per-channel RGB | display, or log |
| ASC CDL (public interchange standard) | channel value | none: out = (x·slope + offset)^power, then saturation | per channel | whatever the pipeline gives it |
| Lightroom Color Grading (2020; replaced Split Toning) | luminance | 3 wheels + global; Blending = overlap, Balance = where the regions split | hue + sat per wheel, plus a luminance slider | **not published: must be measured** |
| RapidRAW (`shader.wgsl:791`, ideas only) | Rec.709 luma in linear | smoothstep at fixed 0.10 / 0.50, widened by blending; midtones = 1 − S − H | `(hsv(h,1,1) − 0.5)·s·k_r`, hand-picked k = 0.1 / 0.6 / 0.8 / 1.0; luminance = + constant | linear RGB, additive |
| Skim today (`Lumina Skim v3`, `LK_FS`) | display luma | power partition: (1−y)^p, y^p, with Balance as a gamma on y | tint minus its own luma (luma-neutral) × 0.15; luminance = + constant × 0.2 | display RGB, additive |

## 2. What goes wrong in the simple forms

1. **Additive offsets in RGB lift blacks into a colour.** A constant added to a near-black pixel is a huge
   relative change: black turns teal and clips. RapidRAW's luminance slider is also a constant offset,
   so it is a lift, not "shadow brightness".
2. **Hue-dependent brightness.** RapidRAW's `hsv − 0.5` for pure blue changes luma by about −0.43 per
   unit and for yellow by about +0.43. The same "amount" darkens with one hue and brightens with another.
   Skim fixes this by subtracting the tint's luma.
3. **The wheel is not perceptually even.** Equal angles in HSV are not equal perceived hue steps: the
   yellows are narrow and the blue/purple span is wide. Equal distances are not equal perceived chroma.
4. **Fixed tone splits ignore the photo.** In a dark night photo the "highlights" (above linear 0.5)
   barely exist; in a snow scene everything is a highlight. The same grade looks different on every
   photo. This is exactly what breaks **repeating a grade across a shoot**.
5. **RGB clamping shifts hue at the gamut edge.** Strong grades push colours out of gamut, and a
   per-channel clamp turns saturated orange toward yellow.
6. **Skin isn't treated specially.** Teal-and-orange turns skin green or grey in the shadows. Colourists
   protect the skin line by hand.

## 3. The form to build (proposal)

- **Space: Oklab, on the display-referred image after the tone stages** (Lumina's mixer already uses
  Oklab bands).
  - The shift is an (a, b) offset: hue = its angle, amount = its length.
  - L is untouched by hue and saturation, so a colour move never changes brightness (fixes 2).
  - Oklab is close to perceptually uniform, so a wheel in Oklab a/b is even (fixes 3).
- **Chroma envelope instead of plain addition.** The offset is scaled by e(L) = (L·(1−L)·4)^γ: full
  in the mids, zero at pure black and pure white (fixes 1).
  - "Coloured blacks", the matte film look, becomes an explicit, separate **lift** control, not an
    accident.
- **Tone coordinate = Oklab L. Region centres either absolute or photo-relative.**
  - *Absolute:* centres at fixed L. This is the Lightroom-parity mode, fitted to the sweep.
  - *Relative:* centres at the photo's own L percentiles (p10 / p50 / p90, the same family as
    `ToneAnchor`). This is the **default for repeat-across-photos**: shadows mean *this* photo's shadows
    (fixes 4).
  - Measure both against Lightroom; it may already be partly relative, as its Shadows slider is.
- **Regions: a smooth partition of unity** (weights sum to 1, so equal wheels = a global shift).
  - Balance moves the split.
  - Blending sets the overlap width.
  - Use raised-cosine or logistic bumps on L, not three hard smoothsteps.
- **Luminance per region = a move on the tone curve** (the same curve machinery as `cDark/cMid/cLight`),
  not an added constant.
- **Gamut: soft-compress chroma toward the L axis in Oklab** before output, keeping hue (fixes 5).
- **Skin protection, on by default for strong grades.** Reuse vibrance's skin band (`skinHue` /
  `skinWidth`): inside the band the offset is turned toward the skin line or scaled down (fixes 6).
  One switch; the agent can turn it off.
- **Order:** after white balance, tone, vibrance/saturation and the HSL mixer; before the output
  transform and the vignette. Inside masks it is the same stage with the mask as an extra weight.

The rules that already bite still apply:
- one maths in three copies (`LookMath`, `LookKernels`, `lookmath.py`), plus Skim's GLSL, ported from
  the same formulas
- every key at rest = identity
- L stays monotonic on a grey ramp
- with no hue amount set, greys stay grey

**Parity first, then better.** Fit the absolute mode to the Lightroom sweep (wheels × 4 hues × 2 sats,
luminance, blending, balance, plus 10 combos; listed in `RAPIDRAW-PARITY.md`). Check the form the way
Contrast was checked: apply it to Lightroom's own base export and compare. Then score the "better"
properties: hue stability, no lifted blacks, consistency across the 156 photos, skin hue drift.

**Look keys.** Same names as Skim's `grade.<sh|mid|hi|all>.<h|s|l>`, `grade.blend`, `grade.bal`, so
stills and video share one vocabulary. Add `grade.rel` (absolute | relative), `grade.lift` and
`grade.skin`. Ranges as in Lightroom: h 0–359°, s 0–100, l ±100, blend 0–100 (default 50), bal ±100.

## 4. A better UX than three wheels

Wheels hide the real idea, *colour as a function of tone*, behind three tiny dots and a separate
luminance slider. Build what the idea is:

- **Tone strip.** A bar from black to white showing the *graded* colour at every tone. Grab any point
  and drag:
  - the direction picks the hue, the distance picks the amount
  - where you grab sets Balance
  - pinch or scroll widens or narrows it (Blending)
  - three regions stay as the stored keys; the strip is their picture
- **On the photo** (the physical-print feel; same drag grammar: ⇧ fine, ⌥ finer, esc, double-click
  resets):
  - Press on any spot (a shadow under a tree) and Lumina reads that pixel's tone.
  - A small wheel appears **under your finger**, drawn in Oklab around the pixel's current colour.
  - Drag toward a colour: that tone and its neighbours move. Vertical with ⌥: lightness of that tone.
  - This mirrors today's ⌥-drag on a colour for HSL, so one gesture family covers "this colour" and
    "this tone".
- **Vectorscope overlay** (hold a key): the photo's colours as a cloud, coloured by region, with the
  skin line drawn. Drag the shadow cloud itself toward teal.
- **⇧ = complementary.** Dragging highlights toward orange mirrors the shadows toward the opposite hue.
- **Match a reference.** Drop any photo or film still. Lumina reads its colour-by-tone signature (§5)
  and proposes the grade that reproduces it; strength from 0 to 150 %.
- **Skin warning.** A tick on the skin line in the scope turns amber when skin leaves it.
- Presets are just stored grades with a strength drag. Repeat across a row uses relative mode by
  default.

## 5. The agent surface

The agent never "looks at colours and sets sliders". It works on a small, measurable signature, and a
deterministic solver turns targets into keys. Same rule as the blueprint: the planner gives intent,
never sliders.

**Signature** (per photo, measured on a 256 px rest render):
- 12 bands of Oklab L; per band: pixel share, mean a, mean b, mean chroma
- skin / sky / neutral means, from `SetsMasks` plus the skin band

That is about 60 numbers. A grade's effect is the change in signature.

**Tools** (all plan → preview → apply → undo; nothing lands until applied):

| Tool | Does |
|---|---|
| `grade.measure(photos)` | signatures, plus skin / sky / neutral stats |
| `grade.describe(look)` | in words: "teal shadows (s 25), warm highlights, slight lift, skin held" |
| `grade.solve(photo, target, keep)` | keys that move the signature to the target bands; keep = skin, neutrals, brightness |
| `grade.match(ref, photos, mode)` | reference signature → per-photo solved keys (relative mode); returns each photo's residual |
| `grade.suggest(intent, photo)` | 3 candidates from the vocabulary below, solved on this photo, with previews |
| `grade.apply(keys, photos, strength)` / `grade.undo()` | lands as ordinary look keys, editable by hand |
| `grade.consistency(photos)` | spread of the graded signatures across the set: the repeat-accuracy score |

**Intent vocabulary = target shapes on the signature**, not slider recipes:
- warm / cool: global b / −b
- teal-orange: low bands toward −a −b, high bands toward +a +b, skin held
- matte: lift L in the lowest bands
- pastel film: chroma down in the high bands, warm
- bleach bypass: chroma down in all bands, contrast up

Personal vocabulary: learn the owner's own grades from the Lightroom CC catalog (their Color Grading
values per shoot) as named targets. Fitting on their edits is the owner's call (`LEARNED-LOOKS.md`).

**Why the signature serves the main goal.** Repeating a grade across 300 photos = match every photo's
signature to the reference's, in relative mode, with skin held, then report the residual per photo,
so the outliers (a frame under different light) are flagged instead of silently wrong.

## 6. Build order

| Step | Days |
|---|---|
| 1. Stage, in three copies + tests (identity at rest, L monotonic, greys grey with s = 0, no lift with lift = 0) | 2 |
| 2. Lightroom sweep (owner) → fit the absolute mode; measure the relative mode | 1 + owner time |
| 3. Page: Grade section in Edit (tone strip + wheels for Lightroom users), keys through plumbing; port to Skim's GLSL | 2 |
| 4. On-photo press-and-drag wheel, vectorscope overlay, ⇧ complementary | 2 |
| 5. Signature + `grade.solve` / `match` / `consistency` (Swift; numpy mirror for evaluation); reference match in the UI | 3 |
| 6. Agent tools wired to the planner; vocabulary; scores on PPR10K groups (research only) and the owner's shoots | 2 |

Total about 12 days. Steps 1–3 alone give a Lightroom-compatible grade; 4–6 are what make it better.

## Not known yet

- How Lightroom computes Color Grading internally: its tone coordinate, region shapes, space, and
  whether it is relative. The sweep will show it.
- Whether display-referred Oklab or scene-referred (before the tone curve) matches Lightroom's look
  better. Try both on the sweep.
- Skin protection strength users accept: an owner judgement, through the A/B page.
