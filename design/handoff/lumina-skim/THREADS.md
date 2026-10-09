# Skim: threads, state and how to continue (read this first in any new chat)

Written 2026-10-08 20:55 PT when the work moved from a cloud chat to the Claude desktop app on this Mac.
Updated after each orchestration round; the latest round is in the Threads table.

## The product, in one paragraph
Lumina Skim: one sorting pass for video before Final Cut. The user's friend shoots a7S III S-Log3 (XAVC HS, HEVC
10-bit 4:2:0, 4K 23.976, ~97 Mb/s, 11–14 s clips, hundreds per trip, metadata in each file's last ~2 KB), dumps the
card to his desktop, deletes random footage, then in Final Cut adds Rec.709 and sorts standouts / filler / looks off,
to save storage. Lumina replaces those two passes: see every clip in Rec.709, flags for dark/bright/clipped/crushed/
soft, group by moment and take, mark selected / maybe / cut (K/M/C, neutral words only), free the cut GB, hand Final
Cut only what he uses. Out of scope now: colour matching, masking, grading.

## Where things run
- Page: design/handoff/lumina-skim/Lumina Skim v3.dc.html (design copy) = Lumina/Sets/Web/… (must be byte-equal).
- Hot app: `bash Scripts/dev-skim.sh --watch` (Lumina Skim, Debug, WKWebView). Second app per worktree with
  SKIM_ID / SKIM_NAME / SKIM_CACHE (see NATIVE-DECODE.md).
- Web preview: `python3 Scripts/build-skim-preview.py`; live at https://lumina-skim.pages.dev via
  `bash Scripts/deploy-skim-preview.sh` (Cloudflare Pages, project lumina-skim). Last deployed 15:32 (4b2ae62);
  everything since is undeployed. Safari is the browser to use (Chromium can't play 10-bit H.264; HEVC 10-bit OK).
- Test media: /Volumes/Untitled (a7 III card, 401 clips, 113 GB, H.264 8-bit 4K Rec.709, read only);
  T7/friend_test_log (5 real a7S III S-Log3 clips, no sidecars), T7/friend_test_colored (his graded exports, other
  shots); dist/a7s3-formats (7 format test clips + codec-check.html). Codec results: Safari decodes all 7;
  Chromium only HEVC 10-bit and 8-bit H.264.
- Change log: LOCAL-CHANGES.md (items 1–45).

## Threads (worktrees under ~/vlm_harness/worktrees)
State after orchestration round 2 (2026-10-08 21:15 PT). No chat was attached to any worktree in this round; each
row's next step is waiting for a chat to pick it up.
| Worktree | Branch | Handoff | State after round 1 |
|---|---|---|---|
| video-skim | video/skim-mvp | this file | Integration + demo. Round 1 merged the faults, grouping, ingest, perfgate and rec709 handoffs and canvas 1.1 (ec71ce7), one at a time; page copies byte-equal and skim-export tests 9 pass after each. |
| skim-native | video/skim-native | NATIVE-DECODE.md | Step 1 committed as work in progress (77c5600, 19 files). A Debug build from 14:54 on 10-08 contains SkimDecoder (so it has compiled once); Swift tests not run, nothing measured. Merging mvp conflicts in the page (both copies) and LOCAL-CHANGES.md (its entry is numbered 36, mvp runs to 45); the merge was aborted and is this thread's next step. |
| skim-export | video/skim-export | FRIEND-DEMO.md | Level with mvp, nothing of its own. Next: real paths, camera timecode (asset and asset-clip start; c.ltc from the file), scene keywords, audio, a real Final Cut import. |
| skim-canvas | video/skim-canvas | CANVAS.md | 1.1 merged into mvp; level with mvp. Next 1.2 layout maths → 1.6, then the dock. |
| skim-grouping | video/skim-grouping | GROUPING.md | lumina-skim-grouping.js + tests committed as work in progress (b40da31; 15 tests pass), mvp merged in (9730f61). Not yet merged into mvp: not wired to the page, not checked on real clips. |
| skim-rec709 | video/skim-rec709 | REC709.md | Handoff merged; level with mvp. Not started. Needs Final Cut stills of C4815 (computer use on Final Cut). |
| skim-ingest | video/skim-ingest | INGEST.md | Handoff merged; level with mvp. Not started. One-shot read + measure; CANVAS-GRAMMAR.md. |
| skim-faults | video/skim-faults | FAULTS.md | Handoff merged; level with mvp. Not started. Fault fixtures, tests, fixes. |
| skim-perfgate | video/skim-perfgate | PERFGATE.md | Handoff merged; level with mvp. Not started. Benchmarks + budgets + baseline + CI. |
| skim-freespace | video/skim-freespace | FREESPACE.md | Created in round 2 with a draft handoff. Not started. Move cut clips to the Trash, Mac app only, never a card. |
| skim-beta | video/skim-beta | BETA.md | Created in round 2 with a draft handoff. Not started. Release build, Developer ID + notarization (ask before any Apple credentials), Sparkle, signed live page, Send report. |

## Planned merge of mvp into skim-native (not done; wait for a chat working there)
A dry merge (git merge-tree) conflicts in three files only. Page, one place, `dropFrames`: keep native's
`natClose()` and `c._nx = null` and mvp's `this.thumbs.forget(c.id)` in the one line; edit the design copy, then
copy to Lumina/Sets/Web. LOCAL-CHANGES.md: keep mvp's 36–45, renumber native's entry to 46. The other mvp page
hunks merge as text; check behaviour where native's runQueue hand-off meets mvp's nearest-full-frame snapping,
in-file Sony metadata and coalesced repaints. Then: Tests/web/skim-native-page.cjs, skim-export tests,
trust_check.py, the Swift tests, a build, and the measures in NATIVE-DECODE.md.

## Deploy checkpoints (web page → https://lumina-skim.pages.dev, Cloudflare Pages project lumina-skim)
Deployed from video/skim-mvp only, by `bash Scripts/deploy-skim-preview.sh`, only after a round's checks pass
(page copies byte-equal, tests pass). The web client ships first; native, beta and free space are Mac-app work
and do not hold it up. Record each deploy here with its commit.
1. mvp as it stands (canvas 1.1, neutral words, in-file Sony metadata).
2. Canvas 1.2–1.3 (layout maths, canvas drawing).
3. Faults: marks survive a reload and a full quota.
4. Ingest: instant listing, flags with the covers.
5. Grouping wired in (takes, usable stretch).
6. Export with camera timecode and scene keywords.
7. Rec.709 refit, if the Final Cut comparison calls for one.

## The goal is Final Cut (owner: skim-perfgate, see PERFGATE.md)
The same card through Final Cut Pro and through Skim: time to every thumbnail, scrubbing, time to sort a card.
Final Cut's measured numbers are the targets. Skim numbers only from the page's clock; Final Cut numbers only
from an actual run on this Mac (needs computer use on Final Cut, or the user with a stopwatch).

## Rules for every thread
Each owns the parts of the page its handoff names; merge video/skim-mvp before page edits; keep the two page copies
byte-equal (wait for the watcher or copy by hand before committing); TRUST.md + trust_check for any bridge op; no
network in the app; read only on cards; speed claims only from the page's clock; Final Cut claims only from an
actual import; neutral words on screen (selected / maybe / cut). Commit author: Aniketh Maddipati
<anikethcov@gmail.com>; end messages with the Co-Authored-By / Claude-Session lines used so far.

## Open blockers
1. skim-native: resolve the mvp merge (page + LOCAL-CHANGES numbering), run the Swift tests, measure on the card.
2. Computer use on Final Cut for rec709 (stills) and export (import check): needs the user to allow it.
3. The live site is still at 4b2ae62 (deploy needs the user's yes).
4. No video/* branch has an upstream; the work exists only on this Mac until it is pushed.
5. Test media: T7/friend_test_log is real S-Log3 (5 clips, HEVC Main 10 4:2:0 23.976, CaptureGammaEquation
   s-log3-cine in each file's tail; checked with ffprobe, read only). FRIEND-DEMO.md's line that the T7 holds no
   S-Log3 predates these clips and describes the seven format-test clips only.
6. Targets to confirm with the user: ingest (listing < 1 s, covers < 60 s for 400 clips) and the perfgate budgets.
