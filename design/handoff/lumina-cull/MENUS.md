# Menus, Settings, About

Every command lives in the menu bar with its shortcut. The page receives them through `window.luminaCommand(name)`; each maps to the key it already handles.

**Lumina** · About Lumina · Settings… ⌘, · Hide ⌘H · Quit ⌘Q (asks if there are keepers not yet saved)
**File** · Open… ⌘O · Open Recent ▸ · Close Shoot ⌘W · Save Keepers ⌘⏎ · Show in Finder ⌘R · Remove Working Files…
**Edit** · Undo ⌘Z · Keep Row ⌘A
**Photo** · Keep P · Flag F · Keep Sharpest of Stack ⇧P · Flag Stack ⇧F · Open Stack ⏎ · Close Stack esc
**View** · Open ⌘1 · Cull ⌘2 · Save ⌘3 · Large View Space · Zoom 100% Z · Unseen Rows Only ⇧U · Smaller Tiles − · Larger Tiles + · Hide Key Bar H · Enter Full Screen ⌃⌘F
**Help** · Lumina FAQ · Keyboard Shortcuts ? · Contact on X

**Settings** · Keeper rating (1–5, default 3) · Auto-advance (on) · Tile size (144). Stored per user.
**About** · icon, "Lumina", version and build, "© 2026 Aniketh Maddipati", link to the FAQ.

**Command names for `window.luminaCommand`:** open · save · finder · undo · keepRow · keep · flag · keepStack · flagStack · openStack · closeStack · stepOpen · stepCull · stepSave · large · unseen · smaller · larger · keyBar · shortcuts · settings · faq
