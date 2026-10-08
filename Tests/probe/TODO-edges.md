# To do: look at these on Lumina Dev

Checked already, in Chromium with the real page and `plumbing.js` (`node Tests/web/plumbing-harness.mjs`, all ok on 2026-10-08):

- Crop keeps the Metal layer up. Straighten and pinch reach the app as an angle, a cover scale, and a box. A second Crop does not stack a second angle. At 0° the app is told 0.
- The crop grid is a thin hole. The dim around the frame is not a hole. The Ratio / Straighten bar is a hole. There is no filled degree badge on the photo.
- Edit opened while a folder is still being read names each file with the folder, and the end of the read stays in Edit.
- The Open card's Edit button is remembered, so the read lands in Edit.

The probe's hidden window does not capture the Metal photo, so the pictures below are still a person looking at Lumina Dev. `Tests/probe/scenarios/crop-edges.json` is the short data check (`LUMINA_FIXTURE_ROOT=~/LuminaEvidence/fixtures bash Scripts/probe.sh scenarios crop-edges`). It does not show whether the photo turned.

## Crop (Edit v23, a 3:2 photo)

- [ ] Open Crop. The photo fills the canvas just under the bar, with a small margin at the sides and bottom. It is not a small frame floating in the middle, and it is not square.
- [ ] Drag Straighten. The photo turns with the frame. One photo, not two copies on top of each other.
- [ ] The angle is on the Straighten control, with "keeps n%" when it applies. Nothing is pasted on the picture. The hint sits at the bottom-left and does not cover the bar.
- [ ] The grid is a faint line over the photo. No black cross, no black seams through the picture.
- [ ] Grid steps through thirds, quarters, golden, diagonals, centre cross, none. Under a narrow window the button says only "Grid" and the footer names the one you picked.
- [ ] **0°** sets the angle to 0.0° and leaves the frame and ratio. It is greyed when the angle is already 0. One ⌘Z puts the angle back. Footer: "Straighten 0.0°. ⌘Z undoes it."
- [ ] **Reset** on the bar, and **Reset crop** on the Cropping row, both go back to Original, 0.0°, and the whole photo. One ⌘Z undoes that one reset. Footer: "Crop reset. ⌘Z undoes it." Reset does not leave Crop, apply, or cancel.
- [ ] Pinch and pan while Crop is open. The photo follows. Letting go settles to the sharp picture.
- [ ] Apply, leave Crop, open Crop again. The same angle, once. Apply again. Still once.
- [ ] Two undos after a re-apply return to the uncropped photo. One undo only removes the second apply.
- [ ] A portrait from `~/LuminaEvidence/fixtures/orientation` (DSC00102 or DSC00103) opens in Edit upright, and Crop uses that shape.
- [ ] Quit and reopen the same folder. The applied crop is still there. It is in the session, not in the `.xmp`.

## Edit while a folder is opening

- [ ] On the Open card, with a card in, click Edit. When the read finishes you are still in Edit, on the photo Pick would have been on. A closed stack opens on its cover.
- [ ] Edit does not ask you to keep something first. The footer does not say "No photos to edit. Keep some in Pick first."
- [ ] Switch to Edit halfway through a long folder. You stay in Edit when the read ends, and the photo on the canvas is a real file from that folder.

## Filmstrip (Prompt 21, not checked in the app)

- [ ] Each Pick row shows its time ("19:50") beside its frames, at a wide window and at a narrow one.
- [ ] Every frame of a burst is its own tile. The position count includes those frames.
- [ ] With nothing kept, the filmstrip still shows the shoot. It does not sit on "No picks yet."

## Window

- [ ] Drag the window taller and wider than 1440×900. The page fills it. There is no empty grey band underneath.
- [ ] Drag it back down. The page follows. It does not go below 1024×700.
- [ ] In Edit, resize during a slider drag and during Crop. The photo stays in the canvas box. The canvas does not keep the old rectangle.

## 100% view

- [ ] Hold G, or zoom past 100%, and pan. The photo moves on the next frame, not a beat later.
- [ ] While you are still panning, the facts line does not flicker through a new RAW 9 region on every move. After you rest, it refines.

## Not this pass

- Screen references are still the v11 pictures. `bash Scripts/probe.sh screens` will differ until the new look is approved and recorded (`sets_sync_design.sh --record`). Do that after the list above, not before.
- `lumina.still` is not implemented. Crop uses the Metal layer. If Crop ever shows only the thumbnail, the layer was hidden and that call is the missing piece.
- The filmstrip, the grid choices, Reset, and 0° are the page's. If one of them is missing or worded wrong, it goes in `design/handoff/DESIGN-ASKS.md`. It does not get patched in this repo.
