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

## Scope set by the user on 2026-10-08 (evening): web only, one ask
His first ask is to stop sifting twice: one pass on the desktop dump, log clips shown in Rec.709, marked
selected / maybe / cut, cut ones gone early, only what he uses handed to Final Cut. Judge by an impatient creator.
In for the first send (web page only): 1. drop the folder, every clip listed at once, no empty tiles;
2. Rec.709 looks right, large view included; 3. every clip plays and scrubs; 4. mark selected / maybe / cut
(coloured on/off toggles, no auto-advance) and see the GB cut would free; 5. selected clips into Final Cut,
proven by a real import. Parked until the user says otherwise: all Mac-app work (skim-native, skim-freespace,
skim-beta), grouping beyond scenes, canvas zoom and dock, the perf gate except the Final Cut comparison.
Web first: every fix is merged, deployed and checked on the live page before anything else.

Deploys this evening (https://lumina-skim.pages.dev, each after page copies byte-equal and tests passing):
121ff31 as it stood · 28d2639 no empty tiles (LOCAL-CHANGES 50, 51) · 155b891 clips listed from metadata,
first look follows the screen (46) · 995ee82 one-touch marking (65-68) · ce0fa2e the large view follows the
Rec.709 switch (60, 61, 69) · 66ed33f scrubbing survives a slight pinch, seek watchdog (55-58).
Later the same evening: e4d7a49 marks are coloured on/off toggles that stay on the clip (71-74) · 72267f2 the
build shown in the page's corner · 36ecbc6 Export cut down to the Final Cut download and the cut list (80-85)
· 960d081 developer memory controls behind ?debug=1, Pause, Close and Forget marks in the top bar (90-96);
the Final Cut button says what the file holds, file name first in the cut list (97-99) · then zoomed in holds
the frame and the pointer looks around (100-104). Confirmed by the user in Safari: slider responds at once,
V flips the large view, pinch then scrub, K / M / C toggle and stay, the cut list downloads. Decided: Safari
only, exports to Downloads; fusing Clips and Scenes is a conversation, nothing built (proposal: capture time as
the one axis, pinch = deeper or shallower). Still open before sending the link: one page-clock run on the
401-clip card in Safari, one real Final Cut import, Final Cut stills for the colour check.
Round 5 (2026-10-08, late): b921acd Enter / Shift-Enter move between clips in the Viewer (105-107) · 08bb1cb
measuring is no longer waited for: flags with the cover, other frames read where he looks, an all-dark clip is a
clip, "N clips ready" (110-113) · 86654bf the .fcpxml is checked in the page before the download is allowed
(120-122) · 69c5007 one grid for scenes and clips, opt-in at ?canvas=1 (130-138): capture time is the axis, one
fold value driven by the slider, pinch and - / =, folded tiles show counts, marks and what is noted inside; the
normal address is unchanged until the user says switch. The user's stopwatch on the 401-clip card in Safari,
before 08bb1cb: about 1:26 to every cover, over 5:40 more for the old measuring pass (not page-clock numbers).
Known and not fixed: for a folder that is not a mounted volume the .fcpxml points at /Volumes/<folder name>/...,
so Final Cut will not find the media without relinking (asking once for the folder's location is proposed,
waiting on the user). Final Cut import, stills and timing moved to a separate thread.
Measured, not in a browser: the page's S-Log3 conversion against Sony's published maths on the five
friend_test_log clips, 15 frames: mean dE2000 1.14, p95 2.38 with the page's tone curve (15 of 15 inside
2 / 5); 4.54 / 11.43 against a plain conversion with no tone curve (3 of 15). The clips are full range
(REC709.md step 1 says 64-940; the files and the page's table say full). Nothing is claimed about Final Cut:
that needs stills from Final Cut. Not yet measured: any speed on /Volumes/Untitled from the page's clock.
2026-10-09, Final Cut is the reference now (superseding the 1.14 above, which was the old curve against Sony's
maths): a real import of a Skim .fcpxml into a new Final Cut Pro 12.4 library, and 15 Save Current Frame stills of
the five friend_test_log clips with the built-in camera LUT Sony S-Log3/S-Gamut3.Cine. The old curve was about a
stop darker than Final Cut (mean dE2000 8.49, p95 10.97). The curve is refitted (LOCAL-CHANGES 139): 1.44 / 2.97
replayed in Python, 2.28 / 4.80 measured from Safari 27's own pixels with the developer colour check (140), 1.70 /
2.50 over small areas; by eye in Safari, similar to the stills. Exposure is noted from a full stop (141).
Deployed 95f75d35 (2026-10-09 17:23 UTC), checked on the live page: build stamp, the new table and the colour check.
Found by that import and fixed the same day (LOCAL-CHANGES 142 to 145, merged a9404440, deployed 2026-10-09 17:40
UTC and checked on the live page): clips arrive online from the folder named in Export ▸ Details, at the rate the
file really has, and S-Log3 / S-Gamut3.Cine clips arrive with Final Cut's Sony Camera LUT; proven by an import into
a new empty library (eleven clips online, five with the LUT, six at 24p). Selected arrives as Favorite. Not done:
the Folder field tried by hand in Safari; a switch for the LUT; other log profiles; camera timecode; audio layout. Open in colour: a matrix refit would take Safari to about
1.61 / 3.63 (not applied); clipping is read a little low; the bright end of the curve has few samples.
Evidence: ~/LuminaEvidence/skim-rec709/ (2026-10-08-fcp-stills, 2026-10-09-fcp-stills-5clips, -safari-check, -flags).
Open, found on the way: C0248 on the card (all black, 0.5 s) is reported as unreadable though it plays;
pass-2 frames skipped on a seek timeout are not queued again; in a browser, pacing by heat does nothing.
Assessed, not changed (waiting on the user): hide the developer memory controls; add a list of cut clips to
copy or download; reword the figure as GB he can free.

## Threads (worktrees under ~/vlm_harness/worktrees)
State after orchestration round 3 (2026-10-08 21:50 PT); branches other than skim-native and the three parked Mac-app threads are level with mvp unless a row says otherwise. No chat was attached to any worktree in this round; each
row's next step is waiting for a chat to pick it up.
| Worktree | Branch | Handoff | State after round 1 |
|---|---|---|---|
| video-skim | video/skim-mvp | this file | Integration + demo. Round 1 merged the faults, grouping, ingest, perfgate and rec709 handoffs and canvas 1.1 (ec71ce7), one at a time; page copies byte-equal and skim-export tests 9 pass after each. |
| skim-native | video/skim-native | NATIVE-DECODE.md | Step 1 committed as work in progress (77c5600, 19 files). A Debug build from 14:54 on 10-08 contains SkimDecoder (so it has compiled once); Swift tests not run, nothing measured. Merging mvp conflicts in the page (both copies) and LOCAL-CHANGES.md (its entry is numbered 36, mvp runs to 45); the merge was aborted and is this thread's next step. |
| skim-export | video/skim-export | FRIEND-DEMO.md | Merged into mvp 2026-10-09 (a9404440) and deployed: true frame rate, Sony Camera LUT for S-Log3 / S-Gamut3.Cine, the Folder field. Next: camera timecode as the asset start, scene keywords, real audio layout, a switch for the LUT. |
| skim-canvas | video/skim-canvas | CANVAS.md | 1.1 merged into mvp; level with mvp. Next 1.2 layout maths → 1.6, then the dock. |
| skim-grouping | video/skim-grouping | GROUPING.md | lumina-skim-grouping.js + tests committed as work in progress (b40da31; 15 tests pass), mvp merged in (9730f61). Not yet merged into mvp: not wired to the page, not checked on real clips. |
| skim-rec709 | video/skim-rec709 | REC709.md | Merged into mvp 2026-10-09 (95f75d35) and deployed: curve refitted to Final Cut stills, developer colour check, exposure noted from a full stop. Next, if wanted: matrix refit, the bright end of the curve, baking the conversion into stored frames. |
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
