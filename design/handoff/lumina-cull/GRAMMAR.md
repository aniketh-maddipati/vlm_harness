# Lumina grammar (v5)

Rule: the cursor acts on the unit under it. It is the only selection. P or R keeps. ⇧ works inside a stack.
Unit = a photo, or a closed stack (burst/bracket). Every decision is one undo step and reports in the footer.

## Move
```
←→            next / previous photo · on a stack: through its frames, then on · hold repeats
⇧←→           same, and stops at the ends of a stack
↑↓            row above / below, same column
⌥←→           skip a whole stack or run of singles
⌘←→           previous / next row
⌥↑↓           previous / next group in a row not yet seen
⏎             closed stack: open at the first frame · open stack: done, move on · photo: next unseen row
esc           close the stack
```

## Decide (the unit under the cursor)
```
P / R         keep / un-keep (right or left hand) · closed stack: sharpest · bracket: all · T also works
F             flag for later (not saved while flagged)
P R F         in an open stack or large view: the frame shown
⌘A            keep every photo in this row · 600 ms preview · esc cancels · one undo
⇧P / ⇧R       stack (open or closed): keep the sharpest only · bracket: all
⇧F            stack (open or closed): flag all · again: unflag
Q / ⌘Z        undo
X U L G 1–5   not used · the footer names the right key
⇪ Caps Lock   auto-advance off while on
```

## Seen
```
a row is marked seen when the cursor leaves it
⇧U            rows not yet seen only
```

## View
```
Space         hold: large view while held · tap: toggle · a stack opens at its first frame · ←→ within the stack, else the row
Z hold        100% · in a stack the same region on every frame · drag moves it
time axis     large view and open stacks · capture time per frame · gold: sharpest · ≈: estimated
− +           tile size: small / medium / large, scaled to the window
B / ⇧B        split / merge here (row or stack)
H             hide key bar · ?  all keys
Tab           move between buttons · ⏎ or Space presses the focused one · esc returns to the grid
```

## Click
```
click                         focus · the Keep button on the focused photo keeps / un-keeps
click row header              focus the row
double-click photo or stack   large view · double-click again closes
double-click stack badge      keep sharpest
double-click row header       keep every photo in the row · ⇧ clears the row · one step
```

## Drag
```
hold P or R + drag    paint keep across tiles · esc cancels · one step
row header ↑↓         move the boundary a group at a time · onto the previous header merges
stack edge → / ←      open / close the stack
```

## Drop
```
tiles → row header    move those photos to that row · onto a stack merges · between rows splits
tiles → outside       drags the RAW files (copies) to Finder, Lightroom, Capture One, Mail
```

## Trackpad
```
two-finger ↕          scroll
two-finger ↔          in an open stack or large view: scrub frames
pinch                 tile size, centred on the cursor
force click / 3-tap   large view while held
⌥ + two-finger ↔      previous / next group
(no decisions by gesture · rotate and pinch in large view ignored)
```

## Settings
```
⌘,            keeper rating (1–5★, default 3) · auto-advance · arrows enter stacks · tile size
```

## Steps
```
⌘1 Open · ⌘2 Cull · ⌘3 Save · ⌘O open a folder or card · ⌘R Show in Finder (Cull: the photo · Save: the folder)
Open: ↑↓ choose · ⏎ open
Save: ⌘⏎ save keepers · one sidecar per keeper, read by Lightroom Classic and Capture One (⏎ alone does not save)
```
