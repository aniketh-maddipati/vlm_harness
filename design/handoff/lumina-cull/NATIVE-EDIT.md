# Native Edit rendering + progressive caching (v0.01)

Decision: native Edit rendering ships (Q1 = yes). Section 11 of the design asks applies, plus the caching plan below.

## The idea
The further the user is in the flow, the more we know which photos they'll edit, so we can spend more decode work on fewer photos:

| Where the user is | What we know | Background work (idle priority) |
|---|---|---|
| Open | nothing | headers + embedded previews only (today) |
| Pick, browsing | the cursor | embedded previews ±2 around the cursor (today) |
| Pick, a photo is kept (⏎) | it's likely to be edited | **P2**: native RAW decode at screen size, linear, cached to disk |
| Pick, ⇧P (picks only) | the edit set | **P1**: every pick → screen-size decode; first 3 picks → full-res |
| Edit, on a photo | the next ones | **P0** current at full res; **P1** ±1 full res, ±3 screen size, same-scene neighbours |
| Edit, Z held | the region | 100% tiles for that ROI only |
| Save (or idle on the last photo) | final looks | full-res renders of every pick with its look, ready for "Also export JPEGs" |

## Cache
- **Key**: file fingerprint (path + size + mtime) + decoder version + stage (`linear-screen`, `linear-full`, `render-<lookHash>`).
- **Linear stage** (demosaiced, before the look): 16-bit half-float, disk at `~/Library/Caches/Lumina/render/<shoot>/`. Changing a slider re-renders from this stage; it never re-decodes the RAW.
- **Render stage**: GPU textures in RAM; LRU by bytes (default 1.5 GB, lower on 8 GB Macs).
- Disk budget: 4 GB per shoot, oldest shoot evicted first. Settings ▸ "Remove Working Files" clears it (alert text in MENUS.md).
- A pick that's later removed: its linear cache stays until eviction (undo is common).

## Scheduling
- Priority queue P0 > P1 > P2. Starting a P0 job pauses everything below it.
- Moving the cursor cancels any P1 job that's no longer within ±3 positions.
- Only one full-res decode at a time; screen-size decodes up to the number of performance cores minus one.
- Pause P2 when `ProcessInfo.thermalState ≥ .serious`, on battery under 20%, or in Low Power Mode. Resume quietly; never tell the user.
- Stale results: each preview request carries `seq`; a result older than the newest shown is dropped (the "409 never replaces a newer image" rule).

## Page → app (new call, in addition to section 11)
`lumina.prefetch([{rel, pri, px}])`. The page sends this on keep, ⇧P, entering Edit, cursor moves in Edit, and entering Save. Each call replaces the earlier list.
- `pri` is 0, 1 or 2; `px` is `'screen'` or `'full'`.
- The page decides *what*; the app decides *when* and *whether*.
- Guard: `typeof lumina.prefetch==='function'`. The browser ignores it.

## What the user sees
- Nothing new. Edit opens instantly on a cached pick, and slider drags stay at 60 fps because they render from the linear stage.
- First Edit on an uncached photo: the embedded preview shows immediately, and the native render fades in (≤150 ms crossfade, the fade that's already there).
- The facts line names the decoder ("RAW 9"). `luminaFacts.note` carries "update shoot" when the decoder version changes, and that invalidates only the render stage.

## Checks
- probe: keep 20 photos → within 60 s idle, 20 linear-screen entries exist.
- probe: ⇧P → Edit → first 3 picks open at full res in under 50 ms (cache hit).
- probe: drag a slider 100× in one frame → 1 preview request (section 11e).
- probe: thermal `.serious` → no P2 work starts.
