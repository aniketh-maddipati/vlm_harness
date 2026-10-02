# Design asks for the native handoff (`lumina-app`)

Status: open. These are asks for the **native** rebuild (`design/handoff/lumina-app/`, built in
`LuminaKit/` and `Lumina/Native/`). The Sets page's asks stay in `design/handoff/DESIGN-ASKS.md`.
Paste a prompt below into Claude Design. When the updated handoff comes back, replace the
changed files in `design/handoff/lumina-app/`, and build to them in `LuminaKit/` (authority:
this handoff's README, then BEHAVIOR_SPEC, then the prototypes).

---

## Prompt 1: first-run tips, a tutorial and Questions (paste into Claude Design)

Why: the handoff's goal is that "a first-timer can't get lost, can't lose work, and can't trigger
something they didn't see coming" (README, Overview). The first-timer suite
(`prototypes/Lumina Newbie Test.dc.html`) checks that the app survives a first-timer. It doesn't
check whether one learns it. What trips people up there: they open the wrong files, go
to Edit with nothing kept, click Start over by accident, mash Esc, never touch the keyboard, put
everything Out and then try to Save. Today the only teaching is the Edit intro
(`lumina.edit.intro.v1`) and Help (`?`), and both exist only in Edit. A first-timer never sees R and X
explained before Cull's footer line. They're never told that Out deletes nothing, or what Save
will write.

> Update the Lumina handoff (`README.md`, `BEHAVIOR_SPEC.md`, `KEYMAP.md`,
> `ACCESSIBILITY_CONTRACT.md`, `TEST_PLAN.md`, `prototypes/Lumina Workflow.dc.html`,
> `prototypes/Lumina Edit v19.dc.html`) to add **minimal onboarding**: three first-run tips, a
> learn-by-doing tutorial on a sample shoot, and a Questions page in Help. Keep every existing
> screen, key, token, motion and string as it is, except where this prompt names a change. Stay
> inside the README's tokens (colours, type, radii, spacing, motion) and LAYOUT_SIZING's rules.
>
> **The UI scale is the app's, not LAYOUT_SIZING §3's** (ruled 2026-10-02):
> `S = clamp(1.0, min(w / 1280, h / 800), 1.5)`. S is 1 at 1280×800, 1.35 at 1920×1080 and 1.5 at
> 2560×1440. Every size below is in points at S = 1. Multiply chrome by S, round fonts to
> 0.5pt and everything else to 1pt.
>
> ### 0. Principles (write these into the README as a new section, "Onboarding")
> - **Few.** A first-timer meets at most **three tips**: one on Open, one in Cull, one in Edit. Save
>   gets no tip. Its screen already says what it writes and the Saved card says what to do next.
> - **Never blocking.** No tip disables a control or swallows a key that the step uses. The Open and Cull
>   tips sit in slots that already exist (Open's Recent slot, Cull's footer message line). The Edit
>   tip *is* the existing intro, which already closes with one key (Esc or ⏎). It stays the only
>   modal one.
> - **Once.** A tip that has been dismissed, or made moot by the action it teaches, never comes back on its
>   own. Each one has a flag:
>   `lumina.onboard.open.v1`, `lumina.onboard.cull.v1`, and the existing `lumina.edit.intro.v1`.
>   They're kept where the intro flag is kept today: the app's defaults, or a marker file in
>   `LUMINA_STORE_DIR` under test.
> - **One teacher at a time.** At most one teaching surface shows at a time: a tip, the
>   tutorial's guide card or Help. While the tutorial runs, no tip shows.
> - **Always reachable again.** Help gets "Take the tutorial" and "Show the tips again". The Help
>   menu has both, plus "Questions".
> - **Reuse.** The only new piece of chrome is the tutorial's guide card (§3). Everything else reuses
>   an existing component: the Recent row, the footer message line, the intro, Help, the key cap,
>   the 3pt gold progress bar, and the gold selection ring from Variations.
> - **House tone.** Plain words, short sentences, second person, no exclamation marks, curly
>   apostrophes (’). Key names are shown as key caps in SF Mono.
>
> ### 1. The three tips
>
> **1a. Open, first launch** (shown when nothing has ever been opened and the flag is unset).
> It takes the **Recent slot** at the bottom of the Open column. Recent is empty on a first launch, so
> nothing moves. It uses the Recent label and row tokens exactly:
> - Label (12pt `#96918A`): `New here`
> - Row (padding 12/14, radius 9, fill `rgba(239,236,230,0.04)`, `0.09` on hover):
>   - Title 13.5pt `#EFECE6`: `Try Lumina on a sample shoot`
>   - Subline 12pt `#96918A`: `117 photos · about 5 minutes · your own files aren’t touched`
>   - On the right, in this order:
>     - a secondary button (height 32, padding 0/14, radius 8): `Start tutorial`
>     - a 12pt text button `Not now`, followed by the key cap `esc`
>   - Under 560 wide, the buttons wrap below the subline, left-aligned.
> - **Keys.** Esc dismisses the row. ⏎ keeps its Open meaning (R-01: copy & start culling, or
>   continue), and doing that marks the tip seen. If Open has nothing to start, ⏎ dismisses the row.
>   ⌘O, a drop, or any import also marks it seen.
> - Clicking `Not now` or pressing Esc fades the row out over 120ms (instant with reduced motion) and
>   says nothing else. The Recent row takes the slot from then on.
>
> **1b. Cull, first arrival** (shown when Cull first has a photo and the flag is unset). Cull's
> footer message line (`cull.message`) shows the tip instead of the key reminder. It uses the same slot, the same
> single line and the same truncation, but in `#B8B3AB` (secondary) instead of `#96918A`:
> - `R keeps a photo, X leaves it out. Lumina moves on by itself. ⌘Z undoes.`
> - followed by a 24-high chip (padding 0/10, radius 6, fill `rgba(239,236,230,0.08)`): `Got it`
>   plus the key cap `esc`.
> - **Keys.** R and X work at once: the tip doesn't own the keyboard. The first R or X marks the tip
>   seen, and for 3.5s (the toast time) the line then reads
>   `Kept. Do the same for each photo, or press U for the next undecided one.` (after R) or
>   `Out. It stays in the shoot, it just isn’t saved.` (after X).
>   After that, the key reminder returns. Esc or ⏎ in Cull (both unbound there today) dismisses
>   the tip without a message. So does clicking `Got it`.
> - **The key reminder gains Help:** it becomes
>   `R keep · X out · ← → photos · ↑ ↓ scenes · U next undecided · ⌘Z undo · ⇧⌘Z redo · ⌘3 Edit · ⌘4 Save · ? help`.
>   It still truncates from the end, so `? help` is the first part to go on a narrow window.
>
> **1c. Edit, first arrival.** This is the existing intro (`IntroContent`, three cards,
> `lumina.edit.intro.v1`), unchanged in copy and behaviour. Two changes:
> - It doesn't show while the tutorial runs.
> - Finishing the tutorial's Edit step (§2, step 5) marks it seen.
>
> **Help → `Show the tips again`** (replaces `Show the intro again`, same place, same
> identifier `edit.help.intro`) clears all three flags and closes Help. In Edit it then shows the
> intro at once, as it does today. On Open and Cull, that step's tip shows at once.
>
> ### 2. The tutorial: learn by doing on a sample shoot
>
> **What it runs on.** A sample shoot that ships inside the app. It has the demo card's 117 photos, 5 scenes,
> 19 bursts and 44 suggested keepers, with the same ids, times and camera details
> (`parity/demo-shoot-117.json`, ILCE-7M4). The pixels are **bundled images**, never fetched,
> because nothing leaves the Mac. The tutorial runs in **its own session**:
> - Its copy, decisions, edits and saves live in a practice folder in Lumina's app data.
> - That folder is deleted when the tutorial ends.
> - The user's own shoot, step, decisions and edits are untouched while it runs, and are back
>   exactly as they were when it ends.
>
> **How it starts.** Any of these starts it:
> - `Start tutorial` on Open
> - Help → `Take the tutorial`
> - Help menu → `Take the Tutorial`
>
> It always starts at step 1 with a fresh sample. It is never offered again after it's finished or
> skipped, except from Help. It doesn't survive a quit: the next launch opens on the user's own
> shoot, as if it had been skipped.
>
> **What completes a step is the state change, not the key.** Clicking Keep, pressing R, or
> VoiceOver's VO-Space on `cull.keep` all count. Each step names its keyboard route, so the whole
> tutorial works without a pointer.
>
> | # | Step | Guide card title | Guide card body | Completes when | Ring on | Done line |
> |---|---|---|---|---|---|---|
> | 1 | Open | `Press ⏎ to copy the sample in` | `This is a practice card: 117 photos from one day. Lumina copies it and checks every file. You can start before it finishes.` | the step becomes Cull | `open.card` | `Copying. Photos arrive as they’re checked.` |
> | 2 | Cull | `Press R to keep this photo` | `Lumina moves to the next one by itself. Gold rings are suggestions; you still decide.` | a photo is kept | `cull.keep` | `Kept. The gold tick marks a keeper.` |
> | 3 | Cull | `Press X to leave one out` | `It turns grey and stays in the shoot. Nothing is deleted.` | a photo is Out | `cull.out` | `Out. It won’t be saved.` |
> | 4 | Cull | `Press ⌘Z to undo that` | `Every decision can be undone, up to 200 steps. ⇧⌘Z redoes.` | a decision is undone (⌘Z, or Edit › Undo in the menu bar) | (none: Cull has no undo button) | `Undone.` |
> | 5 | Edit | `Press ⌘3, then A for Auto` | `Editing is optional and works on the photos you keep. Any slider works too, and ⌘Z undoes it.` | in Edit, a kept photo's look is not empty | `step.edit`, then `edit.tool.auto` | `Edited. Edits save as you go.` |
> | 6 | Save | `Press ⌘4, then ⌘S to save` | `Here Save writes to a practice folder that goes away when you finish. Your own shoots save next to their copies.` | the Saved card exists | `step.save`, then `save.button` | `Saved.` |
>
> - **Step 5 with nothing kept** (the user undid past their keep). Edit shows its empty state
>   (R-45), and the card's title becomes `Keep a photo first: ⌘2, then R`. The body is unchanged and the
>   ring moves to `edit.empty.goCull`. The step completes as soon as the edit lands.
> - **Doing a step early counts.** If the user presses X during step 2, step 3 is done when they
>   reach it. The tutorial skips ahead in order and never sends anyone back.
> - **Between steps.** The done line replaces the title for 900ms with a 16pt gold ✓ in front. Then
>   the next step's title and body show. The ✓ uses the 200ms "pop"; with reduced motion it is
>   static and the 900ms stays.
> - **The ring.** The gold selection ring from Variations (`0 0 0 2px #161514, 0 0 0 4px #FFD27A`),
>   drawn around the control the step names. It is static: no pulse, no loop (R-61). It's removed the
>   moment that control is used.
>
> **The end card.** After step 6, the guide card shows:
> - Title: `That’s all four steps`
> - Body: `Open, Cull, Edit if you like, Save. Press ? any time for shortcuts and answers.`
> - Buttons: primary `Open my photos` with key cap `⌘O` (ends the tutorial, then shows the folder
>   picker), and secondary `Done` with key cap `⏎`.
> - ⏎ or Esc closes it. Here, and only here, the card owns ⏎. On Save, ⏎ after a save does
>   nothing anyway (R-34).
> - When it closes, the flag `lumina.tutorial.v1` becomes `done`.
>
> **Skipping.** `Skip` in the card's header ends the tutorial at once. Esc can also skip it, but it
> is the **last** layer in the Esc chain, after R-25's layers (focus, zoom, before, the scene grid,
> the picker, Help, Crop, Variations):
> - If Esc has nothing else to back out of, the first press only changes the card's kicker to
>   `Press esc again to leave the tutorial` for 4s (the Start over pattern, R-31).
> - A second Esc within those 4s leaves.
> - So R-25's "at most 3 Esc presses back to normal" still holds, with normal meaning that the
>   tutorial is still showing.
>
> Leaving sets the flag to `skipped`, deletes the practice folder and restores the user's state.
> The step's own message line then says `Tutorial closed. It’s in Help when you want it.`
>
> ### 3. The guide card (the one new component)
> - **Look.** It reuses the Recent-row and overlay tokens:
>   - fill `#262523`, radius 12, padding 14/16, gap 8
>   - inset hairline `rgba(239,236,230,0.08)`, shadow `0 8 24 rgba(0,0,0,0.4)`
> - **Contents, top to bottom:**
>   1. Kicker row, 12pt `#96918A`: `Tutorial · 2 of 6` on the left; on the right, the `Skip` text
>      button (12pt, `#EFECE6` on hover) and the key cap `esc`.
>   2. Title: 13.5pt, 600 weight, `#EFECE6`. Key names in it are key caps (SF Mono 11.5).
>   3. Body: 12.5pt `#B8B3AB`, line height 1.5, wraps.
>   4. Progress: the 3pt gold bar (track `rgba(239,236,230,0.1)`) at n/6.
> - **Where it sits.** It is anchored to the bottom-left of the step's content. It never covers the
>   step's main action (`open.card`, `cull.toSave`, `save.button`, Edit's `edit.next`).
>   - **Open and Save:** 16 from the left and bottom of the window.
>   - **Cull:** 16 from the left, 12 above the footer.
>   - **Edit:** inside the canvas, 12 from its left and bottom edges, above the filmstrip.
>   - **Width:** `clamp(280, 0.24 × w, 360) × S`, and never more than `w − 32`.
> - **If it would overlap the main action** (narrow windows), the step's scroll content gets a bottom
>   inset of the card's height plus 16, so the action scrolls clear of it. The card never scrolls.
> - **Compact** (under 560 wide or under 480 tall, R-50 sizes such as 375×812 and 600×300): one line,
>   full width minus 16 on each side:
>   - `2/6` in `#96918A`, then the title (truncating), then `Skip`
>   - the body and the bar are hidden
>   - the line is at least 28 high (R-54)
> - **Motion:** it fades in over 120ms, and the title changes cross-fade over 120ms. With reduced
>   motion, every duration is 0 and the ✓ doesn't pop.
> - **Keys:** the card owns no keys except ⏎ and Esc on the end card. Tab reaches `Skip`
>   (and the end card's buttons) last in the window's focus loop.
> - **VoiceOver:**
>   - The card is one container labelled `Tutorial, step 2 of 6`.
>   - Each step change posts an announcement: `Step 2 of 6. Press R to keep this photo.`
>   - Each done line is announced too.
>   - The ring has no accessibility element of its own. The targeted control's label is unchanged.
>
> ### 4. Help on every step, with Questions
> - **`?` opens Help on every step**, not just Edit. In KEYMAP, `?` moves from the Edit table to
>   Global. Help still owns the keyboard (R-23), and a text field still comes first.
> - **Two tabs** at the top of the Help panel. They use the step-tab control (24 high, 13pt, thumb
>   `#5B5854`, 160ms slide, none with reduced motion): `Shortcuts` · `Questions`.
>   - Help opens on Shortcuts. The Help menu's `Questions` item opens it on Questions.
>   - ← → switch tabs. They're Help's, so they never reach the photo underneath.
>   - ↑ ↓ and Space scroll. Esc closes.
> - **Shortcuts** gains two groups, ahead of the five existing ones. Every key must match KEYMAP
>   (R-26).
>   - `Anywhere`:
>     - `⌘1 – ⌘4` Open · Cull · Edit · Save
>     - `⌘S` go to Save · on Save, save
>     - `⌘O` open a folder
>     - `drop` add photos or folders
>     - `?` this help
>   - `Cull`:
>     - `R` keep · moves on
>     - `X` out · moves on
>     - `← →` previous / next photo
>     - `↑ ↓` previous / next scene
>     - `U` next undecided
>     - `⌘Z · ⇧⌘Z` undo · redo
>
>   On Open, Cull and Save, the panel shows `Anywhere` and `Cull` first. In Edit it shows
>   `Essentials` first, as today.
> - **Footer** of both tabs, left to right: `Take the tutorial` and `Show the tips again`. They are
>   12pt outlined text buttons, the style of today's `Show the intro again`.
> - **Questions.** One column, max width 640 × S, inside the same panel.
>   - Group headings: gold, 12pt, 700 weight, the Help group style.
>   - Each question: 13.5pt, 600 weight, `#EFECE6`.
>   - Each answer: 13pt `#B8B3AB`, line height 1.5.
>   - 14 between entries, 22 between groups.
>   - Everything is expanded: no disclosure triangles and no search, because 15 short answers fit
>     in two screens.
> - **Help menu** (native menu bar, replaces the window's Help items):
>   - `Lumina Help  ?`
>   - `Questions`
>   - `Take the Tutorial`
>   - `Show Tips Again`
>
> **The questions and answers, exactly.** Every answer states the app's behaviour as specified. The
> source for each is in brackets. It's for review, not shown on screen.
>
> *Your photos*
> 1. **Does Lumina change my photos or the card?** No. Lumina only reads the card, and it never
>    changes, moves or deletes an original. What it writes is copies, and small files next to those
>    copies when you save. [README §1 subtitle, §4 subtitle; AGENTS.md trust rules]
> 2. **Where do the copies go?** To ~/Pictures/Lumina, in a folder for the shoot. Folder and JPEG
>    saves go there too, unless you choose another place with Change…. [README §1, §4 Destination;
>    `exportDestination`]
> 3. **When can I take the card out?** When the top bar says “All 117 copied and checked”, with
>    your own count. You can start culling long before that, because photos appear in Cull as
>    they’re checked. [README top bar, §2 copying line; R-80]
> 4. **Does anything leave my Mac?** No. Lumina works on the files on your Mac and doesn’t send
>    them anywhere. [AGENTS.md trust rules]
> 5. **What if I close the window or quit?** Nothing is lost. Lumina keeps every decision and
>    edit as you make it, and opens on the same step next time. An unfinished copy picks up where it
>    stopped. [R-70, R-1A, README State › Persistence]
>
> *Culling*
> 6. **What do Keep and Out do?** R keeps a photo and X leaves it out. Either way, Lumina moves to
>    the next one. Out photos turn grey and stay in the shoot; they just aren’t saved. [KEYMAP Cull;
>    README §2 tiles, §4 summary]
> 7. **Can I undo?** Yes. ⌘Z undoes the last decision and ⇧⌘Z redoes it, up to 200 steps. In
>    Edit, ⌘Z undoes edits only and never touches your Cull decisions. [R-04, R-27, README State]
> 8. **What are scenes?** Groups of photos taken around the same time. A gap of more than 30
>    minutes, or a subfolder, starts a new scene, and ↑ ↓ jump between scenes. [R-15, KEYMAP Cull]
> 9. **What are bursts?** Frames taken 2 seconds apart or less, up to 8, marked by a thin bar along
>    the bottom of each tile. If you keep several frames of one burst, they share one edit. [R-15,
>    README §2 tiles, README State › Edits]
> 10. **What does the gold ring mean?** It’s a suggestion: a photo Lumina thinks you may want to
>     keep. It decides nothing. The “Keep … suggested” button by each scene’s time keeps the
>     suggested photos you haven’t decided yet. [README §2 scene header tooltip]
>
> *Editing and saving*
> 11. **Do I have to edit?** No. Edit is optional, and nothing changes unless you move a setting.
>     You can go from Cull straight to Save with ⌘4. [README top-bar tooltip]
> 12. **What does Save write for Lightroom?** A small .xmp file next to each RAW, with keepers as 3★,
>     plus your edits as develop settings when Include my edits is on. The RAW is untouched. If a
>     photo already has an .xmp, Lumina adds to it and keeps the old one as .lumina-bak. [README §4;
>     AGENTS.md "The native Save writes edits to XMP"]
> 13. **How do I get my keepers into Lightroom?** In Lightroom, choose Import → Add and pick the
>     shoot folder. For photos already in your catalog, select them and choose Metadata → Read
>     Metadata from Files. [README §4 Saved card hint]
> 14. **What do Folder and JPEG do?** Folder copies your keepers’ RAW files into a new folder, with
>     an .xmp for edited ones. JPEG makes full-size sRGB JPEGs with your edits baked in, ready to
>     share or upload. [README §4 descriptions, Saved card hint]
> 15. **Can I save again?** Yes, any time. Save again rewrites only what changed since the last
>     save, and does nothing if nothing changed. [R-34, README §4 note]
>
> ### 5. Accessibility identifiers and test hooks (add to ACCESSIBILITY_CONTRACT.md)
> | Area | Identifier | Element |
> |---|---|---|
> | Open | `open.welcome` | The `New here` row (value = its title) |
> | Open | `open.welcome.tutorial` `open.welcome.dismiss` | `Start tutorial`, `Not now` |
> | Cull | `cull.message` | Unchanged id. Its value is the tip's text while the tip shows. |
> | Cull | `cull.tip.dismiss` | `Got it` |
> | Help | `edit.help` | Unchanged id, now on every step |
> | Help | `help.tab.shortcuts` `help.tab.questions` | Tabs. `isSelected` on the current one. |
> | Help | `help.group.{anywhere,cull,essentials,move,edit,look,trackpad}` | Shortcut groups |
> | Help | `help.question.{1…15}` `help.answer.{1…15}` | Each question and its answer (value = full text) |
> | Help | `help.tutorial` | `Take the tutorial` |
> | Help | `edit.help.intro` | Unchanged id, now `Show the tips again` |
> | Tutorial | `tutorial.card` | The guide card. Value = `"{n}/6"`, or `"end"` on the end card. |
> | Tutorial | `tutorial.title` `tutorial.body` | Value = the text shown |
> | Tutorial | `tutorial.skip` `tutorial.done` `tutorial.openOwn` | Buttons |
>
> **Hooks** (UI-test builds only, like the others):
> - **`LUMINA_INTRO=skip`** now hides all three tips and never offers the tutorial. Every existing UI
>   test launches with it, so the current suites stay as they are.
> - **`LUMINA_INTRO=show`** shows all three tips even when they've been seen.
> - **`LUMINA_TUTORIAL=start`** starts the tutorial at launch.
> - **`LUMINA_REDUCE_MOTION=1`** forces reduced motion.
> - **`debug.command`** gains `{"tutorial":"start"}`, `{"tutorial":"skip"}` and
>   `{"tips":"reset"}`.
> - **`debug.state`** gains these keys (existing keys unchanged):
>   ```json
>   "tips":{"open":true,"cull":false,"edit":false},
>   "tutorial":{"step":2,"of":6,"phase":"doing","practice":"/…/Tutorial"},
>   "helpTab":"shortcuts","announced":"Step 2 of 6. Press R to keep this photo."
>   ```
>   - `tips` holds the seen flags.
>   - `tutorial` is `null` when the tutorial isn't running. `phase` is one of `doing`, `done`,
>     `confirmLeave` or `end`.
>   - `helpTab` is `null` unless Help is open.
>   - `announced` is the last VoiceOver announcement the app posted.
> - **`debug.metrics`** gains `"motionScale"` (`0` with reduced motion, otherwise `1`) and
>   `"guideCard":[x,y,w,h]`.
>
> ### 6. New rules (add to BEHAVIOR_SPEC.md as "Onboarding (R-Hx)")
> - **R-H1** On a fresh store, at most one teaching surface (a tip, the guide card or Help) is
>   visible at any moment.
> - **R-H2** Each tip shows at most once per store. Esc, ⏎ (as §1 defines it) or the action it
>   teaches dismisses it, and it doesn't return after a relaunch.
> - **R-H3** No tip blocks its step. With the Cull tip showing, R keeps at once, and Open's ⏎
>   behaves exactly as R-01.
> - **R-H4** `Show the tips again` brings back all three. `Take the tutorial` starts at step 1 on any
>   step.
> - **R-H5** The tutorial completes by state, not by key. Clicks, keys and VoiceOver actions all
>   advance it.
> - **R-H6** The tutorial never writes outside its practice folder, and deletes that folder when it
>   ends. The user's `debug.state` (`step`, `cur`, `keep`, `look`, `saved`) is identical before
>   and after.
> - **R-H7** Esc leaves the tutorial only as the last layer and only on a second press within 4s.
>   R-25 still holds.
> - **R-H8** The guide card never covers the step's main action, and the Edit photo stays at least 40×40
>   with it showing, at every R-50 size.
> - **R-H9** With reduced motion, nothing in onboarding animates (`motionScale` 0). Nothing ever
>   loops (R-61).
> - **R-H10** Every Questions answer is 1 to 3 sentences, and no onboarding string contains `!`.
>
> ### 7. States to show in the prototype
> Put a state picker in `Lumina Workflow.dc.html` (e.g. `?onboard=open-first`) for each of these:
> 1. Open, first launch, no card: the `New here` row in the Recent slot.
> 2. Open, first launch, with the demo card tile above it.
> 3. Open, first launch at 375×812: buttons wrapped.
> 4. Cull, first arrival: the tip in the footer, the key reminder hidden.
> 5. Cull, right after the first R: the 3.5s follow-up line.
> 6. Edit, first arrival: the intro, unchanged.
> 7. Help from Cull, Shortcuts tab (`Anywhere` and `Cull` first).
> 8. Help, Questions tab, scrolled to "Editing and saving".
> 9. Tutorial steps 1 to 6 at 1280×800, each with its ring.
> 10. Step 5's no-keepers variant.
> 11. The done line between two steps.
> 12. The leave confirmation kicker.
> 13. The end card on Save, with the Saved card beside it.
> 14. The guide card compact at 600×300 and 375×812.
> 15. Step 2 at 2560×1440 (S = 1.5).
> 16. Step 5 at 860×600 (Edit controls below the photo).
>
> ### 8. Not asked for
> These are out of scope on purpose:
> - Coach-mark arrows, spotlights or dimming outside the Edit intro.
> - Videos, checklists, badges or streaks.
> - A Save tip.
> - Auto-starting the tutorial.
> - A search field in Questions.
> - Anything that changes Open, Cull, Edit or Save for someone who has dismissed the tips.

### Decisions to confirm before pasting
- **Sample images.** The demo card's images in the prototype are picsum URLs, and the Unsplash
  set may not be redistributed (README › Assets). The tutorial needs 117 small images that can
  ship inside the app, licensed for redistribution or generated. The rest of this prompt holds
  either way.
- **Help on every step.** This makes `?` global, which is a KEYMAP change (§4). It is the
  smallest way to make the tips and Questions "reachable again from Help" on Open, Cull and Save.

### How Prompt 1 is checked once its handoff lands
All of these can run headless through the existing driver (`LuminaUITests/Support/Lumina.swift`,
`debug.state`, `debug.command`), one at a time, through the runner (`Tests/runner/run.sh`). The copy
checks are unit tests in `LuminaCoreTests`.
- **Copy (unit, `OnboardingCopyTests`):**
  - Every string in §1 to §4 matches the handoff byte for byte.
  - There are 15 questions in 3 groups, every answer is 1 to 3 sentences, and no string contains
    `!` (R-H10).
  - The `Anywhere` and `Cull` Help groups match KEYMAP (R-26: no `T`, and `R` isn't "rotate").
- **`test_RH2_tipsShowOnce`:**
  1. Fresh store, `LUMINA_INTRO=show`, `LUMINA_CARD=demo117`.
  2. `open.welcome` exists. Esc removes it and `tips.open` becomes true.
  3. `relaunchSoon`: `open.welcome` is absent.
- **`test_RH3_cullTipDoesNotBlock`:**
  1. ⏎ on Open lands on Cull (R-01 unchanged).
  2. `cull.message` value is the tip.
  3. One R gives `kept: 1`, then the follow-up line, then after 3.5s the key reminder.
  4. `tips.cull` is true.
- **`test_RH1_oneTeacher`:** on a fresh store with every tip due, step through Open, Cull, Edit and
  Help. At most one of `open.welcome`, the tip value in `cull.message`, `edit.intro`, `edit.help` and
  `tutorial.card` is present at any moment.
- **`test_RH4_showTipsAgain`:** `?` on Open, Cull and Save opens `edit.help`. Clicking
  `edit.help.intro` resets `tips` to all false, and the step's tip shows.
- **`test_RH5_tutorialKeyboardOnly`:**
  1. `LUMINA_TUTORIAL=start`.
  2. Keys only: ⏎ · R · X · ⌘Z · ⌘3 · A · ⌘4 · ⌘S. After each key, `tutorial.step` advances
     (1 to 6).
  3. `save.savedCard` exists, and `tutorial.card` value is `end`.
  4. ⏎ closes it.
- **`test_RH5_tutorialByClicks`:** the same run with button clicks only (`open.card`, `cull.keep`,
  `cull.out`, the menu bar's Edit › Undo, `cull.toEdit`, `edit.tool.auto`, `edit.save`,
  `save.button`).
- **`test_RH6_tutorialIsolated`:**
  1. Record `debug.state` on a fixture shoot.
  2. Run the tutorial to the end and close it.
  3. `step`, `cur`, `keep`, `look` and `saved` are equal to the recording.
  4. The `tutorial.practice` path no longer exists.
  5. No file outside it changed. Snapshot the fixture folder and `LUMINA_STORE_DIR` before and
     after.
- **`test_RH7_escLeavesLast`:**
  1. In tutorial step 5, open Crop and Help.
  2. Esc closes Help, then Crop, and the tutorial is still running.
  3. The next Esc sets `phase: confirmLeave`.
  4. Waiting 4s returns `phase` to `doing`.
  5. Two Esc presses leave: `tutorial: null`, and `cull.message` or `edit.toast` reads
     `Tutorial closed. It’s in Help when you want it.`
- **`test_RH8_guideCardLayout`:** at every R-50 size, on each step:
  - no horizontal scroll
  - `debug.metrics.guideCard` doesn't intersect the main action's frame
  - the Edit photo is at least 40×40
  - text is at least 11×S (R-54)
- **`test_RH9_reducedMotion`:** with `LUMINA_REDUCE_MOTION=1`, `motionScale` is 0. After a step
  completes, the next title is present within one frame of the 900ms done line ending.
- **`test_RH5_voiceOverAnnounces`:** each step change sets `announced` to
  `Step {n} of 6. {title}`. `tutorial.card` has the label `Tutorial, step {n} of 6`.
- **Existing suites:** with `LUMINA_INTRO=skip` (their default), every existing test runs unchanged.
  The exception is the Cull key reminder's new `· ? help` ending, so update the copy checks that read
  `cull.message`.
