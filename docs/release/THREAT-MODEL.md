# Lumina: threat model

The promises and the checked inventory of what the app can reach are [TRUST.md](TRUST.md); this file keeps the findings.

2026-10-01, at `4421a7c`. Covers the app as it ships today (the design page in a WKWebView plus
the native bridge in `Lumina/Sets`). The native SwiftUI rebuild (`LuminaKit`) inherits every
finding that is not marked *WebView only*. Fixes are proposals; `TASKS.md` orders them.

## What is worth protecting

| # | Asset | What must hold |
|---|---|---|
| A1 | The originals (ARWs on the card or in the folder) | Never changed, moved or deleted |
| A2 | Sidecars, including Lightroom's own develop settings in them | Never lost; replaced only with a backup |
| A3 | Decisions (sessions in Application Support) | Hours of culling: never lost or silently reset |
| A4 | The photos' content and metadata (faces, places, client and folder names) | Never leave the Mac |
| A5 | Everything else on the Mac | Out of Lumina's reach |
| A6 | The release itself and the signing identity | What users install is what was built from the repo |

## Where untrusted data crosses

| # | Boundary | What crosses |
|---|---|---|
| B1 | Card or folder → app | ARW heads, embedded JPEGs, whole RAWs (Edit), `.xmp` text, file and folder names, the volume label |
| B2 | Page (WebContent process) ↔ native | The `lumina` message handler (28 ops, `SetsBridge.swift:223`) and `lumina://` (`SetsSchemeHandler`) |
| B3 | App ↔ file system | Reads in opened folders; writes: sidecars, exports, sessions, downloads |
| B4 | App ↔ network | Should be nothing |
| B5 | Design zip → repo → CI → signed build → store | Page code, vendor JS, Swift packages, Actions, certificates |

Who or what goes wrong, most likely first: **accidents** (a pulled card, a full disk, a crash, two
apps writing one sidecar); **bad files** (a damaged or hostile ARW, JPEG or XMP on a card someone
hands over); **a compromised page** (through a bad file reaching a script sink, or through the
supply chain); **the supply chain** itself. Another process running as the same user is out of
scope: it can already read the photos.

## Sandbox findings (measured 2026-10-01, macOS 26.5.2)

`bash Scripts/release.sh local` builds the app sandboxed and signed ad hoc. Launched three ways,
same binary, counting `NetworkProcessProxy::didClose (Network Process 0 crash)` in the unified log:

| Build | Network process crashes in 12 s |
|---|---:|
| Not sandboxed | 0 |
| Sandboxed, entitlements as SAFETY.md 7 says (no network) | several hundred; the page never loads |
| Sandboxed + `com.apple.security.network.client` | 0 |

So a sandboxed app cannot host a WKWebView without the outgoing-network entitlement, even when
every URL is `lumina://`. SAFETY.md 7 ("no network entitlement") and the WebView UI cannot both
ship. See decision D2 in `APP-STORE.md`. Not yet measured: whether the page works fully with the
entitlement, and each item under T9 and T10 (the launches were in the background and the window
captures were not usable; that is task R1's first job).

## Findings

Severity is impact × likelihood for a photographer using the store build. "Open" means no fix in the repo.

### T1 · High · A shoot id from the page is used as a folder name
`saveSession`, `removeShoot`, `workingFiles` and the header take `id` from the page and build
`shoots/<id>/…` with it (`SetsShootStore.swift:63–104`, `SetsBridge.swift:350–370`).
`removeShoot` with `../../..` removes whatever folder that names: today, unsandboxed, anything the
user can delete. Needs a compromised page (T3), but it is the one bridge op that deletes.
**Fix:** `SetsShootStore` accepts only `^[0-9a-f]{16}$` (what `id(for:)` makes), in one place, with
a test for `..`, `/`, empty and over-long ids. An hour's work.

### T2 · High · Not sandboxed (release blocker)
ImageIO (embedded JPEGs) and Core Image's RAW decoder run inside the app process on bytes from
B1. A decoder bug is code execution with the user's full file access. The store also requires the
sandbox. **Fix:** R1. With it, a bad file reaches the container and the folders opened this
session, nothing else.

### T3 · High if the WebView ships · "Nothing leaves the Mac" is held by one rule (*WebView only*)
With `network.client` (see above) the only thing between the page and the network is the content
rule `^https?://` (`SetsBridge.swift:567`) and the navigation policy. That pattern does not name
`ws://` / `wss://`, WebRTC or anything else that is not http(s), and no test tries to get out.
The page is bundled and byte-checked, so this matters only once the page is compromised; but then
it is the difference between a bug and photos leaving.
**Fix (S1):** (a) rules that block every URL and then allow `lumina:`, `blob:`, `data:`, `about:`
(`ignore-previous-rules`); (b) a `Content-Security-Policy` response header on the page from
`SetsSchemeHandler` (the page's bytes stay identical): `connect-src`, `img-src`, `media-src`
limited to `lumina: blob: data:`, `form-action 'none'`, `frame-src 'none'`, `object-src 'none'`,
`base-uri 'none'`; scripts need `'unsafe-inline' 'unsafe-eval'` because Babel compiles the page;
(c) a probe scenario that tries fetch, XHR, WebSocket, an image, a beacon, RTCPeerConnection, a
form post and `window.open`, and fails if any leaves; (d) the lasting fix is the native UI, which
needs no network entitlement at all.
**Status 2026-10-06:** (a), (b) and (c) landed in `SetsOffline.swift`, plus WebRTC removed in every
frame (no URL load, so neither rules nor CSP cover it) and clicked links through
`SetsExternalLinks`. The escape test is `Tests/web/webkit.py offline` (32 ways out, WebKitGTK,
against a real listener); `app-offline` checks the layers in WKWebView. (d) is still D2.

### T4 · Medium · A sidecar written from text read hours earlier (A2)
`plumbing.js:324–327` keeps each sidecar's text from when the folder was opened; Save
(`plumbing.js:413`) sends the merged text. I found no re-read at Save. If Lightroom writes that
sidecar in between, Save puts back the old text with a new rating, and `.lumina-bak` does not
help: `SetsFileOps.write` never replaces an existing backup, so it still holds the first version.
RELEASE.md lists "Lightroom writing a sidecar at the same moment" as untested.
**Fix (S7):** `writeSidecar` takes the hash of the text the merge was based on; when the file on
disk differs, re-read and merge again (plumbing asks the page's own `xmpFor`), or report
`DSC03311 · changed since opened`. Add `app-xmp-changed-since-open` to the probe.

### T5 · Medium · Inputs from a folder have no upper bound
- Every `.xmp` is read whole and sent to the page as text (`SetsIngest.swift:211`): one huge
  file exhausts memory.
- The listing is unbounded and not cancellable (`SetsIngest.list`): opening `/`, the home folder
  or a network share walks all of it, and `others` holds every path.
- Sessions from the page are stored at any size.
**Fix (S3):** skip sidecars over 1 MB and count them in the import notes' existing "unreadable";
stop a listing at a file count and depth with a clear refusal; cancel it when another folder is
opened; cap a session at a few MB. The preview range (64 MB), render size (8192 px) and stand-in
size (6000 px) are already capped.

### T6 · Medium · Links inside a shoot folder lead out of it for reads
`SetsIngest.resolve` compares standardised paths without resolving links, and `read` refuses a
link only as the last component (`O_NOFOLLOW`). A linked subfolder, or a linked file opened by
the Edit render, the canvas or an export copy, is followed. Read-only, and sidecar writes do
resolve links (`SetsFileOps.swift:122`). **Fix (S5):** resolve links in `resolve()` and refuse
anything outside the root; test beside `testLinkedFolderCannotLeadOut`.

### T7 · Medium · A page that keeps crashing is reloaded forever
`webViewWebContentProcessDidTerminate` reloads without a limit (`SetsRootView.swift:176`). A file
that kills the WebContent process gives a loop. Also `applicationShouldTerminate` waits for the
page to answer with no timeout: a hung page means Quit never completes.
**Fix (S6):** three reloads a minute, then a native alert naming the last file read; a 2 s timeout
on the unsaved-keepers question.

### T8 · Medium · Bridge ops and switches nobody uses in v5
`writeInto` still takes v3's `jpg` (CSS look), `copy` and `bytes` with any name and extension;
`SetsEditLook` is "unused by v5"; `reveal` shows any absolute path; `lumina-selftest.js` ships;
six `LUMINA_*` environment switches are read in release builds, and `LUMINA_RULES` loads the look
coefficients from any path. Each is reachable surface with no user.
**Fix (S4):** remove or `#if DEBUG` what v5 does not call; `bytes` only `.xmp`, renders only
`.jpg/.tif/.png`; `reveal` only inside an opened folder or the last export folder; environment
switches behind `#if DEBUG` (the probe builds Debug). `release_preflight.sh --strict` already fails on the switches.

### T9 · Medium · Bookmarks are written but not used correctly (sandbox)
`startAccessingSecurityScopedResource` is never balanced by a stop; a stale bookmark is not
renewed; reopen falls back to the raw path, which a sandbox refuses; the export journal finds the
destination by path on the next launch, so crash recovery silently does nothing there.
**Fix:** R1.

### T10 · Medium · The card flow assumes free access to `/Volumes` (sandbox)
`SetsCardWatcher.inspect` lists `DCIM` on mount and "Cull this card" opens it with no panel. In a
sandbox both need a folder the user picked. **Fix:** R1 plus a design ask: the card banner opens
the folder panel already on the card; the grant is kept per volume UUID, so the same card is one
click the first time and none after.

### T11 · Low · Smaller items
- Downloads go to `~/Downloads` under a name the page supplies, any type (`SetsRootView.swift:164`). The sandbox refuses it; only a debug export uses it. Remove in release.
- Navigation allows `data:` and `blob:` as pages, and any https link the user clicks opens in the browser. Allow only the known contact links.
- ~~Paths and folder names go to the unified log in clear (`NSLog`).~~ Closed 2026-10-06: `LuminaLog` with private fields; `trust_check.py` refuses `NSLog`. (`onEvent` reaches only the probe's log.)
- A damaged `index.json` reads as "no recent shoots" and the next open overwrites it. Keep the damaged file aside.
- Sessions, paths and capture dates sit unencrypted in the container. Acceptable; "Remove Working Files" exists. Say so in the privacy text.

### T12 · Medium · Supply chain (A6)
- **Closed (S8):** the `LuminaPlayground` target and the `Inject` package (GitHub, 1.6.0, with
  `-interposable` and a build phase that copied InjectionIII's bundle) are removed, with the scheme
  and `Package.resolved`. The project has three targets and no package: a clean build fetches nothing.
- **Closed (S8):** GitHub Actions are pinned by commit, with the release in a comment
  (`.github/workflows/lumina.yml`). Moving a pin is a reviewed change; nothing updates them by itself.
- React and Babel are vendored, SRI-pinned in `support.js` and byte-checked by `SetsPageBytesTests`
  and now `release_preflight.sh`. Good.
- A design zip is a code import: the page runs with the bridge. `sets_sync_design.sh` audits wording
  and the demo layer. **Closed (S8), not yet run:** step 2b prints every line the new page files add
  that names `fetch(`, `XMLHttpRequest`, `WebSocket`, `sendBeacon`, `RTCPeerConnection`,
  `EventSource`, `window.open`, `postMessage`, `messageHandlers`, `new Function`, `eval(`, `import(`
  or a URL scheme, for a person to read. It reports and never fails the sync; the first real sync is its test.
- Signing: the API key (`.p8`) and the notary profile stay outside the repo and off CI; releases
  are cut from one Mac by `Scripts/release.sh`, which refuses uncommitted changes.

## What already holds

- Card and originals: `writeSidecar` accepts only `.xmp` inside the root, with links resolved, a RAW beside it, not on a card; copies are streamed, hashed twice and never overwrite (`SetsFileOps`, `SetsSidecarTests`, `SetsTrustTests`, `probe.sh fault`).
- Writes are atomic with fsync and read back; `.lumina-bak` before any replacement.
- Page → native strings into `evaluateJavaScript` are JSON-encoded or letters only.
- The web view's store is non-persistent; no inspector flag; nothing registered as a URL scheme or document type, so nothing outside can drive the app.
- Hardened runtime with no exceptions; no JIT, library-validation or debugging entitlement (preflight fails on any).
- No analytics, no crash reporter, no account.
