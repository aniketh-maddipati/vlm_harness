# 21 · Export: colour spaces, formats, sizes

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-export-colour` from origin/main.

**Goal.** Exports fit for print and the web, not just sRGB JPEG.

**Now.** `SetsLookExport`: sRGB JPEG q0.92 / 16-bit TIFF / PNG; the pipeline already has P3 / ProPhoto spaces (~:27); the output transform is a clamp.

**Build.**
- **Colour space:** sRGB / Display P3 / Adobe RGB / ProPhoto, with the ICC profile embedded. Output gamut mapping: soft compression in Oklab, not a clamp; use the same function as grading's (05) if it has landed.
- **Formats:** HEIF 10-bit, JPEG XL if ImageIO supports it on macOS 15+ (check; otherwise skip), TIFF 16. Optional resize (long edge) with good resampling and output sharpening (screen / matte / glossy, low / standard / high).
- **Metadata:** keep or strip, strip GPS, which already partly exists. Check what Save writes.
- **UI:** the Save screen's export options in the page; defaults unchanged.

**Done when.** Round-trip: a P3 export opened in Preview matches the canvas on a P3 display (ΔE ≤ 1 on patches); every format writes and reads back; the journal and crash recovery cover the new formats.

**Depends on:** none.
