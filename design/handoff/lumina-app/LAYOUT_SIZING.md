# Layout and sizing: fit every screen, nothing small, no dead space

Native rebuilds usually come out **smaller and emptier** than the prototype. The usual causes:
- default `.controlSize(.small)` and `.regular` paddings;
- `List` and `Form` insets;
- a toolbar eating height;
- fixed `frame(width:)` values;
- content centred in a narrow column on a big display.

This file sets the rules that stop that. Tests R-54…R-59 enforce them.

## 1. Units: 1 prototype px = 1 macOS pt
Every number in the README is in **points**. Use these rules:
- Don't multiply by the backing scale.
- Don't swap in `NSFont.smallSystemFontSize` or `.controlSize(.small)`.
- Don't let SwiftUI's defaults shrink anything.
- Body text is **13pt** (the macOS default), and nothing is ever below **11pt**.

If a native control can't hit a size in the spec, use a custom view.

## 2. Two kinds of size
| Kind | Rule | Examples |
|---|---|---|
| **Chrome** (reading and clicking) | Fixed at spec size, never shrinks. On big windows it grows by the UI scale `S` (§3). | Text, buttons, tabs, slider rows, key hints |
| **Content** (photos) | Always fills the space left after the chrome. Never fixed. | Edit canvas, Cull tiles, preview, filmstrip |

## 3. UI scale S for big windows
```
S = clamp(1.0, min(windowWidth / 1440, windowHeight / 900), 1.25)
```
- **S = 1** at 1440×900 and below. Never scale below 1.
- **On big windows** (2560×1440, a 27-inch display at full screen): S = 1.25.
  - Multiply every chrome size by S: font sizes, control heights, paddings, radii, the tab width, the top-bar height, and the Edit controls column.
  - Round fonts to 0.5pt and everything else to 1pt.
- **Use one place for it.** Compute S once at window level and inject it through the environment, e.g. `@Environment(\.luminaScale)`. Views read their sizes from the tokens × S; no view hard-codes a point size.
- **Accessibility text size** (macOS 14+ "Text size", or Dynamic Type where available) multiplies on top of S.

## 4. Breakpoints (window content size, in pt, before scaling)
| Width | Changes |
|---|---|
| < 560 | Tabs 60 wide; key hints hidden |
| < 700 | Wordmark hidden; top-bar padding 10 |
| < 760 | Tabs 72 wide; no ⌘ hints on the tabs |
| < 860 | Edit controls move below the photo |
| < 900 | Cull preview column hidden; shoot meta hidden |

| Height | Changes |
|---|---|
| < 640 | Edit controls start collapsed under the photo |
| < 760 | Top bar 38 |
| < 900 | Top bar 42; otherwise 48 |

## 5. Per screen: what fills the space

**Shell:** the top bar is the only chrome above content. **No native toolbar and no title-bar gap**: use a full-size content view with a transparent, hidden-title titlebar and put the step tabs in the titlebar area so the traffic lights sit beside them. That saves about 28pt of height.

**Open and Save (forms):**
- **Column width:** `clamp(560, 0.46 × width, 760) × S`, centred.
- **Top padding:** `clamp(24, 0.07 × height, 72)`, so short windows don't waste a band at the top.
- **Short windows** (under 700 tall): the column starts at 24 from the top and only the list area scrolls.
- **Vertical centring:** content that fits is centred vertically in the space under the top bar with a ⅓ : ⅔ bias, so the empty space sits below it. It never leaves a big hole above.

**Cull (the big one):**
- **Tile height** is continuous instead of the prototype's 80 or 100:
  `tileH = clamp(80, 0.115 × gridHeight, 200)`
  That's 80 on a laptop, about 120 at 1080 tall, and about 160 at 1440 tall.
  - The user can override it with ⌘+ / ⌘−. Steps are ×1.25; the range is 64…320; the choice is remembered.
- **Justified rows:** the right edge of each scene's rows stays straight.
  - Lay tiles out at `tileH` with gap 6. For every row except the last, scale that row's height so its widths fill the row exactly, within ×0.8…×1.25.
  - The last row stays at `tileH`, left-aligned.
  - Portraits keep their whole photo inside a box at least 1.0× and at most 1.5× their height wide; prefer 1.0× so there are no wide letterboxes. **Change from the prototype:** portraits fill their tile. The 1.5× dotted box is only for strips narrower than 1:2.
- **Preview column** (from 900 wide): `clamp(300, 0.38 × width, 0.5 × width)`. The preview photo fills the column height minus the meta line and buttons, with the photo shown whole and no other padding.
- **Grid padding:** 16 / 20 / 24 × S. No other empty margin.

**Edit:**
- **Canvas** fills everything except the top bar, the controls column, the filmstrip and the facts line. Padding around the photo is at most 12pt at every size.
- **Photo** fits inside the canvas whole and touches it on one axis: its longer fitting side reaches the canvas edge minus padding.
- **Controls column:** `clamp(252, 0.20 × width, 340) × S`. It scrolls internally if needed; the slider rows never shrink.
- **Filmstrip thumbnail height:** `clamp(32, 0.045 × height, 72)`.
- **Focus mode (H):** the canvas fills the whole window, edge to edge.

## 6. Minimums, at every size including 320×480
| What | Minimum |
|---|---|
| Hit targets | 28pt high (24 for tabs and chips), 28 wide. Primary actions 34 high. |
| Text | 11pt. Body 13. |
| Slider row | 28pt high. Track hit area 20pt, even though the track draws at 2.5pt. |
| Edit photo | Visible, at least 40×40, even with the controls expanded (R-50) |

## 7. Anti-patterns (these fail review)
- `.frame(width: 600)` on a content column. Use the clamp formulas.
- `List` or `Form` for the Cull grid or Save options. Use custom layouts.
- `.controlSize(.small)` or `.mini` anywhere.
- `Spacer()` used for vertical centring that creates a hole above the content.
- Fixed tile sizes, or fixed Edit photo sizes.
- Ignoring `S` in any view.
