# Lumina: what to stress before release

2026-10-01. One row per thing that must be pushed until it breaks or is shown not to. "Have" is a
command that exists today (AGENTS.md has the full lines); "Gap" is what a worker has to build or
run. Everything runs on the **sandboxed release build** (`Scripts/release.sh local`) once R1
lands: today every probe run is unsandboxed, so none of the "Have" column is evidence for the
store build yet. Evidence goes to `~/LuminaEvidence/release/<version>/`.

## 1 · Scale

| What | Have | Gap |
|---|---|---|
| 3,000-photo shoot: read, scroll, 3,000-input storm, memory | `probe.sh stress`, `scroll`, `readspeed` | Scroll p95 is 18.0 ms against 17.5: fix or accept in writing |
| 5,000 and 10,000 photos, one folder | none | Forge with `forge_fixtures.sh`; read time, memory ceiling, session size, Save time |
| Deep trees, 200 subfolders, a folder with 50,000 non-ARW files | none | Listing time and memory; the caps from S3 |
| Opening `/`, the home folder, a whole external disk | none | Must refuse or stop cleanly, never hang |
| 100 recent shoots; a 20 MB session | none | Open screen time; `index.json` rewrite cost on every save |
| Save 2,000 sidecars; export 500 look renders | `fuzz-app-card`, `raw9` (small) | Time, memory, App Nap, sleep prevented, progress stays live |

## 2 · Storage and media faults

| What | Have | Gap |
|---|---|---|
| kill -9 mid-write, disk full mid-copy and for a sidecar, read-only card, card pulled mid-read and on Save, case-sensitive disk | `probe.sh fault` | Re-run sandboxed |
| Slow first directory read (12 s) | `probe.sh slowdisk` | Re-run sandboxed |
| Card pulled during Edit render, during export, during the decoder probe | none | Three scenarios |
| Network share (SMB, NAS), disconnect mid-read | none | Listing, F_NOCACHE reads, atomic rename and `replaceItemAt` on SMB |
| iCloud Drive / Dropbox folder with files not downloaded | none | Must not trigger a download storm; says what it skipped |
| exFAT, APFS case-sensitive, APFS encrypted, HFS+, NTFS (read-only), FAT32 4 GB limit | part (`fault`) | One pass per file system: read, Save, export |
| Two card slots with the same file names; two cards named "Untitled" | none | Shoot identity by volume UUID |
| Destination disappears mid-export; destination is the source's parent; destination on a card | `fault-native-dest` (part) | The first one |
| Power loss mid-session-write (truncated `session.json`, `index.json`) | none | Atomic rename covers it; prove it with a damaged-file fixture (T11) |

## 3 · Sandbox and permissions (all new)

| What | Gap |
|---|---|
| First launch on a fresh account: container made, page loads, no sandbox denials in the log | Assert zero `Sandbox: Lumina … deny` lines in every probe run |
| Open → quit → reopen from Open Recent (bookmark), after a reboot, after the folder is renamed or moved, after the disk is renamed | Scenarios; stale bookmarks renewed |
| 200 reopens in one session (bookmark start/stop balanced) | Loop scenario |
| Card: first insert (one panel), second insert (none), a different card | Needs the design ask in R1 |
| Access refused (Files and Folders off, Full Disk Access off, a folder the user cannot read) | "By hand only" today |
| Export journal recovery after a crash, destination reached by bookmark | New `fault-kill-mid-export-sandbox` |
| Upgrade: sessions made by the unsandboxed beta are found or imported once | Migration test |

## 4 · Other apps on the same files

| What | Gap |
|---|---|
| Lightroom Classic / CC writes a sidecar after Lumina opened the folder, then Save (T4) | `app-xmp-changed-since-open` |
| Lightroom has the folder imported and open while Lumina saves; Lightroom reads the rating back | By hand, both directions, plus Capture One |
| Finder renames, moves or deletes a keeper mid-cull | Have: "keepers renamed mid-cull". Add delete and move |
| Spotlight, Time Machine, Photos import running during a read | Soak on a real card |
| Two Lumina processes on one shoot (the dmg copy and the store copy) | Last writer wins today; decide and test |

## 5 · Lifecycle

| What | Have | Gap |
|---|---|---|
| Quit with unsaved keepers | by hand | Automate; page hung at Quit (T7) |
| Sleep and wake mid-read, mid-export, with the card in; lid closed on battery | none | By hand on a laptop, logged |
| Fast user switching, screen lock, display off (page throttled) | none | Debounced session write still lands |
| WebContent process killed (`kill` the WebKit process) during cull, during Save | none | Decisions kept; no reload loop (T7) |
| Force quit at any moment, 200 times, seeded | `fault` (one point) | A kill-anywhere loop: after each, reopen and compare decisions |
| Update 1.0.0 → 1.0.1 over an open shoot's session | none | Session format version and a fixture from each released version |
| System clock or time zone changes mid-session | none | Rows and "last opened" stay sane |

## 6 · Memory, heat, power

| What | Have | Gap |
|---|---|---|
| Edit: latency p95, dropped frames, ≤ 3 photos / 300 MB | `probe.sh edit`, `edit-cold` | Re-run sandboxed |
| M1 8 GB | `probe_remote.sh edit` | Add `stress`, `scroll`, `raw9` remotely |
| Memory pressure (`memory_pressure -l critical`) during cull, Edit, export | none | Tiles then neighbours then never the current base (AGENTS.md) |
| Thermal `.serious`, Low Power Mode | none | Region refinement defers, export says "slowed", nothing disabled |
| 8-hour soak: scripted cull of 3 shoots in a row, no relaunch | none | RSS, file descriptors, GPU memory and bookmark count flat |
| No Metal device (a VM) | `LUMINA_CANVAS=image` | Launch in a macOS VM: the image path, no crash |

## 7 · Hostile and damaged input

| What | Have | Gap |
|---|---|---|
| Camera-data edge cases | `probe.sh edge`, `ingest` (4 known fails) | Close or accept the 4 |
| Truncated ARW at every 4 KB boundary; preview offset past the end; preview length 0, negative, 2 GB | part | A seeded fuzzer over heads and preview ranges, 10,000 cases, through `SetsIngest` and the page's parser |
| Mutated embedded JPEGs into ImageIO; mutated ARWs into the RAW decoder | none | Run under the sandbox with crash reports collected; a crash is a finding even when it is Apple's |
| XMP: 500 MB, not UTF-8, entities, 10,000 nested nodes, script text in fields | none | Skipped or shown as text, never executed, never grows memory (T5) |
| File names: 255 bytes, emoji, RTL, `"<img onerror>"`, newlines, NFD vs NFC, a trailing dot | part (`fuzz`) | Rendered as text; sidecar lands beside the right RAW |
| Volume label with quotes, markup, 0 length | none | Card banner |
| Bridge: every op with wrong types, huge strings, `..`, absolute paths (T1, T8) | none | A table-driven test in `LuminaLogicTests` calling `userContentController(_:didReceive:)` |
| Key and mouse storms | `probe.sh fuzz` | Re-run sandboxed, 10 seeds |

## 8 · Displays and input

| What | Gap |
|---|---|
| 1024 × 700 minimum, full screen, Split View, Stage Manager | Layout holds; the canvas overlay stays on its rect |
| Moving the window between a Retina and a non-Retina display, HDR / XDR, ProMotion vs 60 Hz | Canvas scale and colour; dropped-frame counter |
| Display unplugged while in Edit; clamshell | Canvas recreated |
| Reduce Motion, Increase Contrast, larger text, VoiceOver, Full Keyboard Access | Untested today. The page is a web view: check it is readable at all |
| Non-US keyboards (the single-key shortcuts P, F, Z, `?`, `+`, `−`) | AZERTY, QWERTZ, Dvorak, an IME active |

## 9 · Install and platforms

| What | Gap |
|---|---|
| macOS 15 and 26 on Apple silicon (minimum 15, D5) | A VM or spare volume per version: install, first run, open, cull, Save |
| macOS 27 beta (RAW 9 present) | `probe.sh raw9` there |
| TestFlight install on a Mac that never built Lumina; delete and reinstall; second user account | Fresh-machine pass |
| The notarised dmg on a Mac with Gatekeeper at defaults, downloaded through a browser (quarantine set), run from the dmg without copying, run from `~/Downloads` (translocation) | Fresh-machine pass |
| Both copies installed (dmg and store) | Same bundle id: which one Launch Services opens, whether sessions are shared |
| Intel Mac | Out: the build is arm64 only and the store will not offer it |

## Exit bar for 1.0

1. Every "Have" row green on the sandboxed build, and zero sandbox denials logged.
2. Every row in sections 2, 3, 5 and 7 has a scenario or a signed-off hand run.
3. `release_preflight.sh --strict` passes on the candidate.
4. The 8-hour soak and the kill-anywhere loop pass on the candidate itself, not an earlier build.
5. One fresh-machine install per channel that ships.
