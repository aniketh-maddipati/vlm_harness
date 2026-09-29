# Addendum 1 · applies on top of the v5 package

Read this after PROMPT.md. Where it differs from PARITY.md or CHANGES-v4-beta.md, this file wins. The page, grammar and self-test in this folder are already updated to match it.

## 1. Arrows walk into stacks (two-handed culling)
- **Why:** with both hands on the keyboard, people forget to hold ⇧ to get into a burst.
- **Plain ←→ on a closed stack:**
  - The stack opens in place, at the first frame going forward or the last frame going back.
  - Arrows step through its frames, then carry on to the next photo and close the stack.
  - Holding the key repeats all the way through.
- **Skipping:** ⌥←→ jumps over a whole stack or run of singles.
- **⇧←→:** does the same as plain arrows but stops at the ends of the stack.
- **Setting:** Settings → "Arrows enter stacks" (On by default). Off restores the old behaviour, where plain arrows step one unit and ⇧ is needed to go inside.
- **Where:** `cullKey()` arrow branches, `prefs.enter`.

## 2. The same controls everywhere
- **Keep pill, three places:**
  - The focused tile.
  - Every frame of an open stack.
  - Large view, bottom centre of the photo, 30 high.
- **Keep pill states:** "Keep" is dark `rgba(22,21,20,.82)` with light text. "✓ Kept" is `#FFECCD` with dark text. Clicking toggles, exactly like P.
- **Flagged photos:** large view also shows a "Flagged" pill (`#FFD27A`); clicking it unflags. Tiles show the "flag" chip.
- **⇧P / ⇧R and ⇧F:** behave the same on an open stack as on a closed one. ⇧P / ⇧R keeps only the sharpest (a bracket keeps all); ⇧F flags or unflags every frame.

## 3. Key bar matches what the keys do
| Context | Key bar |
|---|---|
| Photo | ←→ Photos · ↑↓ Rows · P / R Keep · F Flag · Space Large · ⏎ Next row · Q Undo |
| Closed stack | ←→ Into frames · ⌥←→ Skip stack · P / R Keep sharpest · ⇧F Flag all · Space Large · Q Undo |
| Frame in an open stack | ←→ Frames, then on · P / R Keep · F Flag · ⏎ Done · esc Close · Q Undo |
| Large view | ←→ Photos · P / R Keep · F Flag · Z 100% · esc Close |
| Save | ⌘⏎ Save · ⌘R Show in Finder · ⌘2 Back to cull |
- The "/" between alias keys is a plain separator, not a keycap.
- With "Arrows enter stacks" off, the closed-stack and frame rows show ⇧←→ instead.

## 4. Fits every Mac screen
- **Tile sizes:** tiles scale with the cull area's width, `scale = clamp(0.85, width / 1400, 1.5)`. At 1440 wide the three sizes are 96 / 144 / 216; on a 2560 display they are about 1.5× that.
- **Side padding:** `clamp(16px, 2.2vw, 40px)`. The column count uses the same value.
- **Motion:**
  - Tile width and height animate 180 ms when the size or window changes.
  - Row height animates 180 ms.
  - Single moves scroll smoothly. Held keys scroll instantly, so the cursor never lags.
  - Reduced motion turns all of this off.
- **One easing curve** for anything that moves: `cubic-bezier(0.2, 0.8, 0.2, 1)`. Fades stay ease-out 120–160 ms.
- **? sheet:** columns are `repeat(auto-fit, minmax(300px, 1fr))`, so it drops to two columns under about 1,250 px. Keys sit in a 120 px column and wrap.
- **Minimum window:** 1024 × 700. Test at 1280×800, 1440×900, 1512×982, 1728×1117, 1920×1080 and 2560×1440.

## 5. Grammar and on-screen controls agree
- GRAMMAR.md is rewritten to match the code.
- It uses the step names Open, Cull and Save throughout.
- It no longer lists fixed tile sizes.
- The "not used" line now says the footer names the right key.
- The stack tooltip reads "cover: sharpest · → opens, ⌥→ skips".

## 6. Self-test
- The self-test now has 25 checks, including:
  - → walks into a stack.
  - → past the last frame moves on.
  - ⌥→ skips a stack.
  - esc closes an open stack.
- In the design preview all 24 behaviour checks pass. The timing check reads 60–90 ms there because the preview throttles animation frames; the key handler itself takes 0.2 ms. Measure timing in the real app, where the target is still a median under 50 ms.
