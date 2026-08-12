# AUDIT-HIFI

Hi-fi pass audit gate v2 — static contract checks (H8).

**Summary:** 58/58 passed


## Copy

- **PASS** — design/copy-contract.txt present
- **PASS** — contract has ≥20 strings
  - 42 strings
- **PASS** — CopyContract.adaptedIndependently frozen in contract
- **PASS** — CopyContract.editedChip frozen in contract
- **PASS** — CopyContract.nothingLeavesMac frozen in contract
- **PASS** — CopyContract.dropPhotographsOrFolder frozen in contract
- **PASS** — CopyContract.groupingVisibleMotion frozen in contract
- **PASS** — CopyContract.copiesAutomatically frozen in contract
- **PASS** — CopyContract.copyingOriginals frozen in contract
- **PASS** — CopyContract.cullHeaderResume frozen in contract
- **PASS** — CopyContract.tableFooterHover frozen in contract
- **PASS** — CopyContract.tableFooterShortcuts frozen in contract
- **PASS** — CopyContract.editFooterShortcuts frozen in contract
- **PASS** — CopyContract.developThisPhotograph frozen in contract
- **PASS** — CopyContract.exportRecipeHint frozen in contract
- **PASS** — CopyContract.sovereigntyPlumbing frozen in contract
- **PASS** — CopyContract.fetchingFullRAW frozen in contract
- **PASS** — CopyContract.pointedFolderMoved frozen in contract
- **PASS** — CopyContract.fileDamagedPreviewOnly frozen in contract
- **PASS** — CopyContract.staleRender frozen in contract
- **PASS** — Banned words absent from user-visible strings (Develop allowed)
- **PASS** — Auto absent from user-visible strings
- **PASS** — Lightroom appears exactly once in user-visible strings
  - sovereignty wired=True, stray hits=0
- **PASS** — Sovereignty line in copy contract
- **PASS** — fetching full RAW in copy contract (loupe PL exception)
- **PASS** — No legacy pre-H1 staged/receipt strings
- **PASS** — Develop not in banned-words list

## Grammar

- **PASS** — Return/⏎ swallows isARepeat
- **PASS** — A swallows isARepeat
- **PASS** — P keep key present
- **PASS** — S/P keep swallows isARepeat
- **PASS** — X reject swallows isARepeat
- **PASS** — Crop latch re-scopes A (aspect) and X (flip, never reject)
  - Lumina/Views/Workspace/CommandHandlingModifier.swift:154
- **PASS** — Ripple widen/narrow ordering (widenPropagation + propagation.narrow on Esc)
- **PASS** — Exception persistence (wholesaleExcludedPhotoIDs Codable)
- **PASS** — Rubber-band has zero commit paths
- **PASS** — Chip drag has zero commit-on-drag paths
- **PASS** — Selection ring ≠ halo ring by token
- **PASS** — Latch surfaces answer banner + Esc (crop + staged banners present)

## Accessibility

- **PASS** — ⇧-arrow rubber-band extend in CommandHandlingModifier
- **PASS** — VoiceOver selection announcement present
- **PASS** — VoiceOver speaks ring scope / excluded counts
  - Lumina/Shell/WorkbenchSelection.swift:244
- **PASS** — Staged banner accessibility includes scope
  - Lumina/Views/Workspace/WorkbenchShelf.swift:162
- **PASS** — Shapes-not-color: selection ring uses HiFiTokens.Ring.selection
- **PASS** — Shapes-not-color: second-order halo uses HiFiTokens.Ring.secondOrderOpacity
- **PASS** — Reduced Motion over fill-up landing (tableBirth)
- **PASS** — Reduced Motion over ? glance
- **PASS** — Arm-then-A develop staging path exists

## Performance

- **PASS** — Fill-up landing uses tableBirth opacity path (not post-birth transitions)
- **PASS** — Fill-up landing respects reduceMotion (no blur storm)
- **PASS** — Staged preview scope resolves at shoot radius (PropagationState)
- **PASS** — Develop scheduler supports interactive + authoritative tiers
- **PASS** — Cold open latency instrumented (folder_to_first_paint)
- **PASS** — Cold open SLA target documented (< 1 s first paint)
- **PASS** — Table birth enabled on ingest rows (fill-up landing wired)

## Prompt-9

- **PASS** — HiFiTokens histogram 252×64
- **PASS** — No post-birth photograph opacity transition
- **PASS** — Ring distinctness asserted at runtime

All checks passed.
