# Parity spec · Lumina v5

Measured at 1440×900. Colours are hex. Sizes in px. "System" = `-apple-system, BlinkMacSystemFont, "SF Pro Text"` with tabular numbers. "Serif" = `"Iowan Old Style", Palatino, Georgia`, weight 400.

## Tokens
- Background `#1E1D1B` · panel `#262523` · raised `#2A2927` · toolbar `#262523` · loupe `#3A3835` · control fill `rgba(239,236,230,0.08)` · segmented thumb `#5B5854`
- Text `#EFECE6` · secondary `#B8B3AB` · tertiary `#96918A` · on-loupe secondary `#CFCAC2`
- Accent (keep, primary action, sharpest) `#FFD27A` · kept badge `#FFECCD` · ok `#9ED7B0` · error `#FFB4A2`
- Radii: tile 3 · chip 5 · control 7 · button 10–12 · panel 12–16
- Focus ring: 2 px `#FFD27A`, offset 2, keyboard focus only
- Motion: fades 120–160 ms ease-out · segmented thumb 200 ms · large view in 220 ms (backdrop) + 280 ms (photo 0.94 → 1) · out 200 ms · tree expand 280 ms `cubic-bezier(0.2,0.8,0.2,1)` · thumbnails fade in 180 ms on load · reduced motion turns all of it off

## Window
- [ ] Toolbar 52 high. "Lumina" in Serif 21 at left. Segmented control centred: Open · Cull · Save, each 88 × 24, 13 System, thumb slides 200 ms. "saved" in 12.5 tertiary at right (browser only).
- [ ] 2 px loading bar under the toolbar while reading, fill `#B8B3AB`, width = done / total.
- [ ] Key bar 34 high at the bottom: keycaps 20 × 20 radius 5 (arrows 15 px), label 12.5, only keys valid for the unit under the cursor. Right side: "N rows to go · K kept". Footer messages replace the keys for 1.2 s, sentence case.

## Open
- [ ] Two cards side by side (min 300): Card (title "Card" 12 semibold, line `SONY-A7M4 · 104 ARW · 3.6 GB · /Volumes/Untitled`, second line body + time range, "Read-only. Files stay on the card.", gold button "Cull This Card") and "Folder or card" with a ⌘O keycap tile and "Open…". No card → only the ⌘O tile.
- [ ] Access banner above them when macOS denied access (see SAFETY.md 5).
- [ ] Recent: cards (min 220) with date in Serif 21, a 4 px seen bar, "N photos · K keepers", "S / N seen · last DSC…", path in tertiary. Hover / ↑↓ selection ring 1.5 px `rgba(255,210,122,0.6)`.
- [ ] Footer: "FAQ" link · "DM Aniketh Maddipati on X · @aniketh745".

## Cull
- [ ] Rows: header 30 high: "09:25 · 37 photos ·" then "N kept" (+ " · seen" once left), right side the reason in secondary ("12 min gap", "24 → 85 mm"). Row tooltip explains the rule.
- [ ] Tiles 96 / 144 / 216 wide, 3:2, gap 8. Picture only. Current tile ring 2 px bg + 4 px `#EFECE6`. Kept: ✓ circle 18 top-left. Flagged: "flag" chip bottom-right. Focused tile: Keep pill bottom centre ("Keep" dark / "✓ Kept" light), click toggles.
- [ ] Portrait: 1 px dotted outline `rgba(239,236,230,0.38)` around the 2:3 image area.
- [ ] Closed stack: sharpest frame as cover, badge top-left ("31", "±3", "2 kept · 31"), two 1 px strokes on the right edge offset 2 and 4.
- [ ] Open stack: its frames start a new line, preceded by an axis row 26 high: "burst · 31 · continuous drive" (or "≤2 s apart, similar"; brackets "bracket · 3"), start time, a track with a tick per frame at capture time (current 3 × 14 white, sharpest 2 × 10 gold, others 2 × 6), span, current relative time. Frames labelled "sharpest" / "peak" top-right.
- [ ] Import notes panel at the top after reading (see CHANGES §7), "OK" dismisses.
- [ ] Card removed banner at the top when the card goes away.
- [ ] Moves: moved photo pulses 5 px gold for 1.4 s and the view scrolls to it.

## Large view
- [ ] Surround `#3A3835`, 20 padding. Photo as `<img>` at its aspect, hairline `rgba(239,236,230,0.1)` + shadow `0 10px 36px rgba(0,0,0,.4)`; preview behind it until the full image decodes. Z: 260 % zoom at a per-stack region, "100%" chip top-right.
- [ ] Nav row (stacks and rows with 2+ units): left "12 / 31" 18 bold + "sharpest" / "2 kept" / "row 09:25"; 13-frame strip (current 66 × 44 with ring, others 48 × 32, sharpest 1.5 px gold ring), "+N" counts; right: state "kept" / "flagged" / blank.
- [ ] Axis under it, max 760 wide, same tick rules; labels start clock time, current (relative in stacks, clock in rows), span.

## Save
- [ ] Sticky bar at top: title in Serif 28 ("88 keepers of 721" / "No keepers yet"); secondary button then primary. Before save: secondary "⌘R Show in Finder", primary gold "⌘⏎ Save 88 keepers". After save: primary "⌘R Show in Finder", secondary "⌘⏎ Save again". Any keeper change resets to before-save. On a card: primary becomes an outlined "copy to disk first" and an alert panel explains.
- [ ] Two lines under the bar: "Saves an .xmp sidecar rated 3★ next to each keeper, e.g. DSC03311.xmp." and the Lightroom / Capture One line. Rating follows Settings.
- [ ] Result: "88 saved" (+ " · N failed"), app line, errors one per line "DSC03311 · locked".
- [ ] "88 sidecars · 9.5 KB · /Volumes/Untitled" row with ▸ that rotates 90°; expands a folder tree (folder rows with counts and sizes, up to 8 files each with "new · 3★" and size, "+N more").
- [ ] Keepers grid (min 120) with "Back to Cull ⌘2"; click a keeper to open it in Cull.
- [ ] Empty: "No keepers yet", one sentence, gold "Back to Cull ⌘2".
- [ ] "Last save 17:52 · 88 keepers → path". "Remove Lumina's working files (N MB)".

## Overlays
- [ ] ? sheet: grammar in four columns + This shoot + Contact. Keys max 170 wide.
- [ ] FAQ: 820 wide, Serif title, sections from FAQ.md.
- [ ] Settings (⌘,): Keeper rating 1–5★ · Auto-advance On / Off · Tile size 96 / 144 / 216, segmented, "Done".
- [ ] Permission sheet (before the first folder or card): macOS text in the app, Chrome text in the browser; "Don't show again", "Cancel", "Choose Folder…".
- [ ] Tooltips: 750 ms delay, dark `#2E2D2A`, 12 px, hide on key, click, scroll.
