# P0 — Make the photograph provable, then find the flip

## Where you are

Repo: `/Users/aniketh/vlm_harness` (Lumina, native macOS photo culling app, Swift/SwiftUI).
Branch: **`elastic-v4/fixture-generator`**. Run `git branch --show-current` before every
build and commit. If the branch changes under you, stop and say so — something switched
the tree mid-session once before.

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

## How these three fit together

Run **P0 alone first**, branched off `elastic-v4/fixture-generator`. It is small, it
unblocks visual verification for the other two, and it carries the user-visible bug.

Once P0 lands, **P1 and P2 can run in parallel** off its tip: P1 is keys, the Esc ladder
and the drawer; P2 is `BrowsePixelService` and `DevelopRenderScheduler`. Their overlap in
the view files is small *only because P0 already took* the wrap-layout caching and the
version thumbnails — do not move those around.

```
fixture-generator (596362a)
        └── P0
              ├── P1
              └── P2
```

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
