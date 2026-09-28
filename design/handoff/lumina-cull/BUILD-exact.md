# Build plan: exact UI (overrides README "rebuild in SwiftUI")

Goal: the Mac app looks and behaves **exactly** like `Lumina Sets v3.dc.html`. A SwiftUI rebuild can't guarantee that, so don't rebuild the UI. Ship this HTML as the UI inside a native shell, and replace only the browser plumbing underneath.

## Architecture
```
Lumina.app
├─ SwiftUI/AppKit window → one WKWebView, full window, no browser chrome
├─ Resources/ui/  Lumina Sets v3.dc.html, support.js, lumina-core.js (unchanged bytes)
└─ Native bridge (WKScriptMessageHandler + custom URL scheme lumina://)
   ├─ files.openFolder()        NSOpenPanel + security-scoped bookmark → list of ARW/XMP
   ├─ files.read(path, off, len) header + embedded preview bytes
   ├─ files.write(path, bytes)   atomic write, .lumina-bak first, checksum verify
   ├─ files.copy(src, dst)       RAW copy with SHA-256 / xxHash verify
   ├─ card.onMount / onUnmount   NSWorkspace notifications → the existing card panel
   ├─ raw.render(path, edits, px) CIRAWFilter → JPEG (export) and 100% view
   └─ thumbs: lumina://thumb/<id> served from a native cache (ImageIO)
```

## Rules
1. **Don't edit the HTML's layout, styles, copy or keys.** It is the spec and the UI. Changes happen in this project first, then get copied in.
2. **Change only the plumbing.** The places the page touches the browser are listed in `ADDENDUM-remove.md` §1. Each becomes one bridge call. Keep the same function names in the page (`openFolder`, `onDir`, `writeInto`, `renderJpg`, `download`) and change only what's inside them.
3. **Delete the demo layer**: sample shoot, key C, fake copy timer, zip downloads, "open in its own tab" copy, the preview-frame checks. List in `ADDENDUM-remove.md`.
4. **Keys**: WKWebView gets every key, so the host-key workarounds (`Proxy` X→E remap) go. Add the standard menu bar (File ▸ Open ⌘O, Edit ▸ Undo ⌘Z) wired to the same handlers.
5. **Performance**: add grid virtualisation (render only rows near the viewport) *inside the page*, and keep the styling the same. Serve thumbnails from the native cache, not blob URLs. Target 3,000 photos at 60 fps scroll on M1.

## Proving it's exact
- **Pixel diff**: for each screen in `screenshots/`, render the app's WKWebView at the same size with the sample data (debug build only) and compare. Allowed difference: 0 px outside photo areas.
- **Behaviour**: a scripted run of key presses (Open → Cull → R/X/B/⇧B/Space/G/A/V → Edit P/⇧P → Export ⏎). Same keys in the browser prototype and the app must give the same state JSON (`marks`, `final`, `auto`, `cuts`, `mem`).
- **Logic**: fixtures + golden data as in README.

## Throw away
Everything else in the repo and in older design files. Keep only: this folder, the native shell, the bridge, tests.

## App Store
WKWebView apps are accepted when they're a real native app (own window, menus, file access, offline). Sandbox entitlements: user-selected read/write files, removable volumes via bookmarks. No remote code: all HTML/JS is bundled.
