# Prompt for Claude Design: Lumina video skim (v0.01)

Status: draft, 2026-10-08. Paste the prompt below into Claude Design as a new page, `Lumina Skim v1.dc.html`,
mounted beside `Lumina Sets v11.dc.html` the way Edit v22 is. Download the handoff zip, then
`bash Scripts/sets_sync_design.sh "<zip>"`. Sample data: `lumina-video-data.js`, generated from a real
ILCE-7M3 card (401 clips, 8 days, 106 GB; `Tools/video/make-data.mjs`, to come). Until it exists, use
the shape in §9 with invented numbers.

What the page may say and what it may not: §1. The measurements behind the chips are computed by the
Mac (sharpness, clipping share, motion, exposure in stops) and some later lenses may come from on-device
models; the page never says so. It shows the number and the plain word for it, and nothing else.

---

## Prompt to paste into Claude Design

> Design `Lumina Skim v1.dc.html`: the video step of Lumina, a Mac app that gets a shoot from the card
> to a final set. Same family as `Lumina Sets v11.dc.html` (its look, type, key bar, footer, empty
> states, the `?` sheet) and the same contract: touch moves, never decides; held is temporary; a tap
> decides; esc puts it back; ⌘Z undoes; nothing is deleted until a confirmed step; the footer always
> reads `N decided · M undecided · 0 automatic`. Everything below runs on a trackpad first and on keys
> second. Keys mirror every gesture; the `?` sheet lists both columns.
>
> **1. Words.** Plain words and numbers only. Never: AI, smart, intelligent, detects, understands,
> suggests, recommended, magic, auto, learns, confidence, score. A chip is a measurement with a word for
> it: `+1.3 stops`, `4% clipped`, `soft`, `shake`, `pan`, `12 s`, `1.4 GB`. A group states its reason in
> one line: `gap of 41 min`. A filter says what it hid: `6 hidden · clipped over 2%`. The page never
> marks a clip on its own; every mark is the user's, every chip is a fact they can dismiss.
>
> **2. The levels.** One shoot at four levels, moved between with the same gestures, like folding and
> unfolding a sheet:
>
> | Level | Tile | What it shows |
> |---|---|---|
> | Chapters | one per time gap | first frame, span (`06:48 – 07:31`), count (`38 clips`), size (`12.1 GB`), decided/undecided dots |
> | Takes | one per clip | filmstrip of 8 frames, duration, size, up to 3 chips, the mark |
> | Clip | the clip, large | scrubs under the finger, Rec.709 preview on, histogram, every fact as a line |
> | Frame | one frame at 100 % | pans under the finger; `soft` / `sharp` for the frame shown |
>
> **Unfurl** (open one level) and **furl** (close it) are the two gestures the whole page runs on:
> - pinch out on a tile unfurls it: a chapter into its takes, a take into the clip, the clip into a
>   frame; pinch in furls it back. The tile grows into the next level in place, neighbours slide
>   aside, and the furled level stays visible as a strip along the top so the place is never lost;
> - ↓ unfurls, ↑ furls, same as the pinch; esc furls all the way to Chapters;
> - a two-finger swipe left/right moves along the open level (next take, next chapter); on the Clip
>   level it scrubs;
> - a three-finger swipe up/down jumps between chapters without furling;
> - furling a level with the cursor inside it keeps the cursor on the thing it was in.
>
> The gap slider sits above the Chapters level: `chapters ⟷ takes`, cuts the top N gaps; dragging it
> refolds the whole shoot live, and each chapter still names its gap.
>
> **3. Marks.** Three, by hold-then-tap so nothing is decided by touch:
> - hold K, M or X: the tile shows what the tap would do (a green, amber or red edge, the chip
>   `keep` / `maybe` / `cut` ghosted); tap the trackpad (or ⏎): decided; let go without tapping:
>   nothing happened;
> - on the Takes level, K / M / X with no hold act on the clip under the cursor and move on;
> - esc on a just-marked clip puts it back; ⌘Z undoes any number of steps; the key bar shows how many;
> - `maybe` is a real state with its own count in the footer and its own pass later (`⇧P`: maybes
>   only, beside the keepers from the same chapter).
>
> **4. Areas (the thing the trackpad is for).**
> - **Box.** Click-drag on empty grid draws a box; tiles inside it light up; the box stays until esc or
>   a click outside. While a box is up, K / M / X act on everything in it, one undo step, and the footer
>   previews the count first (`mark 14 keep?` for 600 ms, esc cancels, like ⌘A in Sets).
> - **⇧ hold + drag** paints: the mark of the first tile touched spreads to every tile the finger
>   crosses; esc mid-drag cancels the whole stroke.
> - **⌘ hold + drag** over tiles draws a box that acts at once on release with the mark held in the
>   other hand (⌘ + K held + drag box = keep everything in the box on release). Without a mark key, a
>   ⌘-box selects without marking.
> - **⌥ hold + click** on a chip dismisses that fact for that clip (`shake` on a deliberate handheld
>   run); the chip hollows out, the measurement stays in the facts line. Dismissed chips never hide a
>   clip through a filter.
> - **Drag and drop.** Drag a tile onto a chapter boundary to move the boundary; drop a tile on the
>   `keep` / `maybe` / `cut` wells in the footer to mark it; drag a box the same way to mark the area.
>   Drop outside any target does nothing. The dragged tile shows its chips so the choice is visible
>   mid-drag.
> - A box, a stroke and a drop each read in the footer as one plain sentence before they land
>   (`cut 9 clips · 4.2 GB`), and each is one undo step.
>
> **5. The preview.** A switch in the top bar: `Rec.709 preview`, on by default when the clip's profile
> is known, with one line under it: `S-Log3 · S-Gamut3.Cine · from the clip's sidecar`. Off shows the
> file as it is. A clip whose profile can't be read gets the chip `profile unknown` and its tile shows
> the file as it is; clicking the chip opens one question, `What was this shot in?`, with the choices
> S-Log3, S-Log2, HLG, none, remembered per shoot. The switch never changes a file, a mark or a fact.
>
> **6. The chips.** At most three per tile, worst first; the rest in the facts line at the Clip level:
> `+1.3 stops` / `−2.1 stops` (exposure against middle grey, after the preview transform) · `4% clipped`
> · `9% crushed` · `soft` (lowest sharpness among the 8 frames) · `shake` / `pan` · `bump` (one frame
> far from its neighbours) · `120p` / `60p` (only when it differs from the shoot's common rate) ·
> `sidecar missing`. A chip has three states, drawn differently: pending (hollow, no number yet),
> ready, dismissed (hollow with its number). A clip's chips fill in while the user looks; nothing waits
> on them.
>
> **7. Lenses and sweeps.** `L` holds a lens menu: `time gaps` (default), `by rate`, `with a chip`,
> `undecided only`, `maybes`. A lens re-orders; it never changes a clip or a mark. `⇧S` is the sweep:
> it shows only clips with a chip past its line (`clipped > 2%`, `soft`, `bump`), says `N hidden`, and
> ⇧S again shows everything. Every hidden count is a button that reveals. An `ungrouped` chapter holds
> anything the lens can't place.
>
> **8. The footer and the ledger.** Left: `N decided · M undecided · 0 automatic`. Middle: the three
> wells `keep · maybe · cut` with their counts, also drop targets. Right: `cut so far: 14.2 GB` and the
> card's free space. ⌘⏎ opens Hand off: a sheet that lists what leaves for Final Cut (keepers, maybes
> under a keyword), what is cut and its size, with `Move cuts to the Trash` as a separate switch, off by
> default, and one line saying files are never changed. Nothing in the sheet is a verdict.
>
> **9. Data.** The page reads `window.LuminaVideo = { shoot: {name, days, bytes, free, rate},
> clips: [{id, name, path, t: ISO time, dur: s, fps, w, h, bytes, codec, profile: {gamma, primaries,
> source: 'sidecar'|'none'}, frames: [url × 8], facts: {ev, clip, crush, sharp, motion, bump,
> state: 'pending'|'ready'|'unreliable'}, dismissed: [...], mark: 'keep'|'maybe'|'cut'|null}],
> gaps: [{after: id, s}] }` and calls `lumina.video.mark(ids, mark)`, `lumina.video.dismiss(id, fact)`,
> `lumina.video.preview(on)`, `lumina.video.profile(id, answer)`, `lumina.video.handoff(options)`. In
> the browser, `lumina-video-data.js` supplies a sample shoot; the page must look right with it and
> with an empty shoot.
>
> **10. Edge cases the page must show, each as a state in the design:** a clip with no sidecar; a
> shoot of mixed stills and clips (`38 clips · 776 photos · ⇥ photos`, one key to switch); a 5-minute
> clip (its filmstrip still 8 frames, its duration shown in minutes); two frame rates in one shoot; a
> chapter whose clips span midnight; the card pulled mid-skim (the banner from Sets, marks kept);
> 400 clips with chips still pending for most; a shoot where nothing is undecided (the footer offers
> Hand off); the preview switch off because every profile is unknown; a box drawn over tiles from
> two chapters.
>
> **12. The skimmer (Takes and Clip levels).** Skimming is the whole point of the page, so it gets
> the most room and the biggest targets:
> - Takes tiles are large: at the default size a tile is at least 320 px wide, 16:9, and the
>   filmstrip is the tile (8 frames edge to edge, no chrome over them). − / + go 240 / 320 / 480 px.
>   Nothing on a tile is smaller than 44 px to hit: the mark edge, the chips, the duration.
> - Moving the pointer across a tile skims it: the tile's left edge is the clip's start and its right
>   edge the end, the frame under the pointer shows in place of the filmstrip, a thin line marks the
>   time and the time reads above the pointer (`0:04.2`). Leaving the tile restores the filmstrip.
>   On a 12 s clip at 320 px that is 37 ms per px; on a 5-minute clip a tile can't be precise, so
>   the time readout says `≈` and unfurling to the Clip level is the precise skim.
> - A click while skimming pins that frame as the tile's picture (a dot on the time line; click the
>   dot to unpin). A two-finger swipe over a tile nudges a frame at a time.
> - Clip level: the picture fills the width, the scrub bar under it is the full filmstrip, 44 px
>   tall, grab-and-drag or hover; the keyframes are ticks; ←→ step a frame, ⇧←→ a second, J K L
>   play backwards / pause / forwards at 1×, with 2× and 4× on repeat; Space plays and pauses. The
>   pointer's frame shows at once at the nearest keyframe and sharpens to the exact frame; the time
>   readout turns solid when it is exact. A `≈` never hides: it means the frame shown is not yet the
>   frame asked for.
> - Everything in the skimmer is grabbable: the scrub bar, the frame (drag to pan at Frame level),
>   the chapter strip (drag to move between chapters), the gap slider, the chip (⌥-click dismisses,
>   drag to the facts line pins it there).
> - The Rec.709 switch applies to skimmed frames, filmstrips and the Clip picture alike, with no
>   change in timing; a clip whose profile is unknown skims as the file is, chip showing.
>
> **11. Keys.** Every gesture has a key; the `?` sheet shows a gesture column and a key column.
> Tab moves between controls; ⏎ or Space presses the focused one; nothing needs the trackpad.
>
> Keep the look, type and wording of Sets v11. Don't add onboarding, tips, badges, celebrations,
> or any line that explains what the page thinks. The page shows facts; the user decides.

---

## Notes for the sync (not part of the prompt)

- `plumbing.js` gets `window.lumina.video` (the five calls in §9) and feeds `window.LuminaVideo`
  from `SetsBridge` ops `videoOpen`, `videoMark`, `videoDismiss`, `videoPreview`, `videoProfile`,
  `videoHandoff`. Each is a row in `docs/release/TRUST.md` before it lands.
- Frames reach the page as `lumina://video/<rel>?f=<n>&w=160` from `SetsSchemeHandler`, never as
  blobs the page holds. The Mac keeps the 8 frames per clip under `VideoPolicy.Budgets.filmstripBytes`.
- The Clip level's scrub is a `lumina://video/<rel>?t=<s>&w=960` request per hover position, latest
  wins, the same schedule shape as `LookCanvasSchedule`. The Rec.709 transform is applied by the Mac
  before the frame is served; the switch is `lumina.video.preview(on)`.
- The gates for all of this are `Tests/probe/scenarios/video-budget.json` (`probe.sh video`).
