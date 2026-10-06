# Lumina 1.0: release tasks, in order

Updated 2026-10-02. The first list (2026-10-01) is kept at the end, with what landed.

Rules for every worker:
- One task = one branch = one PR. Edit only the files the task owns; one merge owner.
- Never touch `Lumina/Sets/Web/*` except `plumbing.js`. Anything visible goes to `design/handoff/DESIGN-ASKS.md` as "Prompt (number assigned at merge) — …".
- **Tests on this Mac run only when the user asked for that run**, through the guard (`Scripts/test_guard.py`, PR #184), bounded, one at a time, nothing left running at the end of a turn. A refusal is reported, never retried. No loops, no kill loops, no disk images, no screen-owning suites unasked. While `~/LuminaEvidence/.tests-off` exists, nothing runs here: the proof is CI on the PR.
- Never run `gh pr merge --auto` on this repo: `main` has no required checks, so it merges at once.
- CI builds Debug with the runner's older Xcode. Code must compile there and in Release with the local Xcode (the `SetsFirstAnswer` deinit broke Release for three merges).

## Release exit

| KPI | Target | Today |
|---|---|---|
| CI on `main`, including a Release build | all green | Debug only; the Release job is in #179 |
| `release_preflight.sh --strict` | 0 FAIL, 0 WARN except D2 (network entitlement) | D2 and S4 ×2 expected (R6's is closed); not re-run since |
| App-process crashes on the bridge-op table (1,303 calls) and 32,000 fuzz cases | 0 | 4 inputs crash (F1, F2) |
| Denials in the sandboxed probe suites | 0 | 0 here; 1 log line on the CI runner (#179) |
| Unasked test runs on this Mac | 0; every run under 600 s | guard in #184 |
| Fresh install, macOS 14 / 15 / 26, store and dmg | 6 of 6 pass | not run |

## P0 · Blocks any build leaving this Mac

1. **Test guard (#184).**
   - KPI: nothing running at the end of a turn; a refusal is never retried.
   - Steps: merge #184 when CI is green; every later task runs tests only through it.
2. **Bridge crashes (Q4a: F1, F2 in `stress/Q4-hostile.md`).**
   - KPI: the former crash inputs pass in the normal logic-test run.
   - Steps: one finite, clamped number reader for every numeric field in `SetsBridge` and `SetsSchemeHandler`; a rect guard in `LookCanvas`; the gated crash cases become ordinary assertions.
3. **Sidecar data safety (F5, F4, F7).**
   - KPI: 0 sidecars replaced without a merge; `hostile-xmp` and `hostile-names` green.
   - Steps: a sidecar that is not UTF-8 is listed as unreadable and never written over; temp names that fit any legal file name, with crash recovery still recognising them; caps on the strings stored in `index.json`.
4. **Sandbox by default (#179, R3).**
   - KPI: the CI release job green; tests run on the build that ships.
   - Steps: find who asks for `file-issue-extension target:/` in `app-plumbing-contract` on the runner (one log line; all steps pass), fix or classify it with the reason written down; merge.
5. **Card banner (DESIGN-ASKS Prompt 9).**
   - KPI: first card insert shows a banner, one click grants access; second insert needs none.
   - Steps: hand Prompts 4–9 to Claude Design; sync. Today a sandboxed first insert shows nothing (`lumina.cardPending`).
6. **Sessions from before the sandbox (R1e).**
   - KPI: a store written by `4421a7c` opens in the sandboxed build with its decisions.
   - Steps: a one-time import through a folder panel on `~/Library/Application Support/Lumina`. Before anyone installs a sandboxed build over an unsandboxed one.
   - #191: `SetsShootStore.importStore` (a shoot in both stores keeps what the new one has; bookmarks are not brought over), a launch question with a folder panel, tests on Mac and Linux. Left: the hand check (install over an unsandboxed build, choose the folder, open a folder culled before, find its decisions) and the design ask for File ▸ Bring Over Earlier Sessions….
7. **Account setup (the account holder).**
   - KPI: `release.sh store --validate` accepted; the build shows in TestFlight.
   - Steps: `APP-STORE.md` "Once" and decisions D1–D5.

## P1 · Blocks the store submission

8. **Network lockdown (S1; only if the WebView ships).** Landed 2026-10-06 (`SetsOffline`, 32 channels in `webkit.py offline`, `app-offline`); the Mac run of `app-offline` is the last check.
   - KPI: 0 requests reach a local listener over 8 channels (fetch, XHR, WebSocket, image, beacon, WebRTC, form, `window.open`).
   - Steps: block-all content rules with an allowlist; a CSP response header; a navigation allowlist.
9. **Nothing unused in the release binary (S4).**
   - KPI: strict preflight shows no S4 warning.
   - Steps: v3 ops and the six environment switches under `#if DEBUG`; Show in Finder only inside opened folders; the self-test not served in release.
10. **Supply chain (S8).**
    - KPI: a clean clone builds with 0 package fetches; 3 targets; every Action pinned by commit.
    - Steps: remove `LuminaPlayground` and `Inject`; pin Actions; the design sync prints new network and bridge calls.
11. **Stress, each run asked for, bounded, under the guard.**
    - Scale (Q1, WIP on `claude/stress-scale`): 5,000 and 10,000 photos; budgets set from the first measurement; scroll p95 ≤ 17.5 ms (18.0 today).
    - Storage (Q2, WIP on `claude/stress-storage`): every row of `STRESS-MATRIX.md` 2 and 4 has a scenario or a hand procedure; 0 data loss.
    - Lifecycle (Q3, WIP on `claude/stress-lifecycle`): decisions equal after each kill, at most 500 ms of changes lost. The 200-kill loop only on an explicit go.
    - Soak (Q5): 8 h, memory and file descriptors flat.
    - Fresh machine (Q6): macOS 14, 15, 26 × store and dmg.
12. **Hand checks for S6 (five minutes).**
    - KPI: 3 of 3: kill the page's process 4 times in a minute (3 reloads, then the alert); Quit with the page hung (quits in about 2 s); Quit with unsaved keepers (the usual alert).

## P2 · Before the public listing

- The listing: copy, screenshots, privacy and support pages, review notes with sample ARWs (R5).
- Diagnostics: ~~private paths in logs (R7)~~ landed 2026-10-06 (`LuminaLog`); navigation allowlist, a damaged `index.json` kept aside, a session format version (R8).
- `DESIGN-ASKS.md` sections sorted 4–9; `open-folder-awkward-name` added to the probe's `app` suite.
- Known gaps, accepted or to schedule: a huge folder is refused in about 2 s on a fast Mac and about 5 s on a slow one; a link swapped in between the path check and the open by render, canvas or export (S5); two licence texts marked MISSING (R6); F6 and F9 in `stress/Q4-hostile.md`.

## Landed (2026-10-01 to 02)

| Task | PR |
|---|---|
| Release scaffolding | #167 |
| S2 shoot ids · S3 input bounds · S5 links · S6 reload limit, Quit timeout · S7 stale sidecars · S9 awkward names | #168 · #172 · #171 · #169 · #170 · #178 |
| R1a sandboxed probe · R1b bookmarks · R1c card · R1d export recovery, downloads · probe follow-ups | #174 · #175 · #177 · #176 · #180 |
| R6 licence notices · Release-build fix · Q4 hostile-input tests and report | #173 · #181 · #182 |

---

# The first list (2026-10-01), for reference

## First list · P0 · Blocks any build leaving this Mac

| ID | Task | Owns | Done when | Needs | Size |
|---|---|---|---|---|---|
| **D** | Decisions D1–D5 (`APP-STORE.md`) and the one-hour account setup | the account holder | Bundle id and name final in `Config/Release.xcconfig`; certificates, API key, notary profile exist | — | 1 h, human |
| **S2** | T1: shoot ids from the page are validated | `SetsShootStore.swift`, `LuminaLogicTests/SetsShootStoreTests.swift`, `Tests/linux-swift` list | `..`, `/`, empty, 17-char and non-hex ids are refused by `session`, `saveSession`, `remove`, `bytes`, `header`, `saveHeader`; tests on Mac and Linux | — | S |
| **R1a** | A sandboxed probe: the probe's scenarios run against a build with `Config/Lumina-Sets.entitlements`, and a run fails on any `Sandbox: … deny` line in the log for its pid | `Tools/LuminaProbe`, `Scripts/probe.sh` (new `sandbox` mode), `Tests/probe/scenarios/sandbox-*` | `probe.sh sandbox smoke` runs and reports, per scenario, pass / fail and the denials. It will fail at first: the failures are R1b–d's work list. Also answers whether the page loads fully with `network.client` | — | M |
| **R1b** | T9: bookmarks done properly. Start/stop balanced per open shoot, stale bookmarks renewed, no raw-path fallback, the unused `bookmarks/` folder gone | `SetsBridge.swift` (open/reopen only), `SetsShootStore.swift` (after S2), new `Sets/Core/SetsAccess.swift` | Under R1a: open → quit → reopen from Open Recent; after the folder is renamed; 200 reopens with no leak; zero denials | R1a, S2 | M |
| **R1c** | T10: the card flow in a sandbox. Mount is noticed without reading the volume; the folder panel opens on the card; the grant is kept per volume UUID | `SetsCardWatcher.swift`, `SetsBridge.swift` (`cullCard`, `cardChanged`), `plumbing.js` (card hooks), `DESIGN-ASKS.md` (the banner's wording when the count is not known yet) | Under R1a with the probe's disk images: first insert one panel, second insert none, pull mid-read as today; `probe.sh fault` green sandboxed | R1a, R1b | M |
| **R1d** | Export, journal and downloads in a sandbox: the journal stores a bookmark to the destination; recovery uses it; the page's download handler is removed from release or goes through a save panel | `SetsExport.swift`, `SetsRootView.swift` (download delegate only) | `fault-kill-mid-handoff` green sandboxed: temp files removed on the next launch | R1a | S |
| **R1e** | Sessions made by the unsandboxed beta are imported once (a "Import earlier sessions…" folder panel on `~/Library/Application Support/Lumina`, or documented as lost) | `SetsShootStore.swift`, `DESIGN-ASKS.md` if anything shows | A fixture store from `4421a7c` opens in the sandboxed build with decisions intact, or the decision to drop it is written in `APP-STORE.md` | R1b | S |
| **S1** | T3: the page cannot reach the network (only if D2 = WebView) | `SetsBridge.swift` (`SetsWebView.make`), `SetsSchemeHandler.swift` (response header), `SetsRootView.swift` (navigation policy), `Tests/probe/scenarios/offline-*` | A scenario that tries fetch, XHR, WebSocket, image, beacon, RTCPeerConnection, form post and `window.open` to a local listener: the listener sees nothing. `screens` parity still 0 px | R1a | M |
| **S7** | T4: Save never writes a sidecar from stale text | `SetsFileOps.swift` (`writeSidecar` takes the base hash), `SetsBridge.swift` (`writeSidecars`), `plumbing.js` (Save), `SetsSidecarTests`, scenario `app-xmp-changed-since-open`; a design ask for the result line's wording | Lightroom's sidecar edited after open, then Save: Lightroom's settings survive and the rating is set, or the file is reported and untouched. Never the old text | — | M |

## First list · P1 · Blocks the store submission

| ID | Task | Owns | Done when | Needs | Size |
|---|---|---|---|---|---|
| **R2** | First store build | `Scripts/release.sh`, `Config/*` | `release.sh store --validate` accepted by App Store Connect; build visible in TestFlight; any fix to the script or xcconfig it took | D, R1a–d | S |
| **R3** | The sandbox becomes the default: Debug and Release use the entitlements in the project, CI builds `release.sh local --strict` and runs preflight | `Lumina.xcodeproj`, `.github/workflows/lumina.yml`, `Scripts/install_app.sh`, `AGENTS.md` (Checks) | CI has a `release` job; `install_app.sh` installs a sandboxed app; what the probe tests is what ships | R1a–d | S |
| **S3** | T5: bounds on folder input (sidecar size, listing count and depth, cancellable listing, session size) | `SetsIngest.swift`, `SetsBridge.swift` (`openFolder`, `saveSession`), `SetsIngestTests`; a design ask for the refusal wording | 500 MB `.xmp` skipped and counted; opening `/` stops within 2 s with a message; tests | — | M |
| **S4** | T8: nothing unused in the release binary. v3 ops removed or Debug-only, `reveal` limited, environment switches under `#if DEBUG`, self-test not served in release | `SetsBridge.swift` (`writeInto`, `reveal`), `SetsEditLook.swift`, `SetsSchemeHandler.swift`, the six `LUMINA_*` readers in `Sets/Core` and `Sets/Look`, the probe (builds Debug) | `release_preflight.sh --strict` has no WARN left from this task; probe suites unchanged | R3 | M |
| **S5** | T6: links inside a shoot never lead out for reads | `SetsIngest.swift` (`resolve`, `read`), `SetsIngestTests` | A linked file and a linked subfolder are both refused (404) for head, preview, thumb, render, canvas and export copy | — | S |
| **S6** | T7: reload limit and Quit timeout | `SetsRootView.swift`, `LuminaApp.swift`; a design ask if the alert wording should be the page's | Killing the WebContent process 5 times in a minute ends in one alert, not a loop; Quit with a hung page completes in 2 s; decisions intact after both | — | S |
| **S8** | T12: dead target and unpinned inputs. Remove `LuminaPlayground` and the `Inject` package; pin Actions by commit; add the bridge-and-network diff to `sets_sync_design.sh` | `Lumina.xcodeproj`, `.github/workflows/lumina.yml`, `Scripts/sets_sync_design.sh` | A clean clone builds with no package fetch; `xcodebuild -list` shows three targets; the sync prints new network / bridge calls | after R3 (same file) | S |
| **R6** | Third-party notices: React and Babel licence texts in the bundle; Help ▸ Acknowledgements as a design ask (MENUS.md) | `Lumina/Resources/THIRD-PARTY-NOTICES.txt`, `design/handoff/vendor/VENDOR.md`, `DESIGN-ASKS.md` | Preflight's notices check is `ok` | — | S |
| **Q1** | Stress: scale (`STRESS-MATRIX.md` 1) | `Tests/probe/forge_fixtures.sh`, `Tests/probe/scenarios/scale-*` | 5,000 and 10,000 photos, deep trees, 100 recents: numbers in a report; anything over budget filed as a task | R1a | M |
| **Q2** | Stress: storage and other apps (sections 2, 4) | `Tests/probe/scenarios/fault-*`, `app-*` | Network share, iCloud placeholders, pull during Edit / export, destination gone mid-export: a scenario or a signed hand run each | R1a, S7 | L |
| **Q3** | Stress: lifecycle (section 5): kill-anywhere loop, WebContent kill, sleep / wake, update over a session | `Tests/probe/scenarios/life-*`, `Scripts/probe.sh` | 200 seeded kills, decisions equal after each; a session fixture per released version | R1a, S6 | M |
| **Q4** | Stress: hostile input (section 7): head and range fuzzer, mutated JPEG / ARW into the decoders, XMP and names, the bridge-op table test | `Tests/probe/fuzz/`, `LuminaLogicTests/SetsBridgeOpsTests.swift` | 10,000 seeded cases, no crash of the app process, no write outside the fixture; crashes in Apple's decoders recorded with the file | S2, S3, S5 | L |
| **Q5** | Stress: memory, heat, soak (section 6) on this Mac and the M1 8 GB | `Scripts/probe.sh` (`soak`), `Scripts/probe_remote.sh` | 8 h: RSS, descriptors, GPU memory flat; memory-pressure and thermal runs behave as AGENTS.md says | R1a | M |
| **Q6** | Fresh-machine pass per channel and per macOS (section 9), plus displays and input (section 8) | a checklist in `docs/release/`, by hand | macOS 14, 15, 26: install from TestFlight and from the dmg, first run, open, cull, Save; AZERTY and VoiceOver noted | R2 | M, human-in-loop |

## First list · P2 · Before the public listing

| ID | Task | Owns | Done when | Size |
|---|---|---|---|---|
| **R5** | The listing: description, keywords, screenshots, privacy and support pages, review notes with sample ARWs | `docs/release/listing/`, `docs/screenshots`, `README.md` | Everything in `APP-STORE.md` "The listing" filled; no trademark in the copy | M |
| **R7** | Diagnostics without telemetry: dSYMs kept per release in `build/release`; `os_log` with private paths (T11); a Help ▸ "Copy diagnostics" design ask | `Lumina/Sets/Core` logging call sites, `DESIGN-ASKS.md` | A crash from TestFlight symbolicates; no path appears in `log show` in clear | S |
| **R8** | T11 leftovers: navigation allowlist, damaged `index.json` kept aside, session format version field | `SetsRootView.swift`, `SetsShootStore.swift`, `plumbing.js` | Tests for each | S |
| **R9** | `docs/RELEASE.md` (PR #166) updated: #3 points here; "Not tested yet" shrinks as Q1–Q6 land | `docs/RELEASE.md` | — | S |

## First list · Order and parallelism

```
now, in parallel:   D (human) · S2 · R1a · S7 · S3 · S5 · S6 · R6
after R1a:          R1b → R1c ; R1d ; S1 ; Q1 ; Q5
after R1b–d:        R3 → S8 → S4 ; R1e ; R2 (needs D)
after their fixes:  Q2 · Q3 · Q4 → Q6 → R5 → submit
```

`SetsBridge.swift` is touched by R1b, R1c, S1, S3, S4 and S7, each in a different function. Land
them one at a time in that order; each rebases on the last. Everything else is disjoint.

If D2 = native: S1 drops out, R1a targets the native app, `plumbing.js` items move to LuminaKit's
equivalents, and S2, S3, S5, S7, R1b–d apply to whichever file code the native app uses (check
whether it calls `Sets/Core` or its own `LuminaCore` before assigning them).
