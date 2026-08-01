# Lumina MVP (ship today)

Native macOS app: import Sony ARW folder → cull with keyboard → apply Lightroom taste from JPG XMP → export 4:5 Instagram carousel.

## Requirements

- macOS 14+
- Xcode 15+
- [exiftool](https://exiftool.org): `brew install exiftool`

## Run

```bash
open Lumina.xcodeproj
# ⌘R to build and run
```

Or:

```bash
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/*/Build/Products/Debug/Lumina.app
```

## Quick test (mehendi data)

1. **Import RAW Folder** → `/Users/aniketh/Pictures/jeevana_mehendi_2026_MATCHED_RAWS`
2. Choose JPG folder → `/Users/aniketh/jeevana_mehendi_2026`
3. Filter **Needs you** → keyboard: `P` keep, `X` reject, `]` next
4. Hold **Space** for before/after preview
5. **Export Carousel** → pick folder → get `grid_4x5/` + `export.json`

## Keyboard

| Key | Action |
|-----|--------|
| `⌘I` | Import |
| `P` | Keep |
| `X` | Reject |
| `M` | Maybe |
| `]` | Next flag |
| `[` | Previous |
| Space | Before (hold) |
| `⌘↵` | Export |

## What this MVP does

- Extracts embedded preview from ARW via exiftool
- Blur + Vision face scoring
- Timestamp burst grouping
- Tier assignment (~10% keep)
- Taste profile from mean Lightroom XMP in JPG folder
- Core Image preview adjustments
- 4:5 JPEG export + manifest

## Known limits (v0.1)

- Preview/export uses embedded camera JPEG, not full RAW develop
- No SD card auto-import
- No chat agent
- Single project per session
