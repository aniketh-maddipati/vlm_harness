# Lumina: getting to the App Store

2026-10-01. What exists, what only the account holder can do, and the steps for each release.
Companion files: `THREAT-MODEL.md`, `STRESS-MATRIX.md`, `TASKS.md`. `docs/RELEASE.md` (PR #166)
stays the product-side checklist.

## Where it stands

| Piece | State |
|---|---|
| Release build settings (`Config/Release.xcconfig`): sandbox, hardened runtime, arm64, category, copyright, export compliance, version 1.0.0, build = commit count | Done. Applied by the script only; the project file and day-to-day builds are unchanged |
| Entitlements: `Config/Lumina.entitlements` (SAFETY.md 7) and `Config/Lumina-Sets.entitlements` (+ outgoing network, for the WebView) | Done |
| Privacy manifest (`Lumina/Resources/PrivacyInfo.xcprivacy`): nothing collected, no tracking | Done, in the bundle |
| `Scripts/release.sh local` (sandboxed, ad hoc) | Runs: 18 s, preflight passes with 4 warnings |
| `Scripts/release.sh dmg` (Developer ID, signed dmg) | Runs end to end with the certificate on this Mac. Not notarised: no credentials stored yet |
| `Scripts/release.sh store` (pkg for App Store Connect, `--validate`, `--upload`) | Written, **not run**: needs the certificates and app record below |
| `Scripts/release_preflight.sh` (signature, entitlement allowlist, Info.plist, arm64, page and vendor bytes, privacy manifest, stray files) | Runs; `--strict` fails on the open items |
| The app actually working in the sandbox | **No.** The page does not load without the network entitlement (measured), and bookmarks, the card flow and crash recovery assume no sandbox (read from the code). `TASKS.md` R1 |

## Decisions only you can make

| # | Decision | Recommendation |
|---|---|---|
| D1 | **Name and bundle id.** App Store names are unique and "Lumina" is very likely taken. `com.lumina.app` may also be registered by someone else. The id names the sandbox container, so it cannot change after the first TestFlight build without losing sessions. | Check both in App Store Connect first. Fallbacks: "Lumina Cull" / `com.anikethmaddipati.lumina`. One line in `Config/Release.xcconfig`. **Decided 2026-10-05: `com.aniketh.lumina`, registered for team QHB498M84T.** Day-to-day builds (`install_app.sh`, Xcode) keep the project's `com.lumina.app`, so they have their own container |
| D2 | **Which UI ships in 1.0.** The WebView UI needs the outgoing-network entitlement to start in a sandbox, so the system stops enforcing "nothing leaves the Mac" and SAFETY.md 7 must be amended. The native UI needs no network entitlement. | If native passes its gates in time, ship native with `LUMINA_UI=native`. If not, ship the WebView with task S1 done and say "blocked by the app" rather than "by the system" in the privacy text |
| D3 | **Channels.** Store only, or also a notarised dmg. | Both. The dmg works today and gets friends a build while review runs. Same sandbox, same bundle id |
| D4 | **Price and territories.** | Yours |
| D5 | **Minimum macOS.** 14 today. | Keep 14 only if a 14 and a 15 machine are tested (`STRESS-MATRIX.md` 9); else raise it |

## Once (account holder, about an hour)

1. App Store Connect ▸ Apps ▸ +: macOS, the name and bundle id from D1, SKU `lumina-mac`.
2. Certificates: Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + **Apple Distribution** and
   **Mac Installer Distribution**. (Only "Developer ID Application" is in the keychain now.)
3. An API key for uploads: App Store Connect ▸ Users and Access ▸ Integrations ▸ Team Keys, role
   App Manager. Save the file as `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8`. Never in the repo.
4. Notarisation for the dmg:

```bash
xcrun notarytool store-credentials lumina-notary --key ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <ISSUER>
```

5. A privacy policy URL and a support URL (both required by the listing). One static page each.

## Each release

```bash
bash Scripts/release.sh local
```

Sandboxed build for this Mac. Run the stress matrix against it.

```bash
NOTARY_PROFILE=lumina-notary bash Scripts/release.sh dmg --strict
```

The dmg for direct download: signed, notarised, stapled, Gatekeeper-checked, with its SHA-256.

```bash
ASC_KEY_ID=<KEYID> ASC_ISSUER_ID=<ISSUER> bash Scripts/release.sh store --strict --upload
```

Validates with App Store Connect, asks, uploads. The build appears under TestFlight after processing.
Then: TestFlight internal group → fresh-machine pass → external group (first external build is
reviewed) → submit for review.

Version: `MARKETING_VERSION` in `Config/Release.xcconfig`, or `VERSION=1.0.1` for one run. The
build number is the commit count, so it rises by itself. A release is always a commit: the script
refuses a tree with uncommitted changes.

## The listing

| Field | Draft / note |
|---|---|
| Category | Photography (set in the build) |
| Subtitle | "Cull a Sony shoot, keys first" (30 characters max) |
| Privacy label | Data Not Collected. True for both UIs: no analytics, no account, no network use |
| Export compliance | Answered in the build: SHA-256 only, exempt |
| Screenshots | 2880 × 1800 or 2560 × 1600, 1 to 10. `docs/screenshots` are older keys: retake once the UI is final |
| Review notes | The reviewer has no Sony RAW files. Give a download link to five ARWs you own the rights to and three lines: Open the folder, P keeps, ⌘↩ saves. Say that "Save" writes `.xmp` next to the photos and why the folder panel appears |
| Age rating, copyright | 4+; © 2026 Aniketh Maddipati (in the build) |

## Review risks, most likely first

1. **Guideline 2.1, cannot be exercised**: no sample files. Covered by the review notes above.
2. **Sandbox entitlements questioned**: `network.client` with a "no network" claim (D2). Explain in
   the notes: WebKit needs it to start; all content is bundled.
3. **Trademarks (5.2.1, 2.3.7)**: "Lightroom", "Capture One", "Sony" in the description or
   screenshots. Say "writes standard XMP ratings" and "Sony ARW files"; no logos, no "Lightroom-style".
4. **2.3.1, hidden features**: the sample shoot, `?selftest` and the environment switches. Task S4.
5. **4.2, a web page in a wrapper**: the app is local and file-based, with native rendering. Low.
6. **Third-party licences**: React and Babel are MIT; the notice must ship. Task R6.

## Not measured, so not promised

- `release.sh store` has never produced a pkg (no distribution certificate here).
- Whether App Store Connect accepts an arm64-only build with macOS 14 as minimum: expected (the
  rule is 12 or later), confirmed only by `--validate`.
- Whether the privacy manifest's reasons are checked for a Mac app at all. Shipping it costs nothing.
- The local sandbox check left a container at `~/Library/Containers/com.lumina.app.sandbox-check`
  on this Mac. It holds nothing; remove it in Finder if you like.
