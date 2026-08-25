# Lumina

Mac app for culling a shoot. Open a folder or an SD card. Keep with P, cut with X.

Apple Silicon. macOS 14+. Xcode 15+ from the App Store. Homebrew.

## Setup

```bash
git clone https://github.com/aniketh-maddipati/vlm_harness.git
cd vlm_harness
bash Scripts/bootstrap.sh
```

That script installs exiftool, builds Debug, and opens the app. If something is missing it prints the one command to run next. Then re-run bootstrap.

UI polish (playground + Inject):

```bash
bash Scripts/bootstrap.sh --dev
```

## Run

Bootstrap already opens Lumina. To build and open again:

```bash
bash Scripts/bootstrap.sh
```

Click **Choose a folder**, or drop a folder onto the window. For an SD card, pick `DCIM` on the volume. Files stay on disk. Keep shoots out of this repo.

Vision embeddings are on-device. No extra model to install. A folder of Lightroom-edited JPGs with XMP is optional taste. Hold `?` for keys.

## Aim

I am building a cull-first Mac app for people who come home with a card, not a catalog. Land, tidy, cull, export. Success is: finished, happy, organized, having read nothing.

Files stay where they are. Edits live in open sidecars. The shoot should open in Lightroom as-is. Nothing leaves this computer. X never deletes a file. The one file-touching verb is a post-export offer to put rejects in Trash, never automatic.

Wave one is amateurs on a cold Mac. If they can go card to exported set without a tour, the grammar is working. Develop (key `A`) stays banked until a taste model beats each tester's own hand edits on consented shoots. Do not start that model work before the eval set exists.

Authority for product law is `design/contract-v6.md`, then `design/tokens.yaml`, then `design/copy-contract.txt`, then code. The browser mock is `design/play.html`.

## Challenges

These are live. Do not paper over them.

- **Ship path.** I want a notarized Developer ID DMG to a small external beta. Not TestFlight, not the App Store, not this week. Signing, notarize, and staple are still open. Release is ad-hoc today.
- **exiftool.** Capture dates and XMP taste go through a Homebrew binary. The app probes `/opt/homebrew/bin/exiftool` then `/usr/local/bin/exiftool`. If it is missing, ordering falls back to file mtime. Testers still need bootstrap. Sandbox / App Store would have to stop calling an external binary.
- **Two UIs.** P0 (open, table, edit) is the live path. A Legacy shell button still sits on Open. Hide it before anyone outside this repo.
- **Card vs folder.** Copy says the shoot lands when you insert a card. P0 today is Choose a folder / drop / pick `DCIM`. Auto-ingest is not the current path.
- **Bodies.** MVP test fleet is six (Sony ARW, Canon CR3, Nikon NEF, Fuji RAF, iPhone ProRAW, iPhone HEIC). Unsupported bodies should wear `body not yet supported` and keep the table working. Fixtures for that fleet are not cut.
- **Shelf vs code.** Multi-select and two-up stay shelved. Some legacy/shell code still exceeds that. Do not build rubber-band or two-up until a ruling un-shelves it.
- **Mac-only proof.** FAST lint runs on Linux. Logic tests, GUI, and live RAW need a Mac. App-coupled lanes are unmeasured on this cloud box.
- **Chrome.** Empty app icon. Crop keys R/O need wave-one validation. Hold-J clipping and hold-? shortcuts are in the grammar and should stay hold-to-glance.

## Test

Two layers. Do not mix them up.

**Harness (every change):**

```bash
python3 Scripts/harness/run.py fast
```

On a Mac, with your own folders if you have them:

```bash
bash Scripts/regression.sh pre-commit /path/to/raws /path/to/jpgs
```

Logic tests:

```bash
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug \
  -destination 'platform=macOS' -only-testing:LuminaLogicTests test
```

**Wave one (people):** Apple Silicon, macOS 14+, a card or folder from a supported body. No tour. Watch whether they finish. Then ask:

1. Did they get to an exported set unaided?
2. Faster or slower than their current tool, in their words?
3. Verbatim: did you ever wonder whether what you saw was really sharp, really applied, or really reversible?
4. Before explaining grouping: what do you think the rows mean?
5. In crop, R frees aspect, O flips orientation, A and X still mean Develop and Reject.

Full facilitator script: `design/mvp-test-plan.md`. Consent line for later taste proving is in that file. Wave two is pros at full decision rate, and only then the Develop gate.

## Release

Target: notarized Developer ID DMG (or zip), ~5 testers, Gatekeeper-clean. Wave / beta builds stay free. No license screen.

Not this MVP: Mac App Store, TestFlight, sandbox, privacy manifest, bundled exiftool.

Before a DMG leaves this machine: Developer ID sign, notarize, staple, hide Legacy shell, stamp a real build number, no maintainer paths in `strings`, harness flags compiled out of Release. Notes in `docs/release/MACOS_RELEASE_READINESS_AUDIT.md`.

Nothing in a ship build should call a network. Diagnostics stay off (`betaDiagnostics` null).

## Design

```bash
open design/play.html
```

Browser mock. Click the sequence, or click the window and use P, X, arrows, Return, 4, Esc, Space, J, ?. Not the Mac app. The hi-fi PDF dump is `design/hifi-reference.html` if you want the old stills.
