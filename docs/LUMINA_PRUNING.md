# Lumina pruning ledger

Branch: `codex/pruning-lumina`, based on `9f7c92e5286bb5212f15d1875dd6bc63f66ff5e5`.
This is incremental source/artifact cleanup, not Git-history or worktree deletion.

## Method

Use a small, independently revertible commit for each evidenced removal. Check
application, test, harness, script and dynamic entry points before calling code
unused. Keep contract-deferred features and migration readers until their
replacement/lifecycle conditions are met. Preserve the command-center branch
and untracked coordination files when switching branches. Never force-switch
over edits or delete another task's worktree.

## Initial assessment

- Tracked files at the base: 588 files, 17,167,470 bytes. Design references account
  for 8,466,007 bytes; tracked artifacts 4,815,152; app sources/resources 1,891,935.
- Local allocated storage: `DD` about 756 MiB, `.derivedData` about 694 MiB,
  `artifacts` about 385 MiB and `.git` about 413 MiB. These are disk allocation
  readings, not app RAM or independent reclaimable-byte totals. No caches,
  historical evidence, branches or worktrees were deleted.
- The 5.99 MB hi-fi HTML is an actively referenced visual specification, not
  established dead weight. Keep it.
- The legacy disposition register identifies a compiled island but also retained
  propagation/export grammar and supported-install migration obligations.
  Static unreachability alone does not authorize removing that whole island.

## Slice 1: duplicate Workbench evidence

`four-up.png` and the historical `right-pane-enlarged.png` were byte-identical:
SHA256 `c125e0a658d1f6fd9380539184e12a89611b4812af2e3ca3699f102c7a628dfc`.
The capture source also used the same fixture, 1440×900 dimensions, 0.38 set
fraction and receipt setting for both names. No external consumer of the second
name was found. The distinct `divider-resized` and `wide-2560` scenarios remain.

Remove the redundant invocation and duplicate 188,550-byte PNG; retain
`artifacts/workbench-v6/four-up.png` as the canonical historical capture.
This reduces checkout evidence and one repeated harness capture. It does not
establish reduced shipping-binary size, app RAM, or faster editing, and does not
erase the old blob from Git history. Restore both removed pieces from the parent
commit if an actual consumer or distinct scenario is discovered.

Validation: pending. Vet was attempted immediately after the code change and
could not run without its provider credentials; no review pass is claimed.

## Slice 2: retired view declarations

Removed unused `LuminaFooterBar`, `P0AdjustmentRail`, and its sole helper
`P0RailSectionHeader`. Repository searches found no constructors for the rail or
footer; the live `ElasticFocusView` uses `ElasticDevelopDrawer`, and
`ELASTIC_PLAN.md` explicitly retires the rail accordion. The live edit slider,
crop controls, propagation, export and migration readers remain. Removed five
magic-number debt rows and one costume debt row that referred to deleted code.

## Footprint measurement repair

The existing script parsed the word `Segment` instead of its numeric size and
failed on the universal binary. It now selects the host architecture, reads the
numeric `__TEXT` segment size, fails closed on invalid output, records bytes and
architecture, and emits valid JSON with an actual trailing newline.

The resulting Release measurement: app allocated bytes 8,601,600; executable
bytes 8,582,560; arm64 `__TEXT` 3,162,112 bytes (3,088 KiB). There is no matched
before/after binary baseline, RAM result, or latency improvement claim.

## Validation checkpoint

- FAST: 41 orchestration checks PASS; zero app tests in this lane.
- Explicit `/private/tmp/lumina-pruning-DD` compile guard: PASS.
- Logic suite: 523 tests, five skipped, zero failures.
- Release footprint and shipping hook exclusion check: PASS.
- Full pre-merge regression: INCOMPLETE, zero of nine application checks ran;
  missing fixture configuration and existing STUB checks prevent acceptance.
- An initial logic invocation used a missing fingerprint-derived build path and
  failed to launch the test application. This was an invocation failure, not an
  assertion result; the stable explicit derived-data run subsequently passed.
- Vet cannot run without provider credentials. Independent read-only source review found no concrete regressions. Cache-free two-round merge stability and native validation remain
  outstanding; this branch is a reviewable cleanup candidate, not a merge claim.

Local logs: `/private/tmp/lumina-pruning-fast-final.log`,
`/private/tmp/lumina-pruning-compile-final.log`,
`/private/tmp/lumina-pruning-logic-final.log`,
`/private/tmp/lumina-pruning-regression.log`, and
`/private/tmp/lumina-pruning-footprint.log`.
