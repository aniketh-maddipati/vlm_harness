# WP-1 (Shell) contract requests

Nothing here blocks WP-1: each item has a workaround in WP-1's own files, named below.

## 1. `KeyRouter.route` can't tell "bound to nothing on purpose" from "not bound"

`Route(.global, .none)` comes back both for a held ⌘1–4 / ⌘S / ⌘O (bound, deliberately nothing)
and for a key no layer binds. The event monitor has to treat them differently: the first must be
swallowed (or a menu item with the same shortcut acts a second time), the second must go on to
AppKit (menus, ⌘Q, ⌘W, Tab).

**Ask:** a `bound: Bool` on `Route`, or make `KeyRouter.binding(_:_:)` public.
**Workaround:** `AppModel.windowKey` (`LuminaCore/Flow/AppModel+WindowInput.swift`) calls the
internal `KeyRouter.binding` (same module).

## 2. An owning layer swallows unbound ⌘ chords

With Crop open, `route(⌘Q)` is `Route(.crop, .explain("Cropping · ⏎ keeps it · esc cancels"))`;
with Help or Variations open it is `Route(layer, .none)`. KEYMAP says an owning layer swallows
every unbound *single* key; a chord should fall through to the menus.

**Ask:** in `route`, return "unbound" for a ⌘/⌃ chord that neither the owning layer nor Global binds.
**Workaround:** `windowKey` never performs or takes a chord the handling layer doesn't bind.
`model.handle` itself (used by `debug.command` and the trace replay) still explains it.

## 3. `handle` leaves ⌘ chords in `heldKeys`

macOS sends no key-up for a key released while ⌘ is down, so after ⌘V (paste settings) `"v"` stays
in `heldKeys`, and `debug.command` `{"keyDown":"v"}` then reports a repeat, which Variations ignores.

**Ask:** `handle` should not insert a key-down that carries ⌘ into `heldKeys`.
**Workaround:** `windowKey` removes it after `handle`.

## 4. `DebugHooks` sat on the window's corner pixel

The four 1×1 hook elements were overlaid at the window's top-left corner: outside the window's
rounded corner and inside its resize edge, so `debug.command` could not be clicked. The shell now
places them at (12, 31): below the traffic lights, inside the top bar. No change needed in
`Debug/`; noting it because the UI tests depend on it.

## 5. `debug.command` `{"drop":[…]}` and `{"blur":true}`

`drop` calls `importURLs` directly; a real drop goes through `model.dropFiles(_:)`, which also
drops anything that isn't a file URL (R-17). `blur` calls `windowBlurred()` and then `hooks.blur`,
which is what the shell does on a real resign-key, so that one already matches.

**Ask:** `drop` → `model.dropFiles(paths.map(URL.init(fileURLWithPath:)))`; and
`{"dragEnter":true}` → `model.dropHover(true)`.

**Done** (integration).

## 6. Tokens

`LuminaMotion` has `keepPopSeconds` but not the keyframes (tokens.json `keepPop.keyframes`), and
no tokens for the top bar's own numbers (gap 18, hint gap 5, meta gap 12, copy slot 118, track
padding 2, segment widths). They are in `LuminaUI/Motion/Motion.swift` (`LuminaPopCurve`) and
`LuminaCore/Flow/TopBarLayout.swift` for now.

**Ask:** generate them from tokens.json when convenient.

## Platform exceptions for `PARITY_EXCEPTIONS.md` (WP-10)

- **Traffic lights.** The bar sits in the titlebar area, so its content starts 10pt after the
  zoom button (79pt in on today's macOS) instead of at the 20pt padding. The wordmark moves right
  by about 59pt and the tabs, which are centred in the space left, by about half that. Under
  about 400 wide the four segments get narrower than 60 (56 at 320) so they stay whole beside the
  lights. In full screen and in `lumina-snap` there are no lights and the bar matches the prototype.
- **Top bar in Edit.** The prototype's Edit screen draws its own header; native keeps the one
  bar on every step and hides it only in focus mode (H).
