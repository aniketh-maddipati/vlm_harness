# AGENTS.md

Guidance for AI agents and cloud developers working on **Lumina**, a native macOS photo culling app (Swift / SwiftUI / Xcode).

## Platform constraint (critical)

Lumina **cannot be built or run on Linux**. Cloud Agent VMs are Ubuntu-based and do not provide Xcode, the macOS SDK, or Apple frameworks (AppKit, SwiftUI, Vision, Metal, Core Image).

| Capability | Linux cloud agent | macOS dev machine |
|---|---|---|
| `xcodebuild` / run `Lumina.app` | No | Yes |
| `Scripts/ci/regression.sh` (full) | No (needs xcodebuild + Swift ImageIO) | Yes |
| Static lint (`Scripts/lint/*.sh`) | Yes | Yes |
| `exiftool` CLI (metadata) | Yes (`/usr/bin/exiftool` via apt) | Yes (`brew install exiftool` → `/usr/local/bin/exiftool`) |

For end-to-end verification (build, headless audit, GUI), use a **local Mac** with macOS 14+ and Xcode 15+.

## Cursor Cloud specific instructions

### What the Linux install script provides

The `.cursor/environment.json` `install` script installs **`libimage-exiftool-perl`** only. There are no npm, pip, Cargo, or SPM dependencies in this repo.

### Lint / test / build (macOS required for logic tests)

On a Mac with Xcode 15+ and exiftool:

```bash
# Static contract lint (runs on Linux too)
bash Scripts/lint/banned_words.sh
bash Scripts/lint/copy_contract_diff.sh
bash Scripts/lint/contract_structure.sh

# Build
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug build

# Logic tests (real types via @testable import Lumina)
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug \
  -destination 'platform=macOS' -only-testing:LuminaLogicTests test

# Full regression (lint + build + logic tests + headless E2E + SLA check)
bash Scripts/ci/regression.sh [RAW_FOLDER] [JPG_FOLDER]
```

Default regression folders in `Scripts/ci/regression.sh` point to the maintainer's machine; override with your own RAW + JPG shoot folders.

### Headless E2E audit

`Scripts/ci/e2e_audit.swift` runs outside the GUI and checks import/extract/taste/timing signals. It requires **macOS Swift** (Foundation, ImageIO, CoreGraphics) and looks for exiftool at **`/usr/local/bin/exiftool`** (Homebrew path). Install with:

```bash
brew install exiftool
```

### Cloud agents (Linux)

Cloud agents run `bash Scripts/lint/*.sh` for static contract checks. All logic tests require macOS + Xcode (`xcodebuild test -only-testing:LuminaLogicTests`).

Do **not** expect `xcodebuild` or `swift Scripts/ci/e2e_audit.swift` to succeed on Linux.

### Key directories

- `Lumina/` — SwiftUI app (Views, ViewModels, Services, Models)
- `LuminaLogicTests/` — XCTest logic contracts (`@testable import Lumina`)
- `Lumina.xcodeproj/` — Xcode project (single target `Lumina`)
- `Scripts/ci/regression.sh` — lint + build + logic tests + E2E runner
- `Scripts/lint/` — banned-word, copy-contract, and structure checks
- `Scripts/ci/e2e_audit.swift` — headless macOS audit script
- `README.md` — product overview and manual test steps
- `BUILD_LOG.md` — build history and verification notes

### External dependency

- **[exiftool](https://exiftool.org)** — RAW preview extraction, EXIF dates, Lightroom XMP parsing (required on macOS for full app behavior)
