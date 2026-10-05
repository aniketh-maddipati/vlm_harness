# TEST PLAN: v0.01

Tick each row on real hardware and write a note for anything that isn't a clean pass. Apple silicon, latest macOS, built-in SD slot and a USB reader.

## Automated
- [ ] `node lumina-core-v4.test.mjs`: no FAIL. Add fixtures for: an iPhone ProRAW DNG (preview found through SubIFD strips), a Pixel DNG, a Samsung Expert RAW DNG, a Leica or DJI DNG (must **not** count as a phone), and an ARW with Make SONY.
- [ ] `phoneOf` unit cases: Apple/iPhone → phone · Google/Pixel → phone · samsung/SM-S918B → phone · samsung/NX500 → camera · SONY/XQ-DQ54 → phone · SONY/ILCE-7M4 → camera · empty make → camera.
- [ ] `?selftest` in the app: all pass. Timing at `?selftest&n=1000`.

## Open
- [ ] Card insert → Card panel. Non-Sony card → quiet line, card not hidden.
- [ ] ⌘O, the "Go straight to" buttons, and drag a folder from Finder → same shoot.
- [ ] Folder with ARW + JPEG twins → twins skipped silently. JPEG/HEIF with no RAW → note.
- [ ] iPhone export folder (unmodified originals) → DNGs open. HEIC twins skipped.
- [ ] Access denied → banner → Settings → back → retry works.

## Pick
- [ ] Bursts open in place, top frame pinned, rest fade in below. ← → order: top, its row, then the unfurled frames.
- [ ] Mixed Sony + iPhone shoot: "bodies" note names both. Phone rows split on 1× ↔ 3×.
- [ ] Big view Measured column: edge detail, shutter vs focal (phone uses 35 mm eq.), highlights recoverable/all channels, focus point vs sharpest.
- [ ] Hold F/E/M/B overlays. Z 100%. Pinch zoom on trackpad.
- [ ] Window widths 900, 1280, 1440, 1920, 2560 and full screen: tiles resize until set in Settings. Big view columns hide < 980 px. Nothing clips.

## Phone upload page (v0.0.1)
- [ ] Open → Add from phone opens **Phone photos** and does not jump into Pick.
- [ ] iPhone AirDrop with All Photos Data → files in Downloads → drop on page → RAW tags show, with the phone and lens.
- [ ] AirDrop without All Photos Data → HEIC tile, dimmed, "not added".
- [ ] Photos app Export Unmodified Original → drop the folder → RAWs only.
- [ ] Android over cable + OpenMTP → DNGs → drop → RAW tags.
- [ ] Watch Downloads (Comet/Chrome): AirDrop while the page is open → tiles appear within about 2 s.
- [ ] New shoot → Pick, with the name field focused. From inside a shoot: Add to <shoot> keeps its decisions. Back returns with nothing added.
- [ ] Firefox/Safari: Watch is hidden, and drop / Choose files still work.

## Phone go/no-go (file check)
Use `Phone Handoff Check.dc.html` in Chrome. Drop each folder below, then "Copy report" and save it as `fixtures/phone-<device>.json`.
- [ ] iPhone 15/16 Pro ProRAW, sent by AirDrop
- [ ] iPhone, Photos → Export Unmodified Original
- [ ] iPhone with Optimise Storage on (expect 0-byte placeholders to be caught)
- [ ] Pixel RAW (USB file mode → DCIM)
- [ ] Samsung Expert RAW
- [ ] One Leica or DJI DNG (must read as camera, not phone)

Go for v1 if, on every phone folder:
- "Read as phone" is all files
- "Preview found" is all files, each ≥ 1.5 MP
- capture time is present
- portraits show upright

If no-go on previews: native RAW decode (Core Image) becomes a v1 blocker for phones. If no-go on detection: add the Make/Model to `phoneOf` and a fixture.
Cable import (ImageCaptureCore): build a 1-day Swift spike before committing. Pass = list the device, count RAW vs HEIC vs iCloud-only, download 50 DNGs with hashes verified, nothing deleted.

## Sources
- [ ] ⌘O, the +, holding ⇧ and drag-drop in Pick all add to the open shoot. Shoot name kept. Decisions kept.
- [ ] Re-adding the same folder → "nothing new". A copy of the same RAWs elsewhere → "N already here, skipped".
- [ ] Second body with a wrong clock → merge preview with the offset. Shift lines up the rows. Keep leaves them.
- [ ] "Show only" per source dims the others. A source that disappears shows "Reconnect".
- [ ] Phone by cable: counts, iCloud-only count, import new, nothing deleted on the phone.
- [ ] Watched Downloads: new files wait under Pending until pulled in.
- [ ] A photo seen in an earlier shoot brings back its decision, and the note names that shoot.
- [ ] New shoot: the name field is focused with a suggestion. ⏎ keeps it. The name shows in the top bar, on Recent, and on Save.

## Edit
- [ ] Phone portrait DNGs keep their shape (no stretching) in the loupe, crop and variations.
- [ ] Sliders, variations follow the slider, ⇧T tone-mapper compare, edited picks bright and unedited dim.
- [ ] Working-files squares visible bottom right.

## Save
- [ ] ARW picks → .xmp with the chosen rating. Existing sidecar → rating merged, Lightroom edits kept, `.lumina-bak` written.
- [ ] DNG picks → copied to Picks/, checksum verified, originals untouched (compare hashes before and after).
- [ ] Lightroom Classic: import or Read Metadata shows ratings. Capture One: import shows ratings.
- [ ] Show in Finder (button and ⌘R) opens Finder at the right file or folder.
- [ ] Tidy up: sizes are real. Remove clears them. "This card's picks" is locked until saved.

## Trust and release
- [ ] Zero network requests in a full session.
- [ ] Card is read-only throughout: no files created on the volume, including .DS_Store from the app.
- [ ] Tour on first launch only. Reopens from ?. Esc skips.
- [ ] Beta chip → known issues + bug link.
- [ ] `lumina.debug` false: no debug links.
- [ ] Quit with unsaved picks → confirm.
- [ ] Signed + notarized build.
