# Install page — content spec (G2: notarized zip)

**Distribution ruling (G2):** Notarized Developer ID zip/DMG — not TestFlight.  
**Evidence:** `docs/release/MACOS_RELEASE_READINESS_AUDIT.md` §Recommended MVP path; F11 release-integrity harness (Developer ID + notarize + staple, `betaDiagnostics: null`); `BetaDiagnosticsSocket.activeKind == nil` on wave builds.

**Scope:** Content only. No site build, no framework choice, no metrics surface, no telemetry dashboard (D36, D45, F08.4, F10.7).

**Copy authority:** `design/copy-contract.txt` → code. Strings not in the contract are flagged **`[NEW — contract entry owed]`**.

**Hard exclusions on this page:**

| Banned | Reason |
|--------|--------|
| `[○][P] nothing leaves this Mac` (`CopyContract.nothingLeavesMac`) | CONFLICT 4 open — TestFlight reporter contradicts; frozen copy must not appear on beta page until ruled |
| Hand-entered tester metrics / completion rates / time comparisons | A9 facilitator notes only; not a public dashboard (F10.7) |
| F12 bug-report bundle path / “Export diagnostics” / zip attachment instructions | F12.3 **not shipped** — see surface 5 |

---

## Surface 1 — Download + version

### User-visible copy

| Element | Exact string | Source |
|---------|--------------|--------|
| Page title | `Lumina` | `[NEW — contract entry owed]` |
| Primary action label | `Download` | `[NEW — contract entry owed]` |
| Version line | `Version {marketingVersion} ({bundleVersion})` | `[NEW — contract entry owed]` — `{marketingVersion}` and `{bundleVersion}` are manifest data |
| Build citation line | `{bugReportLine}` | **F11.4** — `LuminaBuildManifest.bugReportLine` (`Lumina/Core/LuminaBuildManifest.swift`) |

### Data displayed (read from current ship artifact)

Source file on disk after packaging: embedded `Lumina.app/Contents/Resources/LuminaBuildManifest.json`  
Harness read: `python3 Scripts/harness/release/f11_read_manifest.py --app <path/to/Lumina.app>`

| Field | Manifest key | Example (2026-08-12 Release) |
|-------|--------------|------------------------------|
| Marketing version | `marketingVersion` | `0.1.0` |
| Build number | `bundleVersion` | `1` |
| Git commit | `gitSha` | `11b9ec4e8c8544439f6cdd260baf01bd91034362` |
| Tokens hash | `tokensHash` | `7b0c1552736eba4c253d4f32bd81f35691f8b4c0ff238e602054729c50e36b36` |
| Fixture manifest version | `fixtureManifestVersion` | `1.0-mvp-fleet` |
| Contract / tokens version | `contractVersion` | `6.2-motion-seal` |
| Build timestamp (UTC) | `buildDate` | `2026-08-12T15:35:36Z` |
| Build configuration | `configuration` | `Release` |
| Beta diagnostics socket | `betaDiagnostics` | `null` on wave builds (F11.6 / A7 inactive) |

### Download target

| Data | Source |
|------|--------|
| Artifact URL | `[OPEN — host path not in repo]` — notarized zip or DMG for **current** `artifacts/release/shipped/current/` promotion |
| Filename convention | `[NEW — contract entry owed]` e.g. `Lumina-{marketingVersion}-{bundleVersion}-macOS-arm64.zip` |

**Rendered `bugReportLine` shape (F11.4 shipped):**

```
Lumina {marketingVersion} ({gitSha prefix 12}) · tokens={tokensHash prefix 12} · fixture={fixtureManifestVersion} · contract={contractVersion} · built={buildDate}
```

When `betaDiagnostics` is non-null (TestFlight / A7 path — **not G2**), append:  
`· betaDiag={kind} expires={expiresAtMarketingVersion}`

---

## Surface 2 — First launch (Gatekeeper)

Gatekeeper instructions for a notarized Developer ID app downloaded outside the App Store. Factual steps only — not sovereignty marketing.

### User-visible copy

| Element | Exact string | Source |
|---------|--------------|--------|
| Section heading | `First open on macOS` | `[NEW — contract entry owed]` |
| Body paragraph 1 | `Lumina is signed and notarized. macOS may still ask you to confirm the first open of an app downloaded from the web.` | `[NEW — contract entry owed]` |
| Body paragraph 2 | `If Lumina will not open: right-click Lumina in Finder, choose Open, then confirm Open in the dialog. Or open System Settings → Privacy & Security, find the Lumina block under Security, and choose Open Anyway.` | `[NEW — contract entry owed]` |
| Requirement note | `Requires macOS 14 or later on Apple Silicon.` | **Derived from** `design/mvp-test-plan.md` §1 (floor & fleet) — `[NEW — contract entry owed]` |

### Data displayed

None — static instructions.

**Do not use on this surface:** `nothing leaves this Mac`, `files stay where they are · edits in open sidecars · this shoot opens in Lightroom as-is` (sovereignty copy belongs elsewhere; not required for Gatekeeper steps).

---

## Surface 3 — Previous build (rollback)

Rollback retention: **F11.5** — `Scripts/harness/release/retain_shipped_artifact.py promote` rotates `artifacts/release/shipped/current/` → `previous/`. Rollback is a file copy; no rebuild (D51 / R-I.2).

### User-visible copy

| Element | Exact string | Source |
|---------|--------------|--------|
| Section heading | `Previous build` | `[NEW — contract entry owed]` |
| Body (when previous exists) | `If this build fails on your Mac, download the previous build and replace Lumina.app in Applications.` | `[NEW — contract entry owed]` |
| Body (when no previous) | `No previous build is retained yet.` | `[NEW — contract entry owed]` |
| Secondary action label | `Download previous` | `[NEW — contract entry owed]` |
| Previous version line | `Version {marketingVersion} ({bundleVersion})` | `[NEW — contract entry owed]` — manifest data from **previous** ship |
| Previous build citation | `{bugReportLine}` | **F11.4** — from previous manifest |

### Data displayed (read from rollback artifact)

| Field | Source path |
|-------|-------------|
| Previous app binary | `artifacts/release/shipped/previous/Lumina.app` |
| Previous manifest | `artifacts/release/shipped/previous/LuminaBuildManifest.json` |
| Promote ledger (operator only; not user-facing) | `artifacts/release/shipped/promote-log.json` |

Same manifest keys as Surface 1, read from **previous** manifest file.

### Download target

| Data | Source |
|------|--------|
| Previous artifact URL | `[OPEN — host path not in repo]` — packaged copy of `shipped/previous/Lumina.app` |

**Hide this section** when `shipped/previous/Lumina.app` is absent (first ship).

---

## Surface 4 — Wave signup

Signup collects facilitator contact fields only. **No metrics fields.** No completion/time/trust scores on the page.

### User-visible copy

| Element | Exact string | Source |
|---------|--------------|--------|
| Section heading | `Wave signup` | `[NEW — contract entry owed]` |
| Intro line | `Wave builds are free — no license step.` | **Derived from** `design/mvp-test-plan.md` §5 Setup (A8) — `[NEW — contract entry owed]` |
| Consent block (verbatim) | See below | **`design/mvp-test-plan.md` §6 `[● A10]`** |
| Consent checkbox label | `I agree` | `[NEW — contract entry owed]` |
| Submit action label | `Request access` | `[NEW — contract entry owed]` |

**Consent text — paste verbatim (do not edit):**

> I consent to Lumina using photographs from this test session, and my final hand edits on those photographs, as an evaluation set for taste-model proving. Edits and marks from this session are used only to measure whether a future Develop proposal beats my own hand finishing — not for training without a further agreement, and not for network upload from launch builds (diagnostics: see contract D45 / A7).

### Data collected (form fields — labels only; not copy-contract)

| Field label | Source |
|-------------|--------|
| Name | `[NEW — contract entry owed]` |
| Email | `[NEW — contract entry owed]` |
| macOS version | `[NEW — contract entry owed]` |
| Camera bodies in use (optional) | **Derived from** `design/mvp-test-plan.md` §1 bodies table — `[NEW — contract entry owed]` |

**Do not collect or display:** unaided completion %, time-vs-tool numbers, trust-interview scores, rows-probe pass rates (A9 facilitator notes stay off-page).

---

## Surface 5 — When something breaks

Resolves to the F12 bundle path **only where F12.3 shipped**. F12 build prompt is **not in tree** (`BUILD_LOG.md` — CONFLICT 4 / `design/build-prompts/` absent). **F12.3 bug-report bundle export is not shipped.**

### What F11.4 actually shipped (in scope for this surface)

| Shipped artifact | Path / API |
|------------------|------------|
| Embedded manifest JSON | `Lumina.app/Contents/Resources/LuminaBuildManifest.json` |
| One-line bug citation | `LuminaBuildManifest.bugReportLine` |
| Harness read | `python3 Scripts/harness/release/f11_read_manifest.py --app <Lumina.app>` |

No in-app About surface, no “Export diagnostics” control, no zip bundle writer — **do not instruct testers to attach an F12 bundle.**

### User-visible copy

| Element | Exact string | Source |
|---------|--------------|--------|
| Section heading | `When something breaks` | `[NEW — contract entry owed]` |
| Instruction paragraph 1 | `Email the facilitator with what you were doing, what you expected, and what happened instead.` | `[NEW — contract entry owed]` |
| Instruction paragraph 2 | `Include this build line in your message:` | `[NEW — contract entry owed]` |
| Build line (monospace block) | `{bugReportLine}` | **F11.4** — tester copies from install page version line **or** reads manifest as above |
| Optional manifest path note (facilitator-facing footnote) | `Manifest file: Lumina.app → Contents → Resources → LuminaBuildManifest.json` | `[NEW — contract entry owed]` — documents shipped path only; not an F12 bundle |
| Facilitator contact | `{facilitatorEmail}` | `[OPEN — not in repo]` |

### Data displayed

| Data | Source |
|------|--------|
| `{bugReportLine}` | Current ship manifest (Surface 1) |
| `{facilitatorEmail}` | Operator-configured — not in copy-contract |

### Explicitly out of scope until F12.3 ships

- Bug-report **bundle** zip path
- Automatic log / crash collection
- Screenshot attachment workflow beyond “email the facilitator”
- TestFlight crash reporter (G2 ≠ TestFlight; A7 socket inactive)
- Any dashboard of tester-reported counts

**F12.3 follow-up:** When F12 lands, replace Surface 5 body with F12.3-specified bundle path and copy only — do not expand ahead of ship.

---

## Operator checklist (not user-facing)

- [ ] F11.3 PASS on ship host (Developer ID, notarized, stapled) before linking Surface 1 download
- [ ] Run `retain_shipped_artifact.py promote` before each new ship so Surface 3 has data
- [ ] Populate `[OPEN]` host URLs and facilitator email
- [ ] Add `[NEW — contract entry owed]` strings to `design/copy-contract.txt` before any page goes public
- [ ] Re-read manifest after ship; Surface 1 / 5 `bugReportLine` must match embedded JSON

---

## Contract copy available but not used on this page

| Copy-contract line | Why omitted |
|--------------------|-------------|
| `[○][P] nothing leaves this Mac` | CONFLICT 4 — hard ban on beta page |
| `[○][PL] files stay where they are · edits in open sidecars · this shoot opens in Lightroom as-is` | Not required for install/rollback/Gatekeeper; avoid sovereignty marketing on beta page |
| App-table / cull / export strings | In-app only — not install-page surfaces |
