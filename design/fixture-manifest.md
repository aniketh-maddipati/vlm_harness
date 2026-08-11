# Lumina fixture manifest — Contract v6

**Authority:** `design/contract-v6.md` (D53–D56, D57, WG-quarantine).  
**Purpose:** Enumerate bodies, card images, golden sets, and the sample-shoot content spec for harnesses.  
**Rule:** Fixtures are deterministic. No network. No legacy Workbench route. Marks/edits/staging are not cached as a second store of decisions.

---

## 1. Camera bodies (first-class)

| Body id | Container / extension | Notes | Cite |
|---------|----------------------|-------|------|
| `sony-arw` | `.ARW` | Existing Mehendi-class fixture path | D53 |
| `canon-cr3` | `.CR3` | Card-body coverage | D53 |
| `nikon-nef` | `.NEF` | Card-body coverage | D53 |
| `fujifilm-raf` | `.RAF` | Card-body coverage | D53 |
| `iphone-proraw` | `.DNG` (ProRAW) | **First-class** per R-M.2 / D53 | D53 |
| `iphone-heic` | `.HEIC` | **First-class** per R-M.2 / D53 | D53 |
| `jpeg-sidecar-pair` | `.JPG` + RAW | Provenance / pre-edited pair support | D54 |

Synthetic UI-test bodies (`mixed-60`, `mixed-200`, `missing-originals`) remain valid for XCUITest and must not claim RAW demosaic coverage.

---

## 2. Card images (ingest fault schedules)

| Fixture id | Spec | Cite |
|------------|------|------|
| `card-clean-500` | Clean 500-frame card; single volume; stable names; no videos | D53, L3 |
| `card-slow-reader` | Same topology as clean-500 with injected read latency schedule (harness clock) | L3 |
| `card-corrupt-file` | One damaged file mid-card; wears `file damaged — preview only`; remainder works | L3, copy FAILURE |
| `card-duplicate-names` | Duplicate basenames across folders/volumes; identity must not collapse | WG-quarantine / AssetIdentity |
| `card-two-card` | Two volumes presented in one session; eject/resume checksum honesty | L3, copy “Card ejected early” |
| `card-mixed-video` | Photographs + videos; videos **copied, counted, not shown**; ✓ covers videos | D56 / R-M.5 |
| `card-iphone-proraw-heic` | Mixed iPhone ProRAW + HEIC shoot | D53 |
| `card-offline-originals` | After copy, originals go offline; chips heal on reconnect | L3, copy “Original offline” |
| `card-disk-full` | Fault schedule: write fails with Disk full headline + one action | L3 |

Fault schedules are data, not UI progress bars. Softness/blur + facts-chips remain the loading truth (no spinners/skeletons).

---

## 3. Golden sets

| Golden id | Purpose | Cite |
|-----------|---------|------|
| `golden-cull-marks` | P/X toggle, same-mark clears (D59), undo restore focus | D59, L1, L4 |
| `golden-adapt-row` | Row-scope adapt; A1 banner=header=receipt; exclusions | WG-ripple, WG-A1 |
| `golden-ripple-scene-shoot` | ⇧⏎ widen / Esc narrow; second-order halo | WG-scope |
| `golden-export-three-state` | Export — → outline → dark primary | D61 |
| `golden-rejects-trash-offer` | Offer only after ✓; never auto; Trash only | D36 |
| `golden-fidelity-rungs` | preview → preview · sharpening → absence; settle crossfade only | D41, D43, WG-fidelity |
| `golden-birth-opacity` | Opacity at birth only; no post-birth photo opacity | D27 |
| `golden-adapted-proxy-linear` | Adapted strip from proxy-linear; warm-in 120 ms; loupe on adapted | D57 |
| `golden-sample-retire` | Sample shoot present → silent retire on first real ingest | D54 |
| `golden-hover-absent` | Assert zero hover handlers on table/edit surfaces | D48 |

---

## 4. Sample shoot content spec (onboarding) — D54 / R-M.3

**Copy fact:** `Sample shoot — yours replaces it`  
**Lifecycle:** Bundled; **retires silently** on first real ingest; never overwrites user work.

| Requirement | Spec |
|-------------|------|
| Bodies | **Real RAW** (not synthetic JPEG-only) — at least one supported card RAW body |
| Bursts | ≥1 burst (≥3 frames) so gap vocabulary (3 pt) is visible |
| Scene break | Exactly **one** scene break (dashed elapsed-time rule) |
| Pre-edited frame | Exactly **one** pre-edited frame wearing **provenance** (← chip / Edited as appropriate) |
| Scale | Small enough for first-run calm; large enough to show tidy motion |
| Marks | Starts with a mix that teaches resume-focus without a tour |
| Videos | None in the sample (videos belong to `card-mixed-video`) |
| Network | None |

---

## 5. Existing harness fixtures (carried)

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
