# F07 motion CONFLICT blocks (D27 / D28)

Sites where current behaviour cannot be expressed by **one** owned spring without violating D27 or D28.
**Do not silently collapse.** Left unchanged this session.

---

## CONFLICT: `StablePhotoView.swift` — photograph opacity birth

**Site:** `photoLayer` opacity `birthVisible ? 1 : 0` animated via `Motion.photoBirth` (L241).

**Violates:** **D27** — photographs never fade; chrome fades.

**Notes:** `tokens.yaml` `photo_birth` documents "opacity only at birth" — token vs law tension recorded; spring routed at hub but opacity-on-photograph remains.

---

## CONFLICT: `StablePhotoView.swift` — chained birth + blur crossfade

**Site:** L237–244 then L254–256 — `fidelityCrossfade` after `photoBirth` on same load path.

**Violates:** **D28** — one gesture → one motion → one spring → dead stop.

---

## CONFLICT: `SpineActiveStage` / `StablePhotoView.swift:354` — silhouette opacity

**Site:** `.transition(reduceMotion ? .identity : .opacity)` on photograph silhouette overlay.

**Violates:** **D27** — photograph-layer opacity fade.

---

## CONFLICT: `GradedPhotoView.swift` — develop grade opacity

**Site:** L49 `.transition(... .opacity.animation(Motion.develop))`, L100 `withAnimation(Motion.develop)`.

**Violates:** **D27** — graded photograph image fades in.

---

## CONFLICT: `TreatmentFamilyRow.swift:339–340` — dual animation modifiers

**Site:** `.animation(lift, …)` and `.animation(stage|keyline, …)` on same tile.

**Violates:** **D28** — two springs on one handling gesture.

---

## CONFLICT: `DecisionDock.swift:107–108` — pressed + hover springs

**Site:** two `.animation(Motion.control, …)` modifiers (isPressed, hovering).

**Violates:** **D28** — concurrent springs on one control.

---

## CONFLICT: `LuminaShellView.swift:53–54` — route + lens

**Site:** separate `.animation(Motion.route, value: shell.route)` and `value: shell.lens`.

**Violates:** **D28** when both values change in one navigation gesture.

---

## CONFLICT: Combined transitions (opacity + scale / move)

**Sites:**
- `ContentView.swift:55` (opacity + scale)
- `P0ContactSheetView.swift:26`
- `FocusOverlayView.swift:61` (opacity + move)
- `ContinuousWorkspaceView.swift:431`
- `UncertainAndClusterViews.swift:94`
- `LuminaShellView.swift:51`

**Violates:** **D28** — combined transition types; not collapsible to one scalar spring without losing a dimension.

---

## CONFLICT: `TreatmentStageView.swift:705–715` — receipt / hint chains

**Site:** `withAnimation { receipt = text }` + `Task.sleep` + second `withAnimation { receipt = nil }`; same for `visionHint`.

**Violates:** **D28** — timed second animation chained after first.

---

## CONFLICT: `ProjectViewModel.swift:389–442` — import stream phases

**Site:** `.easeInOut(0.55 / 0.4 / 0.35)` across progress / photosReady / finished / failed.

**Violates:** **D28** — multi-phase import stream uses sequential easings, not one spring; durations **0.55 s** not present in `tokens.yaml`.

---

## CONFLICT: `LuminaTokens.Motion.develop`

**Site:** hub constant kept as `Animation.easeInOut(duration: 0.55)`.

**Violates:** **D28** token law — no yaml ms; routing would change duration/feel.
