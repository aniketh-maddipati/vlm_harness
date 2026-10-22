# Lumina landing page

Revised after the first version. The page is Still and Skim, not a Sony culling page. Sony is a FAQ. The header is two words, Still and Skim, with one line under each in the hero. The end of the page shows the `.xmp` Lightroom reads and the `.fcpxml` Final Cut reads, plus the file, memory and edit screens. The prompt below is the first draft; where it says Sony or Pick, the HTML wins.



The page is `index.html` and `styles.css` in this folder. It is a marketing page for the Mac app. It is not the in-app page, and it does not ship inside Lumina.

Screenshots are the product shots already in `docs/screenshots/`. Open the page from the repo root so those relative paths resolve:

```bash
python3 -m http.server 8766
# http://127.0.0.1:8766/site/
```

`save.jpg` contains the names of other photo apps, because the Save screen does. The App Store listing must not use those names or that shot. This page’s own sentences say “standard XMP” and “other photo apps”.

## Framer

Framer is a reasonable way to publish if someone who will not edit this repo needs to nudge the layout, or if you want a custom domain this afternoon. It is a poor source of truth for this page.

The look already exists as CSS: the colours, the type, the radii, the inset rings, the 160ms rise, the one gold. Framer’s defaults (Inter, soft shadows, large radii, gradient meshes, a stock hero with two columns) pull away from that the moment a template section is inserted. Framer’s code export is a snapshot, not the file you keep editing. This repo would then hold a second, drifting copy.

Use the HTML here when the page should keep matching the app. Use Framer when a non-developer will publish changes, or when you later want a changelog or a waitlist in their editor. If you use Framer, do not start from a template. Paste the prompt below, lock the colour and text styles before drawing sections, and when the two disagree, this page wins.

Framer will want a font from its library. Do not load one from a CDN on the HTML page: the Mac app uses the system, and a marketing page that phones a font host contradicts “nothing leaves your Mac”. On a Mac the stack already resolves to Iowan Old Style and SF Pro. If Framer requires an uploaded face, Newsreader at weight 400 is the closest open serif. Do not set headlines in Inter.

## Prompt

Paste this as the whole instruction. Attach `docs/screenshots/large-view.jpg`, `pick-grid.jpg`, `edit.jpg` and `save.jpg`.

```
Design a one-page marketing site for Lumina, a native Mac app that culls Sony ARW shoots from the keyboard. Match the app. Do not design a startup landing page.

The app is a warm near-black tool. The only colour is a soft gold used for the primary button, a small Beta pill, and focus. Headlines are off-white, in a literary serif, at a modest size. Body is a system sans. There is no illustration, no icon set, no gradient mesh, no glass, no glow, no stock photography, and no second accent colour.

COLOURS (use these exact values, as colour styles)
Background #1E1D1B
Bar and cards #262523
Raised card #2A2927
Keycap #3A3835
Selected segment #5B5854
Ink #EFECE6
Body #B8B3AB
Label #9A958D
Quiet #7D7971
Gold #FFD27A
Gold wash rgba(255, 210, 122, 0.14)
Hairline rgba(239, 236, 230, 0.08)
Deep #161514

TYPE
Wordmark and headlines: Iowan Old Style, then Palatino, then Georgia. Weight 400. No letterspacing tricks.
If a custom font is required: Newsreader, weight 400. Never Inter for headlines.
UI: SF Pro Text, otherwise the system sans.
Wordmark 21px. Hero clamp between 40 and 64px, line-height 1.08. Section titles 28 to 40px, line-height 1.15. Labels 12px, weight 600, colour #9A958D. Body 16–17px, colour #B8B3AB, line-height 1.5. Numbers are tabular.

SHAPE
Cards: radius 14–16, padding 16–24, background #262523, no drop shadow. Separation is an inset 1px ring, rgba(239,236,230,0.12).
Primary button: fill #FFD27A, text #1E1D1B, weight 800, size 15, radius 11, padding 12px 18px. A small key chip sits inside it (dark wash, radius 5). Press sinks 1px.
Secondary button: fill rgba(239,236,230,0.08), text #EFECE6, weight 600, same radius.
Beta pill: 11px weight 600, colour #FFD27A, background the gold wash, radius 5, padding 2px 7px.
Segmented control (the step switcher): 4 columns of 88px, padding 2px, radius 7, track rgba(239,236,230,0.08), the selected cell #5B5854 with radius 5. Labels 13px. The shortcut beside each label is 11px and dimmer.
Key chips: radius 5, background rgba(239,236,230,0.12), 12px weight 700.
Motion, if any: a 6px rise over 160ms. No parallax, no scroll-jacking, no bouncing.

CHROME
A sticky bar, 52px, background #262523, hairline along the bottom.
Left: the word Lumina in the serif, then the Beta 0.01 pill.
Centre: the segmented control, Open ⌘1, Pick ⌘2, Edit ⌘3, Save ⌘4. These are anchors. The gold pill slides to the section in view.
Right: a gold button, “Get the beta”.
A fixed bar along the bottom, 34px, same bar colour, 12px. It shows the keys for the section in view. Pick reads: ⏎ keeps, R sets aside, arrows move, Q undoes, Space looks closer.

PAGE, TOP TO BOTTOM. Copy is exact. Do not rewrite it into slogans.

1. Hero, left aligned, one column. The screenshot sits under the copy at full content width, not beside it.
Kicker: Cull a Sony shoot, keys first
Headline: Cull a shoot before the coffee is cold.
Paragraph: Open a folder of Sony ARW files and decide fast. Bursts stay together, keepers are one key, and ratings are saved as standard XMP next to the photos. Nothing leaves your Mac.
Buttons: gold “Get the beta”, quiet “See Pick”.
Fine line: Apple silicon · macOS 15 or later · No account
Image: large-view.jpg.

2. Four cards in a row, serif titles at 21px, 13px dim descriptions.
Starts while it reads — The preview already inside the ARW is enough to cull. The first rows come up while the rest of the shoot is still being read.
Bursts stay together — Shots taken in quick succession are one unit. Open the stack, compare the frames, and keep the one you want.
Keys do the work — ⏎ keeps. R sets a frame aside. Arrows move. Every decision is one undo.
Ratings travel — Save writes standard XMP beside each RAW. The original file stays as it was.

3. Open. Kicker “Open · ⌘1”. Title “A card or a folder. The files stay where they are.”
Body: Drag a card, a folder or files onto the window, or press ⌘O. Lumina reads only what you choose. A memory card is read-only: Lumina never writes to it.
Then two cards, as in the app. Left card, background #2A2927, label “Card”, the line “A card is in. Read the previews and start picking.”, the line “Read-only. Files stay on the card.”, and a gold button “⏎ Read the card”. Right card, background #262523 with an inset ring, label “Folder or card”, a raised keycap “⌘O” (background #3A3835, a 2px lip in #161514) and the words “Open…”.
Under them, 13px and dim: Drag a card, folder or files from Finder onto the window, or press ⌘O. RAW only: ARW and DNG. JPEG and HEIC aren’t supported yet.

4. Pick. Kicker “Pick · ⌘2”. Title “One key keeps. One key sets a frame aside.”
Body: The shoot is laid out in time. A burst is one unit until you open it. Soft frames and blown highlights are flagged, and a pair can be opened large, on the same moment, so the keeper is obvious.
Second paragraph: Your place and your decisions are kept with the shoot. Close the app and pick up on the same frame.
A row of key chips: ⏎ Keep, next · R Set aside, next · ← → Move · Q Undo · Space Large view.
Image: pick-kept.jpg.

5. Edit. Kicker “Edit · ⌘3”. Title “The keepers, on the Mac’s GPU.”
Body: Exposure, white balance, contrast and the rest of the look, on the photos you kept. Move a slider and the picture updates in the window. The look stays in Lumina. What gets written beside the RAW is the rating.
Image: edit.jpg.

6. Save. Kicker “Save · ⌘4”. Title “A rating next to the file. Nothing deleted.”
Body: Save writes one .xmp sidecar per photo that made a pass, with a standard rating. Photos you set aside get nothing written. Before a sidecar is replaced, Lumina keeps a backup copy. Export copies the RAW files or JPEGs, and checks every copy.
Three cards: “Originals stay put” Lumina never changes the RAW, and it never writes to the card. “A backup first” Replacing a sidecar leaves a .lumina-bak beside it. “Copies are checked” An export is a copy, verified against the file it came from.
Image: save.jpg.
Do not add the names of other photo apps anywhere in the layout. The screenshot already contains some; leave them inside the picture and do not repeat them in text.

7. A full-width band in #262523. Kicker “Private by design”. Title “No account. Nothing leaves your Mac.”
Three cards on the page background: “No network of its own” Lumina makes no network connections. There is no account, no analytics, no crash reporting of its own, and no advertising. “Photos stay in place” Lumina reads only the folders and cards you choose. Ratings are .xmp files next to those photos. “Decisions stay on the Mac” Your place in a shoot is kept in the app’s own folder. Removing that folder removes them.
A quiet 12px line: If macOS is set to share analytics with app developers, Apple may send an anonymous crash report. That switch belongs to macOS.

8. FAQ. Kicker “FAQ”. Title “Practical questions.” Disclosure rows, background #262523, radius 12, inset hairline. Questions and answers:
Which files does it read? — Sony ARW files, in a folder you open or on a memory card. DNG too. JPEG and HEIC aren’t supported yet. Files stay where they are.
Where are the ratings? — Save writes a .xmp file next to each photo, with the same name. Other photo apps that read XMP sidecars pick the ratings up from there.
Why can’t I save on the card? — Lumina never writes to a memory card. Copy the shoot to the Mac first, then save there.
What happens to photos I don’t keep? — Nothing is written and nothing is deleted. A later pass can look at only the keepers, and you can go back to the whole shoot.
Where are my decisions kept? — In the app’s own folder on your Mac. They stay when you quit and are back when you reopen the same folder.
What does it need? — A Mac with Apple silicon, and macOS 15 or later.

9. A second #262523 band. Kicker “Beta 0.01”. Title “Write, and I’ll send the beta.”
Body: Lumina is a Mac app. It isn’t on the App Store yet. Tell me the Mac model and the macOS version, and what you shoot.
Gold button links to mailto:anikethcov@gmail.com with subject “Lumina beta”. Quiet button: DM @aniketh745, linking to https://x.com/aniketh745.

Footer, 13px, dim, with the serif wordmark: Lumina · Cull a Sony shoot, keys first · Privacy · anikethcov@gmail.com · @aniketh745.

LAYOUT RULES
Content width 1120. Page background is one continuous #1E1D1B. Sections stack. Do not put the hero copy in a two-column split with the screenshot: the app’s chrome has to stay large enough to read.
Gold appears only on the Beta pill, the primary buttons, and focus. Headlines stay #EFECE6.
Desktop first, then a single column under 900px. The step control may drop to its own row. No hamburger that hides the steps.
Respect reduced motion: no rise animation in that case.
Do not mention Lightroom, Capture One, or camera logos in any text you write.
Do not add pricing, testimonials, a logo farm, a newsletter box, or a fake download count.
```

## Components

| Piece | Spec |
|---|---|
| Page | `#1E1D1B`, system sans, tabular numbers, antialiased |
| Bar | 52px, `#262523`, bottom hairline `rgba(239,236,230,0.08)`, sticky |
| Wordmark | Iowan Old Style 21 / 400 |
| Beta | 11 / 600, `#FFD27A` on `rgba(255,210,122,0.14)`, radius 5 |
| Steps | 4 × 88px, track `rgba(239,236,230,0.08)`, selected `#5B5854`, slide 200ms `cubic-bezier(0.2, 0.8, 0.2, 1)` |
| Primary button | `#FFD27A` / `#1E1D1B`, 15 / 800, radius 11, padding 12×18, key chip `rgba(30,29,27,0.14)` |
| Quiet button | `rgba(239,236,230,0.08)` / `#EFECE6`, 600 |
| Press | `translateY(1px) scale(0.98)` |
| Focus | 2px `#FFD27A`, offset 2 |
| Card | `#262523`, radius 14, padding 16×18. Serif title 21 / 400 |
| Open card | `#2A2927`, radius 16, padding 22×24 |
| Open folder | `#262523`, inset ring 1.5px `rgba(239,236,230,0.16)`, `⌘O` keycap `#3A3835` with a 2px lip `#161514` |
| Screenshot frame | radius 12, outline 1px `rgba(239,236,230,0.14)`, shadow `0 18px 40px rgba(0,0,0,0.28)`. The shadow is the one place the page is softer than the app, so the window separates from the page |
| Key bar | fixed, 34px, `#262523`, top hairline `rgba(239,236,230,0.06)`, 12px |
| Rise | 6px, 160ms, hero only. Off when the system asks for reduced motion |

## Voice

Sentences are short and concrete. The headline is the App Store line, “Cull a shoot before the coffee is cold.” Say “Sony ARW files” and “standard XMP”. Say what the app does: one key keeps, one key sets aside, the card is read-only, nothing is deleted, nothing leaves the Mac.

Leave out competitor names, camera logos, and any claim that Edit matches another developer. The look stays in Lumina. The rating is what is written out.

## Shots

| File | Use |
|---|---|
| `docs/screenshots/large-view.jpg` | Hero. 1440 × 900 |
| `docs/screenshots/pick-kept.jpg` | Pick. 1440 × 900. A row near the bottom is blank in this capture; the gold outlines and the picks tray are why this shot is used |
| `docs/screenshots/edit.jpg` | Edit. 1440 × 789 |
| `docs/screenshots/save.jpg` | Save. 1440 × 900. Contains other apps’ names inside the product UI |

`pick-grid.jpg` is the same shoot with the frames spread far apart on the time axis. It reads as an empty window at this size, so the page uses `pick-kept.jpg`.
