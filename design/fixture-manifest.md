# Lumina fixture manifest — Contract v6 (+ Amendment Batch 1)

**Authority:** `design/contract-v6.md` (D53–D56, D57, WG-quarantine; A1 fleet).  
**Purpose:** Enumerate bodies, card images, golden sets, and the sample-shoot content spec for harnesses.  
**Rule:** Fixtures are deterministic. No network. No legacy Workbench route. Marks/edits/staging are not cached as a second store of decisions.  
**Change-marks:** `[● A#]` = Amendment Batch 1 · `[○]` = carried from v6 seal · `[◐ E1]` = **PROPOSED** by session E1, not ratified.

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
| `sony-a7iii` `[◐ E1]` | Sony A7 III (`ILCE-7M3`) | `.ARW` | **Seed body actually available on the maintainer's machine and used to cut the E1 latency cards.** Not a fleet target — proposed as a *seed* id so the cut cards name their true origin. Ratify or swap. | E1 Gate 2, D53 |

`[FLAG: body list is Claude's pick; swap freely before fixtures are cut.]`

**Seed-vs-fleet honesty `[◐ E1]`:** The fleet table names `sony-a7iv` (A7 IV). The RAW present on the maintainer's machine is `ILCE-7M3` (A7 III) — same maker, same `.ARW` container, different body. E1 cut its latency cards from the A7 III and records that body rather than labelling the frames with a body that never took them. No A7 IV, R6 II, Z6 III, X-T5, ProRAW, or HEIC frames were found on this machine; those fleet rows remain uncut.

**Critical-path cost `[● A1]`:** Six bodies ~**doubles** fixture / golden / baseline work vs. the prior 3-body plan. Fleet cut sits on the critical path before wave-one testing (`design/mvp-test-plan.md`).

**Unsupported body `[● A1]`:** Any body outside this table → facts-chip `body not yet supported`; table keeps working (D35 exercise, not a failure modal).

Synthetic UI-test bodies (`mixed-60`, `mixed-200`, `missing-originals`) remain valid for XCUITest and must not claim RAW demosaic coverage.

**Id migration note:** Prior seal ids `sony-arw` / `canon-cr3` / `nikon-nef` / `fujifilm-raf` map 1:1 onto the named MVP bodies above; update harness paths when fixtures are cut.

---

## 2. Card images (ingest fault schedules) `[○]`

| Fixture id | Spec | Cite |
|------------|------|------|
| `card-clean-500` `[◐ E1 — CUT]` | Clean 500-frame card; single volume; stable names; no videos. **Cut 2026-08-20** from `sony-a7iii`; 500 distinct frames; replication 1.0× | D53, L3, E1 |
| `card-clean-2000` `[◐ E1 — CUT]` | Clean 2000-frame card for the E2 Gate 1 60 s glide. **Cut 2026-08-20** from `sony-a7iii`; 1000 distinct frames; replication 2.0×; clone-backed | E1 Gate 2, cited by E2 Gate 1 |
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

## 6. Latency card cut provenance `[◐ E1 — PROPOSED]`

Cut by `Scripts/fixtures/cut_latency_card.py`; verified by `Scripts/fixtures/verify_latency_card.py`.
Cut location is a working directory, **not** committed: `~/Pictures/lumina-fixtures/<fixture-id>/`.
Each cut writes `fixture.json` (provenance) and `checksums.sha256` (per-frame SHA-256).

| Field | `card-clean-500` | `card-clean-2000` |
|-------|------------------|-------------------|
| Frames | 500 | 2000 |
| Seed body | `sony-a7iii` — SONY `ILCE-7M3` | `sony-a7iii` — SONY `ILCE-7M3` |
| Seed origin | Sony card volume, `DCIM/100MSDCF` (3,352 real `.ARW`; read-only) | same |
| Distinct frames | 500 | 1000 |
| Replication factor | **1.0× — none** | **2.0×** |
| Clone-backed | No — every frame physically distinct | Yes — the repeat of each seed is an APFS clone |
| Content variety | Full | **Partial — 1000 distinct frames, each appearing twice** |
| Decode cost | Preserved — every file is a whole real RAW | Preserved — every file is a whole real RAW |
| Cold-I/O fidelity | Faithful | **Understated** — cloned repeats share physical blocks |
| Naming | `LUM00001.ARW` … sequential, unique, stable | same |
| Videos | None | None |
| Volume topology | Single directory, single volume | Single directory, single volume |

**What "replication 2.0×" costs, stated plainly.** `card-clean-2000` is 2000 files but only 1000
distinct photographs. Decode work per frame is real and unchanged — every file is a complete RAW
that ImageIO must actually decode. What is *not* real is content variety (the second thousand
repeats the first) and cold-I/O pressure (APFS clones share physical blocks, so the working set is
~10.4 GiB rather than ~21 GiB). On a 24 GB machine that smaller working set is likelier to sit in
page cache than a true 2000-frame card would be. **Absolute numbers taken on `card-clean-2000` are
therefore optimistic and must not be quoted as SLA passes.** Before/after comparisons on the same
fixture remain valid, which is what E2 Gate 1 needs.

Why replication at all: 2000 physically distinct frames cost ~21 GiB, and the machine that cut
these had 42 GiB free on a disk already at 91% — with `xcodebuild` and trace capture still to run
on it. `card-clean-500` was cut at full fidelity because 500 distinct frames cost only 5.14 GiB;
a real 500-frame card *is* that size, so that fixture has no caveat at all.

**Re-cut and verify:**

```bash
python3 Scripts/fixtures/cut_latency_card.py --seed <CARD>/DCIM/100MSDCF --out ~/Pictures/lumina-fixtures --card card-clean-500
python3 Scripts/fixtures/cut_latency_card.py --seed <CARD>/DCIM/100MSDCF --out ~/Pictures/lumina-fixtures --card card-clean-2000 --clone
python3 Scripts/fixtures/verify_latency_card.py ~/Pictures/lumina-fixtures/card-clean-500
```

The cutter refuses synthesized input: seeds must be real RAW over 1 MB, so the 4-byte stub problem
recorded in `design/strategy/render-hazard-inventory.md` cannot recur silently.

---

## 7. OPEN (fixture)

- Exact frame counts for sample shoot beyond “small/calm.”
- Whether `card-mixed-video` surfaces a count in chrome (D56 copy OPEN).
- ProRAW/HEIC licensing for bundled sample (must be redistributable).
- `[FLAG]` final body swap before fixtures are cut (A1).
- Per-body golden matrix ownership once fleet locks.
- `[◐ E1]` Ratify or reject `sony-a7iii` as a seed id; decide whether the A7 IV fleet row is cut or swapped.
- `[◐ E1]` Whether `card-clean-2000` should be re-cut at replication 1.0× (~21 GiB) once disk allows.
