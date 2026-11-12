# 00c · The hand kit: shared interaction pieces every task uses

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-hand-kit` from origin/main.

**Goal.** Build, once, the interaction pieces in `docs/editing/UX.md` ("The grammar", "Repeat is built
in", "Polish"), so each feature prompt only adds its own pick and its own drag. Read UX.md in full; it
is the spec.

**Build** (page: `Lumina Edit v23.dc.html`; Skim's viewer mirrors it in step 6b):
- **Press-picks dispatch.** A press on the canvas asks the open task what is under the finger and hands
  the drag to that task's handler.
  - Each task registers `{pick(x,y) → target, drag(target, dx, dy, mods, pinch, rotate)}`.
  - Today's handlers (`vigDown`, `histDown`, ⌥-drag colour, crop) move onto it unchanged in behaviour.
  - With no task open, a press = Light (tone under the finger); the Light task in 01 fills it in. Until
    then, exposure.
- **The puck.** A 1 px ring (28 px) under the pointer while dragging, with what was picked and one
  value in 12 px tabular figures, plus the footer sentence. Tokens from UX.md only.
- **Detents + haptics.** A soft snap at 0, as-shot and the original value; ⌥ disables it.
  - A native `haptic` bridge op (`NSHapticFeedbackManager`, `.alignment`) fires on each detent.
  - A row in `docs/release/TRUST.md`, and a contract test in `Tests/web/plumbing-harness.mjs`.
  - No-op in browsers and in the probe.
- **Gestures.** Pinch (`gesturechange` scale) and two-finger rotate (`gesturechange` rotation) routed to
  the active drag. Force Touch pressure (`webkitForce` / `pointerevent.pressure`) for painting tasks.
  None of them may fight two-finger ↔ = next photo: they only apply while a press is held.
- **Chrome dim while dragging** (panels to 40 %, 120 ms) and **hover handles** (only within 80 px).
- **Select, then touch (carry preview).**
  - With a filmstrip selection, a drag previews on the selected thumbnails: small-tier renders through
    the image path (`lumina://render … tier=small`), at most 24 at once, newest wins.
  - The `× N` chip by the puck.
  - Release hands the move to the carry solver (prompt 22). Until 22 lands, it copies the look the
    way `matchScene` does.
  - One ⌘Z for all.
- **The fan.** Hold-key radial tiles around the pointer: distance = strength, release applies, release
  at the centre cancels. Used by Looks (19, 23) and the grade agent (05b). Ship it with a stand-in set
  (the photo's variations) so it can be tested.
- **Contact sheet:** Space's large view shows the selection when there is one.
- **The task rail:** Light · Colour · Grade · Detail · Masks · Retouch · Crop, replacing the current
  sections. Rows fold to one line; every gesture keeps a slider twin. Owner sign-off on the rail
  before landing: send screenshots and stop for a yes.

**Done when.**
- Every existing gesture works through the dispatch with no behaviour change; plumbing-harness and the
  parity screens are equal except the intended rail change.
- Puck, detents, haptics, pinch / rotate / pressure, dim, hover handles, carry preview and the fan each
  have a test in `Tests/web` (Chromium, plus WebKitGTK for gesture events).
- The carry preview over 24 thumbnails keeps the canvas at p95 ≤ 16 ms (`probe.sh edit`).

**Depends on:** none. Run it in wave 1, before the feature prompts that use it (all of them).

**Skim (video) mirror.** The same kit on Skim's viewer and scene selection: puck, detents, haptics
(the same bridge op), fan and carry preview on the scene's clip tiles. One shared JS module if both
pages can load it under the page-files rule (`Scripts/page_files.sh`); otherwise the same code in
both pages, held equal by a test.
