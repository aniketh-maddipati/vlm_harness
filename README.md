# Lumina

Native macOS photo culling app. A shoot lands on a table; you decide with the
keyboard; the originals never move.

**Authority:** `design/contract-v6.md` → `design/tokens.yaml` →
`design/copy-contract.txt` → code → tests. Where this file and the contract
disagree, the contract wins.

## Requirements

- macOS 14+, Apple Silicon (Intel is out of scope — D65)
- Xcode 15+
- [exiftool](https://exiftool.org): `brew install exiftool`

## Run

```bash
open Lumina.xcodeproj   # ⌘R
```

Or:

```bash
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug build
```

## Decision keys

Five decision keys commit; everything else only moves (Law 1). Decision keys
never autorepeat.

| Key | Action |
|-----|--------|
| `P` | Keep the focused photograph — pressing it again clears the mark to unreviewed, in place (D59) |
| `X` | Reject — same-key-again clears, and it never touches the file system (D36) |
| `⏎` | Confirm the staged round |
| `⇧⏎` | Stage, then widen one scope ring: row → scene → shoot |
| `A` | Stage a Develop proposal |

`Esc` narrows one ring, or cancels the stage at the row ring. Arrows travel.
Hold `Space` for the loupe; release returns.

Crop is a work-state latch inside Edit: `R` frees the aspect ratio, `O` flips
orientation. **`A` and `X` are never remapped** — decision keys keep their
meaning everywhere (D63).

## Live path

The shipping route is P0: Open a shoot → contact sheet → cull. The
Workbench · Canvas · Proof shell is quarantined under `Legacy/` and retires
checkpoint by checkpoint (D40, `design/checkpoint-sequence-v6.md`); it stays
reachable from the P0 root only until CP4 retires it.

## Layout

| Path | Role |
|------|------|
| `Lumina/` | P0 live path (SwiftUI app) |
| `Legacy/` | D40 quarantine — retires checkpoint by checkpoint, may only shrink |
| `Salvage/` | Salvaged services: `EmbeddingService` (grouping only), `ExifToolService` |
| `DesignTokens/` | `HiFiTokens.generated.swift`, generated from `design/tokens.yaml` |
| `design/` | The constitution; superseded documents live in `design/archive/` |
| `Scripts/lint/` · `Scripts/run/` · `Scripts/ci/` | Lints, runners, CI entry points |
| `Scripts/harness/` | CP0 three-lane harness (see `HARNESS.md`) |

## Test

```bash
python3 Scripts/harness/run.py fast   # lints + unit, any platform, <90s
bash Scripts/ci/regression.sh         # full: build + XCTest + E2E (macOS only)
bash Scripts/run/run_p0_ui_tests.sh fast
```

FAST runs anywhere. FULL and HEAVY are Apple-Silicon-macOS only and report
`PLATFORM-UNAVAILABLE` elsewhere — never a pass. See `HARNESS.md`.

## Sovereignty

Files stay where they are; edits go to open sidecars; nothing leaves this Mac.
The app declares no network entitlement, and `Scripts/ci/target_truth.py`
keeps it that way (D4 / D45).

## Known limits (v0.1)

- Preview/export can still use the embedded camera JPEG rather than a full RAW develop on some paths
- The six-body fixture corpus is not cut yet (`design/fixture-manifest.md`)
- Tier 1 / Develop as a critical path is banked pending taste-model proof (D46 / A10)
