# Lumina — macOS Release Readiness Audit

**Scope:** read-only technical audit of three distinct distribution lanes: (1) unsigned local dogfood, (2) notarized Developer ID external beta — **recommended MVP**, (3) Mac App Store / TestFlight.

**Audited commit:** `0700b95` ("Close out P0 editing on main: probe coverage, leaf identifier fix, artifact cleanup.") — tip of `cursor/p0-single-photo-editing`.
**Prior audit revision:** `8980249` on `research/release-readiness`.
**Date:** 2026-08-07.

**Method:** static inspection of sources, `Lumina.xcodeproj/project.pbxproj`, the shared scheme, test plans, and scripts, plus one non-building settings query:

```bash
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Release -showBuildSettings
```

No app code, build settings, entitlements, or scripts were modified. Nothing was pushed.

**Claims are evidence-backed.** Where the repository contains no evidence either way, the item is labelled **not proven** rather than guessed.

---

## Recommended MVP path

**Ship a notarized Developer ID DMG** to a small external beta (≈5 testers).

This is the shortest path to Gatekeeper-clean installs on machines you do not control. It avoids the sandbox + security-scoped bookmark migration (F2/F9), privacy manifest (F8), and App Store review surface while still exercising real distribution mechanics (signing, notarization, stapling).

**Do not use TestFlight for this MVP.** macOS TestFlight distributes only Mac App Store builds uploaded to App Store Connect and is therefore gated behind every App Store blocker in §4, including sandbox enablement.

---

## 1. Stage-by-stage release matrix

Three distribution lanes are intentionally separate. Blockers, polish items, and deferrals differ by lane.

| Dimension | Unsigned dogfood | **Notarized Developer ID beta (MVP)** | Mac App Store / TestFlight |
|---|---|---|---|
| **Purpose** | Internal builds on maintainer-controlled Macs | External beta; Gatekeeper-clean install | Public distribution |
| **Signing** | Ad-hoc (`CODE_SIGN_IDENTITY = -`) OK | Developer ID Application certificate (F1) | Apple Distribution + MAS profile (F1) |
| **Notarization** | Optional (manual Gatekeeper override OK) | **Required** (F15) | N/A (App Store handles review) |
| **App Sandbox** | Off (current default) | Off — **correct for this lane** | On — **must ship with F9** (F2) |
| **Security-scoped bookmarks** | Path fallback works today | Path fallback works today | Bookmark persistence required; **F2 + F9 land together** |
| **Info.plist** | Xcode-generated is valid (`GENERATE_INFOPLIST_FILE = YES`) | Same — add `INFOPLIST_KEY_*` via build settings (F7, optional) | Same — usage strings + category required (F7) |
| **Privacy manifest** | Not required | Not required for DMG | **Required** — `PrivacyInfo.xcprivacy` (F8) |
| **Folder usage descriptions** | Not required | Optional — improves TCC prompts on re-open (F7) | Required for stored-path re-access (F7) |
| **App icon** | **Optional polish** — generic icon acceptable internally | **Recommended** — empty icon reads as broken to beta testers (F3) | **Blocker** — 1024×1024 required (F3) |
| **exiftool dependency** | Maintainer installs via Homebrew | **Functional blocker** — P0 open degrades silently without it (F10) | **Blocker** — sandbox forbids external binary; must remove or bundle (F10) |
| **Release harness args** | Tolerable internally | **Must `#if DEBUG` gate** (F4) | Must compile out (F4) |
| **Legacy shell button** | Tolerable internally | Hide from shipping UI (F6) | Must hide (F6) |
| **Build number** | Informational | Stamp from commit count at package time (F14) | Must increment per upload (F14) |
| **Packaging tooling** | `hdiutil` sufficient | `Scripts/package_dmg.sh` + notarytool (F15) | Xcode Organizer / Transporter |
| **Verified today** | Reachable now | Blocked on F1, F10, F4, F15 | Blocked on all §4 items |

**Info.plist note:** There is no standalone `Info.plist` file in the repository, and that is **not a defect**. `GENERATE_INFOPLIST_FILE = YES` produces a valid bundle `Info.plist` at build time. Missing keys are added via `INFOPLIST_KEY_*` build settings — no new file is required unless you prefer a checked-in plist for readability.

---

## 2. Blockers for the notarized MVP beta

Everything below must clear before distributing a Developer ID DMG to external testers. Ordered by dependency.

| ID | Blocker | Why it blocks MVP |
|---|---|---|
| **F1** | No signing identity / team; Release is ad-hoc signed | Cannot notarize or staple; Gatekeeper blocks on other Macs |
| **F10** | Hardcoded `/usr/local/bin/exiftool` with silent degradation | **Functional beta blocker.** P0 contact-sheet open depends on EXIF capture dates via `ExifToolService.batchCaptureDates` (`ContactSheetPreparation.swift:441`). Without exiftool, ordering falls back to file mtime with no user notice. Path misses Apple-silicon Homebrew (`/opt/homebrew/bin/exiftool`). Documented as required in `README.md:9` and `AGENTS.md`. Beta testers without Homebrew exiftool get wrong shoot ordering and unreliable chronological navigation — a core P0 contract failure, not a polish gap. |
| **F4** | Release-reachable developer harness entry points | `--capture-workbench`, `--raw-harness`, and `--develop-lab` are live in Release (`LuminaApp.swift:11-17, 23-24`). Alternate UI and headless exits ship in the beta binary. |
| **F15** | No packaging / notarization tooling | Process blocker — no `ExportOptions.plist`, `notarytool`, or DMG script in repo |
| **F5** | Maintainer path in Release binary | `DevelopLabModel.swift:19` — recoverable via `strings`; professionalism blocker for external beta |
| **F6** | "Legacy shell" button on Open screen | `P0OpenView.swift:54-58` — beta feedback contaminant |
| **F14** | Build number never increments | Bug triage impossible when every tester reports `0.1.0 (1)` |

**Recommended before MVP (not hard blockers):**

| ID | Item | MVP impact |
|---|---|---|
| **F3** | Empty app icon set | Generic Dock/Finder icon — does not block install but signals "unfinished" to beta testers |
| **F7** | No folder usage descriptions | Optional for Developer ID DMG; TCC may prompt with empty rationale on Recent-shoot re-open. Does **not** require a privacy manifest. |

**Explicitly deferred from MVP (correct to skip):**

- **F2 / F9** — App Sandbox + security-scoped bookmark hardening (paired; App Store only)
- **F8** — Privacy manifest (App Store / TestFlight only)
- **F11** — Shoot keyed by folder leaf name
- **F12** — Cache location in Application Support
- **F13** — In-app shoot deletion

---

## 3. Blockers deferred to App Store distribution

These do **not** block the notarized Developer ID MVP. Every item must clear before Mac App Store submission or TestFlight.

| ID | Blocker | Notes |
|---|---|---|
| **F2** | App Sandbox disabled; no entitlements file | `ENABLE_APP_SANDBOX = NO`. MAS requires sandbox. |
| **F9** | Security-scoped bookmark migration | **Must ship in the same release as F2.** Path fallback in `SecurityScopedAccess.swift:30-34` works only unsandboxed. Enabling sandbox without F9 breaks Recent shoots silently. |
| **F8** | No privacy manifest | Required for App Store / TestFlight. Declares required-reason API use (`FileTimestamp`, `UserDefaults`). Separate from F7 usage strings. |
| **F7** | No usage descriptions / category / copyright | Required for App Store. Optional for Developer ID beta. Distinct from F8 — usage strings govern TCC folder prompts; privacy manifest governs required-reason APIs and tracking declarations. |
| **F3** | Empty app icon set | App Store hard requirement including 1024×1024. |
| **F10** | External exiftool binary | Sandbox cannot execute `/usr/local/bin/exiftool`. Must migrate EXIF reads to `ImageIO` or bundle exiftool (licence implications). |
| **F4** | Release harness entry points | App Store review risk for hidden functionality. |
| **F5** | Maintainer path in binary | Review / privacy polish. |
| **F6** | Legacy shell exposed | Incomplete / duplicate functionality. |
| **F14** | Build number | App Store Connect rejects duplicate build numbers. |

**Recommended for App Store (not strictly blocking review):**

- **F13** — In-app shoot removal (no account-deletion obligation — app has no accounts and no network)

---

## 4. Executive summary

Lumina is a single-target, dependency-free, fully-offline native macOS app. Structurally it is in good shape for release: universal binary (`arm64 x86_64`), hardened runtime already on, `macOS 14.0` deployment target, an `Archive` action bound to `Release`, zero third-party **bundled** code to license, and no network calls.

The gap is **release configuration and product-surface hygiene**, not architecture:

- Release is **ad-hoc signed** with no team, no entitlements, and no packaging/notarization tooling.
- **`/usr/local/bin/exiftool` is a functional beta blocker** — the P0 open path silently degrades without it.
- Three developer harness entry points replace or exit the app in Release builds.
- App Sandbox is off — correct for Developer ID MVP, blocking for App Store until paired with bookmark migration.

---

## 5. Evidence baseline — verified Release build settings

Output of `-showBuildSettings` (Release, `Lumina` scheme) at audited commit:

| Setting | Value | Assessment |
|---|---|---|
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.lumina.app` | Placeholder-grade; ownership not proven |
| `MARKETING_VERSION` | `0.1.0` | — |
| `CURRENT_PROJECT_VERSION` | `1` | Never incremented (F14) |
| `MACOSX_DEPLOYMENT_TARGET` | `14.0` | Good |
| `ARCHS` | `arm64 x86_64` | Good — universal |
| `ENABLE_HARDENED_RUNTIME` | `YES` | Good |
| `ENABLE_APP_SANDBOX` | `NO` | App Store blocker (F2); **correct for Developer ID MVP** |
| `CODE_SIGN_IDENTITY` | `-` | Ad-hoc — notarization blocker (F1) |
| `DEVELOPMENT_TEAM` | **unset** | Blocker (F1) |
| `CODE_SIGN_ENTITLEMENTS` | **unset** | Blocker for MAS (F2) |
| `GENERATE_INFOPLIST_FILE` | `YES` | **Valid.** Info.plist is synthesized at build time |
| `INFOPLIST_KEY_*` | zero set | F7 gap for App Store; optional for MVP |

Repository absences (excluding `DerivedData` and test artifacts):

```
find Lumina Scripts -name '*.entitlements' -o -name '*.xcconfig'   → no results
Lumina/Assets.xcassets/AppIcon.appiconset/                         → Contents.json only, no PNGs
PrivacyInfo.xcprivacy                                              → absent
ExportOptions.plist / package_dmg.sh                               → absent
.github/                                                           → absent
```

---

## 6. Findings

Severity is engineering severity. "Blocks" names the distribution gates the finding actually stops.

### 6.1 Blockers

#### F1 — No signing identity and no development team; Release is ad-hoc signed

**Blocks:** notarized Developer ID beta, TestFlight, App Store

**Evidence:** `project.pbxproj` — `DEVELOPMENT_TEAM = ""` in all configurations. Resolved Release: `CODE_SIGN_IDENTITY = -`.

**Remediation:** Enrol in Apple Developer Program; set `DEVELOPMENT_TEAM` via `Config/Release.xcconfig`. Add `Scripts/ExportOptions-DeveloperID.plist` with `method = developer-id`.

---

#### F10 — Hardcoded external exiftool at `/usr/local/bin/exiftool` (functional beta blocker)

**Blocks:** **notarized Developer ID beta (functional)**, App Store (sandbox + external binary)

**Evidence:**
- `Lumina/Services/ExifToolService.swift:4` — fixed path `/usr/local/bin/exiftool` (misses `/opt/homebrew/bin/exiftool` on Apple silicon).
- `Scripts/e2e_audit.swift:86` — same hardcoded path.
- `ContactSheetPreparation.swift:441` — P0 open uses `ExifToolService.batchCaptureDates` for shoot ordering.
- `ExifToolService.swift:48-50` — silent fallback to filesystem mtime when unavailable.
- `README.md:9`, `AGENTS.md` — documented as required for full app behavior.

**Beta impact:** Testers without Homebrew exiftool get chronologically wrong contact sheets and filmstrip order with no indication. This is a core P0 workflow failure, not a minor degradation.

**App Store impact:** Sandbox forbids executing an external binary at a fixed absolute path.

**Remediation (MVP minimum):** Probe `/opt/homebrew/bin/exiftool` and `/usr/local/bin/exiftool`; surface a non-blocking notice when neither is found. Document exiftool as a beta install prerequisite until an in-app metadata path exists.

**Remediation (App Store):** Migrate EXIF capture-date reads to `ImageIO`/`CGImageSource` or bundle exiftool (licence review required).

---

#### F2 — App Sandbox disabled and no entitlements file

**Blocks:** App Store, TestFlight · **Does not block:** Developer ID MVP

**Evidence:** `ENABLE_APP_SANDBOX = NO`; no `.entitlements` file. `UITestFixtures.swift:139` confirms unsandboxed path recovery is load-bearing.

**Remediation:** Defer for MVP. When MAS is the goal, add `Lumina.entitlements` with `com.apple.security.app-sandbox`, `files.user-selected.read-write`, and `files.bookmarks.app-scope` **in the same release as F9**.

---

#### F3 — App icon asset set contains no images

**Blocks:** App Store · **Recommended for:** notarized beta · **Optional for:** unsigned dogfood

| Stage | Severity |
|---|---|
| Unsigned dogfood | Optional polish — generic icon OK for internal use |
| Notarized Developer ID beta | Recommended — empty icon undermines beta trust; does not block Gatekeeper |
| Mac App Store | **Blocker** — 1024×1024 required |

**Evidence:** `Lumina/Assets.xcassets/AppIcon.appiconset/Contents.json` — ten mac slots, all empty (no `filename`, no PNGs).

---

### 6.2 High

#### F4 — Release-reachable developer harness entry points

**Blocks:** App Store · **Must fix for:** notarized MVP beta

**Evidence:** `Lumina/LuminaApp.swift` — only `UITestLaunch.runIfRequested()` is `#if DEBUG` guarded. The following are **Release-active**:

| Argument | Behaviour | Source |
|---|---|---|
| `--capture-workbench [dir]` | `.prohibited` activation, renders fixture PNGs, `exit(0)` | `WorkbenchCapture.swift:7-100` |
| `--raw-harness [dir]` | Headless harness, writes JSON report, `exit(...)` | `RawHarnessRunner.swift:17-41` |
| `--develop-lab` | **Replaces entire app UI** with `DevelopLabView` | `DevelopLabLauncher.swift:7-24`, `LuminaApp.swift:23-24` |
| `--capture-develop-lab [dir]` | Layout PNG capture, `exit(0)` | `DevelopLabLauncher.swift:27-84` |

Also Release-active (additional, not in scope of the three named above): `--p0-edit-harness`, `--p0-edit-live` (`LuminaApp.swift:14-15`).

This contradicts `UITestSupport.swift:8` for the **P0 UI automation harness specifically** — that statement is true for `UITestSupport` activation (see F16) but false for the app as a whole because of the harness calls above.

**Remediation:** Wrap `LuminaApp.swift:11-17` and the `DevelopLabLauncher.shouldPresentLab` branch at `:23-24` in `#if DEBUG`.

---

#### F5 — Maintainer's personal filesystem path in Release binary

**Evidence:** `DevelopLabModel.swift` previously hardcoded a maintainer Pictures path. It now only probes `LUMINA_DEVELOP_RAW_DIR`, `--develop-raw-dir`, and `~/Pictures/LuminaFixtures`.

**Remediation:** Delete line 19; fallbacks on lines 20–21 remain functional.

---

#### F6 — "Legacy shell" button exposes unfinished parallel UI

**Evidence:** `P0OpenView.swift:54-58`, `P0RootView.swift:5-8`.

**Remediation:** `#if DEBUG` the button. Required for MVP beta and App Store.

---

#### F7 — No Info.plist usage descriptions, application category, or copyright

**Distinction from F8:** Usage descriptions (`NS*UsageDescription`, `LSApplicationCategoryType`) govern **TCC folder-access prompts** and App Store category. They are **optional for Developer ID MVP** but **required for App Store**. They are **not** a privacy manifest and do not satisfy F8.

**Evidence:** `GENERATE_INFOPLIST_FILE = YES` with zero `INFOPLIST_KEY_*` settings. `INFOPLIST_KEY_NSHumanReadableCopyright = ""` explicitly empty.

**Needed for App Store:**

| Key | Trigger |
|---|---|
| `NSDesktopFolderUsageDescription` | Recent-shoot re-read at launch (`ShootStore.listRecentShoots`) |
| `NSDocumentsFolderUsageDescription` | Same |
| `NSDownloadsFolderUsageDescription` | Same |
| `NSRemovableVolumesUsageDescription` | `/Volumes/` sources (`P0SessionModel.chooseFolder` / SD `DCIM`) |
| `LSApplicationCategoryType` | App Store requirement |
| `NSHumanReadableCopyright` | About panel |

User-picked folders via `NSOpenPanel` (`P0SessionModel.chooseFolder`) need no string — Powerbox grants access. The gap is **re-access on later launches** through stored paths.

**Remediation:** Add `INFOPLIST_KEY_*` build settings. No standalone plist file required.

---

#### F8 — No privacy manifest while required-reason APIs are in use

**Distinction from F7:** `PrivacyInfo.xcprivacy` declares **required-reason API categories** and tracking/data-collection posture. It is **required for App Store and TestFlight**, **not required for Developer ID DMG**.

**Evidence:** No `PrivacyInfo.xcprivacy`. APIs used:

| Category | Usage |
|---|---|
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `ShootStore.swift:112, 119`; `ExifToolService.swift:58` |
| `NSPrivacyAccessedAPICategoryUserDefaults` | `IngestPreferences.swift:4` |

No network calls anywhere — manifest should declare no collected data and no tracking.

**Remediation:** Add `Lumina/PrivacyInfo.xcprivacy`. Defer until App Store track.

---

#### F9 — Security-scoped access falls back to raw paths; sandbox breaks Recent shoots

**Blocks:** App Store (functional regression once F2 lands)

**Must ship paired with F2.** Enabling sandbox without F9 yields an app where every Recent shoot silently fails to load originals.

**Evidence:** `SecurityScopedAccess.swift:30-34` — path fallback works only unsandboxed. Bookmark creation is failure-silent (`try?` at `SecurityScopedAccess.swift:48`, `ShootStore.swift:150`).

**Remediation:** Bundle with F2. Make bookmark failure observable; re-prompt via `NSOpenPanel` on stale resolution; keep path fallback behind `#if !APP_SANDBOX` for Developer ID builds.

---

### 6.3 Medium

#### F11 — Recent shoots keyed by folder leaf name (collision risk)

**Deferred:** MVP and App Store initial submission unless collision observed in beta.

#### F12 — Preview caches in Application Support, not Caches

**Deferred:** no user-visible impact for MVP.

#### F13 — No user-facing shoot deletion

**Deferred:** document manual `~/Library/Application Support/Lumina` cleanup in beta instructions.

#### F14 — No build-number increment mechanism

**Blocks:** App Store repeat uploads · **Degrades:** MVP bug triage

**Remediation for MVP:** Stamp `CURRENT_PROJECT_VERSION` from `git rev-list --count HEAD` at package time.

#### F15 — No packaging, notarization, or CI tooling

**Blocks:** notarized MVP

**Evidence:** No `ExportOptions.plist`, `notarytool` wrapper, or Release build in `Scripts/regression.sh` (Debug only).

---

### 6.4 Low

#### F16 — P0 UI automation harness is compiled into Release but runtime-inert (verified, narrow scope)

**Scope boundary:** This finding applies **only to the P0 UI automation harness** (`UITestSupport`, `UITestStateProbe`, `P0AccessibilityID`). It does **not** claim that all test-adjacent code is inert — F4 documents live Release harness entry points separately.

**Evidence:** Every writer of `UITestSupport.isActive` lives in `#if DEBUG` `UITestLaunch.swift:22-33`. Probe overlay gated on `UITestSupport.isActive` (`UITestStateProbe.swift:205`). State redirect on `stateDirectoryOverride` (`ShootStore.swift:19`). Auto-open additionally `#if DEBUG` (`P0RootView.swift:49-55`). In Release all read inert defaults.

**Residual:** dead binary weight; `--ui-testing` strings in `strings` output. No behaviour change in Release.

---

#### F17 — No crash reporting

Low for five-person beta; retain `.xcarchive` + dSYMs (`DEBUG_INFORMATION_FORMAT = dwarf-with-dsym` already correct).

#### F18 — Dead disk-session cache code (`PhotoImageCache.beginSession`)

#### F19 — `ENABLE_PREVIEWS = YES` in Release

#### F20 — No bundled third-party code to attribute

exiftool (F10) is invoked externally, not bundled — its licence does not attach to the distributed app today.

---

## 7. Verified DEBUG boundary (P0 UI automation only)

The following is **proven inert in Release** and scoped deliberately to the P0 XCUITest harness:

| Component | Guard | Release behaviour |
|---|---|---|
| `UITestLaunch.runIfRequested()` | `#if DEBUG` in `LuminaApp.swift:6-10` | Not called |
| `UITestSupport.isActive` | Set only by `UITestLaunch` | Always `false` |
| `UITestStateProbe` overlay | Gated on `isActive` | Not shown |
| `ShootStore` state redirect | Gated on `stateDirectoryOverride` | Uses real Application Support |
| P0 auto-open fixture | `#if DEBUG` in `P0RootView.swift:49-55` | Not compiled |

**Not covered by this boundary:** `--capture-workbench`, `--raw-harness`, `--develop-lab`, `--p0-edit-harness`, `--p0-edit-live` — all Release-reachable (F4).

---

## 8. Shortest path — unsigned dogfood

1. `#if DEBUG` harness calls (F4) — four lines.
2. Delete `DevelopLabModel.swift:19` (F5).
3. Archive and `hdiutil create`.

Icon (F3) and exiftool (F10) are optional for internal dogfood on maintainer machines with Homebrew.

---

## 9. Shortest path — notarized Developer ID MVP beta

Everything in §8, plus:

1. **F1** — Developer Program; `DEVELOPMENT_TEAM`; Developer ID Application certificate.
2. **F10** — exiftool path probe + visible notice when absent; document as beta prerequisite.
3. **F6** — hide Legacy shell button from Release UI.
4. **F3** — add app icon PNGs (recommended, not Gatekeeper-blocking).
5. **F14** — commit-count build stamp at package time.
6. **F15** — `Scripts/package_dmg.sh`: archive → export → `notarytool submit --wait` → `stapler staple` → `hdiutil create`.

**Acceptance on a clean Mac:**

```bash
spctl -a -vvv -t install /Volumes/Lumina/Lumina.app   # accepted, source=Notarized Developer ID
xcrun stapler validate /Volumes/Lumina/Lumina.app     # The validate action worked!
```

Manual: open a RAW shoot folder; confirm chronological contact-sheet order; navigate P0 single-photo editor; quit; relaunch; Recent shoot reopens with previews.

**Explicitly out of MVP scope:** F2/F9 (sandbox + bookmarks, paired), F8 (privacy manifest), F7 (usage strings — optional), F11, F12.

---

## 10. App Store / TestFlight checklist

Every item must clear. F2 and F9 **must land together**.

- [ ] F1 — Apple Distribution certificate; MAS provisioning profile
- [ ] F2 — `ENABLE_APP_SANDBOX = YES` + entitlements
- [ ] F9 — Bookmark persistence; remove raw-path fallback under sandbox (**with F2**)
- [ ] F3 — App icon including 1024×1024
- [ ] F4 — Harness entry points compiled out of Release
- [ ] F5 — No maintainer path in binary
- [ ] F6 — Legacy shell not reachable
- [ ] F7 — Usage descriptions + category + copyright (`INFOPLIST_KEY_*`)
- [ ] F8 — `PrivacyInfo.xcprivacy`
- [ ] F10 — exiftool removed or replaced with in-process metadata
- [ ] F14 — Build number increments per upload

---

## 11. Recommended release gate

### Tier 1 — Release configuration (under ~2 minutes)

1. `-showBuildSettings` assertions: team set, hardened runtime on, sandbox state matches target lane.
2. `xcodebuild -configuration Release build` — Release is never compiled in CI today.
3. `strings` hygiene: no `--develop-lab`, `--capture-workbench`, `--raw-harness`, or personal home-directory shoot paths.
4. Asset/manifest presence when targeting App Store: icon PNGs, `PrivacyInfo.xcprivacy`, required `INFOPLIST_KEY_*`.

### Tier 2 — Pre-distribution (when cutting a build)

5. `swift Scripts/p0_edit_test.swift`
6. `bash Scripts/run_p0_ui_tests.sh logic` — P0 logic tests only; do not broaden to stress/visual/explorer for release gate.
7. `notarytool` + `spctl` validation for Developer ID builds.

---

## 12. Summary — all findings by gate

| ID | Finding | Severity | Dogfood | Notarized MVP | App Store |
|---|---|---|---|---|---|
| F1 | No signing identity / team | Blocker | — | ● | ● |
| F10 | Hardcoded `/usr/local/bin/exiftool` | **Blocker (beta functional)** | ○ | **●** | ● |
| F4 | Harness entry points live in Release | High | ○ | ● | ● |
| F15 | No packaging / notarization tooling | Medium | — | ● | ○ |
| F5 | Maintainer path in binary | High | — | ● | ● |
| F6 | Legacy shell exposed | High | — | ● | ● |
| F14 | No build-number increment | Medium | — | ○ | ● |
| F3 | Empty app icon | Blocker (MAS) | — | ○ | ● |
| F7 | No usage descriptions / category | High | — | ○ | ● |
| F8 | No privacy manifest | High | — | — | ● |
| F2 | Sandbox off | Blocker (MAS) | — | — | ● |
| F9 | Path fallback breaks under sandbox | High | — | — | ● |
| F11 | Shoot keyed by leaf name | Medium | — | — | — |
| F12 | Caches in Application Support | Medium | — | — | ○ |
| F13 | No user-data deletion | Medium | — | — | ○ |
| F16 | P0 UI harness inert in Release (verified) | Low | — | — | — |
| F17–F20 | Crash reporting, dead code, previews, licensing | Low | — | — | — |

● blocks · ○ degrades or recommended · — not applicable to this lane

---

## 13. What is already right

- Hardened runtime enabled; no entitlement exceptions needed.
- Universal `arm64 x86_64`; `macOS 14.0` deployment target.
- Zero bundled third-party dependencies.
- Zero network calls — offline by construction.
- Xcode-generated Info.plist (`GENERATE_INFOPLIST_FILE = YES`) is a valid shipping approach.
- Debug/Release compiler settings correctly separated; dSYM generation on.
- Atomic, debounced, recoverable shoot persistence.
- Offline / missing-media handled as first-class UI state.
- **P0 UI automation harness verified inert in Release** — narrowly scoped to `UITestSupport` activation path (§7).

---

**Revised audit document commit:** to be recorded when this revision lands on `research/release-readiness`.
**Audited codebase commit:** `0700b95`
