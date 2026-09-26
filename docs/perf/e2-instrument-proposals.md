# E2 instruments — PROPOSED constants

**Branch:** `instruments/e2-keys` · **Date:** 2026-08-21 · **Status:** proposals, not tokens.

Every constant on this page is **invented**. None is ratified, none is in `design/tokens.yaml`,
and adding them there would move the tokens hash — which would stale the F07 spring golden and
the build manifest mid-comparison. They live in code as named `LatencyMetrics` / 
`P0RenderInstruments` constants and are quoted as **PROPOSED** wherever they appear in a table.

Grep basis for "invented": no frame, key, or gesture budget is ruled anywhere today.
`design/contract-v6.md` mentions `120 ms` only as the D57 warm-in crossfade; `design/tokens.yaml`
has no latency budgets at all.

---

## The four keys

| Key | What one sample is | Declared budget | Basis |
|---|---|---|---|
| `p0.scroll.frame` | Interval between two presented frames while the sheet is scrolling | **8.33 ms** | One display interval at a pinned 120 Hz. The only physically grounded value of the four: a frame slower than this *was* a dropped frame. |
| `p0.key.travel` | Arrow-key event → first frame presented after the focus move | **50 ms** | Placeholder. Equal to `navigationSLAms` **by declaration, not inheritance**. |
| `p0.key.mark` | P/X event → first frame presented after the mark | **50 ms** | Placeholder, as above. |
| `p0.zoom.gesture` | Pinch or `+`/`-` → first frame presented after the density change | **50 ms** | Placeholder, as above. |

| Constant | Value | Purpose |
|---|---|---|
| `P0RenderInstruments.scrollIdleTimeoutSeconds` | **0.100 s** | How long after the last bounds change a frame still counts as a glide frame. Without it the key samples the still table too and understates the glide. |

**The three placeholders are the weakest thing on this page.** They are `navigationSLAms`'s value,
chosen because inventing a tighter number before measuring would be a guess wearing a budget.
E2 Window 1 produces the first real distribution for these keys; that data — not this page —
should set them. Until then a breach signpost on those three means "slower than navigation",
nothing more.

---

## Why the mapping exists at all

`LatencyMetrics.sla(for:)` ended in a catch-all returning `navigationSLAms` (50 ms) for every key
no rule matched. A per-frame key would therefore have had to miss its real budget by **6×**
before anything logged a breach, and nothing in the output revealed which budget had been
applied. Declared keys are now matched first, by **exact key**:

```swift
private static let declaredSLAms: [String: Double] = [ … ]

static func sla(for key: String) -> Double {
    if let declared = declaredSLAms[key] { return declared }
    …unchanged historical fallback chain…
}
```

Exact keys, deliberately **not** a `p0.` prefix rule: `p0.edit.slider_to_pixels`,
`p0.edit.nav_prewarm_count` and `p0.visible_cell_cache` already exist and already reach
`sla(for:)`. A prefix rule would have silently re-budgeted all of them.
`testExistingP0KeysKeepTheirHistoricalBudget` pins that it did not.

---

## The instrument's stated bound

The three event keys are quantised by one display interval. The instrument resolves a pending
event on the first display-link callback after the state mutation returns, and cannot tell
whether that frame or the next one carried the change to glass. At a pinned 120 Hz that is up to
**8.33 ms** of over- or under-statement per sample.

The bias belongs to the instrument, not to an engine. It is identical on both sides of an A/B and
cancels in a delta — which is what E2 Gate 3 compares. **Absolute values carry it**, so any table
quoting an absolute `p0.key.*` or `p0.zoom.gesture` number must repeat this bound beside it.

`NSEvent.timestamp` and `CADisplayLink.timestamp` share the mach time base `CACurrentMediaTime()`
reads, so no conversion is involved. The event stamp is taken when the window server received
the input, so queueing delay is inside the number rather than hidden from it.

---

## What is measured here, and what is not

**Measured by these tests:** the sampling rules — interval arithmetic, the scroll-idle gate,
pending resolution, oldest-stamp-wins under autorepeat, and that a disabled instrument records
nothing. Driven through `presentFrame(at:)` with an injected clock.

**Not measured, by construction:** the display link's real cadence, and therefore every number
these keys will eventually report. That needs a person at a machine with a pinned display —
E2 Window 1. This PR ships the stopwatch, not a reading.

---

## Promotion

If Window 1's data supports them, these constants become tokens in a later, deliberate
tokens-hash change — never as a side effect of a measurement session.

---

# W0 develop-draw attribution — PROPOSED

**Branch:** `perf/w0-render-instruments` · **Date:** 2026-09-24 · **Status:** proposals, not tokens.

Measurement only. After this change the app renders the same pixels, in the same order, at the
same times; every key below observes work `DevelopMetalView.draw(in:)` already does. Forcing
rasterization of the authoritative stage is a render-behaviour change and belongs to **W1**.

## The defect this instrument makes visible

`PreparedRawSession.rawStageSurface` materializes the **interactive** RAW tier into an
`MTLTexture` and deliberately leaves the **authoritative** tier as the lazy
`CIRAWFilter.outputImage`. `DevelopMetalView.draw(in:)` then walks whatever `CIImage` it was
handed, so for a settled frame that walk **is the RAW demosaic**, on the presentation path.

`LatencyMetrics.editDrawKey` (`p0.edit.draw_ms`) already brackets that draw from just before the
`startTask` pair to the command buffer's completion handler, so the demosaic is genuinely inside
the number. What it cannot do is hold the two populations apart — cheap materialized draws and
expensive lazy ones land in one distribution, and the cheap ones outnumber the expensive ones
during a scrub. `DevelopDrawInstrumentTests.testMixedKeyHidesTheLazyPopulationThatTheSplitKeysReveal`
is that claim as arithmetic: with 100 draws at 4 ms and 5 at 90 ms, the mixed key's p50 **and**
p95 both report 4 ms and the key never breaches its own 50 ms budget.

## The four keys

| Key | What one sample is | Declared budget | Basis |
|---|---|---|---|
| `p0.develop.draw_walk_lazy_ms` | CPU wall time of the `startTask(toClear:)` + `startTask(toRender:to:)` pair for a draw whose RAW stage is a lazy `CIRAWFilter` graph | **8.33 ms** PROPOSED | Deliberately loose — the walk is a *part* of the draw, so the whole's budget can only under-report breaches. It runs on the thread driving `draw(in:)`, so a large value is a main-thread stall. |
| `p0.develop.draw_walk_materialized_ms` | The same, for a draw whose RAW stage is a materialized `MTLTexture` | **8.33 ms** PROPOSED | As above. |
| `p0.develop.draw_lazy_ms` | The same interval extended to GPU completion — directly comparable to `p0.edit.draw_ms`, except attributed | **8.33 ms** PROPOSED | The frame key's claim: a draw slower than one display interval cannot keep up with a pan. |
| `p0.develop.draw_materialized_ms` | The same, materialized | **8.33 ms** PROPOSED | As above. |

All four reuse `LatencyMetrics.frameBudget120HzMs` rather than inventing a fifth constant.
They are declared by **exact key** in `declaredSLAms`, like the E2 four. `p0.edit.draw_ms` keeps
its name and its historical 50 ms budget, unchanged.

Subtracting walk from total gives GPU time without a second clock — that subtraction is what
distinguishes "the graph was re-walked" from "the GPU was busy".

## The attribution rule

`DevelopRawStageBacking` is read from the surface itself (`RawStageSurface.texture != nil`), not
from the tier that was requested: `materializeInteractiveStage` can fail, and the interactive
tier then caches a lazy graph like the authoritative one. Reading the tier would mislabel that
draw as cheap.

`.unattributed` surfaces — proxy, ImageIO fallback, browse JPEG, Develop Lab frames — record
**nothing**. The count of unattributed draws is recoverable as
`window(for: "p0.edit.draw_ms").totalRecorded` minus the two attributed totals.

## How a W1 delta gets proven from these

W1 materializes the authoritative stage, after which settled draws stop producing `lazyGraph`
samples entirely — the *same* key cannot be compared across the change. The comparison is:

- **Before:** `draw_lazy_ms` (settled pan/zoom) against `draw_materialized_ms` (interactive)
  **in the same run** — same host, same instrument, same session. The gap between them is the
  cost W1 removes, with the materialized key as the contemporaneous control.
- **After:** settled pan/zoom lands in `draw_materialized_ms`; `draw_lazy_ms` should have no
  samples. The materialized key must not have regressed against its before value — that is what
  rules out "the host got faster".

## Off by default

`DevelopDrawInstruments.isEnabled` reads the same `--p0-instruments` launch argument as
`P0RenderInstruments` and `DevelopPresentationMeasurement`. An ordinary run pays one `Bool` read
per draw. Keys promote themselves out of the 512-sample ring on first sample, because a pan is
thousands of draws and the ring would report only its tail.

## `p0.edit.promote_settled_ms` — NOT A LATENCY

Left recording byte-for-byte as it was, with a comment at the recording site in
`DevelopRenderScheduler.openPhotograph` stating precisely what it does and does not measure.
One sample contains the cache lookup, the lane wait, `CIRAWFilter` property application, CI graph
*construction*, and the `createCGImage` call for the settled histogram bitmap. It does **not**
contain the demosaic: `createCGImage` on a full-scale RAW graph returns a deferred image in
0.3 ms against 183.6 ms p50 to rasterize the same graph
(`~/LuminaEvidence/render-latency-research-20260924/03-raw-deferred-vs-forced-24mp.txt`).
A small number there means the graph was built, not that the photograph is on screen.

Making it true requires either forcing rasterization (W1's behaviour change) or resolving it
against a presented drawable, which exists only under `--p0-instruments` and would redefine a key
that already has a budget and a history. Both are out of scope for a measurement-only change.

## What is measured here, and what is not

**Measured by these tests:** the key names, the declared budgets, the attribution rule including
the unattributed exclusion, the off-by-default guarantee, ring promotion, and the mixed-key
defect as arithmetic.

**UNMEASURED, by construction:**

- Every number these four keys will report. No run of this instrument exists yet. This change
  ships the stopwatch, not a reading.
- The walk/GPU split for a lazy draw. The magnitudes quoted from
  `04-lazy-redraw.txt` (288.7 ms first draw; 6.4–6.8 ms identical redraws; 93.6–181.8 ms after a
  pan; 3.7–5.3 ms materialized) come from a standalone bench using the **blocking**
  `CIContext.render(toBitmap:)`, not this app's asynchronous `startTask` + command-buffer path.
  They are the reason these keys exist; they are not this app's numbers.
- Develop Lab draws (`DevelopLabView`) stay `.unattributed` — the lab is a harness surface, not
  the product path.

## Promotion

Same rule as the E2 block above: if a real Window supports them, these constants become tokens in
a later, deliberate tokens-hash change — never as a side effect of a measurement session.
