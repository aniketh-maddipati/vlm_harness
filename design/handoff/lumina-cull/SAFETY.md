# Safety requirements

1. **Sidecar writes.** Write to `name.xmp.tmp` in the same folder, fsync, then rename over the target. If a sidecar existed, copy it to `name.xmp.lumina-bak` first. Read the file back and compare before reporting success.
2. **Autosave.** Persist marks, flags, seen rows, cuts and the cursor every 2 s and on every view change, keyed by folder path + file list (plumbing.js). Reopening restores the cursor.
3. **Card removed.** On unmount call `window.luminaCardGone(true)`; keep state; on remount call `luminaCardGone(false)` and reload the shoot.
4. **No writes to cards.** Set `lumina.readingCard` for any mounted removable volume; Save stays disabled with the copy-first message.
5. **Permissions.** On a permission error call `window.luminaAccess(true, volumeName)`. Provide `lumina.openSettings('files')` (opens Privacy & Security → Files and Folders), `lumina.checkAccess()` → boolean, `lumina.reopen()`. The page re-checks when the window regains focus.
6. **Errors.** Disk full, read-only folder, locked or missing file: each shows in the result list as `DSC03311 · reason`; nothing is retried silently.
7. **Sandbox.** App Sandbox with user-selected read-write, security-scoped bookmarks for recents, no network entitlement.
8. **Signing.** Developer ID, notarised, hardened runtime.
