# Who does what: Claude Code, Cursor, Grok

One person, three tools. AGENTS.md's rules apply to all of them; this page only says which tool
takes which work and how they stay off each other's files.

## Claude Code (the lead)

Work that takes several steps, runs checks, or must follow the repo's process:

- **Page changes** (layout, copy, keys, empty states): the `page-ui-editor` agent. Edit
  `design/handoff/…`, copy byte for byte to `Lumina/Sets/Web/`, `python3 Scripts/page_bytes.py` 12 / 12.
- **The native bridge and trust rules**: `Lumina/Sets/Core`, `plumbing.js`, `SetsOffline.swift`,
  entitlements, `docs/release/TRUST.md`. Anything that could add reach to the app.
- **The Edit canvas**: `canvas-debugger` (measures first). The look maths (three copies, parity rules).
- **Tests on the Mac**: the probe, XCTest, anything through `Scripts/test_guard.py`. Bounded, alone,
  respects `~/LuminaEvidence/.tests-off`.
- **Hot builds**: `hot-build-pusher` (never stops another session's watcher).
- **Shipping**: `bash Scripts/ci_local.sh`, then `pr-shepherd` (one push, one PR, merges only when told).
  Release (`Scripts/release.sh`), notarisation, TestFlight.
- **Orchestration**: `Tools/agentloop` (below) runs from a Claude session and hands cheap read-only
  jobs to Grok.

## Cursor (the editor)

Work you do with your hands on the code, one file or a few:

- In-editor Swift / JS edits, quick refactors and renames inside one area.
- Reading and navigating code, asking about a function, jump-to-definition.
- Small fixes you can see the whole of before saving.

Cursor's rules (`.cursor/rules/lumina.mdc`) point it at AGENTS.md's rules that bite. Cursor does
not run the probe, sync the design, push or open PRs: hand that to Claude Code (`ci_local.sh`, then
`pr-shepherd`).

## Grok (cheap reads, through the loop only)

Read-only jobs with a lot of input and a short answer, routed by `Tools/agentloop`:
bulk code search and summaries, test / CI log triage, large-context reads (1M tokens on
grok-4.3), doc drafts, lint-fix proposals. Grok never writes to the repo itself: its answer is a
report, or a patch the loop applies only outside protected paths and then verifies with
`ci_local.sh`. Grok never sees page design work, the bridge, entitlements or trust files. Key:
Keychain service `xai-api-key`, read at run time.

## Not stepping on each other

- **One writer per worktree.** A Claude session owns its worktree (`.claude/worktrees/<name>`).
  Cursor edits a worktree no Claude session is writing in: open the main checkout or a worktree
  you made for yourself (`git worktree add ../lumina-cursor -b cursor/<topic> origin/main`).
- **One branch per piece of work**, off `origin/main`. Never two tools committing to one branch at
  once. To hand work over, commit (a WIP commit is fine) and say which branch.
- **Never bare `git stash`**: the stash is shared by every worktree. Use a WIP commit.
- **Hot builds have one watcher each**: `~/Library/Caches/com.lumina.dev/dev.lock` (Lumina Dev),
  Skim's in its own cache. A second `dev.sh` exits 75; ask the holder, never kill it.
- **The screen lock** (`~/LuminaEvidence/.screen.lock`): one screen-owning test at a time, from
  any tool. `.tests-off` is the owner's switch; no tool removes it.
- **One push per change**, after `bash Scripts/ci_local.sh` passes. Each push restarts a macOS run.
- **One merge owner.** Nobody merges unless the owner says so.
