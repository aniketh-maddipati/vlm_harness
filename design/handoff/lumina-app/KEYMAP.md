# Keymap: every input, and which layer owns it

**Layer order.** The topmost open layer handles input first; a key goes no further once a layer handles it.

1. Text field (typing a value)
2. Help overlay
3. First-run intro
4. Crop or Straighten
5. Variations grid
6. Rotate-hold (R held in Crop)
7. The focused control (slider, button, radio)
8. The current step
9. Global (⌘1–4, ⌘S, ⌘O)

A layer that owns the keyboard swallows every unbound single key and says why (for example, "Cropping · ⏎ keeps it · esc cancels"). Keys must never fall through to the photo underneath (R-20…R-26).

## Global (every step)
| Input | Action | Notes |
|---|---|---|
| ⌘1 · ⌘2 · ⌘3 · ⌘4 | Open · Cull · Edit · Save | Holding the key doesn't repeat. The last press wins, even in bursts 15ms apart (R-02). |
| ⌘S | Go to Save; on Save, save | Never saves from Edit directly (R-35). Held repeats are ignored. |
| ⌘O | Open folder… | |
| Drop files or folders | Import | Any step. Never makes the app open the file itself (R-17). |

## Open
| Input | Action |
|---|---|
| ⏎ | Copy & start culling / Continue. Repeats and presses within 450ms of a step change are ignored (R-01). |

## Cull
| Input | Action |
|---|---|
| R | Keep, then move to the next photo. Held repeats are ignored. |
| X | Out, then move to the next photo. Held repeats are ignored. |
| ← → | Previous / next photo (repeats allowed) |
| ↑ ↓ | First photo of the previous / next scene |
| U | Next undecided photo (wraps around) |
| ⌘Z · ⇧⌘Z · ⌘Y | Undo / redo the last decision (200 deep) |

## Edit
| Input | Action |
|---|---|
| ⏎ | Mark done and go to the next photo. On the last photo, go to Save without saving (R-03). |
| ← → | Previous / next photo in the set |
| ↑ ↓ | Previous / next scene |
| ⌘Z · ⇧⌘Z | Undo / redo the edit. Doesn't touch Cull decisions (R-27). |
| \ (hold) | Show the original while held; a tap toggles it |
| V (hold) | Variations of the setting under the pointer (or the section's main one). Release applies; a tap opens without applying. |
| C | Crop and straighten |
| S | Straighten: draw along a horizon |
| A | Auto; pressing again undoes it |
| , · . | Nudge the setting under the pointer or the active one; ⇧ ×5 |
| [ · ] | Choose which setting to nudge |
| 0 · ⇧0 | Reset this setting / reset all |
| = | Same edit as the last photo |
| W | Pick white (click something that should be neutral grey) |
| X | Out (⌘Z brings it back) |
| ⌘C · ⌘V | Copy / paste settings |
| Z · click | 1:1 at the pointer; again fits |
| ⌘+ · ⌘− · ⌘0 | Zoom in / out (below Fit too) / fit |
| H | Focus mode: only the photo |
| Esc | Back out one layer: focus → zoom → before → scene grid → picker |
| ? | Help |
| ⌥ + drag ↕ on the photo (Colour section) | Adjust the colour under the pointer |
| **R** | **Does nothing.** Shows "R keeps photos in Cull, so it does nothing here. To turn this photo: C, then R." (R-20) |
| **T** | **Does nothing.** The old picker was removed (R-21). |

## In Crop
| Input | Action |
|---|---|
| R · ⇧R | Turn 90° right / left |
| S | Straighten |
| ← → (⇧ coarse) | Angle ±0.1° (±1°) |
| ↑ ↓ | Grow / shrink the crop |
| ⌥ + arrows (⇧ coarse) | Move the crop |
| ⌘Z · Q | Undo within the crop; ⇧ redoes |
| ⏎ · C | Keep the crop |
| Esc | Cancel ("Crop cancelled") |
| Any other single key | Swallowed, with "Cropping · ⏎ keeps it · esc cancels" |

## In Variations
| Input | Action |
|---|---|
| ← → ↑ ↓ | Move the selection |
| ⏎ | Apply |
| Esc · V (a fresh press, not the held one) | Close; nothing changes |
| Anything else | Swallowed |
| Window loses focus | Grid closes (R-24) |

## Save
| Input | Action |
|---|---|
| ⏎ | Save, but only after a pause: ignored within 1.5s of arriving on Save and within 1s of the previous ⏎. Otherwise it shows "Paused so ⏎ doesn’t save by accident. Click Save or press ⌘S." (R-33) |
| ⌘S | Save. Repeats are ignored. |

## Mouse and trackpad
| Input | Where | Action |
|---|---|---|
| Two-finger horizontal swipe | Photo | Next / previous |
| Two-finger horizontal swipe | Slider | Adjust |
| Pinch / ⌃-scroll | Photo | Zoom, clamped to ¼×–2× of 1:1 (R-46) |
| Force click (hold) | Photo | Before, while held |
| Drag | Slider | Adjust: ⇧ fine, ⌥ finer, Esc cancels |
| Double-click | Slider | Reset |
| Click the value | Slider | Type a value |
| Drag | Zoomed photo | Pan |
