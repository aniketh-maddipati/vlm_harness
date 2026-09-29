# Lumina

Lumina is a Mac app for culling Sony ARW shoots quickly. Open a card or a folder, work through the
shoot with the keyboard, and keep the frames you want. Everything else stays where it was.

![Culling a shoot by time rows](docs/screenshots/cull-row.png)

## How culling works

**The shoot is split into rows by time.** Each row is one stretch of shooting, such as 06:48 or
08:12. Inside a row, frames shot in quick succession are grouped as a **burst**, and the rest are
listed as **singles**. The dot in a frame's corner means Lumina suggests keeping that frame.

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
