# AGENTS.md

Guidance for AI agents and cloud developers working on **Lumina**, a native macOS photo culling app (Swift / SwiftUI / Xcode).

## Platform constraint (critical)

Lumina **cannot be built or run on Linux**. Cloud Agent VMs are Ubuntu-based and do not provide Xcode, the macOS SDK, or Apple frameworks (AppKit, SwiftUI, Vision, Metal, Core Image).

| Capability | Linux cloud agent | macOS dev machine |
|---|---|---|
| `xcodebuild` / run `Lumina.app` | No | Yes |
| `Scripts/regression.sh` (full) | No (needs xcodebuild + Swift ImageIO) | Yes |
| Static repo / project validation | Yes | Yes |
| `exiftool` CLI (metadata) | Yes (`/usr/bin/exiftool` via apt) | Yes (`brew install exiftool` → `/usr/local/bin/exiftool`) |

For end-to-end verification (build, headless audit, GUI), use a **local Mac** with macOS 14+ and Xcode 15+.

## Cursor Cloud specific instructions

### What the Linux install script provides

The `.cursor/environment.json` `install` script installs **`libimage-exiftool-perl`** only. There are no npm, pip, Cargo, or SPM dependencies in this repo.

### Lint / test / build (macOS required)

On a Mac with Xcode 15+ and exiftool:

```bash
# Build
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug build

# Run app
open Lumina.xcodeproj   # then ⌘R in Xcode

# Full regression (build + headless E2E + SLA check)
bash Scripts/regression.sh [RAW_FOLDER] [JPG_FOLDER]
```

Default regression folders in `Scripts/regression.sh` point to the maintainer's machine; override with your own RAW + JPG shoot folders.

### Headless E2E audit

`Scripts/e2e_audit.swift` runs outside the GUI and checks import/extract/taste/timing signals. It requires **macOS Swift** (Foundation, ImageIO, CoreGraphics) and looks for exiftool at **`/usr/local/bin/exiftool`** (Homebrew path). Install with:

```bash
brew install exiftool
```

### Linux-side checks (cloud agents)

When Xcode is unavailable, agents can still:

1. Validate shell script syntax: `bash -n Scripts/regression.sh`
2. Confirm Xcode project structure (`Lumina.xcodeproj/project.pbxproj`, 53+ Swift files under `Lumina/`)
3. Run `exiftool` on sample images to verify metadata tooling

Do **not** expect `xcodebuild` or `swift Scripts/e2e_audit.swift` to succeed on Linux.

### Key directories

- `Lumina/` — SwiftUI app (Views, ViewModels, Services, Models)
- `Lumina.xcodeproj/` — Xcode project (single target `Lumina`)
- `Scripts/regression.sh` — build + E2E runner
- `Scripts/e2e_audit.swift` — headless audit script
- `README.md` — product overview and manual test steps
- `BUILD_LOG.md` — build history and verification notes

### External dependency

- **[exiftool](https://exiftool.org)** — RAW preview extraction, EXIF dates, Lightroom XMP parsing (required on macOS for full app behavior)
