# AGENTS.md

Guidance for AI agents and cloud developers working on **Lumina**, a native macOS photo culling app (Swift / SwiftUI / Xcode).

## Platform constraint (critical)

Lumina **cannot be built or run on Linux**. Cloud Agent VMs are Ubuntu-based and do not provide Xcode, the macOS SDK, or Apple frameworks (AppKit, SwiftUI, Vision, Metal, Core Image).

| Capability | Linux cloud agent | macOS dev machine |
|---|---|---|
| `xcodebuild` / run `Lumina.app` | No | Yes |
| `Scripts/regression.sh` (full) | No (needs xcodebuild + Swift ImageIO) | Yes |
| Static lint (`Scripts/harness/lint/*.sh`) | Yes | Yes |
| `exiftool` CLI (metadata) | Yes (`/usr/bin/exiftool` via apt) | Yes (`brew install exiftool`) |

For end-to-end verification (build, headless audit, GUI), use a **local Mac** with macOS 14+ and Xcode 15+.

## Cursor Cloud specific instructions

### What the Linux install script provides

The `.cursor/environment.json` `install` script installs **`libimage-exiftool-perl`** only. There are no npm, pip, Cargo, or SPM dependencies in this repo.

### Lint / test / build (macOS required for logic tests)

On a Mac with Xcode 15+ and exiftool:

```bash
# Static contract lint (runs on Linux too)
bash Scripts/harness/lint/banned_words.sh
bash Scripts/harness/lint/copy_contract_diff.sh
bash Scripts/harness/lint/contract_structure.sh

# Build
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug build

# Logic tests (real types via @testable import Lumina)
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug \
  -destination 'platform=macOS' -only-testing:LuminaLogicTests test

# Full regression (lint + build + logic tests + headless E2E + SLA check)
bash Scripts/regression.sh [RAW_FOLDER] [JPG_FOLDER]
```

Pass your own shoot folders: `bash Scripts/regression.sh pre-commit /path/to/raws /path/to/jpgs`. Or set `LUMINA_RAW_DIR` / `LUMINA_JPG_DIR`. If those are unset, the media audit is skipped.

### Headless E2E audit

`Scripts/e2e_audit.swift` runs outside the GUI and checks extract/taste/timing signals. It requires **macOS Swift** (Foundation, ImageIO, CoreGraphics) and probes the same exiftool paths as the app (`/opt/homebrew/bin/exiftool`, `/usr/local/bin/exiftool`, `/usr/bin/exiftool`). Install with:

```bash
brew install exiftool
```

### Cloud agents (Linux)

Cloud agents run `python3 Scripts/harness/run.py fast` (or `bash Scripts/regression.sh pre-commit`) for static contract checks. All logic tests require macOS + Xcode (`xcodebuild test -only-testing:LuminaLogicTests`).

Do **not** expect `xcodebuild` or `swift Scripts/e2e_audit.swift` to succeed on Linux.

### Footprint / lightweight Release

- Release builds define `LUMINA_SHIPPING_APP`, excluding headless harness runners from the shipping binary.
- macOS footprint baseline: `bash Scripts/harness/release/footprint_baseline.sh`
- Register: `design/strategy/footprint-register.md`

### Key directories

- `Lumina/` — SwiftUI app (Views, ViewModels, Services, Models)
- `LuminaLogicTests/` — XCTest logic contracts (`@testable import Lumina`)
- `Lumina.xcodeproj/` — Xcode project (single target `Lumina`)
- `Scripts/regression.sh` — lint + build + logic tests + E2E runner
- `Scripts/harness/lint/` — banned-word, copy-contract, and structure checks (FAST lane manifest ids)
- `Scripts/e2e_audit.swift` — headless macOS audit script
- `README.md` — collaborator setup (numbered clone / brew / xcodebuild / open)
- `design/play.html` — standalone browser mock of open / table / edit / crop / export / failure flows
- `BUILD_LOG.md` — build history and verification notes

### External dependency

- **[exiftool](https://exiftool.org)** — RAW preview extraction, EXIF dates, Lightroom XMP parsing (required on macOS for full app behavior)
