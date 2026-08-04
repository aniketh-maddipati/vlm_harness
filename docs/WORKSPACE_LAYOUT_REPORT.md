# Lumina Workspace — Layout, Transition & Color Report

**Version:** MVP cull workspace (Aug 2026)  
**Reference aesthetic:** [Thinking Machines Lab](https://thinkingmachines.ai/) — editorial porcelain, not dashboard chrome  
**Primary view:** `CullWorkspaceView` (`Lumina/Views/Workspace/CullWorkspaceView.swift`)

This document is intended for external design/planning — copy or import as needed.

---

## 1. Executive summary

Lumina’s active culling surface is a **three-band horizontal layout**:

| Band | Role | Background |
|------|------|------------|
| **Header** (54 pt) | Shoot title, lens nav, progress | White `#FFFFFF` |
| **Body** | Set sidebar (232 pt) + main stage | Grey rail `#F3F3F2` + white stage |
| **Footer strip** | Set filmstrip + decision dock | Grey rail + white footer |

Culling happens **inline** — no modal focus overlay. Two large panes (**Selected** / **Compare**) sit side-by-side; gestures and keyboard apply Keep/Cut without leaving the page.

**Known glitch sources (partially addressed in latest pass):**
- Image identity swaps clearing pixels before silhouette arrives
- Compare pane retargeting on every hero change
- Peer-suggestion banner resizing the compare `GeometryReader`
- Multiple `StablePhotoView` instances reloading the same asset independently

---

## 2. Screen map & dimensions

### 2.1 Full window (minimum 1100 × 700)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ HEADER  54 pt  porcelain #FFFFFF                                            │
│  ← │ Shoot Title (Iowan 30 pt) │ Attempts · Light │ 12 of 240 │ ···         │
│  hairline divider  #282828 @ 10%                                            │
├──────────────┬──────────────────────────────────────────────────────────────┤
│ SET RAIL     │ MAIN STAGE  porcelain #FFFFFF                                │
│ 232 pt       │                                                              │
│ rail #F3F3F2 │  ┌─ Selected ─────────┐  ┌─ Compare ──────────┐             │
│              │  │ well #ECECEA       │  │ well #ECECEA       │  ~flex      │
│ [set rows]   │  │ [photo]            │  │ [photo]            │             │
│              │  └────────────────────┘  └────────────────────┘             │
│              ├──────────────────────────────────────────────────────────────│
│              │ FILMSTRIP RAIL  #F3F3F2  ~84 pt                                │
│              │  Group title · subtitle · "3 of 8 decided"                     │
│              │  [thumb][thumb][thumb][thumb]… horizontal scroll               │
│              ├──────────────────────────────────────────────────────────────│
│              │ FOOTER  ~56 pt min  porcelain                                  │
│              │  hint text │ Keep · Cut · Review · Anchor dock                  │
└──────────────┴──────────────────────────────────────────────────────────────┘
```

### 2.2 Spacing tokens (implemented)

| Token | Value | Usage |
|-------|-------|-------|
| `workspaceMargin` | 28 pt | Header/footer/stage horizontal inset |
| `md` | 16 pt | Gap between compare panes |
| `sm` | 10 pt | Filmstrip thumb gap |
| `xs` | 6 pt | Label-to-photo vertical gap |
| `section` | 44 pt | (Legacy board; not used in cull view) |
| `xxl` | 52 pt | (Legacy board group gap) |

### 2.3 Set navigator (left rail)

- **Width:** 232 pt fixed
- **Background:** `Surface.rail` `#F3F3F2`
- **Divider:** trailing edge `Line.emphasis` `#282828 @ 18%`
- **Row height:** ~60 pt (44 pt thumb + padding)
- **Selected row:** white `#FFFFFF` inset card, 6 pt corner radius, hairline border
- **Unselected row:** transparent on grey rail
- **Auto-scroll:** selected set scrolls to vertical center

### 2.4 Compare panes

- **Split:** 50/50 when Compare target exists; Selected full-width when alone
- **Photo well:** `Surface.well` `#ECECEA` — recessed grey behind photos
- **Selected pane border:** `Line.emphasis` 1 px
- **Compare pane border:** `Line.hairline` ~0.5 px (@2x)
- **Photo corner radius:** 4 pt (minimal, not card-like)
- **Max decode:** 2400 px long edge per pane

### 2.5 Filmstrip

- **Background:** `Surface.rail` `#F3F3F2` (two-tone band below white stage)
- **Thumb height:** 72 pt; width = `72 × aspectRatio` (min 48 pt)
- **Top edge:** hairline separator from stage above
- **Auto-scroll:** selected thumb scrolls to horizontal center

### 2.6 Peer suggestion banner (floating)

- **Position:** overlay bottom of stage, 88 pt above footer (does not resize panes)
- **Background:** white `#FFFFFF` + soft shadow
- **Border:** emphasis hairline
- **Trigger:** after Keep/Anchor/Cut when ≥1 lower-quality peer in same cluster/burst

---

## 3. Color system

### 3.1 Current implemented palette

#### Surfaces (two-tone structure)

| Token | Hex | Role |
|-------|-----|------|
| `porcelain` | `#FFFFFF` | Main stage, header, footer, selected nav chip |
| `rail` | `#F3F3F2` | Sidebar, filmstrip band — **grey field** |
| `well` | `#ECECEA` | Photo loading wells — **deeper grey inset** |
| `highlight` | `#FFFFFF` | Elevated chips on grey (same as porcelain; semantic alias) |
| `mist` | `#F3F3F2` | Legacy alias for rail |
| `hover` | `#282828 @ 8%` | Button press / hover |

#### Ink hierarchy

| Token | Hex | Usage |
|-------|-----|-------|
| `primary` | `#282828` | Shoot titles, selected labels, active nav |
| `strongSecondary` | `#3C3836` | Group headings in filmstrip |
| `secondary` | `#676767` | Body metadata, unselected nav |
| `tertiary` | `#969696` | Counts, filenames, hints |

#### Lines

| Token | Opacity | Usage |
|-------|---------|-------|
| `hairline` | 10% of `#282828` | Standard dividers |
| `emphasis` | 18% of `#282828` | Rail edge, selected pane, banner border |

#### Status (photographs supply saturation; UI stays restrained)

| Token | Hex | When visible |
|-------|-----|--------------|
| `selection` | `#0E9EE4` | Selected photo border (optional accent) |
| `reject` | `#AD2111` | **Only after explicit Cut** — badge, swipe hint, active dock |
| `needsAttention` | `#B57614` | Review flag |
| `keep` | `#9CC355` | Rarely used in chrome; prefer ink badge |
| `anchor` | `#282828` | Anchor state |

### 3.2 Two-tone logic (recommended expansion)

The workspace reads as **white work surface on grey infrastructure**:

```
Layer 0: Window chrome (system)
Layer 1: rail #F3F3F2     — navigation + filmstrip (structural grey)
Layer 2: porcelain #FFFFFF — culling stage + header (work surface)
Layer 3: well #ECECEA     — photo mats (content inset)
Layer 4: Photographs      — only saturated color source
```

**Proposed additions for “solid” feel:**

| Proposed token | Hex | Purpose |
|----------------|-----|---------|
| `railDeep` | `#EBEBE9` | Alternate set row zebra / section breaks |
| `wellActive` | `#E4E4E1` | Active pane well (Selected vs Compare subtle shift) |
| `highlightMuted` | `#FAFAF9` | Hover on rail rows before selection |
| `accentTint` | `#0E9EE4 @ 6%` | Focus ring / keyboard focus, not fills |

**Rules:**
- Never fill large regions with accent blue or destructive red
- Grey differentiates **structure** (rail) from **work** (porcelain) from **content** (well)
- White highlights = “this is selected/active” on grey ground

### 3.3 TML reference mapping

| TML site pattern | Lumina adaptation |
|------------------|-------------------|
| White page field | `porcelain` main stage |
| Quiet grey sections | `rail` sidebar + filmstrip |
| `#282828` body text | `Ink.primary` |
| Muted metadata | `Ink.tertiary` |
| No dashboard cards | Inset rows, hairlines, no shadows except floating banner |
| Serif headlines | Iowan Old Style shoot title |
| Sans navigation | SF Pro 13–15 pt |

---

## 4. Typography

| Role | Font | Size | Weight | Tracking |
|------|------|------|--------|----------|
| Shoot title (header) | Iowan Old Style | 30 pt | Regular | 0 |
| Group title (filmstrip) | SF Pro | 18 pt | Regular | −0.3 |
| Set row title (sidebar) | SF Pro | 13 pt | Regular | 0 |
| Navigation / controls | SF Pro | 15 pt | Regular | 0 |
| Metadata / counts | SF Pro | 11–13 pt | Regular | 0 |
| Pane labels | SF Pro | 13 pt | Regular | 0 |

**Rule:** No gratuitous bold. Selected state = darker ink, not heavier weight.

---

## 5. Interaction & transitions

### 5.1 Navigation flows

```
Set sidebar tap
  → selectGroup(id)
  → pick first undecided in set (or representative)
  → paint PreviewSpine
  → refresh pinned Compare target

Filmstrip thumb tap
  → selectAsset(id)
  → hero pane updates
  → Compare stays pinned if still valid

Keyboard ←/→
  → moveAttempt (change set)

Keyboard ↑/↓
  → moveAlternative (within set filmstrip order)

After Keep/Cut
  → advance to next undecided in set
  → else advance to next set with undecided
  → maybe show peer suggestion banner
```

### 5.2 Animation tokens

| Token | Duration | Curve | Used for |
|-------|----------|-------|----------|
| `Motion.control` | 0.15 s | easeOut | Button press, swipe snap-back |
| `Motion.selection` | 0.18 s | easeInOut | Pane crossfade on asset change |
| `Motion.photo` | 0.22 s | easeOut | Filmstrip scroll, image fidelity |
| `Motion.fidelity` | 0.16 s | easeOut | Silhouette → preview upgrade |
| `Motion.route` | 0.20 s | easeOut | Home ↔ workspace route change |

### 5.3 Transition catalog

| Event | Current behavior | Recommended |
|-------|------------------|-------------|
| Hero asset change | Opacity crossfade on pane (`.id` + `Motion.selection`) | ✓ Keep; add matched-geometry optional |
| Compare target change | Pinned ID — only changes when invalid | ✓ Keep pin logic |
| Image load | Silhouette sync from PreviewSpine → preview async | ✓; consider blur-up |
| Set change | Sidebar + filmstrip swap content | Add 0.12 s opacity on filmstrip band |
| Peer banner appear | Slide up overlay (no layout reflow) | ✓ |
| Decision badge | Instant update on asset | Soft 0.1 s scale-in on badge only |
| Route (Home/Workspace) | 0.2 s opacity + 0.995 scale | ✓ |

### 5.4 Gestures

| Input | Action | Target |
|-------|--------|--------|
| Drag pane right > 56 pt | Keep | That pane’s asset |
| Drag pane left > 56 pt | Cut | That pane’s asset |
| Two-finger swipe → (NSEvent) | Keep | Selected asset |
| Two-finger swipe ← | Cut | Selected asset |
| K / X | Keep / Cut | Selected asset |
| Space | Apply peer suggestion | Batch cut peers |
| Esc | Dismiss peer suggestion | — |

---

## 6. Data & state architecture

### 6.1 Presentation pipeline

```
PhotoRecord[] (ProjectViewModel)
  → PresentationAdapter.workspace()
  → WorkspacePresentation
       groups: [GroupPresentation]
       selectedAssetID, selectedGroupID
  → LuminaShellModel overlays selection (no group rebuild)
  → CullWorkspaceView renders
```

**Cache invalidation:** full fingerprint rebuild on tier/decision changes. Selection-only changes overlay without rebuild.

### 6.2 Compare pane logic

1. On set/hero change, compute best undecided peer by `qualityScore` (cullScore)
2. **Pin** compare ID until that asset is decided or leaves set
3. Prevents compare pane swapping every hero advance (major glitch source)

### 6.3 Peer suggestion logic (`PeerCullEngine`)

- Same `clusterID` or `burstID`
- Target undecided, not hero/protected
- After **Keep:** peers with `cullScore < anchor − 0.04`
- After **Cut:** peers with `cullScore ≤ anchor + 0.04`
- Batch apply via `ProjectViewModel.applyTier(.reject, to: ids)`

---

## 7. Glitch inventory & fixes

| Symptom | Root cause | Fix status |
|---------|------------|------------|
| White flash between photos | `StablePhotoView` cleared image before silhouette | **Fixed** — sync PreviewSpine silhouette on ID change |
| Compare pane jumps | Compare retargeted every hero change | **Fixed** — pinned compare ID |
| Stage jumps when banner appears | Banner in layout flow resized GeometryReader | **Fixed** — banner as bottom overlay |
| Drag offset stuck | `CullStagePane` state reused across assets | **Fixed** — `.id(asset)` + `onChange` reset |
| Filmstrip doesn’t follow selection | No ScrollViewReader | **Fixed** — auto-scroll to hero |
| Sidebar doesn’t follow set | No ScrollViewReader | **Fixed** |
| Slow flip on keyboard | No prefetch | **Fixed** — silhouette prefetch ±1 neighbor |

### 7.1 Remaining risks

- **Dual-pane decode:** Selected + Compare + filmstrip thumbs = 4+ concurrent loads; may stutter on large RAW previews
- **Full cache invalidation** on each decision rebuilds all group labels/progress
- **No undo** wired for swipe decisions
- **Compare pane** doesn’t support wipe/slider (legacy `GradedCompareView` exists unwired)

---

## 8. Route map (full app)

| Route | View | Layout character |
|-------|------|------------------|
| `home` | `HomeView` | Editorial single column, max 960 pt |
| `shootSelection` | `ShootSelectionView` | Grid of flat strips |
| `workspace` | `CullWorkspaceView` | Split rail + stage (this doc) |
| `finish` | `FinishView` | Editorial sequence + export |

Legacy (unwired): `PaletteWorkspaceView`, `FocusOverlayView`, `AttemptWorkspaceView`, `DerivedSessionView` + `SpeedBrowseViewer`

---

## 9. Recommended next design iterations

### 9.1 Layout

1. **Fixed compare slot** — always show two wells; empty state = “No more alternatives” grey placeholder (prevents 50/50 ↔ full-width reflow)
2. **Vertical set timeline** — optional collapse of sidebar to chips when stage needs width
3. **Wipe compare** — drag vertical divider between panes (port `CompareOverlayView` pattern)
4. **Overview mode toggle** — return `PaletteBoardView` as scan-only lens; cull stays in split view

### 9.2 Color / two-tone polish

1. Apply `rail` to header OR keep header white with only body grey — **current:** header white, body mixed (intentional hierarchy)
2. Zebra striping in sidebar: alternating `rail` / `railDeep` for long shoots
3. Active pane: `wellActive` vs passive `well`
4. Subtle `accentTint` focus ring on keyboard-focused pane (accessibility)

### 9.3 Motion

1. Matched Geometry effect hero thumb → pane on filmstrip tap
2. Decision outcome micro-animation: cut = brief desaturate; keep = hairline green tick (not fill)
3. Set completion: row progress animates `"7 of 8"` → `"8 of 8"`

### 9.4 Performance

1. Shared image cache key across pane + filmstrip for same asset ID
2. Decision-only presentation diff (don’t rebuild group titles)
3. PreviewSpine warm on set enter, not each arrow key

---

## 10. File reference

| File | Responsibility |
|------|----------------|
| `Lumina/Design/LuminaTokens.swift` | Colors, spacing, motion, typography |
| `Lumina/Views/Workspace/CullWorkspaceView.swift` | Cull layout, gestures, sidebar, banner |
| `Lumina/Views/Components/WorkspaceChrome.swift` | Header, lens switcher |
| `Lumina/Views/Components/StablePhotoView.swift` | Progressive image load |
| `Lumina/Views/Components/DecisionDock.swift` | Inline Keep/Cut/Review/Anchor |
| `Lumina/Shell/LuminaShellModel.swift` | Selection, decisions, peer suggestions |
| `Lumina/Services/PeerCullEngine.swift` | Same-subject peer detection |
| `Lumina/Services/PreviewSpine.swift` | Silhouette + browse cache |
| `Lumina/Presentation/PresentationAdapter.swift` | Groups, assets, qualityScore |

---

## 11. Quick copy — color JSON

```json
{
  "surface": {
    "porcelain": "#FFFFFF",
    "rail": "#F3F3F2",
    "well": "#ECECEA",
    "highlight": "#FFFFFF"
  },
  "ink": {
    "primary": "#282828",
    "strongSecondary": "#3C3836",
    "secondary": "#676767",
    "tertiary": "#969696"
  },
  "line": {
    "hairline": "rgba(40,40,40,0.10)",
    "emphasis": "rgba(40,40,40,0.18)"
  },
  "status": {
    "selection": "#0E9EE4",
    "reject": "#AD2111",
    "needsAttention": "#B57614"
  },
  "proposed": {
    "railDeep": "#EBEBE9",
    "wellActive": "#E4E4E1",
    "accentTint": "rgba(14,158,228,0.06)"
  }
}
```

---

*Generated from Lumina MVP workspace implementation. For questions about wiring, see `AGENTS.md` and shell routes in `LuminaShellView.swift`.*
