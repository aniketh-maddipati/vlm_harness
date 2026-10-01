# Lumina edge-case checklist → how each one is broken on purpose

Every item gets an automated probe scenario unless it's marked **manual**. Run with
`bash Scripts/probe.sh <suite>` (see the script header). ★ = minimum before Reddit.

## v5 (2026-09-29): what changed and what still holds

v5 saves one thing: a `.xmp` sidecar per keeper, written **into the shoot folder** next to its RAW (SAFETY.md 1). There is no RAW/JPEG export, no Edit step, no destination picker. So:

| Case | v5 check | Status |
|---|---|---|
| Sidecar written next to the RAW, atomic, read back | `SetsSidecarTests` (next to the RAW, RAW untouched, no temp files), `app-smoke` (2 keepers → 2 `.xmp`, no `.lumina-tmp-*`), `app-xmp-lightroom` (the RAWs byte-identical after two saves), `Tests/web/plumbing-harness.mjs` | **pass** |
| `.lumina-bak` before replacing a sidecar (F6, F11) | `SetsSidecarTests.testExistingSidecarKeptAsLuminaBak` (kept once, never replaced by Lumina's own), `app-smoke` (second save after a Lightroom edit → the backup is Lightroom's), `app-xmp-lightroom` (real Lightroom sidecars: backups byte-equal, an unchanged second save adds none) | **pass** |
| Only `.xmp` inside the folder; never a RAW; no `../`, no link out (F4) | `SetsSidecarTests.testOnlyXmpInsideTheFolder`, `testLinkedFolderCannotLeadOut` | written; **Mac run pending** |
| No writes to a card (SAFETY.md 4) | `fault-readonly-card` and `fault-card-pull-cull`: on a card the page's Save is "copy to disk first" and ⌘↩ writes nothing. Natively every file is refused "on the card" (`fault-disk-full` step 3, `app-xmp-both`). `fuzz-app-card`: no `.xmp` on the card after 2,000 inputs. A removable volume that isn't a camera card, or a card that was pulled, still shows Save (the native refusal holds): DESIGN-ASKS #9. | **pass** · page: ask 9 |
| Per-file errors: locked, read-only, disk full, missing (F3, F7, SAFETY.md 6) | `SetsFileOps.reason`, `SetsSidecarTests.testLockedSidecarIsLocked`. `fault-disk-full`: a full disk leaves the old sidecar untouched and no temp file, but the reason reads "failed" (open bug 3). `app-rename-mid-cull`: a keeper whose RAW is gone is saved anyway (open bug 1). | **fail**: open bugs 1, 3 |
| Card pulled mid-read / remount (F2, SAFETY.md 3) | `fault-card-pull-read` (pulled mid-read: readers stop, notice, re-insert reads all 200 by itself; the keep made while it was out is lost: open bug 2), `fault-card-pull-cull` (pulled after the read: state kept, notice, no second read, no decision lost), `fuzz-app-card`. Chromium harness covers the page side. | **pass** except open bug 2 |
| Access denied (SAFETY.md 5) | listing refused → `luminaAccess(true, volume)`; `checkAccess`, `openSettings('files')`, `reopen`. Chromium harness. A TCC denial on the Mac is **manual**. | page side **pass** (Chromium) |
| Autosave every 2 s + on view change, cursor restored (SAFETY.md 2) | `app-session`: keeps, a flag, seen rows and the cursor's row survive a relaunch (page reload on the same shoot store); unsaved keepers still counted, saved ones stay saved. The page lands on the first undecided photo of the cursor's row (`land`), not on the exact photo. Chromium harness: marks by path, seen, cursor. | **pass** |
| Quit with unsaved keepers | `__lumina.unsaved()` (harness) + the Quit alert (**manual**). | page side **pass** |

### The v3 scenarios, rewritten or removed (2026-09-30)

`probe.sh v3` is gone. Each of its scenarios now asserts v5 behaviour in a real suite, or was deleted with its feature:

| Scenario | Now | Suite | Status |
|---|---|---|---|
| `app-session` | P / F / seen rows / cursor row across a relaunch; unsaved and saved keepers across a relaunch | `app` | **pass** |
| `app-xmp-lightroom` | Real Lightroom sidecars merged in place: only the rating changes, name keeps its case, `.lumina-bak` is Lightroom's file, unchanged re-save adds nothing | `app` | **pass** |
| `app-xmp-both` | `.xmp` + `.XMP` on a case-sensitive image: `.xmp` read every time and planned for Save; the image is removable so ⌘↩ is refused "on the card"; the page's bytes through the app's write (below the card check) land in `.xmp` only, backup is Lightroom's, `.XMP` never touched | `fault` (disk image) | **pass** |
| `app-empty-start` | The empty app: no sample, no recents, ⌘2 / ⌘3 stay on Open, an 800-input storm (the v3-era design ask 1 is answered by v5) | `app`, `smoke` | **pass** |
| `app-rename-mid-cull` | Keepers renamed / deleted mid-cull: culling, large view, cached preview, reopen all hold; Save must list the gone ones as "missing" | `open` → `app` | **fail**: open bug 1 |
| `fault-card-pull-read` | Card pulled mid-read, v5 keys, the card-gone notice, the automatic second read, the keep made while the card was out | `open` → `fault` | **fail**: open bug 2 |
| `fault-disk-full` | v5 has no destination disk. Now Mac layer only: the sidecar write on a full disk image | `open` → `fault` | **fail**: open bug 3 |
| `fault-card-pull-export` → `fault-card-pull-cull` | v5 never copies from a card and the page has no copy-to-disk flow (it says "copy the folder to disk first · then ⌘O"). The heir: the card pulled while its keepers wait on Save | `fault` | **pass** |
| `fuzz-app-card` | Card storm with random pulls; then all 80 read, nothing written to the card. The probe's re-insert no longer dies on "Resource busy" | `fuzz` | **pass** |
| `card-stress` | Whole-card scroll budget, fast row moves, 3,000-input storm, memory; without the Edit step | `stress` (needs `LUMINA_CARD_DIR`) | steps pass on a 12-photo folder; frame budget **red** (p95 18.0 ms vs 17.5); not run on a real card |
| `card-stress-app` | deleted: the same steps as `card-stress`; `probe.sh stress` runs `card-stress` a second time with `LUMINA_PROBE_MODE=app` | | |
| `app-export` | deleted: v5 has no destination picker and no RAW / JPEG export. Sidecars into the folder: `app-smoke`; the Mac's export job itself: `fault-native-dest`, `fault-kill-mid-handoff` | | |
| `look-parity` | deleted: v3's CSS look is gone from the page. The Edit look is checked by `probe.sh edit` (canvas vs export ΔE) and `Tools/parity` | | |

### Open bugs (found by the rewrites; app code, not fixed here)

1. **Save writes a sidecar for a keeper whose RAW is gone.** `app-rename-mid-cull`: after `A_DSC00001.ARW` is renamed and `B_DSC00001.ARW` deleted, ⌘↩ reports "3 saved" and leaves `A_DSC00001.xmp` and `B_DSC00001.xmp` with no RAW beside them. SAFETY.md 6 wants `A_DSC00001 · missing` in the result list. Where: `SetsBridge.writeSidecars` / `SetsFileOps.writeSidecar` never look for the RAW.
2. **A keep made while a half-read card is out is lost when the card comes back.** `fault-card-pull-read`: `SetsShootStore.id(for:)` hashes the volume UUID; with the card out the UUID is empty, so the shoot opened by the stopped read gets another id than the same card re-inserted. The session with the keep sits under the first id (and a second entry appears in recents). SAFETY.md 3 wants state kept across the remount.
3. **A full disk reads "failed", not "disk full".** `fault-disk-full`: with no space left `FileManager.createFile` returns false in `SetsFileOps.atomicWrite`, which throws its own `Failure`, and `SetsFileOps.reason` maps that to "failed". The old sidecar is untouched and no temp file is left (the trust rules hold); only the word is wrong (SAFETY.md 6).

The rows below (Files … Export look) are the pre-v5 checklist. Where a row cites a scenario from the table above, the table is the current state.

Status (2026-09-29, handoff v6, native ingest; before v5):
- **pass**: scenario runs green today.
- **gap**: scenario runs and fails because the page falls short of the checklist. The fix goes to design first, because the HTML and `lumina-core.js` ship unchanged.
- **red**: perf budget scenario, failing until Phase 4.
- **P2** / **P3**: needs the native bridge (Phase 2) or the demo layer removed (Phase 3). The injection method is fixed below.
- **manual**: needs a third-party app or a human.

Fault injection never touches a real card. "Card" below means a disk image built from forged fixtures (`hdiutil create -fs ExFAT`, attached under the run's output folder), and in the probe the card watcher only accepts those images, so a real card that happens to be mounted is ignored. Run: `LUMINA_FIXTURE_ROOT=… bash Scripts/probe.sh fault`.

## Files

| # | Case | How the harness breaks it | Status |
|---|---|---|---|
| F1 ★ | Card pulled mid-copy (Export RAW) | v5 never copies from a card. `fault-card-pull-cull`: the card pulled while its keepers wait on Save (state kept, nothing written, no second read). The Mac's copy job itself: `fault-native-dest`. | **pass** |
| F2 | Card pulled mid-read (culling) | `fault-card-pull-read`: 200-photo card image pulled while "⏎ Cull this card" reads it natively. The readers stop on the unmount notice (0 files opened after it, 0 reads in flight), the page keeps what it read and says "Card removed · 14 of 200 read · re-insert to keep going" (`lumina.read`), Cull shows the card-gone notice, previews of read photos still show; re-insert reads all 200 by itself with 0 unreadable. The keep made while the card was out is lost (open bug 2). `fuzz-app-card`: 2,000 seeded inputs with the card pulled/re-inserted at random, app invariants every 20. | **fail**: open bug 2 · fuzz **pass** |
| F3 ★ | Destination disk full | v5 has no destination: sidecars go into the shoot folder. `fault-disk-full`: the sidecar write on a full disk image leaves the old sidecar untouched, no new sidecar, no temp file, but reads "failed" instead of "disk full" (open bug 3). `fault-native-dest`: the disk fills up *during* the Mac's copy job: stops with "… is full · every file written before this one is complete and checked", no partial or temp file, the written copies hash-equal to the originals (8 RAWs now, so the filler wins the race on a fast disk). | **fail**: open bug 3 · copy job **pass** |
| F4 | Destination = card or inside source | v5 has no destination picker. `fault-native-dest`: a folder outside DCIM on a card image is refused per file, nothing written. `SetsSidecarTests`: only `.xmp` inside the folder, no `../`, no link out. | **pass** |
| F5 ★ | Duplicate DSC numbers | `dup-dsc` (page: both kept, distinct sidecar paths). Bridge: a different file with the same name gets `-2`, the same file is recognised by SHA-256 and skipped (`SetsFileOpsTests`). | **pass** |
| F6 ★ | Existing .XMP / .xmp / both | `app-xmp-lightroom` on real Lightroom 9.3.1 sidecars (`forge_fixtures.sh` lr-sidecar): .xmp and .XMP each merged in place under its own name, only the rating changes, 150–158 `crs:` settings and Lightroom's label byte-identical, exiftool reads the same stars; each old file is kept as `.lumina-bak` (byte-equal). `app-xmp-both` on a case-sensitive APFS image: with both DSC.xmp and DSC.XMP, the lower-case .xmp is read every time and is the one Save plans; written through the app's write, only .xmp is merged and backed up, .XMP is never touched. The page's own read still races: DESIGN-ASKS #2. | **pass** (app) · page: ask 2 |
| F7 | Read-only / locked card | `fault-readonly-card`: read-only card image reads all 12; Save is "copy to disk first", ⌘↩ writes nothing. | **pass** |
| F8 | Network drive, iCloud not downloaded | SMB share to localhost, plus `brctl evict` on files in a test iCloud folder. Check: clear message, no hang (probe hang watchdog 5 s). | P2 |
| F9 ★ | Lightroom writing .xmp during export | A writer process rewrites the target .xmp in a loop during export. Check: atomic write, re-check before write, no torn file. The real-Lightroom run is **manual**. | P2 |
| F10 ★ | Crash / quit mid-export | `fault-kill-mid-handoff`: a real process runs the app's export (6 RAW + 6 .xmp, half replacing an older sidecar) and is SIGKILLed 24 times at seeded points (inside a file, between files, before the first). After each: the app's launch recovery (`SetsExportJournal.recover`) removes Lumina's own temp files and nothing else, no .xmp is torn, journal-done files are verified, old sidecars are untouched or kept as `.lumina-bak`; exporting again completes. The page can't list done vs not done yet (design). | **pass** (files) · list: design |
| F11 | .lumina-bak before every overwrite | `app-smoke`, `app-xmp-lightroom` (exactly one `.lumina-bak` per replaced sidecar, still Lightroom's after a second save), `SetsFileOpsTests` (old bytes kept, identical bytes not rewritten, no temp files left), `SetsTrustTests`. | **pass** |

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
| M1 ★ | 5,000-photo card | Synthetic card: header+preview-only clones of the 721, retimed, 5,000 files on a disk image. Budgets: scroll p95 ≤ 17.5 ms, web process ≤ 1.5 GB, memory flat over a 10-minute fuzz. | **red**: `card-stress` (`probe.sh stress`) misses the frame budget; v5 numbers on the 721-photo card not taken yet (`probe.sh scroll` reports the same scroll without a gate) |
| M2 | Stale folder permission after restart | Debug hook drops the bookmark, then relaunch. Check: detected, asks again. | P2 |
| M3 | Sleep / wake, drive spin-down | Inject `NSWorkspace.willSleep/didWake` through a debug hook, and detach/re-attach the image. A real lid-close run is **manual**. | P2 |
| M4 | File deleted / renamed in Finder while culling | `app-rename-mid-cull`: two kept files renamed / deleted mid-Cull. Culling, large view and invariants keep working; the preview already read still shows and the original isn't read again (404); the renamed original is byte-identical; reopening keeps decisions whose files still exist and shows the renamed file as new and undecided. Save writes sidecars for the two gone RAWs and says "3 saved" (open bug 1). | **fail**: open bug 1 |
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
| X1 | JPEG export looks like Edit (ANSWERS §3) | v3's CSS look and its `look-parity` fixture are gone with the v3 page. The Edit look: `probe.sh edit` (canvas vs export ΔE), `Tools/parity`. | n/a in v5 |

## Native read (gates 1–3)
`probe.sh ingest` runs every camera edge case through the native reader: same verdicts and the same per-step results as the page's own read. On the real 721-ARW α7 III card (`card-clock.json`, both modes): all 721 photos bit-identical to the page's read on every field (time, measures, sharpness rank, kind, soft/blown/shake, suggestions), 10.4–10.8 s vs 11.8–12.2 s, first photo 190–225 ms vs 270–290 ms; web process during culling 953 MB vs 1,178 MB (v3's `card-stress-app`; now `probe.sh stress`, both reads). Evidence: `~/LuminaEvidence/gates-2026-09-29`.

## Always on, every scenario
- Any `console.error`, uncaught error, render error, web-process crash, or page silent for more than 5 s fails the run.
- Page invariants are checked after every step and every 20–25 fuzz inputs: focused photo exists, marks are valid, no duplicate ids, undo stays a list.
- App mode adds the state surface (`__lumina.inspect()`) and the Mac reader's own counters: no large preview held by the page, zoom = large view, read counts add up to the listing, no file opened after its card was pulled, reads in flight within the limit, no single read larger than 16 MB (never a whole RAW).
- CPU and memory of the app and the web process are sampled every 200–250 ms and checked against the budgets.
- A seeded fuzzer (keys, held keys, clicks, drags) replays exactly from its seed. The last 60 inputs are printed on failure. The page's `dragstart` is refused in the probe, so a drag over a tile never becomes a system drag (a drag image on the user's screen, the drag pasteboard); dropping tiles isn't fuzzed.
