# E1 baseline — current SwiftUI engine

**Session:** E1 (instruments). **Branch:** `instruments/e1-baseline`. **Date:** 2026-08-20.
**Purpose:** the table E2 Gate 1 cites as "before". Cut so that a hostile reviewer asking
*"over what window, on what fixture, cut from what seed?"* gets an answer in every row.

**Authority:** `design/contract-v6.md` → `design/tokens.yaml` → `design/copy-contract.txt` → code → tests.

> **Read this first.** Most of the rows E2 Gate 1 asked for are **UNMEASURED**, and the reason is
> not laziness — it is that *the instruments for them do not exist in the app*. `scroll.frame`,
> `key.travel`, and `key.mark` appear nowhere in `Lumina/` (grep below). E1 repaired the stopwatch
> and cut the fixtures; naming and wiring those three keys is work E2 must do before it can quote a
> before/after on them. An UNMEASURED row here is a promise kept, not a hole.

---

## Hardware, OS, display

| Field | Value |
|---|---|
| Machine | MacBook Pro, `Mac16,7` |
| Chip | Apple M4 Pro — 14 cores (10 P + 4 E) |
| Memory | 24 GB |
| macOS | 26.5.2 (build 25F84) |
| Xcode | 26.6 (17F113) |
| Display | Built-in Liquid Retina XDR, 3456×2234 |
| Display Hz | **UNMEASURED** — `system_profiler SPDisplaysDataType` emitted no refresh-rate field on this host. The panel is ProMotion-capable (nominally 120 Hz), but this session did not confirm the active rate, and a frame-budget claim resting on an unconfirmed Hz would be a guess wearing a number. |
| Build config | Debug |

**Debug, not Release.** Every number below was taken with a Debug-configuration toolchain.
Release numbers will differ. E2 must compare like with like.

---

## Fixtures

Cut by `Scripts/fixtures/cut_latency_card.py`, verified by `Scripts/fixtures/verify_latency_card.py`.
Full provenance: `design/fixture-manifest.md` §6 (**proposal — not ratified**).

| Fixture | Frames | Seed body | Distinct | Replication | Clone-backed | Checksums |
|---|---|---|---|---|---|---|
| `card-clean-500` | 500 | `sony-a7iii` (SONY `ILCE-7M3`) | 500 | **1.0× — none** | No | 500/500 verified |
| `card-clean-2000` | 2000 | `sony-a7iii` (SONY `ILCE-7M3`) | 1000 | **2.0×** | Yes (1000 clones) | 2000/2000 verified |

**Seed honesty.** The fleet table names `sony-a7iv` (A7 IV). These frames are `ILCE-7M3` (A7 III) —
same maker, same `.ARW` container, different body. No A7 IV, R6 II, Z6 III, X-T5, ProRAW, or HEIC
frames exist on this machine. The cards name the body that actually took the frames.

**`card-clean-2000` caveat.** 2000 files, 1000 distinct photographs. Decode cost per frame is real
(every file is a whole RAW ImageIO must decode). Content variety is not, and cold-I/O pressure is
understated — cloned repeats share physical blocks, so the working set is ~12 GiB physical against
~20.8 GiB logical. On a 24 GB machine that is likelier to sit in page cache than a true 2000-frame
card. **Absolute numbers on this fixture are optimistic and must not be quoted as SLA passes.**
Before/after comparison on the same fixture — which is what E2 Gate 1 needs — remains valid.

**Page-cache state: UNCONTROLLED.** Both fixtures were written, checksum-verified, and benched
within the same session, so an unknown fraction was resident in page cache. No `purge` was run
(it needs root). Treat these as *warm-ish* numbers with an unquantified cache benefit.

---

## MEASURED — decode floor, current engine

`Scripts/perf/e1_decode_baseline.swift` — one embedded-preview decode per frame at
`PhotoImageTier.gridMaxPixelSize` (512 px), the tier `PhotoImageCache.load` requests on the grid
path. Every frame in the fixture decoded exactly once; every sample is in the percentile.

**What this is:** the decode floor of the current engine.
**What this is not:** `scroll.frame`. It excludes SwiftUI layout, cell reuse, compositing, and
display-link pacing. Do not report it as a frame time.

| Metric | p50 (ms) | p95 (ms) | p99 (ms) | max (ms) | Window |
|---|---|---|---|---|---|
| `decode.grid_512` · `card-clean-500` | 16.56 | 17.84 | 18.62 | 182.16 | `n=500, full run` |
| `decode.grid_512` · `card-clean-2000` | 16.56 | 18.04 | 18.75 | 189.16 | `n=2000, full run` |

| Metric | Value | Window |
|---|---|---|
| Bench peak RSS · `card-clean-500` | 212 MB (start 175 MB) | `n=500, full run` |
| Bench peak RSS · `card-clean-2000` | 236 MB (start 187 MB) | `n=2000, full run` |
| Wall clock · `card-clean-500` | 8.5 s | full run |
| Wall clock · `card-clean-2000` | 33.5 s | full run |

Peak RSS above is the **bench process**, not `Lumina.app`. App peak memory is UNMEASURED (below).

### The Gate 1 fix, proven on real data

The same run, read through the old 512-sample ring versus capture mode:

| Fixture | Instrument | p99 (ms) | max (ms) | Window |
|---|---|---|---|---|
| `card-clean-2000` | **old — 512 ring** | 18.43 | **19.37** | `n=512, tail (of 2000 recorded)` |
| `card-clean-2000` | **new — capture** | 18.75 | **189.16** | `n=2000, full run` |
| `card-clean-500` | old — 512 ring | 18.62 | 182.16 | `n=500, full run` (500 < 512: ring holds everything) |

The slowest frame on both cards is **sample #0** — a cold-start decode roughly 10× p99. On
`card-clean-2000` the ring reports a worst frame of **19.37 ms**; the truth is **189.16 ms**. The old
instrument understated the worst frame by **9.8×** and did so silently, because nothing in its output
said which window it covered. `card-clean-500` shows no divergence for the honest reason that 500
samples fit inside a 512-slot ring — the bug needs a run longer than the ring to appear, which is
exactly E2's 60 s glide.

---

## UNMEASURED

Each row names why. An absent row would be a hole E2 falls into; these are stated gaps.

| Row | Status | Why |
|---|---|---|
| `scroll.frame` p50/p95/p99 | **UNMEASURED** | The key does not exist. `grep -rn "scroll\.frame" Lumina/` → 0 hits outside a doc comment. Nothing in the app records a per-frame scroll sample, so there is no series to take a percentile over — capture mode cannot rescue a measurement that was never taken. |
| `key.travel` key-to-pixels | **UNMEASURED** | Key does not exist in `Lumina/`. Nearest existing instruments are `spine.input_to_photon` and `navigation.select`. |
| `key.mark` key-to-pixels | **UNMEASURED** | Key does not exist in `Lumina/`. |
| Zoom / expand gesture-to-pixels | **UNMEASURED** | No key exists, and a pinch/expand gesture cannot be synthesized honestly — this session is non-interactive and no person was at the machine. |
| 60 s glide, any metric | **UNMEASURED** | Requires a person driving a trackpad with real momentum. `design/strategy/render-hazard-inventory.md` records the same constraint for SPIKE B/C ("Needs a person at a machine"). A programmatic scroll would measure synthetic pacing, not a glide. |
| App peak memory | **UNMEASURED** | Needs `Lumina.app` running against a cut card with a person driving it. The RSS figures above are the headless bench, and saying otherwise would mislabel the process. |
| Energy impact | **UNMEASURED** | Needs an Instruments Energy Log over a live 60 s glide — same person-at-the-machine constraint. |
| Display refresh Hz | **UNMEASURED** | See hardware table. |
| Release-configuration numbers | **UNMEASURED** | All figures are Debug. |

### What E2 must build before it can fill these

1. Name and wire `scroll.frame` on the contact-sheet scroll path, `key.travel` and `key.mark` on
   the cull grammar path, and a zoom/expand gesture key. E1 deliberately did not add them — wiring
   a frame-time key means touching the render path, which is E2's to earn, not E1's to pre-empt.
2. Call `LatencyMetrics.beginCapture(key:)` for each before the glide, so the percentile covers the
   whole run. Cost is ~57.6 KB per key for a 60 s @ 120 Hz glide.
3. Report every row with `Reading.row`, which cannot be constructed without its `Window`.
4. Have a person perform the glide, and record display Hz, build configuration, and page-cache
   state alongside the numbers.

---

## Reproduce

```bash
python3 Scripts/fixtures/verify_latency_card.py ~/Pictures/lumina-fixtures/card-clean-500
python3 Scripts/fixtures/verify_latency_card.py ~/Pictures/lumina-fixtures/card-clean-2000
swift Scripts/perf/e1_decode_baseline.swift ~/Pictures/lumina-fixtures/card-clean-500  --json artifacts/perf/e1-decode-card-clean-500.json
swift Scripts/perf/e1_decode_baseline.swift ~/Pictures/lumina-fixtures/card-clean-2000 --json artifacts/perf/e1-decode-card-clean-2000.json
```

Raw JSON: `artifacts/perf/e1-decode-card-clean-500.json`, `artifacts/perf/e1-decode-card-clean-2000.json`.
