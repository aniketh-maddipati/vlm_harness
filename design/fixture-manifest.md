# Lumina fixture manifest — Contract v6 (+ Amendment Batch 1)

**Authority:** `design/contract-v6.md` (D53–D56, D57, WG-quarantine; A1 fleet).  
**Purpose:** Enumerate bodies, card images, golden sets, and the sample-shoot content spec for harnesses.  
**Rule:** Fixtures are deterministic. No network. No legacy Workbench route. Marks/edits/staging are not cached as a second store of decisions.  
**Change-marks:** `[● A#]` = Amendment Batch 1 · `[○]` = carried from v6 seal.

---

## 1. Camera bodies (MVP test fleet) `[● A1]`

Floor: Apple Silicon, macOS 14+. Intel: never.

| Body id | Camera (MVP test) | Container / extension | Notes | Cite |
|---------|-------------------|----------------------|-------|------|
| `sony-a7iv` | Sony A7 IV | `.ARW` | Replaces generic `sony-arw` id for fleet lock | D53, A1 |
| `canon-r6ii` | Canon R6 II | `.CR3` | Card-body coverage | D53, A1 |
| `nikon-z6iii` | Nikon Z6 III | `.NEF` | Card-body coverage | D53, A1 |
| `fujifilm-xt5` | Fujifilm X-T5 | `.RAF` | Card-body coverage | D53, A1 |
| `iphone-proraw` | iPhone (Pro) | `.DNG` (ProRAW) | **First-class** per R-M.2 / D53 | D53, A1 |
| `iphone-heic` | iPhone (Pro) | `.HEIC` | **First-class** per R-M.2 / D53 | D53, A1 |
| `jpeg-sidecar-pair` `[○]` | — | `.JPG` + RAW | Provenance / pre-edited pair support | D54 |

`[FLAG: body list is Claude's pick; swap freely before fixtures are cut.]`

**Critical-path cost `[● A1]`:** Six bodies ~**doubles** fixture / golden / baseline work vs. the prior 3-body plan. Fleet cut sits on the critical path before wave-one testing (`design/mvp-test-plan.md`).

**Unsupported body `[● A1]`:** Any body outside this table → facts-chip `body not yet supported`; table keeps working (D35 exercise, not a failure modal).

Synthetic UI-test bodies (`mixed-60`, `mixed-200`, `missing-originals`) remain valid for XCUITest and must not claim RAW demosaic coverage.

**Id migration note:** Prior seal ids `sony-arw` / `canon-cr3` / `nikon-nef` / `fujifilm-raf` map 1:1 onto the named MVP bodies above; update harness paths when fixtures are cut.

---

## 2. Card images (ingest fault schedules) `[○]`

| Fixture id | Spec | Cite |
|------------|------|------|
| `card-clean-500` | Clean 500-frame card; single volume; stable names; no videos | D53, L3 |
| `card-slow-reader` | Same topology as clean-500 with injected read latency schedule (harness clock) | L3 |
| `card-corrupt-file` | One damaged file mid-card; wears `file damaged — preview only`; remainder works | L3, copy FAILURE |
| `card-duplicate-names` | Duplicate basenames across folders/volumes; identity must not collapse | WG-quarantine / AssetIdentity |
| `card-two-card` | Two volumes presented in one session; eject/resume checksum honesty | L3, copy “Card ejected early” |
| `card-mixed-video` | Photographs + videos; videos **copied, counted, not shown**; ✓ covers videos | D56 / R-M.5 |
| `card-iphone-proraw-heic` | Mixed iPhone ProRAW + HEIC shoot | D53, A1 |
| `card-offline-originals` | After copy, originals go offline; chips heal on reconnect | L3, copy “Original offline” |
| `card-disk-full` | Fault schedule: write fails with Disk full headline + one action | L3 |
| `card-unsupported-body` `[● A1]` | Body outside fleet; chip `body not yet supported`; remainder of table works | A1, D35 |

Fault schedules are data, not UI progress bars. Softness/blur + facts-chips remain the loading truth (no spinners/skeletons).

---

## 3. Golden sets `[○]` (+ A1 scale note)

| Golden id | Purpose | Cite |
|-----------|---------|------|
| `golden-cull-marks` | P/X toggle, same-mark clears (D59), undo restore focus; pointer ✓/✕ parity (A3) when built | D59, L1, L4, A3 |
| `golden-adapt-row` | Row-scope adapt; A1 banner=header=receipt; exclusions | WG-ripple, WG-A1 |
| `golden-ripple-scene-shoot` | ⇧⏎ widen / Esc narrow; second-order halo | WG-scope |
| `golden-export-three-state` | Export — → outline → dark primary | D61 |
| `golden-rejects-trash-offer` | Offer only after ✓; never auto; Trash only | D36 |
| `golden-fidelity-rungs` | preview → preview · sharpening → absence; settle crossfade only | D41, D43, WG-fidelity |
| `golden-birth-opacity` | Opacity at birth only; no post-birth photo opacity | D27 |
| `golden-adapted-proxy-linear` | Adapted strip from proxy-linear; warm-in 120 ms; loupe on adapted | D57 |
| `golden-sample-retire` | Sample shoot present → silent retire on first real ingest | D54 |
| `golden-hover-absent` | Assert zero hover handlers on table/edit surfaces | D48 |
| `golden-crop-latch` `[● A2]` | Crop work-state; R/O keys; A/X not remapped; Esc restores entry layout | A2, D23 |
| `golden-hold-j-clipping` `[● A4]` | Hold-J clipping overlays; release returns | A4, D42 |

Goldens must be cut **per MVP body** where demosaic/truth differs — the six-body fleet doubles this work vs. 3-body (`[● A1]`).

---

## 4. Sample shoot content spec (onboarding) — D54 / R-M.3 `[○]`

**Copy fact:** `Sample shoot — yours replaces it`  
**Lifecycle:** Bundled; **retires silently** on first real ingest; never overwrites user work.

| Requirement | Spec |
|-------------|------|
| Bodies | **Real RAW** from the MVP fleet (not synthetic JPEG-only) — at least one supported card RAW body |
| Bursts | ≥1 burst (≥3 frames) so gap vocabulary (3 pt) is visible |
| Scene break | Exactly **one** scene break (dashed elapsed-time rule) |
| Pre-edited frame | Exactly **one** pre-edited frame wearing **provenance** (`← 8288` / Edited as appropriate — A5) |
| Scale | Small enough for first-run calm; large enough to show tidy motion |
| Marks | Starts with a mix that teaches resume-focus without a tour |
| Videos | None in the sample (videos belong to `card-mixed-video`) |
| Network | None |

---

## 5. Existing harness fixtures (carried) `[○]`

| Id | Role |
|----|------|
| `mixed-60` | XCUITest default contact-sheet / cull |
| `mixed-200` | Stress / explorer |
| `missing-originals` | Offline chip paths |

These do not replace `card-*` or sample-shoot specs for ingest/RAW honesty.

---

## 6. OPEN (fixture)

- Exact frame counts for sample shoot beyond “small/calm.”
- Whether `card-mixed-video` surfaces a count in chrome (D56 copy OPEN).
- ProRAW/HEIC licensing for bundled sample (must be redistributable).
- `[FLAG]` final body swap before fixtures are cut (A1).
- Per-body golden matrix ownership once fleet locks.
