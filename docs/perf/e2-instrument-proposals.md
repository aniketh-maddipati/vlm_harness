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
