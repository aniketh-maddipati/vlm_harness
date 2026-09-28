# Lumina edge-case checklist → how each one is broken on purpose

Every item gets an automated probe scenario unless it's marked **manual**. Run with
`bash Scripts/probe.sh <suite>` (see the script header). ★ = minimum before Reddit.

Status (2026-09-28, handoff v6):
- **pass**: scenario runs green today.
- **gap**: scenario runs and fails because the page falls short of the checklist. The fix goes to design first, because the HTML and `lumina-core.js` ship unchanged.
- **red**: perf budget scenario, failing until Phase 4.
- **P2** / **P3**: needs the native bridge (Phase 2) or the demo layer removed (Phase 3). The injection method is fixed below.
- **manual**: needs a third-party app or a human.

Fault injection never touches a real card. "Card" below means a disk image built from forged fixtures (`hdiutil create -fs ExFAT`, attached as `/Volumes/LUMINA_TEST_*`).

## Files

| # | Case | How the harness breaks it | Status |
|---|---|---|---|
| F1 ★ | Card pulled mid-copy (Export RAW) | Export to a folder while the source image is detached with `hdiutil detach -force` at a random point. Check: no file is marked done without a verified checksum, and resume works on re-attach with the same volume UUID. | P2 |
| F2 | Card pulled mid-read (culling) | Detach during `openFolder` load and during Cull. Check for "Card removed · re-insert to keep going", no crash, state kept, resume on re-attach. | P2 |
| F3 ★ | Destination disk full | Export to a 64 MB image. Check: the size check runs before start, it stops cleanly with a count, and there are no partial files. | P2 |
| F4 | Destination = card or inside source | Point Export at the source image and at a subfolder of it. Check: blocked before any write. | P2 |
| F5 ★ | Duplicate DSC numbers | `dup-dsc` fixture. Page check: both kept, distinct sidecar paths. Bridge check: second export of same names doesn't overwrite, and the checksum is compared. | page **pass** · P2 |
| F6 ★ | Existing .XMP / .xmp / both | Fixtures with upper, lower and both. Check: merged into the right one, no duplicate, `.lumina-bak` written. | P2 |
| F7 | Read-only / locked card | `hdiutil attach -readonly`. Check: reads fine, and zero write attempts (bridge write log empty). | P2 |
| F8 | Network drive, iCloud not downloaded | SMB share to localhost, plus `brctl evict` on files in a test iCloud folder. Check: clear message, no hang (probe hang watchdog 5 s). | P2 |
| F9 ★ | Lightroom writing .xmp during export | A writer process rewrites the target .xmp in a loop during export. Check: atomic write, re-check before write, no torn file. The real-Lightroom run is **manual**. | P2 |
| F10 ★ | Crash / quit mid-export | `kill -9` the app at a random point in export, then relaunch. Check: the list shows done vs not done, and no half-written sidecars (every .xmp parses). | P2 |
| F11 | .lumina-bak before every overwrite | Asserted in F6, F9 and F10: every replaced file has a byte-identical `.lumina-bak`. | P2 |

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
| M4 | File deleted / renamed in Finder while culling | Probe renames or deletes files on the image mid-Cull. Check: UI updates, no crash, invariants hold. | P2 |
| M5 | Fast keys while previews load | Key storm during `openFolder`. Check: each action hits the photo focused at keydown (probe logs the focused id per key). | page scenario possible now |

## People

| # | Case | How | Status |
|---|---|---|---|
| P1 | Undo after export | Page scenario: export, then Q. Check: copy says written files aren't undone. | page check possible now |
| P2 | Same folder twice / two windows | Launch the app twice, open the same folder. Check: one session, or blocked. | P2 |
| P3 | Non-Sony files skipped quietly | `edge-junk-in-folder` (CR3, txt, `.DS_Store`, `._` stubs) | pass (WebKit skips dotfiles; the native lister must too) |
| P4 | VoiceOver, larger text, reduced motion | AX tree audit of the WKWebView (every control has a role and label). Reduced motion and VoiceOver are **manual**: the harness never changes system settings. | manual + P2 |

## Always on, every scenario
- Any `console.error`, uncaught error, render error, web-process crash, or page silent for more than 5 s fails the run.
- Page invariants are checked after every step and every 20–25 fuzz inputs: focused photo exists, marks are valid, no duplicate ids, undo stays a list.
- CPU and memory of the app and the web process are sampled every 200–250 ms and checked against the budgets.
- A seeded fuzzer (keys, held keys, clicks, drags) replays exactly from its seed. The last 60 inputs are printed on failure.
