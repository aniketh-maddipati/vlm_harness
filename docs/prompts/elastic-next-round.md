# Organizer — cut the next round of parallel prompts

## What this is

You are not fixing anything in the app. **Your deliverable is four or five prompt files**
in `docs/prompts/`, each one a self-contained stream that another agent will run in a
loop, on its own branch, at the same time as the others.

The round before you was three streams — P0 (render proof and the flip), P1 (grammar),
P2 (scroll) — written this way and run concurrently. It worked, and the two things that
made it work are the ones you must preserve: **every stream owns a disjoint set of
files**, and **every prompt is re-enterable**, because the conversation running it may
not survive.

Read `docs/prompts/elastic-p0.md`, `elastic-p1.md` and `elastic-p2.md` before you write a
line. They are the format. Read their **Progress** sections especially — that is where
the previous round recorded what turned out to be wrong, and a new prompt that repeats a
known-wrong diagnosis wastes a whole stream.

## Where you are

Repo: `/Users/aniketh/vlm_harness` (Lumina, native macOS photo culling app, Swift/SwiftUI).
Base branch for the round: **`elastic-v4/fixture-generator`**, unless the three streams
have landed by the time you run, in which case it is whatever they merged into. Check.

The lineage, oldest first:

```
596802c  checkpoint 03 (base)
1b74acc  Elastic surfaces match the prototype's own numbers   ← elastic-v4/checkpoint-03-elastic-shell
34f001d  Fixture cards generator
59d1cf7  Index assets by id; pin the orientation contract
596362a  Plan: the elasticity backlog
a4792c5  Prompts: loop-safe, and all three run at once        ← elastic-v4/fixture-generator
```

Streams of the previous round, each in its own worktree under `~/lumina-wt/`:

| Branch | Worktree | Theme |
|---|---|---|
| `elastic-v4/p0-render-proof` | `~/lumina-wt/p0-render-proof` | photo-pixel proof, the flip, three cheap P0s |
| `elastic-v4/p1-grammar` | `~/lumina-wt/p1-grammar` | keys, peeks, before, develop drawer |
| `elastic-v4/p2-scroll` | `~/lumina-wt/p2-scroll` (may be the main checkout) | scroll latency |

**`elastic-v4/model-assist` is superseded** — pre-ruling WIP that fails `banned_patterns`
on `URLSession.shared`. The constitution question it was parked on was answered by
**D67 / R-N.1, model inference is loopback-only**, which landed on
`elastic-v4/model-core` (branched from checkpoint-02, so it has none of the Elastic
shell). The two lineages both descend from `a034e52` and overlap in exactly two files:
`Lumina/ViewModels/P0SessionModel.swift` and `docs/ELASTIC_PLAN.md`. Reconciling them is
real work and a candidate for this round — see below — but it is a decision, not a
cleanup, so a prompt for it must say who decides what.

Also read `AGENTS.md`, `docs/ELASTIC_PLAN.md` (§6, the visual accuracy pass, and the
"Elasticity backlog"), and `docs/DEVELOP_ENGINE.md` if any stream you cut touches render.

## Step 1 — re-establish the facts before you write anything

**Every number in this file is stale by the time you read it.** Do not copy one into a
prompt. Measure, then write what you measured.

```bash
git branch -v --list 'elastic-v4/*'
git worktree list
for b in p0-render-proof p1-grammar p2-scroll; do
  echo "=== $b"; git log --oneline elastic-v4/fixture-generator..elastic-v4/$b
done
```

Then, in a worktree on the base branch:

```bash
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug -derivedDataPath DD -destination 'platform=macOS,arch=arm64' -only-testing:LuminaLogicTests build-for-testing
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug -derivedDataPath DD -destination 'platform=macOS,arch=arm64' -only-testing:LuminaLogicTests test-without-building
python3 Scripts/harness/run.py fast
```

Record the test count, the skip count and the fast-lane count. Those go into the **Gate**
section of every prompt you write, as that prompt's starting baseline. A stream that does
not know whether it started green cannot tell you whether it broke something.

Read the unchecked checklist items and the full Progress of all three previous prompts.
An unchecked item is either still open, or was closed and never ticked — check the
commits, not the box.

## Step 2 — decide what the round contains

Candidate sources, in the order you should mine them:

1. **Unchecked items in the three prompts.** Anything the previous round did not finish
   is the highest-value candidate, because it already has a written acceptance bar.
2. **The Elasticity backlog** in `docs/ELASTIC_PLAN.md` — the P1, P2 and P3 lists.
3. **Corrections in the Progress sections.** The previous round found several things the
   plan asserts that are not true. Those are not chores; they are open questions.
4. **"Known gaps in checkpoint 03"** in the plan.
5. **The two lineages.** `elastic-v4/model-core` versus the Elastic stack.
6. **The research branches** — `research/release-readiness`, `research/p0-ux-spec`,
   `research/grouping-eval` — which hold findings nobody has scheduled.

Rank by **what blocks what, not by size**. A stream that must wait on another stream's
unlanded code is a broken stream; if you cannot avoid the dependency, put both halves in
the same prompt or sequence the rounds.

As of this writing the obvious candidates were, and you must verify each is still open:

- **Develop drawer, crop, straighten, profile picker** (checkpoint 05). Large, coherent,
  and mostly its own files.
- **Hardening and edges** — the P3 `[edge]` list: offline originals, damaged file
  mid-card, disk full, two-card eject, duplicate basenames, byte-identical duplicates,
  filenames with spaces, sidecar date divergence, boundary values at exactly 2% / 0.5% /
  2 s.
- **Races** — the P3 `[dbg]` list: stale promotion after the cursor moves, scroll
  outrunning decode, eviction of a pinned tier mid-render, `⌘Z` during an in-flight auto
  pass, Lightroom rewriting a sidecar while the shoot is open.
- **Export and Lightroom handoff** — the receipt has no XMP sample line, the receipt
  never fades, `crs:CameraProfile` values Lumina never writes.
- **Lineage reconciliation** — model-core into the Elastic stack, or a ruling that it
  stays separate.
- **Release readiness** — footprint, shipping fence, the audit on
  `research/release-readiness`.
- **Fixture coverage for what the card does not cover** — orientations 2/3/4, square
  images, and anything a new stream needs that the generator cannot yet cut.

## Step 3 — split by file ownership, not by topic

This is the part that makes the round run in parallel, and it is the part that is easy to
get wrong. Do it explicitly:

1. For every candidate item, list the files it must touch. If you cannot name them, the
   item is not specified well enough to hand to a stream — specify it or drop it.
2. Group items so that **each stream's file set is disjoint from every other stream's**.
3. Where two items genuinely fight over one file, either put them in the same stream, or
   give the file to one stream and have the other stub behind its own type with a
   `// TODO(Pn):`.
4. Name the shared files explicitly and mark them **append only**: today that is
   `Lumina/Design/ElasticLayout.swift` and `docs/ELASTIC_PLAN.md`. Appending at the end of
   a section keeps merges clean; reflowing or renumbering does not.
5. Build the ownership table **from that grouping**. Do not copy the previous round's
   table — it described the previous round's split, and a stale table is worse than none,
   because streams trust it.

Every prompt gets the same table, so each stream can see what the others own.

## Step 4 — write each prompt in the house format

Sections, in this order. The three existing prompts are the reference implementation.

1. **Title** — stream id and a one-sentence goal that says what changes for the reader.
2. **Where you are** — repo path, the branch to create and off what, and the instruction
   to run `git branch --show-current` before every build and commit, and to stop if the
   branch moved. Several sessions share `/Users/aniketh/vlm_harness`; tell the stream to
   work in its own worktree under `~/lumina-wt/<name>`.
3. **What is already right — do not rebuild it.** Name the machinery that exists and the
   contracts that are correct. This section prevents the most expensive failure mode,
   which is a stream rewriting something that already works.
4. **Known-wrong diagnoses.** Name them, with the evidence that killed them. The previous
   round burned time on a theory that was already disproven in a doc nobody re-read.
5. **The work, in order** — numbered, each with a falsifiable acceptance bar. "Feels
   faster" is not one. "A test fails if X" is.
6. **Test data** — the fixture generator invocation and which card, including the trap
   that you open `<out>/card-elastic-v4/frames` and not the bundle root.
7. **Running this in a loop** — copy the block from any existing prompt verbatim. Confirm
   branch, re-read Progress, run the gate, do the next unchecked item only, commit it and
   update Progress in the same commit, stop when everything is checked.
8. **Working alongside the other streams** — the ownership table from step 3, plus the
   rules: touch a file you do not own only if you must and say so in the commit message;
   shared files are append only; never rename or move another stream's file; never rebase
   onto another stream's branch, only onto the base; stub what another stream is building
   behind your own type with a `// TODO(Pn):`.
9. **Gate** — the commands, and the baseline you measured in step 1.
10. **Rules that will bite you** — the durable list below, trimmed to what that stream can
    actually hit.
11. **Wrap up** — update `docs/ELASTIC_PLAN.md`, the commit attribution line, and **ask
    before pushing**.
12. **Checklist** — five to seven items, each independently committable.
13. **Progress** — empty, with the instruction to append one line per completed item:
    date, item number, commit sha, and anything the next pass needs to know, *especially
    anything in the prompt that turned out to be wrong*.

## Step 5 — the quality bar for each prompt

Before you call a prompt finished, check it against this:

- Every checklist item has an acceptance bar someone else could test.
- Any performance claim requires a measurement **before** the change, in the same shape
  as the measurement after it.
- Anything that must not be weakened is named. Lints and contracts outrank convenience:
  a lint and the code disagreeing means the code is wrong.
- What is out of scope is named, with whose it is.
- No item depends on another stream's unlanded code.
- Where a bug is involved, the prompt asks for a repro or a fixture first, and says what
  is *not* reproduced rather than implying it is understood.
- The prompt says what to do when the work turns out to be unnecessary or wrong —
  writing that down is a completed item, not a failure.

## The durable house rules — carry these into every prompt

- **Authority order:** contract-v6 → `tokens.yaml` → copy-contract → code → tests.
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.** Render/export-path types must be
  explicitly `nonisolated`, UI/session helpers explicitly `@MainActor`.
  `render_data_plane_isolation` enforces the structure; `xcode_compile.py` is the proof.
- **Magic-number lint** scans `Views`, `Design`, `Shell`, and skips lines mentioning
  `HiFiTokens`/`LuminaTokens` — do not exploit that. Route numbers through
  `ElasticLayout`. Only tokenize a value already in the forbidden set; never grow the
  allowlist.
- **Costume lint:** every `Button` needs a `Lumina*Style`; no bare `Text`/`Image` gets
  `.onTapGesture`.
- **Orphan lint** flags a symbol referenced only within its own file. Registering it
  claims it has no live wiring — delete the needless type instead of lying.
- **Banned:** `onHover`, `ProgressView`, `.alert`, anything network, and the word "sync"
  in copy.
- **Never `pkill -x Lumina`.**
- Project uses synchronized folders — new files are picked up automatically.
- **Motion goldens are keyed to the tokens hash.** Changing `design/tokens.yaml` fails
  `spring_physics_f07` until re-approved via
  `Scripts/harness/golden/service.py propose/approve spring_trajectory_place_return`.
  Re-approve with the *previous* payload unless motion genuinely changed — passing then
  proves the change was motion-neutral.
- **The repo squash-merges.** A stacked branch moves with
  `git rebase --onto origin/main <old-base-sha> <branch>`, never a plain rebase.
- Commit with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`, one commit per
  checklist item, and **ask before pushing**.

## Traps that have already cost time — carry these forward

- **A capture cannot show the photograph.** `Scripts/e2e_audit.swift` and
  `P0EditLiveRunner` host views offscreen and read them back with `cacheDisplay`; SwiftUI
  `.task` does not run for such a view and Metal layers do not composite through it. Every
  tile and every photograph is an empty well in a capture. Pixels are proved by
  `PhotoPresentProof` + `PhotoRenderProofTests`, not by looking at a PNG.
- **xcodebuild cannot put an environment variable into a hosted logic test.** Neither
  `TEST_RUNNER_LUMINA_RAW_DIR=` nor a plain `LUMINA_RAW_DIR=` reaches the process — both
  measured. The host app launches with a scrubbed environment. Fixture-gated tests resolve
  their folder from disk and skip when it is absent.
- **`Process` + `Pipe` deadlocks if you wait before you read.** `ExifToolService.runData`
  hung forever on any output past a pipe buffer. Read the pipe, then `waitUntilExit`, and
  send stderr to `nullDevice` rather than into a buffer nothing drains.
- **Adding a `ProbeSnapshot` field means five files.** Both probe sites plus the two
  full-init sites; the lints reveal them two at a time.
- **The Debug app sometimes launches with no window under automation.** It has bitten two
  streams. Budget for it rather than treating it as a one-off.
- **The fixture card carries orientations 1, 6 and 8 only.** No 2/3/4, no square frame, so
  anything relying on those needs a new fixture cut first.
- Several Claude sessions share `/Users/aniketh/vlm_harness`. Never switch its branch; give
  each stream its own worktree.

## Deliverable

- Four or five files, `docs/prompts/elastic-<name>.md`, in the format above.
- One short summary in your reply: the stream names, their one-line goals, the file each
  owns, and anything you deliberately left out of the round and why.
- Do **not** start any stream's work yourself, and do not push. Ask first.

## Checklist

- [ ] 1. Facts re-established: branch tips, unchecked items, Progress corrections, and a
  measured gate baseline on the base branch
- [ ] 2. Candidate work listed and ranked by what blocks what, with the files each item
  touches named
- [ ] 3. Streams split so every stream's file set is disjoint; shared files named as
  append-only; the ownership table built from that split
- [ ] 4. Prompts written, each with a loop section, a gate with the measured baseline, a
  checklist of five to seven independently committable items, and an empty Progress
- [ ] 5. Each prompt checked against the quality bar in step 5; summary reported; nothing
  pushed

## Progress

_Append one line per completed item: date, item number, commit sha, and anything the next
pass needs to know — especially anything here that turned out to be wrong._
