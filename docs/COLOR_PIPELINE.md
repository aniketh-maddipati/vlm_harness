# Color pipeline

## Working space

- **Linear working space:** `extendedLinearSRGB` when available, else `linearSRGB`.
- Core Image context: `DevelopColorPolicy.ciContextOptions` — `workingFormat: RGBAh` (half-float), Metal renderer, intermediate caching enabled.
- Filters evaluate in this working space. **No intentional 8-bit intermediates inside the tone graph.**

## Orientation

- Applied **once** at decode, as pixels, never as a second CI transform on the Metal present path.
- Browse / JPEG seed: ImageIO `CreateThumbnailWithTransform` (`OrientedDisplayImage`) then `CIImage(cgImage:)`. Do **not** feed `CIImage(contentsOf:)` + `applyOrientationProperty` into `DevelopMetalView` — that path flashes inverted for a frame against `CIRenderDestination.isFlipped`.
- RAW: `CIRAWFilter` output, then `OrientedDisplayImage.aligning` if the demosaic is still in sensor space. Metal destination flip is the only Y conversion.
- Crop and 1:1 regions are normalized in **oriented** image space (origin top-left for UI; converted to CI bottom-left when cropping).

## Display conversion

- Exactly **once** at the end of the graph via `CIContext.createCGImage(..., colorSpace:)`.
- Preview / lab display: Display P3 when available, else sRGB.
- Respects display ICC insofar as AppKit / Core Image color management applies to the produced `CGImage` / `NSImage`.

## Export

| Format | Space | Depth | Notes |
|---|---|---|---|
| JPEG | sRGB | 8-bit | Long-edge 1800 after aspect crop; q≈0.92 — **lossy** |
| TIFF | Adobe RGB (1998) if named space resolves, else Display P3 / sRGB | Source CGImage depth | Written from full develop result before JPEG downscale; metadata EXIF/TIFF/GPS copied when present |

XMP sidecars remain crs-compatible via `XMPDevelopParser.writeSidecar`.

## Alpha

Photographs are opaque. Premultiplied last is used only for histogram sampling bitmaps.

## Lossy boundaries

1. Interactive / settled long-edge caps (resolution).  
2. JPEG proxy fallback when RAW decode fails — fidelity label **Proxy**.  
3. Display 8-bit BGRA for Metal browse (browse path only; develop uses CI→CGImage).  
4. JPEG export quantization.  
5. Approximate presence / dehaze / NR / sharpen mappings (not LR Detail).

## Avoided defects

- Double gamma / double tone mapping: single display convert.  
- Accidental 8-bit CI intermediates: RGBAh working format.  
- Browse JPEG as authoritative edit: settled / 1:1 / export require `originalRAW` source policy.

## Preview vs export equivalence

Same `DevelopRenderGraph` operation order and recipe interpretation. Differences are resolution caps and final tagged output space only. Fidelity tests should downsample export with high-quality Lanczos/CGContext `.high`, align extents, and report per-channel MAE, luminance MAE, and SSIM — tolerances from measured evidence, not invented “perfect match” thresholds.
