# Q4 · Hostile and damaged input

2026-10-01, at `5ed40ee` (main `bcac1f9` + PR #172, S3 input bounds), macOS 26.5.2, Apple silicon,
24 GB. Stress matrix section 7; threat model T1, T5, T6, T8. This measures and adds tests; it fixes
nothing. (Since then: F1, F2 and F10 are fixed by Q4a, `8cbabf0`; see "Q4a" below.) Every input is synthetic or a mutation of one, except the RAW decoder run, which also
mutates two fixture ARWs (see part 3); those stay in `~/LuminaEvidence/hostile`, never in the repo.

## Summary

| Part | Cases | Crash | Hang (> 5 s) | Memory spike | Wrong status / refusal | Write outside |
|---|---:|---:|---:|---:|---:|---:|
| 1 · Bridge op table (`SetsBridgeOpsTests`) | 1,303 table calls + 7 structured tests (~10,200 items) | **4 inputs** (F1, F2), fixed by Q4a | 0 | 0 | 2 open (F7, F8) | 0 |
| 2 · Head and preview-range fuzzer | 20,000 (2 seeds × 10,000) | 0 | 0 | 0 | 0 | n/a |
| 3 · Decoder mutation (sandboxed helper) | 10,000 JPEG + 2,000 ARW | 0 | 0 | 0 | n/a | n/a |
| 4 · XMP, names, volume labels (probe, app mode, plain + sandboxed) | 3 scenarios, 8 sidecars, 12 names, 5 labels | 0 | 0 | 0 | 3 (F3, F4, F5) | 0 |

Nothing in a file name, sidecar or volume label ran: no alert, no `<img src=x>`, no markup in the
DOM, in any run. Nothing was written outside the run's folder. No Apple decoder crashed.

## Findings

| # | Severity | What | Evidence | Proposed task |
|---|---|---|---|---|
| F1 | Medium, **fixed** (Q4a, `8cbabf0`) | `canvasLook` with `seq` = `1e300`, `Infinity` or `NaN` stops the app: `Int(body["seq"] as? Double ?? 0)` traps (`SetsBridge.swift:482`). Needs a page that sends it (T3, or a page bug). | `~/LuminaEvidence/hostile/bridge-crash/seq{Huge,Inf,NaN}.{log,ips}`; `run.sh bridge-crash` | Q4a |
| F2 | Medium, **fixed** (Q4a, `8cbabf0`) | `canvasLayout` with `w`/`h` = `1e308` on the native canvas stops the app: `Int(px.width)` traps (`LookCanvas.swift:255`). | `bridge-crash/layoutInf.{log,ips}` | Q4a |
| F3 | **High** (function) | A RAW whose name has a space is **unreadable** in the app: plumbing's `media()` builds `lumina://app/media/head?p=…` with `URLSearchParams`, which writes a space as `+`; `SetsSchemeHandler.media` reads `queryItems`, which keeps the `+`, so the file is "not in an opened folder" (404). `renderURL` already avoids this (`plumbing.js:582`). Renamed shoots ("Wedding 001.ARW") lose every photo. | `probe-2/hostile-names/names-read.json` (`n 9, bad 2`: `📷 ceremony 🔥.ARW`, `<img src=x onerror=alert(1)>.ARW`), `names-unreadable-list.png` | Q4b |
| F4 | Low | A sidecar name over 234 bytes can't be written: the temp file `.<name>.lumina-tmp-XXXXXXXX` is 21 bytes longer and hits `ENAMETOOLONG`; the reason says only "failed". The same pattern is in the copy path (`SetsFileOps.swift:247`) and `.lumina-bak` adds 11. | `probe-2/hostile-names/names-saved.json` (`8 saved · 1 failed`, the 255-byte name) | Q4c |
| F5 | Medium (A2) | A sidecar that is not UTF-8 is dropped from the listing silently (neither in `xmp` nor `skippedXmp`), so the page thinks the photo has none and Save **replaces it with a fresh ratings-only sidecar**. Its old content (here a Latin-1 label and `crs:Exposure2012`) survives only in `.lumina-bak`; Lightroom, reading the new file, loses the develop settings. | `probe-2/hostile-xmp/`: `DSC00107.xmp` (350 B, rating only) vs `DSC00107.xmp.lumina-bak` (393 B, the original); bridge log `listed 8 ARW + 6 xmp` for 7 sidecars | Q4d |
| F6 | Low (probe) | With #172, a sidecar over 1 MB counts as one "unreadable" in the page's import notes, and the probe's read invariant (read + unreadable = listed) then fails every step of any scenario with one. The page also says "1 unreadable" for a photo that read fine (Prompt 6 wording). | `probe-1/hostile-xmp/` (every step: `8 read + 1 unreadable ≠ 8 listed`) | Q4e |
| F7 | Low (T5) | `shootOpened` stores `date` and `n` from the page in `index.json` at any size: a 10 MB date gives a 10.5 MB index, rewritten on every upsert and session summary. | `SetsBridgeOpsTests.testShootOpenedFieldsAreBounded` (expected failure, prints the size) | Q4f |
| F8 | Low (T8, known) | `reveal` takes any absolute path that exists (here a canary outside the shoot). | `testEveryOpEveryFieldEveryHostileValue` (expected failure, names S4) | S4 (existing) |
| F9 | Low (design) | `LuminaCore.mergeXmp` leaves a sidecar with no `<rdf:Description` unchanged: Save writes it back without a rating and reports it saved. Measured on the page's code only (`fuzz.mjs xmp`: `no-description`, `binary` → `ratingSet: false`), not end to end. | `~/LuminaEvidence/hostile/xmp.noindex/xmp-page.json` | Q4g |
| F10 | Medium, **fixed** (Q4a, `8cbabf0`) | Found while sweeping the bridge's numbers for Q4a: `setPrefs` with a `NaN` or `Infinity` anywhere in `prefs` stops the test process. `JSONSerialization.data(withJSONObject:)` raises `NSInvalidArgumentException` ("Invalid number value (NaN) in JSON write") instead of throwing, through a Swift async frame (`SetsBridge.savePrefs`). The table never hit it: it fed `prefs` whole values, not a dictionary with a number inside. | `~/LuminaEvidence/hostile/bridge-crash/prefsNaN.ips` (SIGABRT in the test host, before the fix); `testSetPrefsRefusesNumbersJSONCannotHold` | Q4a |

### Fixed since (F4, F5, F7)

- **F5, fixed.** `SetsIngest.list` names a sidecar that is not UTF-8 in `unreadableXmp` (beside
  `skippedXmp`); `plumbing.js` counts it with the page's unreadable files and gives its photo the
  sidecar's own path; `SetsFileOps.writeSidecar` refuses to replace a sidecar on disk that is not
  UTF-8, whatever base comes with the write, with the reason `unreadable`
  (`SetsFileOps.sidecarUnreadable`). The file stays byte for byte as it was and no backup is made.
  Tests: `SetsSidecarTests.testListingNamesASidecarThatIsNotUTF8`,
  `testSidecarThatIsNotUTF8IsNeverReplaced`; `Tests/web/plumbing-harness.mjs` "unreadable sidecar:";
  `hostile-xmp` now expects `6 saved · 2 failed` (`DSC00107 · unreadable`, `DSC00108 · over 1 MB`)
  and `DSC00107.xmp` equal to the fixture. The wording is a design ask (DESIGN-ASKS, last prompt).
  Not changed: the bridge's log line still reads `listed 8 ARW + 6 xmp … · 1 xmp over 1 MB skipped`
  and does not count the unreadable one.
- **F4, fixed.** Temp files are `.lumina-tmp-<tag>-<8 hex>` (37 bytes; `<tag>` = 16 hex of the
  SHA-256 of the final name), so the temp name fits beside any name. `SetsExportJournal.recover`
  removes a temp file only when its tag is a planned name's or that name's `.lumina-bak`'s (a
  numbered copy keeps the planned name's tag), and still recognises the old
  `.<planned name>.lumina-tmp-*`. `ENAMETOOLONG` now reads `name too long`. Left as it is: a sidecar
  name over 244 bytes can be written once but not replaced, because its `.lumina-bak` cannot be
  named; nothing is replaced and the reason says `name too long`. Tests:
  `SetsFileOpsTests.testTempNamesHaveAFixedLengthAndATag`, `testNamesOf255BytesAreWrittenAndCopied`,
  `testRecoveryRecognisesItsOwnTempNames`, `SetsSidecarTests.testSidecarWithA255ByteNameIsWritten`;
  `hostile-names` expects `11 saved`. Its `*.xmp` count step expects 10: the probe's glob cannot
  match `line\nbreak.xmp` (`*` becomes `.*`, which stops at a newline), a probe fix still to make.
- **F7, fixed.** `SetsShootStore` bounds every string it writes to `index.json` in its one `write`
  (`Cap`: `firstCapture` 32 characters, `title` and `last` 255); `shootOpened` drops a body whose
  model name is over 64 bytes (or whose path is over 4096) and takes at most 16 bodies, so a 10 MB
  key no longer reaches `Lumina.json`. `n` is not clamped (numbers belong to Q4a). Test:
  `SetsBridgeOpsTests.testShootOpenedFieldsAreBounded`, no longer an expected failure.

Not findings, checked: `..`, absolute paths, NUL bytes and 10 MB names into `writeSidecars`,
`readSidecars`, `writeInto`, `saveSession`, `removeShoot`, `workingFiles`, `reopen` are all refused
(a NUL name comes back "missing", it is never truncated into the RAW's name); `readSidecars` never
returns a byte from outside the opened folder; T1 holds (`isID` on every id). The 500 MB sparse
sidecar is skipped unread (probe process peak 31–37 MB, web 237–252 MB) and Save refuses it
("over 1 MB"). The entity bomb and the external entity are never expanded or fetched: nothing in the
app parses XMP as XML (no `XMLParser` in `Lumina/`; the page merges with regexes). Script text in
sidecar fields stays escaped text in the file. 10,000 nested elements merge in 0.03 ms.

## Part 1 · Bridge op table

`LuminaLogicTests/SetsBridgeOpsTests.swift`. A `WKScriptMessage` subclass that overrides `body`
reaches `SetsBridge.userContentController(_:didReceive:)` exactly as WebKit calls it: no seam needed.

- **Table:** 29 ops (all but `openSettings`, which opens System Settings) × each field the op reads
  × 27 values: null, 42, −1, `Int.max`, `Int.min`, 1e308, `true`, "", `../../outside/<marker>`,
  `shoot/../../../../tmp/<marker>`, absolute paths (one to an existing canary), a NUL inside a
  `.xmp` name, 10 MB, non-hex and upper-case 16-char ids, `../../../outside` as an id, an array, a
  dictionary, an RTL override, newline + markup, emoji; and `Infinity`, `−Infinity`, `NaN`, `1e300`,
  `−0`. Plus missing everything and 8 malformed messages (not a dictionary, no op, a 10 MB op). 1,303 calls.
- **Structured:** `writeSidecars` with 24 hostile names; `readSidecars` with 10 escaping names;
  `writeInto` with 14 hostile names / sources, the destination a temp folder; 60 hostile preview
  ranges into `prefetch`, `near`, `canvasEnter`, plus 10,000 junk items in one `prefetch`; canvas
  rects and ROIs with every non-finite number on the image path; `shootOpened` with a 10 MB date.
- **Holds:** the process survives; files outside the store and the export folder are byte-identical
  after every call; no file with the run's marker appears in the run's parent, `/tmp` or `~`;
  refusals come back as false / null / 0 / an error.
- At the time of the run, `testCrashingInputs` ran one trapping input per process, only with
  `LUMINA_BRIDGE_CRASH_CASES` (`run.sh bridge-crash`): seqHuge, seqInf, seqNaN, layoutInf trapped
  (F1, F2); loupeInf survived (the synthetic RAW never gets a base, so the region code is not
  reached). Q4a removed the gate and the mode: the same inputs run in the normal pass (see "Q4a").
- `setPrefs` writes the host app's defaults (`com.lumina.app`); the test puts the value back.

### Q4a · numbers from the page (F1, F2, F10 fixed, `8cbabf0`)

Every number a bridge op or a `lumina://` query reads goes through `SetsNumber`
(`Lumina/Sets/Core/SetsNumber.swift`): a number (never a boolean), finite, in the field's range;
otherwise the field's default (what a missing field gets) or, where stated, the nearest end.

| Field | Where | Range | Outside it |
|---|---|---|---|
| `o`, `l` (preview range) | `prefetch`, `near`, `canvasEnter` previews; `media/*` and `render` queries | 0 … 2^32 − 1 (an ARW is a TIFF: 32-bit offsets) | 0 → "no preview range" (422), as an unreadable value always was |
| `ori` | the same | 0 … 65535 (EXIF SHORT) | 1 |
| `seq` | `canvasLook`; `render` query | 0 … 2^53 − 1 (JS's largest exact integer), whole | 0 |
| `t` | `canvasLook` | 0 … 1e13 ms | nil (latency from arrival) |
| `x`, `y` | `canvasLayout` | ± 32,768 CSS px | the rect is refused: canvas hidden, size kept |
| `w`, `h` | `canvasLayout` | 0 … 16,384 CSS px (twice an 8K display; Metal's texture edge) | the same |
| `dpr` | `canvasLayout` | 0.5 … 8, clamped | not a number: 1 |
| `roi.x`, `roi.y` | `canvasLook`, `canvasLoupe` | − 8 … 8 (fractions of the frame) | no region |
| `roi.w`, `roi.h` | the same | 0 (exclusive) … 8 | no region |
| `n` | `shootOpened` | 0 … 100,000 (`SetsIngest.Limits.entries`) | 0 |
| `summary.n`, `.dec`, `.kp` | `saveSession` | 0 … 100,000 | the stored count stays |
| `look.px` | `writeInto` | 1 … 65,536 (larger clamps: a develop never upscales) | nil, full size (as ≤ 0 always was) |
| `px` | `render` query | 64 … 8192, clamped (as before) | 1024 |
| `decoder` | `render` query | 1 … 99 | nil, the default decoder |
| numbers inside `prefs` | `setPrefs` | whatever JSON holds | the settings are refused whole (false), nothing stored |

`LookCanvasController.layout` holds on its own (`layable`): a rect or pixel ratio that is not
finite, a negative size, an edge over 16,384 points, an origin past ± 32,768, a ratio outside
0 (exclusive) … 16 hides the canvas and leaves the drawable alone; the drawable is never larger
than 16,384 px on an edge. A real rect lays out exactly as before. The `photo` stand-in's width and
height (prototype mode only) were already clamped to 1 … 6000 by `StandInPhoto`.

Tests, all in the normal logic pass (`SetsBridgeOpsTests`, 12 tests): the table now feeds `seq`
`Infinity`, `−Infinity`, `NaN`, `1e300` and `1e308` (1,308 calls); `testCanvasLookTakesAnySeqAndClock`
(F1); `testHostileLayoutOnTheNativeCanvas` (F2: 10 rects through the bridge, 5 pixel ratios, 12
rects straight into the controller, the loupe with non-finite regions, on a Metal view in a host
view; without a Metal device only survival and the ratio are checked); `testNumbersFromThePageAreFiniteAndInRange`
(the helper and every field's range); `testSessionSummaryCountsAreBounded`; `testSetPrefsRefusesNumbersJSONCannotHold` (F10).
Not run end to end: the `lumina://` query numbers through a real `WKURLSchemeTask` (their parsing is
the helper's, tested above), and a non-finite ROI reaching the region tiles (it no longer can: the
bridge refuses it).

## Part 2 · Head and preview-range fuzzer

`bash Tests/probe/fuzz/run.sh ingest <seed> <n>`. `hostile-ingest` compiles `SetsIngest.swift` and
`SetsFileOps.swift` unchanged; `fuzz.mjs` generates the cases (SplitMix64, seeded), runs the page's
own `LuminaCore.parseHead` (the shipped `lumina-core-v4.js`, in Node: the same file the page loads)
on the same bytes, and passes the request plumbing would make (`o`, `l`, `ori` from the parse, only
when `o + l ≤ size`) plus any hostile range to `head`, `preview` (as stored and upright) and `thumb`.
Four synthetic bases: preview inside the head (Sony layout), camera-sized portrait, preview past
256 KB, tiny.

| Class | Seed 1 | Seed 2 | What |
|---|---:|---:|---|
| trunc | 196 | 196 | every 4 KB boundary of every base |
| range | 2,209 | 2,276 | offsets 0, −1, −4096, past the end, 2^31, 2^32, 2^53−1, inside / across the head; lengths 0, −1, 2 GB, 64 MB, 64 MB + 1, 2^53−1; ori 0, 9, 65535, −1 |
| exif | 2,317 | 2,257 | IFD entry counts 0 / 1000 / 65535, value counts up to 2^32−1, types, IFD loops, Exif pointer loops, preview offset / length tags, byte order |
| orient | 762 | 737 | every u16, LONG where SHORT goes |
| flip | 1,484 | 1,555 | 1–24 random bytes in the TIFF structure |
| jpeg | 2,270 | 2,215 | SOF dimensions 65535 × 65535 / 0 × 0 / 1 × 65535, flips, zeroed blocks, Huffman counts, zero quantisation, JPEG cut short |
| combo | 762 | 764 | orient + exif + flip |

Results, both seeds: 0 crash, 0 hang, 0 footprint over 1.5 GB, **0 wrong status**. Statuses (seed 1):
preview 200 × 8,756 / 422 × 2,988; upright 200 × 4,871 / 422 × 1,903; thumb 200 × 7,555 / 422 × 4,189.
Every 200 preview equals the file's bytes in that range; every refusal is 422 (never 404 / 410 for a
file that is there); no range outside the file got a 200; every 200 thumb decodes. Slowest case 446 ms
(a 9310 × 5701 SOF turned upright). Footprint: flat at ~310 MB after the caches fill (96 + 24 MB caches
plus decode buffers) in seed 2; seed 1 ran before the tool drained an autorelease pool per case and
rose ~14 MB per 1,000 cases from the tool's own JSON, not from `SetsIngest`. Page parser: 0 throws, 383 null ("unreadable"), slowest 6.3 ms.

## Part 3 · Decoder mutation

`bash Tests/probe/fuzz/run.sh decode <seed> <jpegs> <raws>`. `hostile-decode` is signed ad hoc with
`Config/Lumina-Sets.entitlements` and its own Info.plist: it runs in the App Sandbox (container
`com.lumina.hostile-decode`; it could not list `~/LuminaEvidence` or `~/Documents`, checked at
start). It opens no file: each case arrives on stdin. JPEGs go through `SetsIngest.thumbnail`,
`SetsIngest.upright` (the app's code) and a full ImageIO decode; ARWs through `CIRAWFilter`
(default decoder, versions 7 and 8 here: no RAW 9 on this Mac) rendered at 1/8 scale.

| Seed | JPEG cases | decoded | ARW cases | decoded | Slowest | Peak footprint |
|---|---:|---:|---:|---:|---:|---:|
| 1 | 5,000 | 2,192 | 500 | 192 | 3.3 s (RAW) | 528 MB |
| 2 | 5,000 | 2,200 | 1,500 | 585 | 146 ms | 528 MB |

0 crashes, 0 hangs, 0 memory stops. The synthetic ARWs never decode as RAW (they reach only the
container parse); the 777 decoded RAW cases are mutations of `fixtures/src/DSC00001.ARW` and
`DSC00002.ARW` (`LUMINA_FIXTURE_ROOT`), kept only under `~/LuminaEvidence/hostile/decode-seed*.noindex`.

## Part 4 · XMP, names, volume labels

`bash Tests/probe/fuzz/run.sh fixtures` writes `$LUMINA_FIXTURE_ROOT/hostile-names` and
`hostile-xmp`; `bash Scripts/probe.sh scenarios hostile-card-label hostile-names hostile-xmp`, and the
same with `sandbox` (0 denials each).

| Scenario | Plain | Sandboxed | Notes |
|---|---|---|---|
| `hostile-card-label` | PASS 38/38 | PASS | 5 labels via `__lumina.card(true, cardJSON)`: no disk image is mounted (desktop rule) |
| `hostile-names` | FAIL 8 of 42 | FAIL (same) | fails on F3 and F4 only; every "nothing ran" check passes; `%2e%2e%2fescape` lands as itself |
| `hostile-xmp` | PASS 29/29 | PASS | steps run with `"invariants": false` (F6); Save: 7 written, 7 bak, DSC00108 refused "over 1 MB" |

On APFS the NFD and NFC `Café` names are one file (the first name's form is kept); its sidecar keeps
the RAW's form. A 255-byte RAW name lists and reads; only its sidecar fails (F4).

## Proposed tasks

| Task | What | Owns | Size |
|---|---|---|---|
| Q4a (**done**, `8cbabf0`) | Bridge numbers from the page through one helper that refuses non-finite and out-of-range values (`seq`, rect, `dpr`, `t`, ROI, `px`); `LookCanvasController.layout` clamps the drawable size. Move `seqHuge/Inf/NaN` and `layoutInf` from `testCrashingInputs` into the table. | `SetsBridge.swift`, `LookCanvas.swift`, the test | S |
| Q4b | `media()` in `plumbing.js` encodes with `encodeURIComponent`, as `renderURL` does; a case in `Tests/web/plumbing-harness.mjs` and a name with a space in `edge-junk-in-folder`; then `hostile-names` should pass but for F4. | `plumbing.js`, `Tests/web` | S |
| Q4c | Temp and backup names that fit: a temp name that does not repeat the file's (`.lumina-tmp-<uuid>`), and the reason "name too long" when the sidecar or its backup can't be named. | `SetsFileOps.swift` | S |
| Q4d | A sidecar that is not UTF-8 is listed as present-but-unreadable (with `skippedXmp`, or its own list) and Save leaves it alone with a reason, as for over-1 MB; never replaced by a fresh one. | `SetsIngest.swift`, `SetsFileOps.readSidecar` / `writeSidecar`, plumbing | S |
| Q4e | The probe's read invariant counts `skippedXmp`; then drop `"invariants": false` from `hostile-xmp`. Design ask: say "sidecar too big" instead of "unreadable" (Prompt 6). | `Tools/LuminaProbe`, `DESIGN-ASKS.md` | XS |
| Q4f | `shootOpened`: cap `date` (32 chars) and `n` (≥ 0, ≤ the listing's count) before they reach `index.json`. | `SetsBridge.swift` | XS |
| Q4g | Design ask: `mergeXmp` on text with no `rdf:Description` either adds one or the page refuses that sidecar, so Save never reports a rating it did not write. | `DESIGN-ASKS.md` | XS |

## Not covered

- A real disk image with a hostile volume label (the desktop rule forbids showing disk images; the
  probe's `diskImage` mounts browsable). The banner is tested through the exact JSON the bridge sends.
- The page's own image decode in the WebContent process (`createImageBitmap`): not fuzzed directly.
  WebKit decodes JPEG with ImageIO on macOS, which part 3 covers outside WebKit.
- RAW 9 (absent here), the Edit render path (`LookPipeline`, `lumina://render`) and export on mutated
  RAWs: part 3 calls `CIRAWFilter` directly at 1/8 scale.
- The loupe's region-tile code with a non-finite ROI (needs a decodable RAW on the native canvas).
  Since Q4a the bridge refuses such a region before it reaches the canvas.
- Key and mouse storms re-run sandboxed (matrix row "Key and mouse storms"): not part of Q4 as given.
- The page parser ran in Node on the shipped `lumina-core-v4.js`, not inside Chromium or WebKit.

## Reproduce

```bash
bash Tests/probe/fuzz/run.sh ingest 1 10000          # ~5 min; ~/LuminaEvidence/hostile/ingest-seed1.noindex
bash Tests/probe/fuzz/run.sh ingest 2 10000
LUMINA_FIXTURE_ROOT=~/LuminaEvidence/fixtures bash Tests/probe/fuzz/run.sh decode 1 5000 500
LUMINA_FIXTURE_ROOT=~/LuminaEvidence/fixtures bash Tests/probe/fuzz/run.sh decode 2 5000 1500
bash Tests/probe/fuzz/run.sh xmp
bash Tests/probe/fuzz/run.sh bridge                  # SetsBridgeOpsTests (F1, F2, F10 run here since Q4a)
bash Tests/probe/fuzz/run.sh fixtures
LUMINA_FIXTURE_ROOT=~/LuminaEvidence/fixtures bash Scripts/probe.sh scenarios hostile-card-label hostile-names hostile-xmp
LUMINA_FIXTURE_ROOT=~/LuminaEvidence/fixtures bash Scripts/probe.sh sandbox scenarios hostile-card-label hostile-names hostile-xmp
```

Each stop (crash, hang, memory) keeps its input and crash report in `<run>/findings/`; there were
none in parts 2 and 3. Mutated inputs live only in `.noindex` folders under `~/LuminaEvidence/hostile`
(with `.metadata_never_index`); nothing was opened in Finder, Preview or Quick Look and nothing was sent anywhere.
Evidence used above: `~/LuminaEvidence/hostile/{q4-seed1,ingest-seed2,decode-seed1,decode-seed2,xmp}.noindex` (q4-seed1 is ingest seed 1),
`probe-2` (plain), `probe-sandbox-1`, `probe-3` (the unreadable list), `bridge-crash/`, `bridge-ops-run3.log`.
