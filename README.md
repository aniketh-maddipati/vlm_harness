# Lumina

Lumina is a Mac app for culling Sony ARW shoots quickly. Open a card or a folder, work through the
shoot with the keyboard, and keep the frames you want. Everything else stays where it was.

![Culling a shoot by time rows](docs/screenshots/cull-row.png)

## How culling works

**Open a shoot.** Choose File ▸ Open (⌘O) and pick a folder, or insert a Sony card and press
**Return** when the open screen offers to cull it. Lumina remembers each shoot, so if you reopen it
later you pick up where you left off.

**The shoot is split into rows by time.** A new row starts after a break of more than 90 seconds,
and each row is labeled with its start time, such as 06:48 or 08:12. Inside a row, frames shot less
than a second apart form a **burst** (or a **bracket**, if the exposures step from under to over),
and the rest are listed as **singles**.

**Lumina suggests what to keep.** In a burst it suggests the sharpest frame that isn't blown, soft,
or shaky. It suggests every frame of a bracket, and each single that has none of those problems. A
dot in a frame's corner means that frame is likely out.

**Work a whole row at once.** Use ↑ ↓ to move between rows. Press **R** to keep the suggested frames
or **X** to reject the entire row. Hold **L** to also see the frames Lumina didn't suggest.

**Or go one photo at a time.** Press → to step into a row. Then **R** keeps a photo, **X** rejects it,
and ← → moves through the frames. Lumina tags frames that have a problem, such as **blown** or
**soft**, and points out the **sharpest** frame in a burst.

![A single photo selected, tagged "blown"](docs/screenshots/cull-photo.png)

**The frames you keep collect in the strip at the bottom.** The count in the top bar updates as you
go, and your work is saved on its own. **Q** or ⌘Z undoes the last action. Press **Space** to see a
photo large, hold **G** for 100%, or press **W** to compare the frames of a burst.

![Keeping the first frame of a burst; it lands in the kept strip](docs/screenshots/cull-kept.png)

**Auto** is an automatic look (exposure, contrast, highlights, shadows and white
balance) that Lumina works out for each photo. While you cull, press **V** to preview it on a row or
group, or hold **A** to compare one photo with and without it. A preview changes nothing until you apply it in Edit.

Press **?** to list every key.

![Every culling key](docs/screenshots/cull-keys.png)

When you finish culling, press **Tab** to move on to **edit** (optional touch-ups) and then **export**.
Export either copies the RAWs with XMP sidecars for Lightroom or Capture One, or writes RAW and JPEG.

## What it won't do

- Write to the card or change your original files.
- Move files. Lumina only copies, and it checks every copy.
- Replace a file without first saving a `.lumina-bak` backup.
- Send anything off your Mac. The app has no network access.

## Run it

You need Xcode 16.4 or later, an Apple silicon Mac, and macOS 14 or later.

```bash
open Lumina.xcodeproj
```

Choose the **Lumina** scheme and **My Mac**, then press ⌘R.

## For contributors

The UI is designed in Claude Design and ships unchanged inside the native window, so don't edit it
in this repo. [AGENTS.md](AGENTS.md) explains how the pieces fit together and how to sync a new
design.
