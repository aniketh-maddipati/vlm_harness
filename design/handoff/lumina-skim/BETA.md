# Skim beta release: a build he can open and keep up to date (branch video/skim-beta) — DRAFT

Draft written by the orchestration thread from the user's brief on 2026-10-08; the first chat here should correct it.
Worktree `~/vlm_harness/worktrees/skim-beta`, cut from `video/skim-mvp`. Read THREADS.md and FRIEND-DEMO.md (item 3) first.

## Goal
A Release build of Lumina Skim the friend can download, open without warnings, and that updates itself.

## Work, in order
1. **Release build with its own bundle ID.** Today Skim is Debug only (`LUMINA_PAGE=skim`, SetsPage). Add a Release
   path (scheme or target "Lumina Skim"), separate bundle ID, so it sits beside Lumina.
2. **Developer ID signing and notarization.** Scripts for sign, notarize, staple, and a DMG.
   **Stop and ask the user before anything that uses their Apple credentials** (certificates, app-specific
   password, notarytool profile, team ID). Write the scripts so they read a keychain profile and never a secret.
3. **Sparkle updater.** Signed appcast (EdDSA), fixed feed address, updates checked by signature.
4. **Live page.** The page fetched only from one fixed address and signed by us; the app verifies the signature
   before loading and falls back to the bundled page. No other host, ever.
5. **Send report.** The session log saved to a file the user chooses and sends themselves; nothing is uploaded.
6. **One-command release script.** Build, sign, notarize, staple, DMG, appcast entry; dry-run by default.

## TRUST.md
Skim's rule is no network in the app. Items 3 and 4 are the exception: write it into `docs/release/TRUST.md`
exactly (the two fixed addresses, what is fetched, how each is verified, what is never sent), and teach
`Scripts/trust_check.py` to allow only those and still fail on anything else.

## Owns
The Release target, Scripts for release, the updater and live-page loader, Send report. Not the page's sorting
features. Merge video/skim-mvp before page edits; keep the two page copies byte-equal.

## Tests
Signature checks (good, tampered, wrong key, wrong host) as pure logic; `trust_check.py` passing and failing cases;
the release script's dry run in CI. Notarization itself only on the Mac, with the user's go-ahead.

## Open questions for the user
- The bundle ID and the two fixed addresses.
- Where the DMG and appcast are hosted (the existing Cloudflare Pages project, or elsewhere).
