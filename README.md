# Lumina

Lumina is a Mac app for culling Sony ARW shoots quickly. Open a card or a folder, work through the
shoot with the keyboard, and keep the frames you want. Everything else stays where it was.

![Culling a shoot by time rows](docs/screenshots/cull-row.png)

## How culling works

**Open a shoot.** Choose File ▸ Open (⌘O) and pick a folder, or insert a Sony card and press
**Return** when the open screen offers to cull it. Lumina remembers each shoot, so if you reopen it
later you pick up where you left off.

**The shoot is split into rows by time.** A new row starts after a break of more than 90 seconds,
and each row is labeled with its start time, such as 06:48 or 08:12. Inside a row, frames shot less
than a second apart form a **burst** (or a **bracket**, if the exposures step from under to over),
and the rest are listed as **singles**.

**Lumina suggests what to keep.** In a burst it suggests the sharpest frame that isn't blown, soft,
or shaky. It suggests every frame of a bracket, and each single that has none of those problems. A
dot in a frame's corner means that frame is likely out.

**Work a whole row at once.** Use ↑ ↓ to move between rows. Press **R** to keep the suggested frames
or **X** to reject the entire row. Hold **L** to also see the frames Lumina didn't suggest.

**Or go one photo at a time.** Press → to step into a row. Then **R** keeps a photo, **X** rejects it,
and ← → moves through the frames. Lumina tags frames that have a problem, such as **blown** or
**soft**, and points out the **sharpest** frame in a burst.

![A single photo selected, tagged "blown"](docs/screenshots/cull-photo.png)

**The frames you keep collect in the strip at the bottom.** The count in the top bar updates as you
go, and your work is saved on its own. **Q** or ⌘Z undoes the last action. Press **Space** to see a
photo large, hold **G** for 100%, or press **W** to compare the frames of a burst.

![Keeping the first frame of a burst; it lands in the kept strip](docs/screenshots/cull-kept.png)

**Auto** is an automatic look (exposure, contrast, highlights, shadows and white
balance) that Lumina works out for each photo. While you cull, press **V** to preview it on a row or
group, or hold **A** to compare one photo with and without it. A preview changes nothing until you apply it in Edit.

Press **?** to list every key.

![Every culling key](docs/screenshots/cull-keys.png)

When you finish culling, press **Tab** to move on to **edit** (optional touch-ups) and then **export**.
Export either copies the RAWs with XMP sidecars for Lightroom or Capture One, or writes RAW and JPEG.

## What it won't do

- Write to the card or change your original files.
- Move files. Lumina only copies, and it checks every copy.
- Replace a file without first saving a `.lumina-bak` backup.
- Send anything off your Mac. Lumina's own code makes no network requests (see
  [Trust and privacy](#trust-and-privacy) for the one caveat).

## Trust and privacy

This section says what Lumina can reach, what it keeps, and what could go wrong. It describes `main`
as of 2026-10-06. Where something has not been tested, it says so. The longer working document is
[docs/release/THREAT-MODEL.md](docs/release/THREAT-MODEL.md).

### What Lumina can read and write

- Lumina runs in the App Sandbox. It can read and write only the folders you pick in an Open or
  Export panel (or the card you grant access to), plus its own container. It cannot see the rest
  of your home folder.
- It reads the RAW files, their embedded JPEG previews and any existing `.xmp` sidecars. Edit and
  export read the whole RAW.
- It writes three kinds of files outside its container, all in folders you chose:
  - **`.xmp` sidecars** with your rating, beside the RAWs. Never on a card or any removable volume.
    An existing sidecar is merged, not replaced (Lightroom's develop settings in it are kept), a
    `.lumina-bak` copy is made first, and if the sidecar changed on disk since the folder was opened
    (for example Lightroom wrote it), Lumina reports it and does not write.
  - **Exports**: copies of RAWs and sidecars, or rendered JPEGs, into the folder you pick. Copies
    are hashed (SHA-256) and checked; nothing is overwritten.
  - **`.lumina-bak`** backups, as above.
- Edit looks are never written to XMP. Only ratings are.

### What stays on your Mac, and where

Everything Lumina keeps is in `~/Library/Containers/com.aniketh.lumina/`, unencrypted (FileVault
covers it if you use FileVault):

- `shoots/index.json`: your recent shoots, with the folder's name and path, the volume's UUID, the
  photo count, the first capture time, the keeper count, the last photo's file name, and a
  security-scoped bookmark to the folder.
- `shoots/<id>/session.json`: your decisions and Edit looks, keyed by file name.
- `shoots/<id>/Lumina.json`: which RAW decoder versions each camera body supports.
- `exports/`: a journal per export, so an interrupted export can be cleaned up on the next launch.

Previews and thumbnails are kept in memory only (from reading the code), and the web view uses a
non-persistent store. Not checked: caches that WebKit, Core Image or Metal may write on their own. File ▸ Remove Working Files… deletes a shoot's files from the container.

Sessions made by builds before the sandbox stay in `~/Library/Application Support/Lumina` until
you bring them over or delete them.

Similar-photo detection (`lumina.near`) uses Apple's Vision framework on the embedded previews. It
runs on the Mac. There is no face recognition, no account, no analytics and no crash reporter.

### Network

Lumina's Swift code and `plumbing.js` contain no networking code. The caveat is the sandbox
entitlement `com.apple.security.network.client`: the UI is a web page in a WKWebView, and in a
sandboxed app WebKit does not start without that entitlement (measured 2026-10-01, see the threat
model). So macOS does not stop outgoing connections; Lumina does:

- A content rule blocks every `http`, `https`, `ws`, `wss` and `ftp` load from the page.
- The navigation policy lets the page load only `lumina:`, `about:`, `blob:` and `data:` URLs.
- The page is bundled with the app and checked byte for byte against the design. It loads no
  remote scripts.
- A link you click (Report a bug, LinkedIn, X) opens in your browser or mail app. Report a bug
  only opens a draft email with an empty template; nothing is attached and nothing is sent until
  you send it.

These matter only if the page is compromised, for example by a hostile file reaching a script, or
by a bad design import. Gaps today:

- Nothing blocks WebRTC, and there is no Content-Security-Policy header. No test yet tries every
  way out (fetch, XHR, WebSocket, image, beacon, WebRTC, form post, `window.open`). Task S1 in
  [docs/release/TASKS.md](docs/release/TASKS.md).
- On `main`, any `https` or `mailto` link the page reports as clicked is handed to your browser or
  mail app. An allowlist of the three known links (`SetsExternalLinks.swift`) exists with tests but
  is not yet used by the navigation policy. Not checked: whether a click made by a script counts as
  a click there.
- Whether the WebView build or a native UI without the entitlement ships in 1.0 is still open
  (decision D2 in [docs/release/APP-STORE.md](docs/release/APP-STORE.md)).

Open pull request #210 adds release checks that fail if the binary imports a networking API, links
Network or CFNetwork, has an App Transport Security exception, ships an unreviewed script, or loses
the content rule.

### Concerns for professional work

- **Client photos and names.** Photos, metadata and folder names do not leave the Mac through
  Lumina. They do sit in the container (paths, folder names, file names, capture times) and in the
  system log (below).
- **The system log.** Some messages include photo file names in clear text, for example when a RAW
  decoder falls back. The log stays on the Mac but is included in a sysdiagnose you send to Apple.
  Task R7 (private fields in logs) is open.
- **Exported files carry metadata.** RAW and sidecar copies are byte copies: GPS, camera serial
  number, owner name and anything else in the file go with them. Not verified: which metadata
  Lumina's rendered JPEGs keep. Check before sending exports to a client.
- **Cards.** Lumina never writes to a card and treats any removable volume as one. It does not
  format or delete anything on it.
- **Crash reports.** Lumina has none of its own. If you share analytics with app developers in
  macOS settings, or install through TestFlight, Apple may pass crash logs to the developer; those
  can include file paths.

### What could go wrong

Most likely first:

- **Accidents**: a pulled card, a full disk, a crash or kill mid-write, two apps writing one
  sidecar. Writes are atomic, synced and read back; backups are kept; the fault tests cover pulls,
  full disks and kills on disk images.
- **A bad file** on a card someone hands you: a damaged or hostile ARW, JPEG or XMP. Apple's image
  decoders run inside the app process, so a decoder bug could run code with the app's access: the
  folders you opened and the container, nothing else (the sandbox). Inputs are size-capped, links
  inside a shoot folder cannot lead out of it (a link swapped in at the moment of reading is a
  known gap), and a page that keeps crashing stops reloading after
  three tries.
- **A compromised page**, through a bad file or a bad design import. It could ask the native side
  to do what the page normally does in the folders you opened. It cannot delete files outside the
  container, write anything but `.xmp` sidecars and exports, or use shoot ids as paths. The network gaps above are what it could
  try.
- **The supply chain.** React and Babel are vendored and pinned by hash, GitHub Actions are pinned
  by commit, the project fetches no packages, and releases are signed from one Mac with keys kept
  outside the repo.
- **Out of scope**: another program running as you. It can already read your photos.

### Not yet verified

- A fresh install on macOS 14, 15 and 26, from TestFlight and from the dmg.
- Long runs: 8 hours of use, 10,000-photo shoots, repeated kills.
- The offline test described under Network.
- What metadata rendered JPEG exports keep.

Open pull requests #208, #209 and #211 (the native Edit canvas) change none of the above; #209
also shows the cut-short-export notice on the page, with the same log lines. #212 (Auto from the
RAW) and #213 (phone DNGs) add on-device processing only.

## Run it

You need Xcode 16.4 or later, an Apple silicon Mac, and macOS 14 or later.

```bash
open Lumina.xcodeproj
```

Choose the **Lumina** scheme and **My Mac**, then press ⌘R.

## For contributors

The UI is designed in Claude Design and ships unchanged inside the native window, so don't edit it
in this repo. [AGENTS.md](AGENTS.md) explains how the pieces fit together and how to sync a new
design.
