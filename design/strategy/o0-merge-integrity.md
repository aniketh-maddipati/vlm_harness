# O0 — W-cascade merge-integrity audit

## PRECONDITION AND MODE

**SHA read:** `dbd476685391a041ea5457cc77d840f3ae0cd488` (`origin/main`). The tree was clean: the final `git status --porcelain` in C0 printed no lines.

**MODE CHANGE:** the required P8.2 adjudication was measured at `f2e9ee3`; current main also contains `dbd4766` from PR #57. This audit therefore includes #57 as a post-cascade, non-W commit. The W merge set itself is unchanged from the adjudication.

**Six merges landed on main with no recorded compile, and the nine-row instrument reads static analysis of code nobody has built.**

Command C0:

```text
$ git fetch origin --prune --tags && git log --oneline -10 origin/main && git status --porcelain
dbd4766 build(C3): make a no-op FAST run leave the tree clean (#57)
f2e9ee3 Lightweight footprint: exclude harness from Release and defer P0 develop init (#55)
3f41c93 Clean up harness inventory and repeated scans (#54)
c7c999b harness: rebaseline gate-truth tests and allowlist for W cascade merge
e0d4473 Merge pull request #53: W8 legacy severance — lazy shell door and dead-code removal
25dcbef Merge pull request #51: W6 memory budget — RAM tier gate and bounded caches
30aa6a5 Merge pull request #50: W5 key-routing — one owner and one Esc ladder
137deaa Merge pull request #49: W4 motion wiring through sealed spring
90c075f Merge pull request #48: W3 cull grammar through CullGrammarMachine
a366d38 Merge pull request #47: W1 gate truth (orphan register, magic numbers, banned patterns)
<git status --porcelain printed no lines>
```

The common development base is `83ba118`; the actual integration-start SHA is `78309ec`, the first parent of W1's merge. C1 distinguishes them:

```text
$ git show -s --format='%h parents=%P subject=%s' 83ba118
83ba118 parents=a565c2e... subject=docs: refresh RESUME after P7/P5/P8 and #43/#44 merge cascade

$ git log --first-parent --oneline 78309ec..origin/main
dbd4766 build(C3): make a no-op FAST run leave the tree clean (#57)
f2e9ee3 Lightweight footprint: exclude harness from Release and defer P0 develop init (#55)
3f41c93 Clean up harness inventory and repeated scans (#54)
c7c999b harness: rebaseline gate-truth tests and allowlist for W cascade merge
e0d4473 Merge pull request #53: W8 legacy severance — lazy shell door and dead-code removal
25dcbef Merge pull request #51: W6 memory budget — RAM tier gate and bounded caches
30aa6a5 Merge pull request #50: W5 key-routing — one owner and one Esc ladder
137deaa Merge pull request #49: W4 motion wiring through sealed spring
90c075f Merge pull request #48: W3 cull grammar through CullGrammarMachine
a366d38 Merge pull request #47: W1 gate truth (orphan register, magic numbers, banned patterns)
```

## HEADLINE

**No merged feature commit or branch-delta path from W1, W3, W4, W5, W6, or W8 was wholly dropped; however, main is not exactly the seven-PR union: W5 carries patch-equivalent F11.6 commit `dcc6015` alongside PR #45 merge `78309ec`, W7 remains intentionally unmerged, `c7c999b` is a direct post-merge commit with no PR, and W8 carried the P8.2 document commit outside its build delta.**

## METHOD

All seven PR records are accounted for: #47 W1, #48 W3, #49 W4, #50 W5, #51 W6, #52 W7, and #53 W8. PR #46 is the four-commit W3 predecessor; #48 contains it and adds the ADOPT commit.

Command C2 resolved every merged PR as a two-parent merge commit whose second parent is the recorded branch tip:

```text
$ for c in a366d38 90c075f 137deaa 30aa6a5 25dcbef e0d4473; do
    git show -s --format='%h parents=%P subject=%s' "$c"
  done
a366d38 parents=78309ec... 8ef67e6... subject=Merge pull request #47: W1 gate truth (...)
90c075f parents=a366d38... d35eae1... subject=Merge pull request #48: W3 cull grammar (...)
137deaa parents=90c075f... 018ecaa... subject=Merge pull request #49: W4 motion wiring (...)
30aa6a5 parents=137deaa... f7bc9fe... subject=Merge pull request #50: W5 key-routing (...)
25dcbef parents=30aa6a5... 1a67da5... subject=Merge pull request #51: W6 memory budget (...)
e0d4473 parents=25dcbef... 8628307... subject=Merge pull request #53: W8 legacy severance (...)
```

| PR | Method | Verification technique |
|---|---|---|
| #47 / W1 (C2) | merge commit; second parent `8ef67e6` (C2) | exact ancestry, `git cherry`, and branch-file set versus first-parent delta (C3–C5) |
| #48 / W3 (C2) | merge commit; second parent `d35eae1` (C2) | exact ancestry, including PR #46 predecessor, plus file-set comparison (C3–C5) |
| #49 / W4 (C2) | merge commit; second parent `018ecaa` (C2) | true base `8ef67e6`; inherited W1 SHAs counted once (C3–C6) |
| #50 / W5 (C2) | merge commit; second parent `f7bc9fe` (C2) | own commit delta checked separately from `dcc6015`, which is patch-equivalent to already-landed PR #45 merge `78309ec` (C3–C6) |
| #51 / W6 (C2) | merge commit; second parent `1a67da5` (C2) | true base `f7bc9fe`; inherited W5 and PR #45 SHAs counted once (C3–C6) |
| #52 / W7 (C3) | open, unmerged; no merge commit (C3) | `git cherry` and reachability; its one file remains absent from main (C4–C5) |
| #53 / W8 (C2) | merge commit; second parent `8628307` (C2) | intended and landed 13-file sets, conflict-resolution audit, and retained probe fields (C5, C7–C8) |

No squash or rebase-and-merge method was found, so no squash tree-equivalence substitute was needed.

## COMPLETENESS TABLE

Command C3:

```text
$ git log --oneline 83ba118..<branch-tip>
W1: 8ef67e6, c1a6f4c
W3: d35eae1, cdd4f35, a9ec702, 8e49a58, 0b52323
W4: 018ecaa, 8ef67e6, c1a6f4c
W5: f7bc9fe, dcc6015
W6: 1a67da5, f7bc9fe, dcc6015
W7: 314ef1e
W8: 8628307, 78309ec, 6dd6997, 712fea9
```

Command C4:

```text
$ git cherry origin/main <branch-tip>
W1: <no lines>
W3: <no lines>
W4: <no lines>
W5: <no lines>
W6: <no lines>
W7: + 314ef1e55513195808ca23b20295776889328053
W8: <no lines>
```

Command C5 compared path sets changed from each branch's true base with paths changed by its merge result. It proves path presence, not blob equality:

```text
a366d38 base=83ba118 branch-files=14 merge-result-files=14 missing-branch-files=0
90c075f base=83ba118 branch-files=15 merge-result-files=15 missing-branch-files=0
137deaa base=8ef67e6 branch-files=22 merge-result-files=22 missing-branch-files=0
30aa6a5 base=83ba118 branch-files=24 merge-result-files=16 missing-branch-files=8
  the 8 are PR #45/F11.6 files already present in 30aa6a5^1; W5's own 16-file delta is complete
25dcbef base=f7bc9fe branch-files=13 merge-result-files=13 missing-branch-files=0
e0d4473 base=78309ec branch-files=13 merge-result-files=13 missing-branch-files=0
```

Command C6 ran `git merge-base --is-ancestor <sha> origin/main` for every branch commit, including W8's inherited `78309ec`, then counted exact SHA occurrences with `git rev-list origin/main`. All 15 distinct merged-range SHAs printed `reachable=YES` and `occurrences-in-main-dag=1`; `314ef1e` printed `reachable=NO`. Stable patch IDs additionally show `dcc6015` and `78309ec` are the sole patch-equivalent pair in the range (`b2d99027…`), so distinct-SHA occurrence is not evidence of unique content.

| Branch | Commits on branch | Reachable on main | `git cherry origin/main` `+` | Wholly dropped paths | Conflict-resolution paths |
|---|---:|---:|---:|---:|---:|
| W1 (C3) | 2 (C3) | 2 (C6) | 0 (C4) | 0 of 14 (C5) | 1 (remerge-diff) |
| W3 (C3) | 5 (C3) | 5 (C6) | 0 (C4) | 0 of 15 (C5) | 1 (remerge-diff) |
| W4 (C3) | 3, including 2 W1 SHAs (C3) | 3 (C6) | 0 (C4) | 0 of 22 from true base (C5) | 1 (remerge-diff) |
| W5 (C3) | 2, including patch-equivalent F11.6 SHA (C3/C6) | 2 (C6) | 0 (C4); merge-relative check marks `dcc6015` `-` and `f7bc9fe` `+` | 0 of 16 W5 paths (C5) | 8 (remerge-diff) |
| W6 (C3) | 3, including W5 and F11.6 SHAs (C3) | 3 (C6) | 0 (C4) | 0 of 13 from true base (C5) | 2 (remerge-diff) |
| W7 (C3) | 1 (C3) | 0 (C6) | 1 (C4) | 1: `BUILD_LOG.md`, intentionally unmerged (C4) | not integrated |
| W8 (C3) | 4, including its internal merge (C3) | 4 (C6) | 0 (C4) | 0 of 13 (C5) | 6 (remerge-diff) |

## CORRECTNESS FINDINGS

### Stacking

Command C9:

```text
$ git merge-base --all 83ba118 <branch>; git log --oneline 83ba118..<branch>
W1  base 83ba118: 2 W1 commits
W3  base 83ba118: 4 predecessor W3 commits + 1 ADOPT commit
W4  base 83ba118: 2 W1 commits + 1 W4 commit
W5  base 83ba118: 1 PR #45 commit + 1 W5 commit
W6  base 83ba118: 1 PR #45 commit + 1 W5 commit + 1 W6 commit
W7  base 83ba118: 1 W7 commit
W8  base 83ba118: W8 build + P8.2 doc + PR #45 main parent + internal merge
```

The four cross-session stacks are W4→W1, W5→the patch-equivalent F11.6 feature commit, W6→W5/F11.6, and W8→main/PR #45. W3→its own PR #46 predecessor is a same-owner predecessor. C6 prints one exact occurrence for each SHA, while the patch-ID check records the `dcc6015`/`78309ec` content duplicate. PR #50's effective first-parent delta excludes the already-landed F11.6 content, so it was not applied to the tree twice.

### W8's merge of main into itself

Command C7:

```text
$ git show -s --format='8628307 parents=%P subject=%s' 8628307
8628307 parents=6dd6997... 78309ec... subject=merge(main): resolve BUILD_LOG conflict — keep W8 and F11.6 entries

$ git diff --name-status 78309ec 8628307
$ git diff --name-status 25dcbef e0d4473
<both commands print the same 13 paths>
BUILD_LOG.md
Lumina/Testing/UITestStateProbe.swift
Lumina/Views/Components/DecisionDock.swift
Lumina/Views/LuminaButtons.swift
Lumina/Views/P0/P0LegacyShellDoor.swift
Lumina/Views/P0/P0RootView.swift
LuminaLogicTests/P0LogicTests.swift
LuminaUITests/Flows/OpenNavigationTests.swift
LuminaUITests/Robots/LuminaRobot.swift
LuminaUITests/Support/ProbeSnapshot.swift
Scripts/harness/lint/swift_reachability.py
design/strategy/legacy-disposition.md
design/strategy/surface-sweep.md
```

`git show --remerge-diff e0d4473` reports conflict resolutions in 6 files: `BUILD_LOG.md` and 5 probe/test mirrors. Command C8 verified the W3/W4/W5/W8 probe fields after resolution:

```text
$ rg -n 'pointerCullTargetsVisible|reduceMotionActive|keyRoutingOwner|legacyShellActive' \
    Lumina/Testing/UITestStateProbe.swift LuminaLogicTests/P0LogicTests.swift LuminaUITests
pointerCullTargetsVisible: present in app probe, logic test, UI probe, robot, navigation test
reduceMotionActive: present in app probe, logic test, UI probe, robot, navigation test
keyRoutingOwner: present in app probe, logic test, UI probe, robot, navigation test
legacyShellActive: present in app probe, logic test, UI probe, robot, navigation test

$ rg -n '^## 2026-08-13 — W(1|3|4|5|6|8)' BUILD_LOG.md
42:W8
92:W6
121:W5
144:W4
172:W3 ADOPT
193:W3 CP4
212:W1
```

OBSERVED: W8 changed exactly its 13 intended paths at the final merge, all earlier probe fields and all W log entries survive, and no W1–W6 path outside those 13 changed from `25dcbef` to `e0d4473`. No revert or revert-then-reapply of W1–W6 was found.

### Unattributed main commits

Command C10 combined C1's first-parent list with `gh pr list --state all --json number,title,mergeCommit`:

```text
78309ec -> PR #45, F11.6 prerequisite
c7c999b -> no PR
3f41c93 -> PR #54
f2e9ee3 -> PR #55
dbd4766 -> PR #57

$ gh pr list ... --jq 'select(.mergeCommit.oid == "c7c999b038f84bcb0d1eeb98e93465e739593618")'
[]
```

`c7c999b` is the sole direct main commit in the audited range. It changed 2 files:

```text
$ git show --stat --oneline c7c999b
c7c999b harness: rebaseline gate-truth tests and allowlist for W cascade merge
 Scripts/harness/tests/test_gate_truth.py     | 20 ++++++++------------
 artifacts/harness/magic_number_allowlist.txt |  3 +++
 2 files changed, 11 insertions(+), 12 deletions(-)
```

### Ownership

The original W prompts' exhaustive owned-path manifests are not stored on main or in PR bodies, so a full path-by-path ownership comparison is **UNRESOLVED** rather than inferred.

The ownership facts that are recoverable from commits and PR bodies are:

- W1's PR declares harness/register-only and its 14-file delta contains no product Swift (C5 plus `gh pr view 47 --json files,body`).
- W3 alone changes `Lumina/ViewModels/P0SessionModel.swift`; W2 has no ref or PR (C11 below).
- W4 discloses W1 as its base; C6 shows the two W1 SHAs once.
- W5 carries PR #45; W6 carries W5 and PR #45. Those inherited SHAs were already present or subsequently merged exactly once (C6).
- W8 carries `6dd6997 docs(P8.2)` and therefore lands `design/strategy/surface-sweep.md` through PR #53. That document commit is outside W8's build claim.
- W8 moves `LuminaQuietButtonStyle` from deleted `DecisionDock.swift` into `Lumina/Views/LuminaButtons.swift`. C16 finds 1 live-path hover at the new location, 18 style call sites across 7 P0 files, and no strict-lane coverage for the top-level view file. This is both an ownership finding and the contract conflict recorded below.

## W7 AND W2

### W7

Command C11:

```text
$ gh pr view 52 --json state,headRefOid,commits,files,body
state=OPEN
headRefOid=314ef1e55513195808ca23b20295776889328053
commits=1
files=[BUILD_LOG.md]
body status="PLANNED — not SCHEDULED"; CP8 gate="PARTIAL"

$ git cherry origin/main origin/cursor/w7-failure-grammar-39dd
+ 314ef1e55513195808ca23b20295776889328053
```

W7's facts-chip work is still CP8-gated, but its one stale-base `BUILD_LOG.md` planning commit should not merge. The PR is 25 commits behind main, conflicts in `BUILD_LOG.md`, and contains trailing whitespace. Closing versus retaining the planning PR is a process ruling; either choice must preserve the CP8 implementation door.

### W2

Command C12:

```text
$ git for-each-ref ... | rg -i '(^|[/_-])w2([/_-]|$)|part.?2' || echo NO_W2_REFS
NO_W2_REFS
$ gh pr list --state all --search 'W2 in:title' --json ...
[]
```

Command C13:

```text
$ git diff --name-status 78309ec..origin/main -- \
    Lumina/Services/ShootStore.swift Lumina/Persistence \
    Lumina/Services/ContactSheetPreparation.swift
<no lines>

$ for merge in a366d38 90c075f 137deaa 30aa6a5 25dcbef e0d4473; do
    git diff --name-status "$merge^1" "$merge" -- <the same paths>
  done
<no lines for all six merges>
```

No W2 branch or PR exists, and no partial W2 persistence-path change leaked through a merged W branch. W3's `P0SessionModel` work is the only overlap with the formerly shared W2/W3 model path.

## ARTIFACT AND MANIFEST INTEGRITY

Command C14:

```text
$ git tag --contains 78309ec
<no lines>
tags-containing-integration-start=0

$ git log --oneline --tags --no-walk
985ad2b Constitution: Batch 1 seal verify — agent-rules D63 + Phase 4 (#31)
0838579 h8: fixes — P keep key and decision-key repeat guard

$ gh release list --limit 100
<no lines>

$ git ls-tree -r --name-only origin/main | rg 'LuminaBuildManifest|\.dmg$|\.zip$|\.app/'
NO_SHIP_ARTIFACTS_IN_TREE
```

No tag, GitHub release, or ship artifact was cut during the audited range. The surface-sweep §5 stale-manifest rule therefore finds no artifact to block, but R3 remains required before any future wave cut.

Command C15:

```text
$ compare artifacts/harness/tokens.hash with the generated-header tokens-hash
ledger=1b1db60f4b927c6ba29f320508ebfe2f427a0eb1d6acef7f64051edff7b7158c
header=1b1db60f4b927c6ba29f320508ebfe2f427a0eb1d6acef7f64051edff7b7158c
match=YES

$ git ls-tree -d --name-only origin/main:artifacts/harness/goldens
1b1db60f4b927c6ba29f320508ebfe2f427a0eb1d6acef7f64051edff7b7158c
4165261bd21cd51478584549c48bebfc0c9868adfd4bcfe85431918d9780b375
666762f75cbf7b3a3302b044e89c68641fabd852a911039afc52d1067f557f89
```

The token ledger and generated header agree. There are 2 superseded hash directories containing 4 tracked files: 2 chrome-metric files under `4165261…` and 2 spring-trajectory files under `666762f…`. The current hash has 2 spring-trajectory files. No tracked build-cache directory exists. The 4 superseded files are reported, not deleted.

## VERIFICATION GAP

Command C17 searched every cascade BUILD_LOG entry:

```text
$ awk 'NR>=42 && NR<=233 {print}' BUILD_LOG.md |
    rg -n 'xcodebuild|LuminaLogicTests|BUILD SUCCEEDED|SUCCEEDED|PLATFORM-UNAVAILABLE'
W8 build: PLATFORM-UNAVAILABLE
W8 LuminaLogicTests: PLATFORM-UNAVAILABLE
W6 LuminaLogicTests: PLATFORM-UNAVAILABLE
W5 LuminaLogicTests: PLATFORM-UNAVAILABLE
W4 LuminaLogicTests: PLATFORM-UNAVAILABLE
W3 ADOPT LuminaLogicTests: PLATFORM-UNAVAILABLE
W3 CP4 LuminaLogicTests: PLATFORM-UNAVAILABLE
```

Command C18 searched PR bodies #47–#53:

```text
47 macOS xcodebuild / FULL: PLATFORM-UNAVAILABLE
48 LuminaLogicTests: PLATFORM-UNAVAILABLE
49 LuminaLogicTests: macOS required
50 LuminaLogicTests: macOS required
51 macOS ram_tier_runs + LuminaLogicTests required
52 <no build claim; planning-only>
53 xcodebuild build + LuminaLogicTests required on ship host
```

There is **no recorded successful compile or LuminaLogicTests run for any cascade branch or for the merged union**. BUILD_LOG contains older successful macOS builds, including the 2026-08-11 tree-compile session and pre-cascade P0 edit sessions; those do not compile the W union.

M1 therefore outranks P5, SPIKE C, and every remaining Swift session. The first Mac session must run, against current main:

```bash
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug build
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug \
  -destination 'platform=macOS' -only-testing:LuminaLogicTests test
python3 Scripts/harness/run.py full
```

It must also record at least one live P0 flow on an idle Apple Silicon Mac; FAST's orchestration-only result cannot close this gap.

## REMEDIATION

1. **BLOCKING — M1 macOS automation diagnostic.** Owner: M1. Run the three commands in VERIFICATION GAP and record one live P0 flow before P5, SPIKE C, or another Swift session.
2. **HIGH — direct commit `c7c999b`.** Owner: operator/O1. Record whether to accept it as a one-time integration reconciliation or route a non-destructive replacement through a PR. Recommendation: accept the content and record the protocol exception; reverting its gate expectations and three registrations is not justified by this git-only audit.
3. **HIGH — W8 hover relocation.** Owner: the already-named row-10 hygiene session from P8.2-ADJ. Remove the live hover and widen the strict lane; this audit performs neither.
4. **MEDIUM — W8 cross-session document commit.** Owner: strategy/O1. Attribute `6dd6997` explicitly to P8.2 in history and require future build PRs to exclude strategy-session commits.
5. **MEDIUM — W7.** Owner: CP8/W7. Do not merge PR #52 as-is. Operator may keep or close the conflicting planning PR, but implementation must be re-cut from then-current main when CP8 is scheduled.
6. **MEDIUM — stale hash-keyed goldens.** Owner: R3/golden bookkeeping. Re-measure or disposition the 4 files under 2 superseded hashes; do not delete them from this audit. R3 remains mandatory before a wave artifact.
7. **UNRESOLVED — exhaustive ownership manifests.** Owner: O1 process. Preserve each W prompt's owned-path list in-tree or in its PR body so future audits can compare paths without inference.

## RULINGS OWED

```text
RULING-OWED — c7c999b direct integration commit
OPTION A: accept the content and record a one-time protocol exception.
  COST: main retains a commit with no PR review record.
OPTION B: route a replacement/remediation through O1.
  COST: the current commit remains in immutable history; a revert would alter gate
  expectations and registrations and requires a separate measured session.
RECOMMENDATION: A. Git proves the commit reconciles W6/W8 gate expectations and
three literals; this audit found no dropped W content caused by it.
```

```text
RULING-OWED — W7 planning branch
OPTION A: keep PR #52 open and unmerged until CP8 is scheduled.
OPTION B: close the stale planning PR and create a new CP8-owned door record.
OPTION C: merge the planning-only BUILD_LOG commit now.
RECOMMENDATION: reject C. Git decides that the commit must remain unmerged; whether
to retain A as a visible door or choose B is an operator process decision.
```

## CONFLICTS

```text
CONFLICT — D48 versus the W8-relocated live button style
SIDE A: grep-verified contract-v6 D48 / R-X.1 says hover is deleted entirely and
no hover handlers may carry product information.
SIDE B: current main contains Lumina/Views/LuminaButtons.swift:147
`.onHover { hovering = $0 }`; the style has 18 call sites across 7 live P0 files.
COMMAND:
  rg -n '\.onHover' Lumina
OUTPUT:
  Lumina/Views/LuminaButtons.swift:147
  Lumina/Views/Workspace/ContinuousWorkspaceView.swift:722
  Lumina/Views/Workspace/ContinuousWorkspaceView.swift:839
  live-style-call-sites=18
  live-style-files=7
DISPOSITION: unresolved here. This is a git-only audit and performs no code or
harness remediation. Route to P8.2-ADJ row-10 hygiene before another Swift session.
```

No additional D/R conflict was found in the merge mechanics. D38 was grep-verified as “Doors, not deletions”; the W7 and stale-artifact recommendations preserve their doors.

## FOLLOW-UPS

- M1: compile current main, run LuminaLogicTests, run FULL, and record one live P0 flow.
- O1/operator: rule on `c7c999b` and W7 using the blocks above.
- Row-10 hygiene: resolve the D48 conflict without folding the change into this audit.
- R3: rebuild manifest-bearing release output only after the current token hash, before a wave cut.
- O1 process: store owned-path manifests with future PRs.
- This audit did not run FAST; C3 at `dbd4766` already records 37/37 and FAST is outside the merge-integrity question.
