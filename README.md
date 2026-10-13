# Lumina

A Mac app for culling Sony shoots fast. Open a card or a folder, go through it with the keyboard,
keep the frames you want. Your originals are never changed.

![Culling a shoot by time rows](docs/screenshots/cull-row.png)

## Culling photos

Open a folder with ⌘O, or insert a Sony card and press **Return**. Lumina splits the shoot into rows
by time (a break of 90 seconds starts a new row), groups frames shot under a second apart into bursts
and brackets, and suggests what to keep: the sharpest good frame of a burst, every frame of a
bracket, each single without a problem.

| Key | Does |
|---|---|
| ↑ ↓ | Move between rows |
| **R** / **X** | Keep the suggested frames / reject the row (or one photo, after → steps into the row) |
| ← → | Step through the photos of a row |
| **Space** · hold **G** · **W** | See a photo large · at 100 % · compare a burst |
| **V** · hold **A** | Preview the Auto look · compare with and without it |
| **Q** or ⌘Z | Undo |
| **Tab** | On to Edit, then Export |
| **?** | Every key |

Your work saves on its own and a reopened shoot picks up where you left off. **Save** writes your
ratings as `.xmp` sidecars beside the RAWs for Lightroom Classic or Capture One; **Export** writes
JPEGs of your edits.

## Skimming video (in development)

Skim is the same idea for clips: open a folder, mark clips keep, maybe or cut, and hand the keepers
to Final Cut Pro. To try it on the a7S III clips at the root of the T7 drive:

| Clips | Format | Rate | Length |
|---|---|---|---|
| C0054 | XAVC S-I, H.264 4:2:2 10-bit | 23.98p | 27 s, 0.8 GB |
| C0079, C0094, C0095, C0100 | XAVC S-I, H.264 4:2:2 10-bit | 29.97p | 62 to 65 s, 2.2 to 2.3 GB |
| C0099 | XAVC S-I, H.264 4:2:2 10-bit | 59.94p | 54 s, 3.9 GB |
| C0070 | XAVC S, H.264 4:2:0 8-bit | 59.94p | 78 s, 1.5 GB |

All are 3840 × 2160 and Rec.709 (no S-Log), with no `M01.XML` sidecar beside them.

```bash
python3 Scripts/build-skim-preview.py   # writes dist/Lumina Skim (web preview).html; open it in Safari
bash Scripts/dev-skim.sh                 # or the "Lumina Skim" dev app
```

Then choose **Open** and pick `/Volumes/T7`. Skim only reads the clips; it never changes or moves them.
For the budget probe on the same clips: `LUMINA_LONG=1 LUMINA_VIDEO_DIR=/Volumes/T7 bash Scripts/probe.sh video`
(it fails by design until the native video bridge lands).

## What it won't do

- Write to the card or change your original files.
- Move files. Lumina only copies, and checks every copy.
- Replace a file without first keeping a `.lumina-bak`.
- Send anything off your Mac. How that is enforced, what Lumina keeps and where:
  [docs/release/PRIVACY.md](docs/release/PRIVACY.md).

## Run it

Xcode 16.4 or later, an Apple silicon Mac, macOS 15 or later.

```bash
open Lumina.xcodeproj    # choose the Lumina scheme and My Mac, then ⌘R
```

The UI is designed in Claude Design and ships unchanged inside the native window, so it is not edited
here. [AGENTS.md](AGENTS.md) explains how the pieces fit and how to run the checks.
