# Paste into a new Claude / Cursor chat

> **Bar (owner, 2026-10-28):** Minimalist, elegant, B&W wireframes. Ugly-clear over
> hi-fi. One job per surface; the thinnest control that proves the grammar. Palette is
> `--ink` / `--mute` / `--line` / `--fill` / `--bg` plus kept green and danger red —
> no amber, no purple, no gradients, no chrome bloat. Motion only when it teaches
> (clock-align beats, pinch); otherwise quiet. The page is the product: edit only
> under `design/handoff/wireframes/keep-sort/`. Prefer stripping chrome over adding it.

```markdown
# Keep-sort wireframes — continue (minimal / elegant)

Repo: `/Users/aniketh/vlm_harness`  
**Worktree:** `.claude/worktrees/keep-input-dock-chron` · branch `design/keep-input-dock-chron`

**Read first (authority order):**
1. `design/handoff/wireframes/keep-sort/CONTINUATION.md` — what shipped + pending
2. `design/handoff/wireframes/keep-sort/README.md` — locked Import/Sort grammar
3. `design/handoff/wireframes/keep-sort/PLAN-input-dock-chron.md` — dock plan (done)
4. `design/handoff/wireframes/keep-sort/MODEL-EVAL.md` — claim boundaries

**Live pages (edit these):**
- `design/handoff/wireframes/keep-sort/import-wf.html`
- `design/handoff/wireframes/keep-sort/keep-wf.html`
- (skim/index/hotserve only if needed for run)

```bash
cd /Users/aniketh/vlm_harness/.claude/worktrees/keep-input-dock-chron
python3 design/handoff/wireframes/keep-sort/hotserve.py --port 8788
# → Import; enable 2–3 vols → Sort now; exercise pinch, hover play, clock stems
```

---

## Design intent — elegance bar

These are **product wireframes**, not a polished app mock and not shipping Sets/Skim UI.

- **Ink on paper.** Reuse existing CSS variables. No new palette, glass, glow, shadow stacks, stock photos, or fake Rec.709 pixel previews.
- **Structure over beauty.** If a feature needs UI, add the thinnest control that proves the grammar — not a new visual language.
- **One job per surface.** Fold bar = dump identity + Saving to + TI word. Axis = time. Cards = the take. Dock = keeps. Rail = tools when large.
- **B&W first.** Grey/cream/ink only. Functional accents already on the page: kept green, danger red. Do not add more color systems.
- **Tiles = frame + quiet meta.** Empty/grey thumbs, pills, soft-shadow edges. No skeuomorphic cards, no marketing hero, no dashboard chrome.
- **Motion teaches or it goes.** Align’s three beats stay; pinch should feel continuous; everything else is 140 ms or less, no layout-animating transitions, no hover lift, no stagger.
- **If fidelity creeps up, strip back** to ink / boxes / labels and ship the interaction.

When unsure: open the current Import page and copy its variables and restraint.

---

## Locked grammar — do not break

### Product
- **Models, not modes.** Harrison (A/B-cam + drone, clocks off) + Uday (cam + drone, place/time gaps) = one dump. No scene toggle.
- **No Ready / preprocess.** Clips are just included. Do not revive unread tiles, Ready N/M, or Import RAM/offload UI.
- **No source chips** in the Sort header. Align pill is the clock story; tile/viewer still show src.
- **No amber.** Picks = dashed ink; Clean warn = danger.
- Stay in `design/handoff/wireframes/keep-sort/` unless the owner promotes.

### Import (`import-wf.html`)
- Suggested volumes **top**; Drop + AirDrop; **dock ≡ Drop**
- Files + directories **drag-droppable**; boot Files **fully collapsed** (no Downloads default)
- Pull `ACCEPT_EXT`; peripheral **also** sense (objective criteria, still imported) — **no `off` / skip file class**
- Prep is **Log only**

### Sort (`keep-wf.html`)
- Union chron axis; bare hairline time-gap breaks (no stack labels)
- Auto clock-align, three beats; pill fades after receipt
- **Clock proof:** vertical stems **on the time rod only** — hollow = as stamped, arrowhead = aligned, vertical label `src · 6m`. Edge cases: ssd −6m, drone +3m, phone +50s. **52px axis strip inside `.canvas`**, scrolls with content, **no scroll repaint**, never over tiles, never fight canvas smoothness
- **+ Add clips** / `A` → Import with vols held → **Back to Sort**; keeps / place / shift in `sessionStorage`
- Fold title: `Sort · N · M in` (no “from Import” file dump)
- **Large view (2026-10-28, owner: "go minimalist", "frame front and center", "trace like a pen"):** chrome hides; the 16:9 frame fills the width with the scrub line + neighbour strip under it; one **340 px rail**: name · Color / Outline / Heal (keys 1 / 2 / 3) · Keep. No facts column, no Files list, no furls, no mask-kind buttons.
  - **Color** = four Stills rows (Exposure · Contrast · Warmth · Color): label + value on top, track under, **the whole row drags** (ev 1 stop / 120 px, others 1 / 2 px), double-click resets, sideways wheel nudges, ← → on a focused row. Target chip = Whole clip or the picked layer.
  - **Outline = the pen.** `Find everything` → one named layer per object (Person · Face · Sky · Water…), each followed through the clip. Any stroke draws: closed shape = new layer; a stroke that starts and ends on a picked layer's edge **redraws that run**; loupe at the pen tip; Snap to edges; pressure widens the stroke. Tap an empty spot = fill a region; **⇧-draw grows**, **⌥-draw carves**; drag a point, tap an edge to add one, ⌥-tap removes. Invert · Delete / ⌫. Each layer has an **in / out dot** (⇧-click solos): out = hatched, cut from the frame while scrubbing / playing. `O` overlay, Esc backs out one level.
  - **Heal** = click a spot, it follows; Clear.
- Selection: persistent = Shift / ⌘A / ⌘⇧A / tile dblclick; plain marquee ephemeral; Enter = large; fluid rod scrub
- Export: full-bleed XML+facts · FS flow · canonical dated folder · Clear ledger (delete off)
- Saving-to sheet + Clean destination ledger; stringout Export copy (no FCP/ΔE claim)

---

## NEXT (this session’s owner asks — do these)

### 1. Smoother / continuous pinch zoom
Current TI pinch is **stepped** (`PINCH_STEP` 48px / discrete `setTi` levels; pointer pinch with 0.6 hysteresis). Owner wants **smoother continuation** — the zoom should feel continuous while the gesture is live, still landing on TI levels without flap, and still never fire under marquee / rod scrub. Keep magnitude-based discipline; do not bring back sign-based jitter. Prefer elegance over cleverness: continuous feedback that still respects the discrete run grouping.

Touch: `keep-wf.html` wheel + pointer pinch handlers, `setTi`, maybe light CSS on `--tw` / tile scale **only if** it stays quiet and does not reintroduce layout-animating jank.

### 2. Fill-frame cards + meta under / overlay + hover preview play
Today tiles have a separate meta row (name + pills) under a grey thumb — that eats the frame.

**Intent:** the **frame fills the card**. Filename + Log (and duration / soft as needed) sit either:
- **under** the frame as a single quiet line, or
- **overlay** on the frame (ink pills / name on the image plane) —

pick the thinner of the two that stays readable in B&W; do not do both. Hovering a tile **preview-plays** that take (wireframe stand-in: skim/play mark on the frame — not a real decoder). Double-click still opens large view. Keep soft-shadow edges; state marks (on / pick / kept) stay crisp.

Touch: `.clip-tile` / `.thumb` / `.cinfo` / `.pills` CSS + `renderCanvas` markup; Kept dock tiles should follow the same grammar if cheap.

### 3. Large-view editor — make the stand-ins honest, keep the grammar
Everything in Outline is a wireframe stand-in (blobs, not vision): Find places shapes by source, fill makes a blob at the tap, Snap pulls toward existing outline points, "follows through the clip" is 8 drifting keys. Next:
- **Redraw-a-run on every key** currently moves the other keys with their centroid; make the redrawn run propagate by shape (or mark the run as keyed only at this frame and glide).
- **Loupe:** 3× around the tip; check it reads on a real frame, and that it never covers the stroke's leading edge (move it to the side the pen came from).
- **Heal** has one spot per clip; allow several, each a dot that follows, and a size drag.
- **Copy / paste look** across clips (⌘C / ⌘V in large view) for shot-to-shot colour — owner's creator workflow; the look lives per clip (`state.looks`, keyed `clip` or `clip#layer`).
- Do **not** bring back: Subject / Sky / Lasso / Linear / Radial buttons, the facts / Files columns, the "Grade · cull min" furl, `<input type=range>`.

### 4. Leave clock-proof alone unless it regresses
Vertical-on-axis language stays. If a change fights scroll or covers tiles, fix the regression — do not reinvent elbow paths over frames.

---

## Checks

```bash
# Script syntax (both pages)
node --check <(sed -n '/<script>/,/<\/script>/p' design/handoff/wireframes/keep-sort/keep-wf.html | sed '1d;$d')
node --check <(sed -n '/<script>/,/<\/script>/p' design/handoff/wireframes/keep-sort/import-wf.html | sed '1d;$d')

# Spot-check in browser on :8788 — pinch continuous; cards fill-frame; hover play; stems on rod
# Large view: ⏎ on a tile → 2 (Outline) → Find everything → draw a closed shape → click a layer's dot out → 1 (Color) drag a row
```

Update `CONTINUATION.md` (and README one-liners if grammar shifts) when you land the NEXT items. Do not expand into native app code, SPC/VC strategy, or archive rebuilds. **Prefer ugly-clear elegant wireframe over hi-fi.**
```
