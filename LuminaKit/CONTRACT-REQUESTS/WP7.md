# WP-7 (Save): contract requests

Nothing here blocks WP-7; each has a workaround in place.

1. **`ExportJob.removed: [Photo]`** (Protocols.swift). A photo that was saved as a keeper and is
   then taken out keeps its 3★ sidecar: the job only carries what is kept, so the exporter can't
   take the rating back. `changedOnly` already names the id; the exporter has no `Photo` for it.
   Workaround: the old sidecar stays as it was.

2. **As-shot white balance on `Photo`** (`asShotKelvin`, `asShotTint`; Models.swift, filled by
   WP-2 or the app's adapter). Lightroom only honours Temperature and Tint as a pair, so a look
   with one of them needs the other's as-shot value. Workaround: `EditSetting.asShotKelvin`
   (5200) and tint 0.

3. **`SaveState.saving` doc comment** (AppModel.swift) says clicks and ⌘S are ignored while a
   save runs. They can't be: the recorded `save-flow` trace saves, changes the format and saves
   again without the main actor ever yielding, so a save that waited for the first export would
   be dropped. WP-7 records each save at once and queues the exports one after another;
   `saving` is true while any export is running, and gates nothing. Please reword the comment.

4. **`SaveState.messageIsError`** (AppModel.swift). A failed export shows its message in
   `save.note` in the error colour. Workaround: the flag lives in `SaveFeature`
   (`model.saveFeature.messageIsError`).

5. **`save.summary` is the header block** (ACCESSIBILITY_CONTRACT.md). `test_R57_R58_noDeadBands`
   measures the dead band from the tabs to `save.summary` (≤ 72 + 40) and wants it as wide as the
   column. With the title above the summary and LAYOUT_SIZING's top padding (up to 72) that only
   holds if the element starts at the title. WP-7 gives the identifier to the group
   "title + subtitle + summary" (label = the summary text, children still reachable). If the
   contract means the one line, the test's `first` for Save needs to be the title instead.

6. **Design asks (copy the design doesn't have).** For `design/handoff` rather than the contract:
   - the message when some files could not be written ("2 of 12 photos weren’t saved:
     DSC03311 · on the card, and 1 more. Nothing was lost. Save again to retry.");
   - "Change…" for Lightroom: sidecars always go next to each photo, so it is shown disabled
     there (the prototype shows it for every format);
   - the message for a destination on a card ("Pick a folder that isn’t on the card. Lumina
     never writes to the card.").

7. **AGENTS.md "Parity" says looks are never written to XMP.** The new handoff's README §4 says
   "edits as develop settings", and WP-7 follows it (`XMPSidecar.develop`). The mapping is
   unverified against Lightroom (crop angle sign, the curve as a point curve, vignette style);
   the parity harness should own it before the app switches to `FileExporter`.
