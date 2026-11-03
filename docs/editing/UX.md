# Editing UX: the photo is the control

2026-10-29. One interaction language for every editing task in Stills (Edit) and Video (Skim). Each
feature prompt in `prompts/` carries its own task's section below; this file is the whole picture.

Three things each task must do:
1. **easy to do**: one gesture, on the photo, with no hunting for the panel;
2. **easy to repeat** over many photos and clips: the move is stored as *what you meant*, not just
   numbers;
3. **tactile**: it feels like handling a print, with precision when you want it.

All of it under minimalist polish.

## The grammar (every task uses it, so learning one teaches all)

**Press picks, drag changes.** Pressing on the photo picks what is under the finger: a tone, a colour,
a subject, a region, a corner. Dragging changes it. The panels are an index and a place for exact
numbers, not where the work happens.

| Hand | Always means |
|---|---|
| press | pick what is under the finger (tone, colour, subject, corner) |
| drag ↕ | amount / lightness of what you picked |
| drag ↔ | the second axis: warmth, hue, tolerance |
| pinch (while pressed) | spread: width, feather, blending, radius |
| two-finger rotate | angle: straighten, gradient angle, hue spin |
| pressure (Force Touch) | strength while painting |
| ⇧ / ⌥ | fine / finer; ⌥ alone on a press widens the pick (all four corners, every colour) |
| esc · double-click · click the number | cancel · reset · type a value |
| hold a key | *see* something (scope, mask, zebras, before); let go and it's gone |

- **Feedback lives at the finger.** A small **puck** (a 1 px ring, 28 px) sits under the pointer while
  you drag. It shows what you picked and one value, e.g. `Shadows +18` in 12 px tabular figures. The
  footer line repeats it in words. No dialogs, no popovers that stay.
- **Detents you can feel.** Values snap softly at 0, at as-shot and at the photo's original, with a
  Force Touch trackpad tick: the native `haptic` op, `NSHapticFeedbackManager`, one row in `TRUST.md`.
  ⌥ drags without detents. Values never coast: no inertia, ever.
- **One task at a time.** The rail (Light · Colour · Grade · Detail · Masks · Retouch · Crop) picks the
  task. Its panel shows only that task's rows, folded to one line each, and the canvas gestures follow
  the task. With no task open, a press on the photo does Light (tone under the finger).

## Repeat is built in (the owner's main goal)

- **A move is stored with its intent.** Examples: "this photo's shadows", "the sky", "the person",
  "skin", "this hue", "the corner". Paste, "same as last" and apply-to-selection re-solve the intent on
  each photo or clip (`prompts/22`), instead of copying numbers that only fit one frame.
- **Select, then touch.** With photos selected in the filmstrip (⇧-click, or a scene), any gesture on
  the main photo previews live on every selected thumbnail.
  - A count chip `× 24` rides beside the puck. Release applies to all; one ⌘Z undoes all.
  - Photos that couldn't match get a small amber dot. Click it for the reason ("darker light, subject
    12 % of frame vs 30 %") and a nudge.
- **Contact sheet.** **Space** is already the large view. With a selection it becomes the contact
  sheet: all of them graded, side by side, to judge consistency. Dragging on one adjusts that one, relative to the others.
- **Video.** The same, per shot: measured on a few frames and held, so nothing flickers. A scene in
  Skim is a selection.

## Polish (minimalist)

- **Colour:** the page's own tokens only:
  - ink `#EFECE6`, secondary `#B8B3AB` / `#9A958D`, ground `#161514` / `#1E1D1B`
  - hairlines `rgba(239,236,230,0.1–0.22)`
  - **gold `#FFD27A` only for the live value and the active thing**
- **Type:** 12 px rows, 11 px secondary, 13 px titles, tabular figures for numbers.
- **Motion:** 120 ms ease-out for appearing and fading; nothing bounces. The wheel and fan bloom from
  the finger (scale 0.92 → 1, 120 ms).
- **Chrome disappears while you drag:** panels dim to 40 %, and only the photo, the puck and the
  thumbnails being carried stay. Hover reveals handles within 80 px of what they move; otherwise
  nothing sits on the photo.
- **Words, not icons:** footer lines say what happened ("Sky −0.4 · 24 photos"). Empty states are one
  quiet line.
- **Every gesture has a slider twin** for exact numbers and for Lightroom users, folded under its
  section.

---

## The tasks

### Light: exposure, highlights, shadows, whites, blacks (prompts 01, 02 for vibrance)
- **Do:** press anywhere and drag ↕. The tone under the finger chooses the slider: blacks, shadows,
  highlights or whites. ⌘-drag ↕ is exposure for the whole photo.
- **Hands:** while pressed, a thin tone bar (black → white, 4 px) beside the puck marks where your tone
  sits. The pixels in that band glow faintly on the photo (a 20 % luminance key) so you see what moves.
- **Repeat:** stored as "this photo's band"; re-solved per photo with the tone anchor, so "lift the
  shadows" lifts *each* photo's shadows by the same look.
- **Polish:** the histogram lights the band you hold; nothing else changes on screen.

### Presence: texture, clarity, dehaze (02, 03)
- **Do:** press on detail and a 1:1 loupe (160 px) opens at the finger, because texture is only seen
  at 100 %. Drag ↕ = amount.
  - The puck shows which control: **T**, **C** or **D**. `[ ]` cycles them (it already picks the setting to nudge; Tab stays for keyboard focus).
  - Pressing on sky or distance picks Dehaze by itself.
- **Hands:** pinch while pressed = Clarity ↔ Texture balance (fine to coarse). The full canvas shows
  the whole-photo result behind the loupe.
- **Repeat:** these don't adapt to the photo, so the values carry as they are. Halos are guarded: if
  the halo score rises, the loupe outlines the halo in a thin warm line.
- **Video:** preview only in Final Cut; the puck says so.

### Colour: HSL and B&W (04)
- **Do:** press on a colour in the photo. A short arc of the hue ring appears around the puck, showing
  that colour's band.
  - Drag ↔ slides the colour along its arc (hue).
  - Drag ↕ = saturation; ⇧↕ = luminance.
  - The other pixels of the same band pulse once, so you see what else will change.
- **B&W:** the same press-and-drag ↕ makes that colour's grey lighter or darker, like a coloured filter
  on the lens. The puck shows the filter's colour chip.
- **Repeat:** a hue band is the same on every photo, so it carries naturally. Skin protection is on
  when the band crosses skin.
- **Polish:** the eight colour dots in the panel are the only colour in the UI; the active one gets a
  gold ring.

### Grade: colour grading (05, 05b), the flagship
- **Do:** press anywhere. A **grade wheel blooms under your finger** (160 px), centred on that pixel's
  current colour, drawn in Oklab so equal distances look like equal changes.
  - A thin arc around it shows which tone you grabbed (shadows to highlights).
  - Drag toward a colour: the distance is the amount, with resistance that grows from the centre, so
    small moves are fine and big moves still possible. That tone and its neighbours take the colour.
  - Release and the wheel fades (120 ms).
- **Hands:**
  - ⌥↕ = lightness of that tone.
  - Pinch while pressed = blending (how far the colour spreads through the tones).
  - Two-finger rotate = spin the hue only, keeping the amount.
  - **⇧ = complementary:** a ghost dot moves the opposite region toward the opposite hue (teal against
    orange), and the two stay locked while you drag.
  - Detents tick at neutral and on the skin line's hue.
- **The tone strip** (the panel, replacing three static wheels):
  - a 12 px bar from black to white showing the graded colour at every tone;
  - three soft handles (shadows / mid / highlights) slide along it (balance), and grabbing one blooms
    the same wheel.
  - Lightroom users get the classic three wheels plus a global one behind a fold, with the same keys.
- **See:** hold **⌘** while grading for the vectorscope over the photo. The photo's colours appear as a
  soft cloud tinted by region, with the skin line as a hairline. Drag the shadow cloud itself toward a
  colour. The skin tick turns amber if skin leaves the line.
- **Repeat:**
  - grades are tone-relative, so "teal shadows" means *each photo's* shadows;
  - **drop any photo or film still onto the strip** to match its colour-by-tone;
  - apply to a selection with per-photo solve and amber residual dots.
  - Video: shot matching across clips, per shot.
- **Agent (05b):** press **/** and type what you want ("warmer, teal shadows, keep skin"). Three
  candidates fan out as tiles (the same fan as Looks, below); release on one to apply. It lands as
  ordinary strip handles you can grab.
- **Polish:** the wheel is a 1 px hairline circle with six hue ticks. The only fill is the colour you
  are pushing toward. The value reads `Shadows · teal 196° · 24`.

### Curve (06)
- **Do:** press on the photo and a point drops on the curve at that tone. Drag ↕.
- **Hands:** the curve panel is one 1 px line over the histogram. Points are magnetic to the original
  line (a detent), and double-click removes one.
  - Luma is the default, so curves never shift colour.
  - R, G and B are behind ⌥ on the panel.
- **Repeat:** each point can be stored at its percentile ("the photo's 20 % tone"), so a curve carries
  across exposures.
- **Polish:** no grid; three faint quarter ticks only.

### White balance (07)
- **Do:** tap something that should be neutral: done. (W, then tap.)
- **Hands:** hold **W** and drag. A soft field appears under the finger, blue ↔ amber across and green
  ↔ magenta up and down, with a crosshair. Detent at as-shot.
- **Repeat:** stored as "neutral on this kind of thing" (grey card, white shirt). On other photos it is
  re-picked from the same object where it can be found; otherwise the Kelvin move from as-shot carries.
  Video: per shot, before the log transform.
- **Polish:** the field is 120 px at 30 % opacity; the photo stays visible through it.

### Detail: sharpening and noise (08, 09)
- **Do:** detail is judged at 100 %, so the task opens the loupe. Hold **G** on a detail (the loupe; AGENTS.md's RAW 9 loupe key) and drag ↕ =
  amount.
- **Hands:**
  - Sharpening: pinch = radius; ⌥ shows the edge mask in the loupe (white = sharpened).
  - Noise: ↕ = luminance noise, ↔ = colour noise. A split line inside the loupe slides between before
    and after.
- **Repeat:** keyed to ISO. Applying to a selection proposes the same noise reduction for the same
  ISO, scaled for the others.
- **Polish:** the loupe has no frame, just a 1 px ring and its zoom figure.

### Lens (10)
- **Do:** nothing. Corrections apply from the camera's own data; the facts line says `lens ✓`.
- **Hands:** to fix a line that should be straight, press its middle and drag it straight (a bend
  handle). Lumina fits the distortion to that.
- **Repeat:** automatic per lens.
- **Polish:** no panel unless asked; one toggle row.

### Crop and perspective (11)
- **Do:** C. A grid lies over the print.
  - Drag a corner to keystone, like tilting a print toward the light.
  - Two-finger rotate straightens, with detents at 0° and at the horizon Lumina found.
- **Hands:**
  - **U** = upright: the grid glides to the fix in 160 ms, then it's yours to adjust.
  - Draw along two lines that should be parallel and they become parallel.
  - F / ⇧F flips.
- **Repeat:** tripod series copy the numbers; handheld series re-detect lines per photo. In Final Cut,
  native transform keys.
- **Polish:** the grid is thirds only, 1 px at 22 %; it fades while you rotate except near the horizon.

### Vignette (12)
- **Do:** move toward a frame corner and its handle appears. Drag in = darker *in that corner*, out =
  lighter.
- **Hands:**
  - ⌥-drag = all four corners.
  - Drag the centre dot to move the light's centre.
  - Pinch = feather; two-finger rotate = roundness.
- **Repeat:** relative to the frame, so it carries across crops and orientations.
- **Polish:** handles are 10 px hairline quarter-arcs, shown only within 80 px.

### Grain (13)
- **Do:** one puck in the loupe (grain at fit is a lie). ↕ amount, pinch = size, ↔ = roughness.
  Three swatches (fine / medium / coarse) as starting points.
- **Repeat:** carries exactly. Seeded per photo; per frame on video.
- **Polish:** the swatches are 24 px live crops of *this* photo.

### Masks: subject, sky, person, objects (14, 17)
- **Do:** click a subject and **it lifts**: a soft outline glow, everything else dims to 70 %. From now
  on *every* task's gesture applies inside it: grade the person, lighten the sky. Esc puts it down.
- **Hands:**
  - A slim left rail of layer thumbnails: click a layer out or in, ⇧-click solos it.
  - "Find everything" lists what Lumina found.
  - Hold **O** to see the mask.
- **Repeat:** masks are stored by kind ("the person", "the sky") and found again on each photo; on
  video, Follow tracks them.
- **Polish:** the lift is the only shadow in the UI.

### Drawn masks: pen, gradient, radial (15)
- **Do:**
  - Pen: any stroke paints; pressure = flow; ⌥ erases. Edges snap to the photo (refined).
  - Drag in from the frame's edge = a gradient; two-finger rotate turns it.
  - ⇧-drag = a radial from its centre.
- **Repeat:** drawn shapes carry by geometry (same framing) or, on video, by Follow. A small chip warns
  when a photo's framing differs.
- **Polish:** the loupe at the pen tip; strokes draw as a 1 px gold edge only while active.

### Range masks: colour, tone, depth (16)
- **Do:**
  - ⌘-click a colour: the mask grows from it, and ↔ = tolerance with a live marching outline.
  - ⌘⌥-click a tone: the same for brightness.
  - Depth: drag from near to far on the photo to set the band.
- **Repeat:** ranges are about colour and tone, so they carry well across photos and frames.

### Retouch: heal, clone, remove (18)
- **Do:** J, then click a blemish: healed at once, with the source found for you. Paint over a
  distraction with the remove brush; release and it is gone.
- **Hands:**
  - Drag from the heal ring to move its source; a hairline thread shows the source.
  - ⇧J = clone.
  - Hold ⌥ to see every ring; click one to edit it, ⌫ to remove it.
- **Repeat:** sensor dust carries across the shoot and every clip from the body, by itself (the spots
  sit in the same place). Other heals don't carry, and the chip says so.

### Looks: presets, LUTs, learned looks (19, 23)
- **Do:** hold **L** and 3–5 looks **fan out around the pointer** as live tiles of *this* photo.
  - Move toward one and it grows and previews on the canvas; the distance from the centre = strength.
  - Release applies; release in the centre cancels.
- **Hands:** drop a `.cube` file or a reference photo onto the fan to add it. Learned outcomes (23) and
  presets (19) share the fan.
- **Repeat:** a look applied to a selection is solved per photo.
- **Polish:** tiles are 72 px with 4 px corners; no labels until hover; 120 ms bloom.

### Compare (20)
- **Do:** **B** splits the photo: before on the left, now on the right. Drag the divider like sliding a
  print over its proof.
- **See:** hold **K** for clipping: red highlights, blue shadows; zebras on video. Hold `\` for before.
  ⇧`\` compares with your last step.
- **Polish:** the divider is a 1 px line with a 12 px grip that appears on hover.

### Export (21)
- **Do:** Save offers three choices (Web · Print · Archive), each a space, format and size; details are
  folded.
- **Repeat:** the choice is remembered per shoot.

### Carry: repeat across photos and clips (22)
This is the "Repeat is built in" section above, as a task of its own:
- select, then touch, with live thumbnails, `× N`, amber residual dots;
- Space (large view) as the contact sheet;
- one ⌘Z.
- Video: scenes, per shot.
