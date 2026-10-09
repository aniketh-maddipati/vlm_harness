# Skim: threads, state and how to continue (read this first in any new chat)

Written 2026-10-08 20:55 PT when the work moved from a cloud chat to the Claude desktop app on this Mac.

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
| Worktree | Branch | Handoff | State at hand-over |
|---|---|---|---|
| video-skim | video/skim-mvp | this file | Integration + demo. HEAD fb74475. Merge others in one at a time, push back out. |
| skim-native | video/skim-native | NATIVE-DECODE.md | Step 1 written (SkimDecoder/Measure/Schedule…), 19 files UNCOMMITTED, never compiled; 26 commits behind mvp; page conflicts expected near the loading code and LOCAL-CHANGES 36. Commit, build, then merge mvp. |
| skim-export | video/skim-export | FRIEND-DEMO.md | Headless export harness + DTD check merged (2b174c1). Next: real paths, camera timecode (asset and asset-clip start; c.ltc from the file), scene keywords, audio, a real Final Cut import. |
| skim-canvas | video/skim-canvas | CANVAS.md | 1.1 done (ThumbCache, 4bae434). Next 1.2 layout maths → 1.6, then the dock. |
| skim-grouping | video/skim-grouping | GROUPING.md | Started (3 uncommitted files). Moments/takes/shot type/accidental/usable stretch. |
| skim-rec709 | video/skim-rec709 | REC709.md | Not started. Needs Final Cut stills of C4815 (or computer use on Final Cut). |
| skim-ingest | video/skim-ingest | INGEST.md | Not started. One-shot read + measure; CANVAS-GRAMMAR.md. |
| skim-faults | video/skim-faults | FAULTS.md | Not started. Fault fixtures, tests, fixes. |
| skim-perfgate | video/skim-perfgate | PERFGATE.md | Not started. Benchmarks + budgets + baseline + CI. |

## Rules for every thread
Each owns the parts of the page its handoff names; merge video/skim-mvp before page edits; keep the two page copies
byte-equal (wait for the watcher or copy by hand before committing); TRUST.md + trust_check for any bridge op; no
network in the app; read only on cards; speed claims only from the page's clock; Final Cut claims only from an
actual import; neutral words on screen (selected / maybe / cut). Commit author: Aniketh Maddipati
<anikethcov@gmail.com>; end messages with the Co-Authored-By / Claude-Session lines used so far.

## Open blockers
1. skim-native has never been compiled. 2. Computer use was off for the cloud chat — in the desktop app it should
work directly (Final Cut checks for rec709 and export). 3. The live site is 3 hours behind (deploy).
