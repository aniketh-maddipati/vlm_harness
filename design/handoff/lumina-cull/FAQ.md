# Lumina FAQ

## Using Lumina

**What does Lumina do?**
It opens a card or folder of Sony RAW files, groups them into rows and stacks, lets you mark keepers with P, and writes an .xmp sidecar for each keeper so Lightroom Classic or Capture One can pick up the rating.

**Which cameras and files are supported?**
Sony ARW. Other RAW formats are skipped and listed after import. JPEG and HEIF files without a matching RAW are skipped because Lightroom does not read sidecars for JPEG.

**How are rows made?**
A new row starts after a long time gap for that shoot (compared with the last 10 gaps, at least 10 seconds), or when the lens, focal length, orientation, shooting mode, white balance, flash or ISO changes. You can split or merge with B and ⇧B.

**How are stacks made?**
Frames from the camera's continuous drive sequence form a stack. Without sequence data, frames taken within 2 seconds that look alike form a stack. A large change between frames starts a new one.

**How is the sharpest frame chosen?**
By the amount of edge detail in the preview image stored inside each RAW. It is a starting point. Check it in large view with Z for 100%.

**Can I undo?**
Yes. Q or ⌘Z undoes one step at a time. The undo history resets when you close the shoot.

**What happens if I shot with two cameras?**
Photos are sorted by capture time, so rows only line up if both camera clocks were set to the same time.

## Your files

**Does Lumina change my RAW files?**
No. RAW files are never modified, moved or deleted.

**What does Save write?**
One small .xmp file next to each keeper, with the same name as the RAW. It sets the rating to 3★. Photos you did not keep get nothing.

**What if a photo already has a sidecar?**
Only the rating is updated. Edits and other metadata stay. The previous file is kept as .xmp.lumina-bak.

**Why 3★ and not a Lightroom pick flag?**
Lightroom stores pick flags in its catalog, not in sidecar files. A rating is the part of a sidecar Lightroom reads, so keepers are easy to filter.

**Can I cull straight from the card?**
Yes. The card is read only. Sidecars cannot be written to a card, so copy the folder to your Mac before you save. Your decisions carry over when you open the copy.

**How do I get the keepers into Lightroom Classic?**
Import the folder. For photos already in your catalog, select them and choose Metadata → Read Metadata from Files.

**And Capture One?**
Import the folder. The ratings come with the sidecars.

## Privacy and security

**Does Lumina use AI?**
Not in this version. There is no AI model and no online service. Lumina uses plain image measurements (edge detail, brightness and a small fingerprint to compare frames) that run on your Mac. You make every decision.

**Will Lumina add editing or AI features?**
Later versions may add editing and AI features, based on what users ask for. Any AI feature will be optional and will say clearly what it does and whether anything leaves your Mac.

**Are my photos uploaded anywhere?**
No. Files are read on your Mac and are not sent to a server.

**Are my photos used to train anything?**
No.

**Where are my decisions stored?**
On your Mac, in Lumina's app data. In the browser version they are stored in that browser only.

**How do I remove Lumina's data?**
Use Remove Lumina's working files at the bottom of Handoff. It deletes saved sessions and cached previews. Your RAW files and sidecars are not affected.

**Why does macOS ask for access?**
macOS asks before any app reads a removable drive or protected folder. Lumina needs read access to open the card. You can change this in System Settings → Privacy & Security → Files and Folders.

**Why did Chrome ask to upload files?**
That is how Chrome words folder access for web pages. The browser version opens the files on your Mac and does not send them anywhere. The Mac app does not show this prompt.

## Contact

**How do I report a problem or ask a question?**
DM Aniketh Maddipati (@aniketh745) on X.

**Can I suggest a feature?**
Yes. DM Aniketh Maddipati (@aniketh745) on X. Feedback decides what comes next.
