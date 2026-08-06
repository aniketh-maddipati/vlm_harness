# Live Edit Root-Cause Report

Branch: `cursor/raw-perf-lr-handoff`  
Fixture: Sony A7-class ARW, 6000×4000 (24 MP), `~/Pictures/jeevana_mehendi_2026_MATCHED_RAWS`  
Hardware: MacBook Pro, Apple M4 Pro

## Failure modes observed (pre-fix)

| # | Failure | Present? | Evidence |
|---|---|---|---|
| 1 | Binding does not write every tick | No | SwiftUI `Slider` Binding set continuously; Workbench `commit` fired per tick |
| 2 | Binding writes into row-local state | Partial | `ContextualTreatmentStrip` had duplicate sliders on rows (proxy path). Removed for this phase |
| 3 | Recipe changes but revision does not | Yes | No monotonic `recipeRevision` existed; cache keyed only by fingerprint |
| 4 | Scheduler never receives new recipe | Partial | Workbench routed through `.task(id: scrubKey)` after body recompute — delayed vs Lab’s direct `scrubRecipe` |
| 5 | **Scheduler cancels / coalesces incorrectly** | **Primary** | `scrub()` cancelled the in-flight `Task` on every tick. `renderNow` discarded results when `Task.isCancelled`. RAW-sensitive evaluates (~100ms+) almost never published until drag paused → **release-to-apply** |
| 6 | Prepared session belongs to prior photo | Risk | No `preparedSessionID`; registry eviction could reuse asset key without identity gate |
| 7 | Valid render fails publication gate | N/A before | Generation gate existed; revision/session gates added |
| 8 | Texture changes but MTKView not drawn | No | `updateNSView` set `needsDisplay` |
| 9 | SwiftUI recreates editor / Metal / session | **Yes** | Live Metal surface lived inside `LazyVStack` focus carousel cards (`.id(asset.id)`). Scrolling / focus changes reconstructed `DevelopMetalView` + coordinator |
| 10 | Equatable / `.id` / task boundary suppresses updates | **Yes** | `.task(id: scrubKey)` cancelled prior tasks on every fingerprint change |
| 11 | Render only on `onEditingChanged(false)` | Effectively yes | Not literally mouse-up API, but cancel-discard made it behave as release-to-apply for Exposure/Warmth |
| 12 | Older render overwrites newer | Guarded | Generation ordering existed; revision gate strengthens this |
| 13 | Recipe not applied to `CIRAWFilter` | No | `PreparedRawSession.apply` sets exposure / WB / NR / sharpen |
| 14 | Displaying JPEG proxy / `GradedPhotoView` | Partial | Underlay until first Metal frame; carousel neighbors used `GradedPhotoView` |

## Root cause (concrete)

The interactive scrub path was:

```text
Slider tick
  → cancel inflight Task
  → sleep 16ms
  → renderNow (100ms+ for RawIntent)
  → if Task cancelled → discard pixels
```

During a continuous Exposure or Warmth drag, a new tick arrived before the evaluate finished, so completed (or nearly completed) work was thrown away. The first frame that survived was typically the last value after the gesture paused. Look-only controls (contrast) could appear livelier because RAW-stage cache hits finished in ~3–16ms and sometimes won the race.

Secondary causes: Metal editor inside a scroll carousel (lifecycle thrash) and Workbench scrub driven by `.task(id:)` instead of a synchronous editor-model setter.

## Fixes

1. **Latest-wins drain loop** in `DevelopRenderScheduler.scrub` — pending recipe updates never cancel an in-flight interactive evaluate; after each finish, drain the newest pending revision. Settled still waits ~150ms after the last drain.
2. **`DevelopEditorModel`** — one persistent MainActor model: draft/committed recipe, monotonic `recipeRevision`, session identity, before/after, latency.
3. **`DevelopEditorIdentity` + publication gate** — publish only when photoID, preparedSessionID, recipeRevision, and display profile match.
4. **Workbench TreatmentStageView** — carousel removed; one persistent `DevelopMetalView` + filmstrip selection intents + single control stack. Sliders call `editor.setDraftRecipe` synchronously on MainActor.
5. **Row strip** — live sliders removed from `ContextualTreatmentStrip` (Treat… opens the real editor).
6. **`--live-editor`** proof surface for isolated verification.
7. Structured `[live-edit]` path logging + Metal lifecycle counters.

## After lifecycle expectations

| Object | While scrubbing one photo |
|---|---|
| `DevelopEditorModel` | 1 init (shared `WorkbenchDevelop.editor`) |
| `PreparedRawSession` | 1 prepare (`prepareCount` stable) |
| `DevelopMetalView` / MTKView / Coordinator | 1 make (not inside LazyVStack) |
| Interactive `CIRAWFilter` | Reused; params reapplied |

Harness `scrubDrain` (40 exposure steps): `lifecycleSessionPrepares: 1`, `completedPublishes: 40`, `staleRejected: 0`, `convergedOnLatest: true`.

## Honest latency notes

- Look-only interactive scrub with forced GPU evaluate: p50 **13.7ms**, p95 **16ms** (20/20 RAW-stage hits).
- Scheduler drain `inputToVisible` samples in the harness measure **CIImage publish** time (lazy graph), not MTKView present — do not claim 1.3ms glass-to-glass from that number.
- RAW-sensitive interactive cold evaluate remains on the order of **~100–145ms** for a warm 24MP ARW at 1600 long-edge; the UI stays responsive because the drain loop always converges on the latest revision without release-to-apply freeze. Glass-to-glass p50/p95 must be read from `os_signpost` `inputToVisible` during a real MTKView session (`--live-editor` or Treatment).

## Remaining limitations

- Animated focus carousel deferred until live scrub is accepted.
- Agent session could not capture a real GUI screen recording (Aqua window from background launch); manual checklist required.
- Histogram still updates on settle, not every scrub frame.
- Clarity / Texture / Dehaze / Whites / Blacks remain disabled (no honest algorithm).
