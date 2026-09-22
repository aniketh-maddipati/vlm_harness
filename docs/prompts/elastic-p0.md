# P0 — Make the photograph provable, then find the flip

## Where you are

Repo: `/Users/aniketh/vlm_harness` (Lumina, native macOS photo culling app, Swift/SwiftUI).
Branch: create **`elastic-v4/p0-render-proof`** off `elastic-v4/fixture-generator`
(`541119f` or later) and stay on it. Run `git branch --show-current` before every build
and commit. If the branch changes under you, stop and say so — something switched the
tree mid-session once before.

The stack, oldest first:

```
596802c  checkpoint 03 (base)
1b74acc  Elastic surfaces match the prototype's own numbers   ← elastic-v4/checkpoint-03-elastic-shell
34f001d  Fixture cards generator
59d1cf7  Index assets by id; pin the orientation contract
596362a  Plan: the elasticity backlog                          ← elastic-v4/fixture-generator
9745c9e  WIP model assist                                      ← elastic-v4/model-assist
```

All three branches are pushed to `origin`.

**`elastic-v4/model-assist` is superseded — do not build on it and do not open a PR for
it.** It is pre-ruling WIP that fails `banned_patterns` on `URLSession.shared`. The
constitution question it was parked on has since been answered: **D67 / R-N.1, model
inference is loopback-only**, landed on `elastic-v4/model-core` (`93862b5`), which also
deleted the hosted provider and amended `banned_patterns.sh` to permit loopback in one
sanctioned file while failing any non-loopback URL literal.

`elastic-v4/model-core` branches from **checkpoint-02**, so it does **not** contain the
Elastic shell or any of this stack. The two lineages both descend from `a034e52` and need
reconciling — that is a separate decision, not yours. They overlap in exactly two files:
`Lumina/ViewModels/P0SessionModel.swift` and `docs/ELASTIC_PLAN.md`. Leave `model-core`
alone, but know it exists and that its `race/edge/threat pass` and
`docs/security/MODEL_ASSIST_THREAT_MODEL.md` may already cover part of the P3 list.

Read `AGENTS.md` and `docs/ELASTIC_PLAN.md` (§6 and "Elasticity backlog").

## The task, in order

### 1. Make the photograph provable — do this first

Today **nothing verifies that the photograph renders at all**. `Scripts/e2e_audit.swift`
and `P0EditLiveRunner` host views offscreen and capture with `cacheDisplay`; SwiftUI
`.task` does not run for an offscreen-hosted view, and Metal layers do not composite
through `cacheDisplay`. So every capture shows an empty well, and the one thing a reader
actually looks at is the one thing the harness cannot see.

This blocks item 2, so it comes first.

Options, roughly in order of preference — pick after reading the code, and say which you
picked and why:

- Render the Metal path to an offscreen `CIRenderDestination`/`MTLTexture` in the runner
  and write that PNG alongside the chrome capture, so photo pixels get their own proof
  separate from the layout capture.
- Add a headless assertion that `DevelopRenderGraph` produces a non-blank image of the
  expected extent for a given asset + recipe, which does not need a view at all.
- Drive a real window via the existing XCUITest harness (see the P0 UI automation work,
  PR #19) and screenshot it.

Whatever you choose, the acceptance bar is: **a test fails if the photograph stops
rendering, comes out blank, or comes out the wrong way up.**

Do not weaken `progressive_render_architecture` to get there — it pins the no-remount
contract and it is right.

### 2. Find the flip

The user reports photographs "glitching and flipping upside down". It is **not**
reproduced and the first diagnosis was **wrong** — do not repeat it:

> `OrientedDisplayImage.aligning(_:toFile:)` decides whether to rotate by comparing
> extents, and orientations 2/3/4 do not change the extent. That looked like the bug.
> It is not: `CIRAWFilter` applies the file's orientation itself (verified — an
> orientation-8 ARW comes out of the decoder already 4000×6000), so `aligning`'s no-op
> is correct for all eight values. The hole is latent, reachable only by a backend that
> returns sensor-space pixels, and `libraw`/`rawspeed` are registered `linked: false`.
> `LuminaLogicTests/OrientationContractTests.swift` pins all of this.

So start from evidence, not from that file. Ask the user for a repro if you cannot
produce one: which frame, and whether it flips on open, on scroll, or at the moment RAW
promotion lands. Candidate paths worth instrumenting:

- `OrientedDisplayImage.stablePresent` — guards the aspect swap on promotion; check it
  actually holds for a portrait frame whose promotion arrives sensor-shaped.
- `DevelopMetalView`'s `destination.isFlipped = true` — the only Y conversion. Anything
  reaching it bottom-up instead of top-down inverts.
- `ciImage(fromOrientedPixels:)` assumes its input already has EXIF baked. Audit every
  caller for one that passes unbaked pixels.
- The doc comment at the top of `OrientedDisplayImage` describes a historical
  upside-down flash on click-through. Check whether that path is genuinely dead.

### 3. The three cheap P0s

These are **yours, not P2's**. Both touch `ElasticTableView.swift` and
`ElasticFocusView.swift`, which is where a later parallel P1 and P2 will both be
working — doing them once here is what keeps those two from colliding.

- **`ElasticWrapLayout` sizes every subview twice per pass**, uncached, in both
  `sizeThatFits` and `placeSubviews` (`Lumina/Views/P0/ElasticTableView.swift`). Tiles
  are fixed-width (`ElasticLayout.tile` 168 / `tileInOpenBurst` 128); return the known
  size instead of asking each subview.
- **Version thumbnails all read `gridThumbPath`**, so shot / auto / yours render
  identically while the column claims they differ. Either render them through the
  scheduler's interactive tier or stop implying a difference.
- **A cold catalog reports `previews 0/N`** while extraction runs; the second open
  reports `N/N`. Decide whether that is warm-up to surface honestly in copy, or a real
  miss. Reproduce with a freshly generated card (below).

## Test data

A generator exists — use it rather than hand-making folders:

```bash
python3 Scripts/harness/fixtures/elastic_cards.py \
  --raw-dir /Users/aniketh/jeevana_mehendi_raws \
  --phone-dir ~/Downloads/lumina_phone_pool \
  --out ~/LuminaFixtures --force
```

It cuts 27 frames into 8 moments covering all six light words, all three gap heights,
both label formats, a five-frame burst, a camera+phone moment, a crop/straighten A/B
pair, a long exposure, and a byte-identical duplicate pair whose second file has a space
in its name. It **verifies what it built** and fails if the card does not match its plan.

Frames land in `<out>/card-elastic-v4/frames` — open *that*, not the bundle root, or
`card.json` and `checksums.sha256` are counted as unsupported files.

Known-good pixel conditions in that card, already measured: `IMG_6426` has 3.64%
highlight clipping (clears the 2% tick, the 0.5% AutoDevelop threshold and the 2.67%
−80 saturation point) and 1.99% shadow clip (one hundredth under the tick);
`IMG_6420` has mean 0.551, the only frame that makes `AutoDevelop` darken.

## Running this in a loop

This prompt is written to be re-entered. Each time you start or wake:

1. `git branch --show-current` — confirm you are on your own branch. If it
   changed under you, stop and say so.
2. `git log --oneline -5` and re-read the **Progress** section at the bottom of
   this file. That is the only record of what you already did; the conversation
   may not survive.
3. Run the gate before changing anything, so you know whether you are starting
   from green.
4. Do the **next unchecked item only**, then commit, then update **Progress**
   in this file in the same commit.
5. When every item is checked and the gate is green, say so and stop. Do not
   invent more work — the other two streams own the rest.

Commit after every item, never in a batch. A loop that dies between items must
lose at most one item's work.

## Working alongside P0, P1 and P2

All three streams run **at the same time**, each on its own branch off
`elastic-v4/fixture-generator` (`541119f` or later). The Elastic views were
split by owner in `541119f` precisely so this works:

| File | Owner |
|---|---|
| `ElasticWrapLayout.swift` | **P0** |
| `ElasticVersionColumn.swift` | **P0** (pixels) and **P1** (hide under drawer) |
| `P0EditLiveRunner.swift`, `OrientedDisplayImage.swift`, `DevelopMetalView.swift` | **P0** |
| `ElasticSetShelf.swift`, `P0KeyRoutingModifier.swift`, `P0EscLadder.swift` | **P1** |
| `ElasticFocusView.swift`, `ElasticTableView.swift` | **P1** |
| `ElasticFilmstrip.swift`, `BrowsePixelService.swift`, `DevelopRenderScheduler.swift`, `PreparedRawSession.swift` | **P2** |
| `ElasticLayout.swift`, `docs/ELASTIC_PLAN.md` | **shared — append only** |

Rules that keep this collision-free:

- **Touch a file you do not own only if you must**, and say so in the commit
  message so the others can find it.
- `ElasticLayout.swift` and `ELASTIC_PLAN.md` are shared. **Append** at the end
  of the relevant section; never reflow or renumber, because that turns a clean
  merge into a conflict.
- Never rename or move a file another stream owns.
- Do not rebase onto another stream's branch. Rebase onto
  `elastic-v4/fixture-generator` only, and only when it moves.
- If you genuinely need something another stream is building, stub it behind
  your own type and leave a `// TODO(Pn):` — do not wait, and do not reach into
  their branch.

## Gate

```bash
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug -derivedDataPath DD -destination 'platform=macOS,arch=arm64' -only-testing:LuminaLogicTests build-for-testing
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug -derivedDataPath DD -destination 'platform=macOS,arch=arm64' -only-testing:LuminaLogicTests test-without-building
python3 Scripts/harness/run.py fast
```

Baseline on this branch: **285 logic tests, 2 skipped** (one is
`testRawDecoderAppliesFileOrientation`, which skips unless `LUMINA_RAW_DIR` is set — pass
it as `TEST_RUNNER_LUMINA_RAW_DIR=...`, since xcodebuild does not forward shell env to the
test process). Fast lane **41/41**. Live capture **29/31**; the two failures are
pre-existing and `main` scores 29/31 too.

## Rules that will bite you

- **Authority order:** contract-v6 → tokens.yaml → copy-contract → code → tests. A lint
  and the code disagreeing means the code is wrong, not the lint.
- **Magic-number lint** scans `Views`, `Design`, `Shell`. It skips lines containing
  `HiFiTokens` or `LuminaTokens` — do not exploit that. Route numbers through
  `ElasticLayout`. Only tokenize a value already in the forbidden set; never grow the
  allowlist.
- **Costume lint:** every `Button` needs a `Lumina*Style`; no bare `Text`/`Image` gets
  `.onTapGesture`.
- **Orphan lint** flags a symbol referenced only within its own file. Registering it is
  a claim that it has no live wiring — do not register something that is live; delete the
  needless type instead.
- **Banned:** `onHover`, `ProgressView`, `.alert`, anything network, and the word "sync"
  in copy.
- **Never `pkill -x Lumina`.**
- Project uses synchronized folders — new files are picked up automatically.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: render-path types must be explicitly
  `nonisolated`, UI/session helpers explicitly `@MainActor`. See AGENTS.md.

## Wrap up

Update `docs/ELASTIC_PLAN.md` — move what you finished out of the P0 list and record
anything you learned that contradicts what is written there. Commit with
`Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`. Ask before pushing.

## Checklist

- [x] 1. Photo-pixel proof: a test fails if the photograph stops rendering, comes out blank, or comes out the wrong way up
- [x] 2. Reproduce the flip (ask the user for a repro if you cannot)
- [x] 3. Fix the flip, or write down precisely what it is and why it is not fixable here
- [x] 4. `ElasticWrapLayout` returns known tile sizes instead of asking every subview twice per pass
- [x] 5. Version thumbnails render through the interactive tier, or the column stops implying a difference
- [x] 6. Cold-catalog `previews 0/N` — decided and either surfaced honestly or fixed
- [x] 7. `docs/ELASTIC_PLAN.md` P0 section updated, gate green

## Progress

_Append one line per completed item: date, item number, commit sha, and anything
the next pass needs to know — especially anything here that turned out to be wrong._

- 2026-09-22 · item 1 · commit "P0 item 1: prove the photograph actually renders" (sha recorded by the next item, since amending to write it here changes it) · Photo-pixel proof landed as a headless
  assertion (the second option), not an offscreen Metal capture. Reason: it needs
  no view, so it runs inside `LuminaLogicTests` on every PR, and it can assert on
  pixels instead of writing a PNG nobody checks. `PhotoPresentProof.positioned`
  now holds the aspect-fit/zoom/pan transform and `DevelopMetalView` calls it, so
  the proof measures the drawable's real geometry rather than a copy.
  `PhotoPresentProof.probe` renders to a CPU bitmap through a `CIRenderDestination`
  with `isFlipped = true` — the drawable's own flag — so buffer row 0 is the top of
  the photograph (measured, not assumed). Both negative controls were run: negating
  the present scale fails 3 tests, and turning off `CreateThumbnailWithTransform`
  fails 2. Gate after: **292 logic tests, 2 skipped**, fast 41/41.
- **The prompt's env instruction is wrong.** `TEST_RUNNER_LUMINA_RAW_DIR=` does
  *not* reach a hosted logic test; neither does a plain `LUMINA_RAW_DIR=` argument
  (both measured — the test still skipped). The host app is launched with a
  scrubbed environment, so only a scheme or test plan can set it. `LUMINA_RAW_DIR`
  therefore still skips `testRawDecoderAppliesFileOrientation` in the gate above.
  The new RAW proof resolves its folder from disk instead
  (`~/LuminaFixtures/card-elastic-v4/frames` first) and does run.
- Fixture card orientations, measured: 14 frames at 1, 6 at 6, 7 at 8. No 2/3/4
  and no square frame anywhere in it, so the latent P3 hole has no fixture.
- 2026-09-22 · item 2 · **a flip is reproduced**, in the browse tier, not in
  `OrientedDisplayImage`. `PreviewExtractor.extract` tries `extractWithImageIO`
  (orientation applied) and falls back to `exiftool -b -PreviewImage` when ImageIO
  cannot make a thumbnail. That fallback writes the embedded preview **verbatim**:
  measured on the fixture card, an orientation-8 ARW yields a 1616×1080 *landscape*
  JPEG carrying **no orientation tag of its own**. Nothing downstream can recover
  it — `cgImage(at:)` applies a transform that is a no-op on an untagged file, and
  `aligning` is never applied to browse-tier files — so the tile, the filmstrip and
  the focus fallback all show that photograph on its side. Re-measure with
  `xcrun swift Scripts/harness/develop/preview_orientation_repro.swift <raw-folder>`:
  **7 of 21 frames** in `card-elastic-v4` land sideways through that branch.
  Two things make it stick rather than flicker:
  1. `stablePresent` compares portrait-ness and **keeps the fallback** when the
     promotion disagrees, so the correct RAW render is rejected by the wrong
     browse pixels rather than replacing them.
  2. `extractBrowsePreview` returns early when the destination already exists, so
     a once-written sideways file survives every reopen.
  Reachability: the fallback runs only when ImageIO cannot thumbnail the RAW — a
  camera macOS does not know, or a truncated/partially copied file. Sony ARW on
  this host decodes fine, which is why this never reproduced from the UI. The
  other entry point, `extractBrowsePreview`, transforms on every branch and is
  clean; only `extract` is holed, reached from `DevelopEngine.ensureProxy` and
  `extractBest`.
- 2026-09-22 · item 3 · fixed in three places, and **the fallback path had a
  second bug that mattered more**: `ExifToolService.runData` called
  `process.waitUntilExit()` *before* draining the pipe, so any output larger than
  a pipe buffer deadlocked. An embedded preview is ~600 KB, so preview extraction
  did not produce a sideways photograph — it hung forever. Found because the new
  fixture test timed out at 3 minutes; it now runs in 1.1 s. The same call is used
  by `batchCaptureDates` with `-json`, which exceeds a pipe buffer at a few hundred
  frames, so this was a live hang on import for any decent-sized shoot. stderr was
  an unread `Pipe()` for the same reason and is now `nullDevice`.
  The orientation fix itself:
  1. `OrientedDisplayImage.uprightPreview(at:fromSourceAt:)` bakes the **source's**
     orientation into a tagless sensor-space preview. It leaves alone a preview
     carrying its own tag, and one already in the source's display shape — turning
     an upright picture is the same bug facing the other way.
  2. `PreviewExtractor.extract` uses it on the exiftool branch, and only re-encodes
     when something actually had to turn.
  3. `DevelopRenderGraph` now runs proxy-derived images through `aligning`, which
     heals a catalog that already holds a sideways proxy. It is a no-op on every
     proxy that is upright, which `testUprightProxyIsNotHealedIntoBeingWrong` pins.
  Files touched outside the ownership table, deliberately:
  `Lumina/Services/ProjectStore.swift` and `Lumina/Services/ExifToolService.swift`.
  Gate: **299 logic tests, 2 skipped**, fast 41/41.
  Visual proof rendered from LUM0005 (orientation 8) — sideways before, upright
  after — and sent to the user; regenerate with `Scripts/harness/develop/preview_orientation_repro.swift`.
  **Not touched:** `stablePresent`. Once the browse tier is upright the promoted and
  fallback shapes agree, so its latch never fires wrongly, and changing its
  signature would mean editing `ElasticFocusView.swift`, which is P1's.
- 2026-09-22 · item 4 · `ElasticWrapLayout` now measures each group **once per
  pass** (it was three times: arranging in `sizeThatFits`, arranging again in
  `placeSubviews`, then once more while placing). It uses a `Layout` cache, and
  the row arrangement is kept too when the width has not moved.
  **The prompt's framing does not survive contact:** "return the known size" is
  right only for a lone frame (`tile` 168). A collapsed stack is 168 **plus
  `stackPadding`**, and an open burst is `frameCount × tileInOpenBurst` plus gaps,
  so a constant would misplace two of the three group shapes. The measurement is
  also deliberately *not* cached across passes: leaning on a burst changes a
  group from collapsed to open **without adding or removing a subview**, and a
  stale size would lay the open burst on top of its neighbour.
  Proof it changed nothing visible: `--p0-edit-live` table captures before and
  after are **byte-identical** (sha256 `9132b462f0907980…`) over the 27-frame card,
  which contains lone frames, a collapsed ×5 burst and a camera+phone moment.
- 2026-09-22 · item 5 · took the second branch — **the column stops implying a
  difference**, because rendering the three versions through the interactive tier
  is on P2's list and touching `DevelopRenderScheduler` is not P0's to do.
  `ElasticVersionColumn.previewPath(for:)` returns the browse thumbnail for `shot`
  and nil for the other two. Reasoning: that thumbnail is the camera's own
  rendering of the frame, so it truthfully depicts `shot` and nothing else;
  `auto` and `yours` keep their plate until pixels exist that are actually theirs.
  A `// TODO(P2):` marks where the real previews plug in.
  Pinned in `progressive_render_architecture` (REQUIREMENTS + FORBIDDEN) so the
  column cannot quietly go back to drawing one thumbnail three times; the same
  commit pins the render proof's `isFlipped` destination and the present transform
  living outside `DevelopMetalView`. **Note for the other streams:** this edits
  `Scripts/harness/lint/progressive_render_architecture.py`, appending keys only.
  Not capture-visible: `ChapterPlateImage` loads in `.task`, which does not run for
  an offscreen-hosted view, so every version tile is an empty well in a capture
  either way. That is the same limitation item 1 exists to route around.
- 2026-09-22 · item 6 · **decided: warm-up, and the count was never wrong.**
  Measured by consuming the real preparation stream over a freshly copied
  27-frame card with no catalog and no cached previews:

      3 ms  0 photos                        (discovering)
     10 ms  27 photos · previews 0/27       (sheet opens, nothing extracted yet)
    381 ms  27 photos · previews 16/27      (first chunk — `previewConcurrency` is 16)
    500 ms  27 photos · previews 27/27
    500 ms  27 photos · 27 previews

  So `0/N` is a real state that lasts as long as the first chunk takes, not a
  miss, and the second open reads `N/N` simply because the previews are already
  on disk. The chunk is 16 wide whatever N is, so the window does not grow with
  the card — it grows with per-file extraction cost.
  What was wrong was the copy: at the instant the sheet appears, `previews 0/27`
  reads as a stall rather than as work starting. It now says `previews…` until
  there is a count to report, which is the idiom the same line already uses for
  `dates…`. Pinned by `ColdOpenStatusTests`, including a cold open that asserts
  the count only rises, ends at N/N, and is never announced as a fraction of zero.
  **Note for the other streams:** this edits
  `Lumina/Services/ContactSheetPreparation.swift`, which no stream owns.
  The copy-contract lint covers `Lumina/Design/CopyContract.swift` only, so this
  string is not contract-pinned; the fast lane is green either way.
- 2026-09-22 · item 7 · `ELASTIC_PLAN.md` gets a **`#### P0 stream — closed`**
  block appended inside the P0 section. The finished bullets are left where they
  are rather than moved out: P1 and P2 are editing this file at the same time and
  reflowing a list they also touch is how a clean merge becomes a conflict. The
  diff is 52 insertions, 0 deletions. **Keys are not migrated** is the one P0
  bullet still open, and it belongs to P1.
  Final gate: **303 logic tests, 2 skipped, 0 failures · fast lane 41/41.**
  Live capture, same fixture card, same default settings, measured both ways:
  **base `a4792c5` 27/31 · this branch 29/31.** The two checks that flipped to
  passing are "RAW preview presents without blank canvas" and "Progressive
  fidelity is monotonic", and the authoritative long edge went 1658 → 2212 of
  2560 — all consistent with preview extraction no longer deadlocking. The two
  that still fail, "Quality promotion keeps geometry stable" and "Authoritative
  preview reaches drawable target", fail on the base commit too.
  Note the prompt's 29/31 baseline was measured on a different shoot; on this card
  the base is 27/31, so compare within a card, not across.
  **Still open for the user:** whether this is the flip they saw. If their frames
  are Sony and ImageIO decodes them, something else is also wrong — the question
  to ask is which frame, and whether it flips on open, on scroll, or at the moment
  RAW promotion lands.
