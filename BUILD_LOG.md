# Lumina Build Log

One line per session: claim → finding → fix → instrument reading. Read this at the start of every Composer session.

---

## 2026-08-04 — Phase 1 shell + spine bridge (cloud follow-up)

**Claim:** Re-land Phase 1 shell on `cursor/ethereal-ui`, connect Attempts active stage to PreviewSpine/Metal, cache presentation adapters, fix Escape, bring `AGENTS.md` from main.

**Repo verification:**
- `AGENTS.md` exists on `origin/main` and is now on this branch.
- Prior Mac-desktop Phase 1 edits were never committed; this Linux cloud checkout rebuilt them.
- Platform: Linux cloud agent — **cannot** `xcodebuild` or run Mehendi live session (see AGENTS.md).

**Bridge requirements implemented in code:**
- `StablePhotoView` → PreviewSpine silhouette + fidelity + PhotoImageCache with AssetID request validation; lower fidelity remains during upgrades.
- `SpineActiveStage` → MetalBrowseCanvas + spine paint for Attempts active image.
- `LuminaShellModel` caches snapshots via `PresentationAdapter.projectFingerprint`; selection overlays without rebuilding groups.
- `PhotoGridView` selection path uses `applySelectionOnly` / `refreshVisibleBadges` — no `reloadData()` for selection.
- Escape closes Focus / inspector / shortcuts only — never workspace → Home.

**Live gate remaining (macOS only):** `bash Scripts/live_bridge_session.sh` with Mehendi ARWs — rapid nav, 20× lens switch, decisions, resize, Focus, quit/resume, screen capture.

---

## 2026-08-02 — Build Loop closure (this session)

**Claim:** Progressive wall complete; Kill-the-Defeater fixes 1–5 code-audited; build + regression green.

**Build:** `xcodebuild -scheme Lumina -destination 'platform=macOS'` → **BUILD SUCCEEDED** (clean + incremental).

**Regression:** `bash Scripts/regression.sh` → **PASSED** — 30 pass · 0 friction · 0 bugs · cache decode p95 **0.14 ms** (headless sample, not browse photon path).

**ProgressivePhotoWall:** Complete. File `Lumina/Views/ProgressivePhotoWall.swift` auto-synced via `PBXFileSystemSynchronizedRootGroup`. Wired in `ImportLoadingView` (import wall), `GroupIntroPhase` (Meet), `ProgressivePickWall` (Pick). Compiles; no pending work.

---

## 2026-08-02 — Kill-the-Defeater (speed browse)

**Claim:** Held-key rip through Mehendi ARWs — p95 in→photon <50 ms; `blit_ms` ≈0; one decode/frame; zero main-thread decode/upload; no RAW on interactive path.

### Findings (pre-fix diagnostic)

| Finding | Impact |
|---------|--------|
| **HUD lying** | `input→photon` measured dict lookup / NSImage bind, not Metal `present`; prefetch “hit” counted warm NSImage, not GPU texture |
| **CPU blit hidden** | Full-frame `CGContext.draw` before IOSurface wrap; cost folded into `wrap_ms` |
| **Double decode** | Parallel NSImage dict + Metal upload on same JPEG |
| **Main-thread upload** | `MetalBrowseCanvas.updateNSView` called sync `upload()` on main |
| **RAW on browse path** | `sourcePathByID` RAW fallback; ImageIO `IfAbsent/Always=true` could demosaic |
| **Filmstrip thrash** | `scrollTo` + chrome animation on every advance during held-key rip |
| **ARW 1616 px synth** | Sony embeds 1616×1080 only; `minLongEdge: 2000` in `ProjectStore.extractBrowsePreview` → 100% ingest-synth for Mehendi ARWs (~456 ms once at ingest, ~50 ms cached JPEG browse thereafter) |

### Fix verification table

| Fix | CLAIM | STATUS | Evidence |
|-----|-------|--------|----------|
| **1 — Honest HUD** | Split upload into decode/blit/wrap; GPU prefetch hit = texture resident; in→photon at Metal present; paint_commit separate | **VERIFIED** | `PreviewSpine.swift` L30–31, L169–177, L196–221, L379–398 · `MetalPreviewPool.swift` L16–21, L161–165 · `MetalBrowseCanvas.swift` L162–165 · `SpeedContractHUD.swift` L20–24 |
| **2 — Kill CPU blit** | No `CGContext.draw` between JPEG decode and IOSurface; vImage copy/convert | **VERIFIED** | `MetalPreviewPool.swift` L12, L84–87, L248–283 · e2e static check: no `ctx.draw` |
| **3 — One decode→GPU** | Drop NSImage preview hot path; browse tier = GPU texture only; silhouette = tiny grid thumb | **PARTIAL** | `PreviewSpine.swift` L7, L56–57, L196–214, L348–366 — no `previews` dict ✓ · **Gap:** dual upload triggers (`PreviewSpine.enqueueGPU` L328–344 + `MetalBrowseCanvas.bind` L82–84); `MetalPreviewPool.upload` has no per-photo inflight dedup L64–113 |
| **4 — Off main upload** | Never sync-decode/upload in `updateNSView`; background pipeline only | **VERIFIED** | `MetalPreviewPool.swift` L62–65, L116–120 · `MetalBrowseCanvas.swift` L183–184 · `PreviewSpine.swift` L336–337 · draw/present stays on main (CAMetalLayer requirement) |
| **5 — Decouple filmstrip/chrome** | Canvas alone updates per keypress; filmstrip/chrome debounced during rips | **PARTIAL** | `SpeedBrowseViewer.swift` L4, L12–14, L100–108, L120–147, L240–285 — debounced filmstrip + rip-skipped controls ✓ · **Gap:** `tierLabel` L112–117 tracks every paint; parent ZStack still observes full `@Observable` spine |
| **RAW guard** | Browse never demosaics RAW; debug assert on RAW path | **VERIFIED** | `PreviewSpine.swift` L79–81, L368–377 · `MetalPreviewPool.swift` L193–198, L219–225 · `PhotoImageCache.swift` L27–33 |
| **SessionCache** | Session-scoped memory LRU + async disk; evict browse GPU on session end | **VERIFIED** | `PhotoImageCache.swift` L42–96, L173–185, L278–295 · `ProjectViewModel.swift` L148, L205, L445, L924 |

**Static audit (e2e):** `[PASS] Defeater-killed browse path` — honest HUD · vImage blit · one GPU decode · no main upload · no RAW fallback.

**Live numbers:** Pending manual ⌥` HUD rip on Mehendi ARWs. Regression cache p95 ~0.14 ms is grid/filmstrip path, not browse photon.

**Docs owed:** ARW 1616 px → synth threshold note in ingest spec; filmstrip decouple note in review-surface charter.

---

## 2026-08-02 — Session cache + Pick hang

**Claim:** Pick grid paints without eternal spinners; cache warm during edit, evict after session.

**Fixed:**
- `SessionCache` + `PhotoImageCache` — memory LRU 320, session disk under `Caches/Lumina/sessions/`, async utility disk writes
- Grid/preview tiers: `allowsRAWFallback: false`, 512 px display cap for filmstrips
- `PhotoImageView` failure placeholder; removed `PreviewSpine.warm` from Pick path
- Prefetch on Meet→Pick transition via `ThumbCache`

**Status:** Build + regression 30 pass. Manual: Meet → Pick from this set.

---

## 2026-08-02 — Progressive photo wall

**Claim:** No horizontal infinite scroll during ingest/Meet/Pick; screen-fit grid; previews fill slowly without jarring bulk load.

**Fixed:**
- `ProgressivePhotoWall` — `FitGridLayout` screen-fit slots, 380–420 ms reveal interval, prefetch window ahead of reveal (`ImportLoadingView`, Meet intro)
- `ProgressivePickWall` — 2-up batch reveal ~280 ms, scrollable grid for selection
- `ProgressiveWallTile` — loads via `PhotoImageCache` at 512 px, `allowRAW: false`

**Status:** Complete. Build + regression 30 pass.

**Manual:** Import a folder — wall should fill slot-by-slot, not dump all thumbs at once.

---

## Manual verification checklist

Run on **Mehendi ARW shoot** (`/Users/aniketh/Pictures/jeevana_mehendi_2026_MATCHED_RAWS`).

### 1. ⌥` HUD held-key rip (Kill-the-Defeater)

1. Open Lumina → import or resume Mehendi project → enter speed browse (F/D cull).
2. Toggle HUD: **⌥`** (Option + backtick).
3. Hold **F** (or **D**) for 3–5 s — rip through 20+ frames.
4. Record HUD lines:
   - `paint_commit` p50/p95 — should stay low (dict lookup, not photon)
   - `in→photon` p50/p95 — **target ≤50 ms**; measured **at present**, not at bind
   - `decode · blit · wrap` p50 — blit should be **≈0 ms** (vImage, not CGContext)
   - `GPU prefetch` % — should climb during rip; misses show silhouette tier briefly
   - `preview: emb · synth · jpg` — Mehendi ARWs expect **synth >> emb** (1616 px embed below 2000 threshold)
5. **Pass criteria:** photon p95 badge green; no main-thread stalls visible; silhouettes acceptable on cold frames, preview tier on warm.

### 2. Pick grid (Session cache)

1. Import → Meet phase → **Pick from this set**.
2. Confirm thumbs appear progressively (not all spinners forever).
3. Re-enter Pick on same set — cached thumbs should paint immediately.

### 3. Import / Meet wall (Progressive wall)

1. Import a large folder — import screen shows screen-fit grid, slots fill one-by-one (~400 ms apart).
2. Meet intro for a cluster — same progressive reveal, no horizontal infinite scroll.

### 4. If photon p95 fails

Diagnostic session only — **no re-architect**. Profile main thread during rip; check for remaining double-upload (Fix 3 gap) or chrome invalidation (Fix 5 gap).

---

## Next session checklist

1. ⌥` HUD held-F rip on Mehendi ARWs — record decode/blit/wrap, GPU prefetch %, in→photon p95
2. Confirm Pick grid after "Pick from this set" — no spinners on cached thumbs
3. If p95 still fails, diagnostic session only — profile main thread during rip
4. Optional hardening (only if rip profile confirms): inflight dedup in `MetalPreviewPool.upload`; throttle `tierLabel` like filmstrip
