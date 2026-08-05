# Develop Engine

Technically trustworthy RAW development foundation for Lumina. **Not Lightroom parity.**

## Audit summary (pre-change)

| Area | Prior state |
|---|---|
| Interactive edit | JPEG proxy ≤2048 via `DevelopEngine.render` + Core Image |
| Export | Separate ImageIO demosaic ≤6000 then same CI `apply` |
| Whites / Blacks / Sharpen / NR | Stored on recipe, **not applied** in CI graph |
| Original / Auto / Current | Enum exists; shell mostly shows ungraded browse JPEG |
| Multi-select / batch | None |
| Undo | Decision undo only; ⌘Z for edits was a no-op |
| Color | No documented working space; Metal used DeviceRGB fallback |
| Cancellation | PreviewSpine generation only; develop had ad-hoc task cancel |

Root cause of inaccurate / unresponsive editing: interactive path graded **camera JPEG proxies** while export demosaiced RAW; slider scrub could kick heavy work without a unified generation gate; several recipe fields were cosmetic.

## Ownership

| Concern | Type |
|---|---|
| Immutable edit recipes | `EditRecipe` |
| Per-frame overrides / shared links | `PhotoEditBinding`, `EditRecipeStore` |
| Batch staging / commit / undo | `BatchTreatmentSession` |
| RAW render requests | `RawRenderRequest` |
| Preview quality / fidelity labels | `DevelopRenderQuality`, `DevelopFidelityState` |
| Cancellation / stale rejection | `RenderGenerationGate`, `DevelopRenderScheduler` |
| Unified graph + export | `DevelopRenderGraph`, `ExportService` |
| Lab entry | `--develop-lab` → `DevelopLabView` |

## Develop Lab (Phase 1)

```bash
# macOS
open Lumina.xcodeproj
# Scheme args: --develop-lab --develop-raw-dir /path/to/ARW/folder

# Optional layout captures
…/Lumina.app/Contents/MacOS/Lumina --develop-lab --capture-develop-lab artifacts/develop-lab
```

Layout: ~66% leader, two reference frames, aspect-fit, Before/After, 1:1 pan, fidelity chip, histogram from displayed pixels, controls in a side rail (not over the image).

**Live RAW gate:** If no fixture directory is found, the lab reports that live RAW validation is blocked. Set `LUMINA_DEVELOP_RAW_DIR` or `--develop-raw-dir`.

Workbench integration is **intentionally deferred** until the lab passes live-RAW correctness and responsiveness gates on a Mac.

## Operation order (preview ≡ export)

1. Decode (`CIRAWFilter` preferred, else ImageIO demosaic); orientation once  
2. Long-edge downsample (quality cap only)  
3. White balance  
4. Exposure  
5. Highlights / Shadows  
6. Whites / Blacks (tone curve endpoints)  
7. Contrast  
8. Clarity / Texture / Dehaze approximations  
9. Vibrance / Saturation  
10. Noise reduction  
11. Sharpening  
12. Straighten + crop  
13. 1:1 region  
14. Display or export conversion **once**

## Controls

Trusted with documented mappings: Exposure, Temperature, Tint, Highlights, Shadows, Whites, Blacks, Contrast, Straighten, Crop, Noise Reduction, Sharpening.

Approximate (labeled, not LR-identical): Clarity, Texture, Dehaze.

## Batch grammar

- ⌘-click toggles 2–3 photo selection; releasing ⌘ does not clear selection  
- Hold ⌘ → shared action shelf  
- ⌘Return → stage leader recipe onto each selected RAW **independently**  
- Release Return, keep ⌘, Return again → commit  
- Esc → cancel staged; ⌘Z → undo batch as one transaction  
- Auto-repeat ignored; empty selection cannot stage/commit  

## Performance targets (measure on Mac — not claimed)

| Path | Target p95 |
|---|---|
| Cached present | ≤50 ms |
| Settled after scrub | ≤300 ms |
| Warmed switch | ≤80 ms |
| Before/After | ≤50 ms |
| 1:1 region | ≤250 ms |

Instrumentation: `DevelopRenderScheduler.metrics` (cache hit/miss, cancel, stale, duration, quality).

## Tests

```bash
python3 Scripts/develop_engine_test.py          # Linux + macOS
swift Scripts/develop_recipe_test.swift         # macOS Swift
bash Scripts/regression.sh [RAW] [JPG]          # macOS full
```

## Known Lightroom differences

See `docs/COLOR_PIPELINE.md` and the “Known differences” section in the delivery report.
