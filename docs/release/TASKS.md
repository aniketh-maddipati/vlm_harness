# Lumina 1.0: release tasks, in order

Updated 2026-10-06 (after the v0.05 sync, #206: Sets v11 + Edit v22). The 2026-10-02 list is folded
in below; the first list (2026-10-01) is kept at the end, with what landed.

Rules for every worker:
- One task = one branch = one PR. Edit only the files the task owns; one merge owner.
- Never touch `Lumina/Sets/Web/*` except `plumbing.js`. Anything visible goes to `design/handoff/DESIGN-ASKS.md` as "Prompt (number assigned at merge) — …".
- **Tests on this Mac run only when the user asked for that run**, through the guard (`Scripts/test_guard.py`, PR #184), bounded, one at a time, nothing left running at the end of a turn. A refusal is reported, never retried. No loops, no kill loops, no disk images, no screen-owning suites unasked. While `~/LuminaEvidence/.tests-off` exists, nothing runs here: the proof is CI on the PR.
- Never run `gh pr merge --auto` on this repo: `main` has no required checks, so it merges at once.
- CI builds Debug with the runner's older Xcode. Code must compile there and in Release with the local Xcode (the `SetsFirstAnswer` deinit broke Release for three merges).

## Decisions (APP-STORE.md)

| # | Decision | State |
|---|---|---|
| D1 | Name and bundle id | `com.aniketh.lumina`, record "Lumina Editor" (2026-10-05) |
| D2 | Which UI ships | **The design page in the web view** (2026-10-06), with `network.client`; S1 makes the app block the network itself and the review notes explain the entitlement |
| D3 | Channels | Store and notarised dmg |
| D4 | Price, territories | **Free, all countries** (2026-10-06). The EU needs the trader status declaration in App Store Connect |
| D5 | Minimum macOS | **15** (2026-10-06): `Config/Release.xcconfig` and the project. The fresh-machine pass is macOS 15 and 26 |
| — | Testers | Build 568 (Sets v8) goes to TestFlight testers now; a v11 build follows once #206's Mac checks pass |

## Release exit

| KPI | Target | Today |
|---|---|---|
| CI on `main`, including a Release build | all green | Release job `release.sh local --strict` in CI (`lumina.yml`) |
| `release_preflight.sh --strict` | 0 FAIL, 0 WARN except D2 (network entitlement) | CI allows D2 only; S4 and R6 are closed |
| App-process crashes on the bridge-op table and the fuzz cases | 0 | F1, F2, F10 fixed (Q4a, `8cbabf0`) |
| Denials in the sandboxed probe suites | 0 | 0 (R3 merged: sandboxed in every configuration) |
| Unasked test runs on this Mac | 0; every run under 600 s | guard (#184) |
| Fresh install, macOS 15 / 26, store and dmg | 4 of 4 pass | not run (procedure below, Q6) |

## Open · blocks a build leaving this Mac

1. **v0.05 on the Mac (#206 merged on Linux checks).** The Xcode build and logic tests, `probe.sh contract`, `screens`, `smoke`, `edit`; then `probe.sh reference --record` once the v11 screens are approved.
2. **Card banner (Prompt 9).** In the v11 page (`cardPending`). Left: the hand check on a sandboxed build (first insert shows the banner and one click grants; the second insert needs none).
3. **Sessions from before the sandbox (R1e).** Code in #191. Left: the hand check, and the page's File ▸ Bring Over Earlier Sessions… (Prompt 11 / REMAINING-v0.03 A3, not in v11).
4. **Native Edit canvas reached by the page.** #208 and #209; crop and grid overlays under the canvas need a design ask. Edit's default sharpening differs (page 40, native 0).
5. **`lumina.sidecars` (REMAINING-v0.03 D1 B/C).** Open after v11.

## Open · blocks the store submission

6. **Trust model (one thread, draft #215):** S1 network lockdown (WebRTC, a CSP header; a scenario that tries 8 channels against a local listener), the external-link allowlist wired in (`SetsExternalLinks.swift` has no caller), R7 private paths in logs.
7. **Stress, each run asked for, bounded, under the guard.** Q1 scale, Q2 storage, Q3 lifecycle (their WIP branches are gone; start again from `STRESS-MATRIX.md`), Q5 soak 8 h.
8. **Hand checks for S6 (five minutes).** Kill the page's process 4 times in a minute (3 reloads, then the alert); Quit with the page hung (about 2 s); Quit with unsaved keepers (the usual alert).
9. **Fresh machine (Q6), by hand.** The procedure below, on macOS 15 and 26, store and dmg.

## Open · before the public listing

- The listing (R5): drafts in `docs/release/listing/`. Left: screenshots of the v11 UI (2880 × 1800), the privacy and support pages published at real URLs, the five sample ARWs uploaded for review.
- R8 leftovers: a damaged `index.json` or session is kept aside (this change); the navigation allowlist is part of item 6.
- Known gaps, accepted or to schedule: a huge folder is refused in about 2 s on a fast Mac and about 5 s on a slow one; a link swapped in between the path check and the open by render, canvas or export (S5); F6 and F9 in `stress/Q4-hostile.md`.

## Q6 · fresh-machine procedure

For each of macOS 15 and 26 (a VM or a spare volume, Apple silicon, a user that never ran Lumina):

1. **Store build.** Install from TestFlight. Open a folder of ARWs: the folder panel appears once. Cull ten photos, ⌘↩ Save: `.xmp` files appear next to the RAWs. Quit, reopen from Open Recent: decisions are back, no panel.
2. **Card.** Insert a card: the banner shows; one click grants; cull, Save is refused "on the card". Eject and insert again: no panel.
3. **dmg.** Download the notarised dmg through a browser (quarantine set). Open it with Gatekeeper at defaults: no warning beyond "downloaded from the internet". Run once from the dmg without copying, then from `/Applications`.
4. **Both installed.** With the store and dmg copies present, note which one Launch Services opens and that both see the same sessions (same bundle id, same container).
5. **Delete and reinstall** the store copy; the container stays, sessions come back.
6. Note: an AZERTY layout (P, F, Z, `?`), VoiceOver on the Open screen, a second user account.

Record each run (macOS build, channel, pass/fail, notes) in a table here.

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
