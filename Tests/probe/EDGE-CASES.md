# Lumina edge-case checklist → how each one is broken on purpose

Every item gets an automated probe scenario unless it's marked **manual**. Run with
`bash Scripts/probe.sh <suite>` (see the script header). ★ = minimum before Reddit.

Status (2026-09-29, handoff v6, native ingest):
- **pass**: scenario runs green today.
- **gap**: scenario runs and fails because the page falls short of the checklist. The fix goes to design first, because the HTML and `lumina-core.js` ship unchanged.
- **red**: perf budget scenario, failing until Phase 4.
- **P2** / **P3**: needs the native bridge (Phase 2) or the demo layer removed (Phase 3). The injection method is fixed below.
- **manual**: needs a third-party app or a human.

Fault injection never touches a real card. "Card" below means a disk image built from forged fixtures (`hdiutil create -fs ExFAT`, attached under the run's output folder), and in the probe the card watcher only accepts those images, so a real card that happens to be mounted is ignored. Run: `LUMINA_FIXTURE_ROOT=… bash Scripts/probe.sh fault`.

## Files

| # | Case | How the harness breaks it | Status |
|---|---|---|---|
| F1 ★ | Card pulled mid-copy (Export RAW) | `fault-card-pull-export`: 36-photo card image pulled mid RAW + JPEG export. Stops after 33 verified files, says "the card was removed · re-insert it and export again", journal `ok=false` with the done list, no temp files, copies byte-identical to originals. | **pass** |
| F2 | Card pulled mid-read (culling) | `fault-card-pull-read`: 200-photo card image pulled while "⏎ Cull this card" reads it natively. The readers stop on the unmount notice (0 files opened after it, 0 reads in flight), the page keeps what it read and says "Card removed · 25 of 200 read · re-insert to keep going" (`lumina.read`), previews of read photos still show; re-insert revives them before any re-read, ⏎ reads all 200 with 0 unreadable. `fuzz-app-card`: 2,000 seeded inputs with the card pulled/re-inserted at random, app invariants every 20. | **pass** |
| F3 ★ | Destination disk full | `fault-disk-full`: RAW + JPEG to a 40 MB disk is refused before any write ("Not enough space…"), no files, no temp files; a small XMP export to the same disk still works. `fault-native-dest`: the disk fills up *during* the copy (after the up-front check passed): stops with "… is full · every file written before this one is complete and checked", no partial or temp file, the written copies hash-equal to the originals. | **pass** |
| F4 | Destination = card or inside source | `app-export`: picking the source folder is refused and asked again. `fault-native-dest`: a folder outside DCIM on a card image is refused per file, nothing written. `SetsTrustTests`: a symlink inside the destination that leads into the source is refused per file (it used to write the .xmp next to the originals); names can't climb out with `../`. | **pass** |
| F5 ★ | Duplicate DSC numbers | `dup-dsc` (page: both kept, distinct sidecar paths). Bridge: a different file with the same name gets `-2`, the same file is recognised by SHA-256 and skipped (`SetsFileOpsTests`, `app-export` re-send). | **pass** |
| F6 ★ | Existing .XMP / .xmp / both | `app-xmp-lightroom` on real Lightroom 9.3.1 sidecars (`forge_fixtures.sh` lr-sidecar): .xmp and .XMP each merged into the right name, only stars and label change, 150–158 `crs:` settings byte-identical, exiftool reads the same stars; into a folder holding Lightroom's files each old file is kept as `.lumina-bak` (byte-equal). "Both" needs a case-sensitive volume: not run. | **pass** (upper, lower) |
| F7 | Read-only / locked card | `fault-readonly-card`: read-only card image reads all 12; choosing it as the export destination is refused and asked again. | **pass** |
| F8 | Network drive, iCloud not downloaded | SMB share to localhost, plus `brctl evict` on files in a test iCloud folder. Check: clear message, no hang (probe hang watchdog 5 s). | P2 |
| F9 ★ | Lightroom writing .xmp during export | A writer process rewrites the target .xmp in a loop during export. Check: atomic write, re-check before write, no torn file. The real-Lightroom run is **manual**. | P2 |
| F10 ★ | Crash / quit mid-export | `fault-kill-mid-handoff`: a real process runs the app's export (6 RAW + 6 .xmp, half replacing an older sidecar) and is SIGKILLed 24 times at seeded points (inside a file, between files, before the first). After each: the app's launch recovery (`SetsExportJournal.recover`) removes Lumina's own temp files and nothing else, no .xmp is torn, journal-done files are verified, old sidecars are untouched or kept as `.lumina-bak`; exporting again completes. The page can't list done vs not done yet (design). | **pass** (files) · list: design |
| F11 | .lumina-bak before every overwrite | `app-export` (changed re-export → exactly one `.lumina-bak`), `SetsFileOpsTests` (old bytes kept, identical bytes not rewritten, no temp files left), `SetsTrustTests`: a second export no longer replaces the backup, so it stays the pre-Lumina original (it used to become Lumina's first export). | **pass** |

## Camera data (these run in the page's own JS today, via `Tests/probe/forge_fixtures.sh`)

| # | Case | Scenario | Status |
|---|---|---|---|
| C1 | Wrong clock / time-zone jump | `edge-tz-jump` | **gap**: rows split, but there is no "shift shoot time" |
| C2 ★ | Two bodies in one folder | `edge-two-bodies` | **gap**: the serial is never read, so photos interleave by time |
| C3 | Dual-slot α7 III (same shots on both cards) | Open both slot folders. Check: no duplicates (needs body serial + counter + time key). | P2 · likely gap (no serial) |
| C4 | 10 fps burst inside one second | `edge-burst-10fps` | **gap**: the frame 1 s later joins the burst (rule is ≤ 1 s, EXIF has whole seconds) |
| C5 | No / tiny / corrupt preview | `edge-corrupt-preview` | **gap**: 3 of 5 dropped as unreadable, with no placeholder, and they can't be exported |
| C6 | Compressed, lossless, pixel-shift, APS-C crop | Needs one real sample of each. | fixtures needed |
| C7 | ARW + JPEG pairs → one photo | `edge-junk-in-folder` | pass |
| C8 | Orientation 1, 3, 6, 8, missing | `edge-orientation` | pass (portrait flags); upright pixels checked in the pixel pass |
| C9 | Shutter-only bracket → split/merge fixes it | `edge-shutter-bracket` | pass |

## Lightroom / Capture One: manual, with a scripted half

| # | Case | Check | Status |
|---|---|---|---|
| L1 | Photos already in LR with unsaved edits | Warning copy exists in Export. The behaviour check is **manual**. | manual |
| L2 | After Read Metadata from Files | Scripted: exported .xmp round-trips through exiftool (stars and label). Visual in LR is **manual**. | P2 + manual |
| L3 | Custom LR colour-label set | Documented copy is present. | manual |
| L4 | Capture One without XMP preference | Instruction line present when the C1 target is picked (page scenario). | page check possible now |
| L5 | Reject (−1) behaviour in LR | Verify before promising it. | manual |

## Mac app / WKWebView

| # | Case | How | Status |
|---|---|---|---|
| M1 ★ | 5,000-photo card | Synthetic card: header+preview-only clones of the 721, retimed, 5,000 files on a disk image. Budgets: scroll p95 ≤ 17.5 ms, web process ≤ 1.5 GB, memory flat over a 10-minute fuzz. | **red**: 721 photos already hit p95 30–36 ms and 1.45 GB (`card-stress`) |
| M2 | Stale folder permission after restart | Debug hook drops the bookmark, then relaunch. Check: detected, asks again. | P2 |
| M3 | Sleep / wake, drive spin-down | Inject `NSWorkspace.willSleep/didWake` through a debug hook, and detach/re-attach the image. A real lid-close run is **manual**. | P2 |
| M4 | File deleted / renamed in Finder while culling | `app-rename-mid-cull`: two kept files renamed / deleted mid-Cull. Culling, large view and invariants keep working; the preview already read still shows and the original isn't read again (404); a RAW export of the renamed file stops with "… is no longer in tb · moved, renamed or deleted?" (it used to say the card was removed), nothing written, not even a folder; other files still export; the renamed original is byte-identical; reopening keeps decisions whose files still exist and shows the renamed file as new and undecided. `SetsTrustTests`: truncated after the listing → preview refused; symlinks inside the folder neither listed nor followed. | **pass** |
| M5 | Fast keys while previews load | Key storm during `openFolder`. Check: each action hits the photo focused at keydown (probe logs the focused id per key). | page scenario possible now |

## People

| # | Case | How | Status |
|---|---|---|---|
| P1 | Undo after export | Page scenario: export, then Q. Check: copy says written files aren't undone. | page check possible now |
| P2 | Same folder twice / two windows | Launch the app twice, open the same folder. Check: one session, or blocked. | P2 |
| P3 | Non-Sony files skipped quietly | `edge-junk-in-folder` (CR3, txt, `.DS_Store`, `._` stubs), page read and native read (`probe.sh ingest`) | pass |
| P4 | VoiceOver, larger text, reduced motion | AX tree audit of the WKWebView (every control has a role and label). Reduced motion and VoiceOver are **manual**: the harness never changes system settings. | manual + P2 |

## Export look
| # | Case | Scenario | Status |
|---|---|---|---|
| X1 | JPEG export looks like Edit (ANSWERS §3) | `look-parity`: 5 recipes through `LuminaCore.editFilter`, WebKit CSS vs the app's Core Image. Mean ΔE 0.40–0.62 (gate < 1). p95 0.79–1.12, max about 2.4, from WebKit's 8-bit fixed-point filter path. | **pass** |

## Native read (gates 1–3)
`probe.sh ingest` runs every camera edge case through the native reader: same verdicts and the same per-step results as the page's own read. On the real 721-ARW α7 III card (`card-clock.json`, both modes): all 721 photos bit-identical to the page's read on every field (time, measures, sharpness rank, kind, soft/blown/shake, suggestions), 10.4–10.8 s vs 11.8–12.2 s, first photo 190–225 ms vs 270–290 ms; web process during culling 953 MB vs 1,178 MB (`card-stress-app`). Evidence: `~/LuminaEvidence/gates-2026-09-29`.

## Always on, every scenario
- Any `console.error`, uncaught error, render error, web-process crash, or page silent for more than 5 s fails the run.
- Page invariants are checked after every step and every 20–25 fuzz inputs: focused photo exists, marks are valid, no duplicate ids, undo stays a list.
- App mode adds the state surface (`__lumina.inspect()`) and the Mac reader's own counters: no large preview held by the page, zoom = large view, read counts add up to the listing, no file opened after its card was pulled, reads in flight within the limit, no single read larger than 16 MB (never a whole RAW).
- CPU and memory of the app and the web process are sampled every 200–250 ms and checked against the budgets.
- A seeded fuzzer (keys, held keys, clicks, drags) replays exactly from its seed. The last 60 inputs are printed on failure.
