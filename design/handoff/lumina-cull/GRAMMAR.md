# Lumina Pick grammar (v0.02)

Generated from `lumina-v4-data.js` → `GRAMMAR`, which the ? sheet shows word for word. If the two ever differ, the data file wins.

```
LUMINA PICK GRAMMAR
Rule: ⏎ goes forward, ⇧⏎ goes back. ⇧K keeps, ⇧R marks for removal. Green is kept, red is removed. Arrows just pass. The cursor acts on the unit under it. ⇧ works inside a stack.
Unit = a photo, or a closed stack (burst/bracket). Two states: kept or not. Nothing is deleted; Save lists what wasn't kept and offers another pass, as many as you like. Every decision is one undo step and reports in the footer.

MOVE
←→            next / previous photo · on a stack: through its frames, then on · hold repeats
⇧←→           same, and stops at the ends of a stack
↑↓            row above / below, same column · on a stack: ↓ opens, ↑ closes
⌥←→           skip a whole stack or run of singles
⌘←→           previous / next row
⌥↑↓           previous / next group in a row not yet seen
⏎             next photo · closed stack: open · open frame: next frame · after the last frame the stack closes · changes nothing
⇧⏎            the same, going back · hold either to repeat
⌥↓            next row not yet seen
esc           close the stack

DECIDE (the unit under the cursor)
⇧K            keep, next · again: un-keep · closed stack: every frame
⇧R            mark for removal, next · again: clear · closed stack: every frame
K R           alone: not used · the footer names the right key
⇧K ⇧R         in an open stack or large view: the frame shown
⌘A            keep every photo in this row · 600 ms preview · esc cancels · one undo
Q / ⌘Z        undo · ⇧Q / ⇧⌘Z redo · the key bar shows how many steps each way
⌥⌘⌫          start over · press twice · clears every keep for this shoot · one undo step
U L G Y 1–5   not used · the footer names the right key
⇪ Caps Lock   auto-advance off while on

SEEN · PASSES
a row is marked seen when the cursor leaves it
⇧U            rows not yet seen only
⇧P            start the next pass: only what you kept · ⇧K keeps, ⇧R removes · rows reset to not seen
              later ⇧P just shows this pass's photos or all photos · Save lists every pass: All → Pass 1 → Pass 2 …
⇧P again      all photos, picks tray hidden · ⇧P once more shows the tray · esc: all photos with the tray
picks tray  along the bottom · every pick in time order · click one to jump

VIEW
Space         hold: large view while held · tap: toggle · a stack opens at its first frame · ←→ within the stack, else the row
Z hold        100% · in a stack the same region on every frame · drag moves it
time axis     large view and open stacks · capture time per frame · gold: most detail · ≈: estimated
− +           tile size: small / medium / large, scaled to the window
B / ⇧B        split / merge here (row or stack)
H             hide key bar · ?  all keys
Tab           move between buttons · ⏎ or Space presses the focused one · esc returns to the grid

CLICK
click                         focus · the Keep button on the focused photo keeps / un-keeps
click row header              focus the row
double-click photo or stack   large view · double-click again closes
double-click stack badge      open the stack
double-click row header       focus the row · ⌘A keeps every photo in it

DRAG
hold ⇧K or ⇧R + drag  paint keep / remove across tiles · esc cancels · one step
row header ↑↓         move the boundary a group at a time · onto the previous header merges
stack edge → / ←      open / close the stack

DROP
tiles → row header    move those photos to that row · onto a stack merges · between rows splits
tiles → outside       drags the RAW files (copies) to Finder, Lightroom, Capture One, Mail

TRACKPAD
two-finger ↕          scroll
two-finger ↔          in an open stack or large view: scrub frames
pinch                 tile size, centred on the cursor
force click / 3-tap   large view while held
⌥ + two-finger ↔      previous / next group
(no decisions by gesture · rotate and pinch in large view ignored)

SETTINGS
⌘,            pick rating (1–5★, default 3) · auto-advance · arrows enter stacks · tile size

STEPS
⌘1 Open · ⌘2 Pick · ⌘3 Edit · ⌘4 Save · ⌘O open a folder or card · ⌘R Show in Finder (Pick: the photo · Save: the folder)
Open: ↑↓ choose · ⏎ open
Save: ⌘⏎ save · one sidecar per photo that made a pass: rating = last pass made, keyword “Lumina pass N” (one pass: the Settings rating) · read by Lightroom Classic and Capture One
Guards: with undecided photos left, ⌘⏎ asks once · opening another card with unsaved picks asks once · esc stays
```
