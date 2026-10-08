# Skim: the friend demo (export, Final Cut, a build he can open)

Branch `video/skim-export`, worktree `~/vlm_harness/worktrees/skim-export`, cut from `video/skim-mvp` at f9c37fe.
Native decode runs separately in `video/skim-native` (`worktrees/skim-native`, NATIVE-DECODE.md); do not edit its files.

## Who it's for
A videographer on a Sony a7S III, S-Log3 / S-Gamut3.Cine (PP8), editing in Final Cut Pro. Huge volume of 4K;
today he goes through it in several light passes so the Mac doesn't crash or overheat. He archives everything.
Workflow open: card → dump drive, card → Final Cut library, or card → archive + working drive (we support all three).
The pitch: sort the whole card in one pass without heat or crashes; Final Cut only ever touches what you keep.

## Defaults (keep them)
- Lumina reads clips wherever they are (card, dump, archive), read only; never moves or deletes originals.
- Nothing blocks on keepers: Export defaults to **Everything** (keepers = Final Cut favorites, cuts = rejected,
  maybes tagged "maybe", the rest unrated); **Keepers only** is a switch (f9c37fe).
- S-Log3 from the sidecar (or the answer the user gives once) turns the Rec.709 preview on.

## Work, in order
1. **His clip.** Message for the user to send (edit freely):
   > Could you send me one clip straight off the card with its .XML (same name with M01.XML, from PRIVATE/M4ROOT/CLIP)?
   > Also: after a shoot do you copy the card to a drive first, or import straight into Final Cut? Roughly how many
   > clips and GB is a typical card? And do you keep everything in an archive drive?
   When it arrives: does it decode in Lumina Skim (app) and in Safari? Record codec / bit depth / chroma (ffprobe).
2. **Final Cut export fidelity**, checked by importing into Final Cut on this Mac (the user has the card at
   /Volumes/Untitled, read only, and S-Log3 samples on the T7 / repo fixtures):
   - exact file paths: in the app, the real URL of each clip (native knows it; pass it to the page with the listing);
     the browser keeps today's guess and says to use File ▸ Relink Files;
   - camera timecode from the Sony sidecar (LtcChangeTable) as the asset `start`, so in/out match the file;
   - ratings already written (`<rating value="favorite|reject">`): confirm Final Cut 10.6+/11 reads them, fix the form if not;
   - one keyword per scene ("Scene 3 · 10:32–13:00") so scenes become keyword collections;
   - S-Log3: make Final Cut apply its Sony Log conversion (check what the FCPXML needs, if anything; else document);
   - audio: real channel count / rate from the file instead of hasAudio=1 for all;
   - DTD-valid FCPXML (1.10/1.11), checked with `xmllint --dtdvalid` if the DTD is available in Final Cut's bundle.
   Tests: buildX cases in a small Node test or the probe; a golden .fcpxml for the six-clip fixture.
3. **A build he can open.** Release (not Debug) Skim app: today Skim is Debug-only (`LUMINA_PAGE=skim`, SetsPage).
   Add a release path for the Skim page (separate scheme or target "Lumina Skim"), Developer ID signing and
   notarization steps in Scripts (needs the user's Apple Developer account; stop and ask before anything that
   uses credentials). Until then: the standalone HTML for Safari with a one-page how-to.
4. **Later (do not build now, write down):** copy keepers to a working drive with checksums (SetsFileOps has SHA-256
   copies) and link the export to the copies; "safe to format in camera"; move cuts to Trash on a dump drive (never a card);
   per-camera presets.

## Rules
AGENTS.md, TRUST.md for any bridge op, trust_check passes, page copy and Lumina/Sets/Web byte-equal, no network.
Hot build: `SKIM_ID=com.lumina.app.skimexport SKIM_NAME="Lumina Skim Export" SKIM_CACHE=~/Library/Caches/com.lumina.skimexport bash Scripts/dev-skim.sh --watch`
(the SKIM_* overrides are on video/skim-native; cherry-pick ff1117a's Scripts/dev-skim.sh change, or copy those three lines).
