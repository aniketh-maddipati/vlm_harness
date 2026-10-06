# Prompt for Cursor (Grok): validate 8g and decide ⇧A

Context: `lumina-core-v4.js` buildShoot now judges "soft" and "blown" relative to the photo's stack or row (8g). "slight" is gone. ⇧A suggested picks are hidden behind `Component.AUTO_ON=false` in Lumina Sets v7.dc.html. When it was last measured, ⇧A proposed ~69% of photos and missed 24% of the photographer's picks.

Do this, changing nothing else:
1. Run `make culleval` on every labelled shoot in Tools/culleval. Report per shoot and overall:
   - share of photos auto-proposed;
   - recall (the photographer's picks that ⇧A proposes);
   - precision;
   - how many soft/blown words land on photos the photographer kept (false alarms).
2. Compare against the pre-8g baseline (git stash the core change or use b9d5107).
3. If recall < 90% or proposed share > 1.5× the photographer's pick rate, tune only these constants in buildShoot and re-run:
   - soft `0.45×` stack max;
   - blown `clip ≥ 3` and `> min + 3`;
   - row clip `max(5, median × 2.5)`.
   Don't change any other logic, and don't overfit: hold one shoot out and report it separately.
4. If, after tuning, recall ≥ 90%, proposed ≤ 1.5× the pick rate and the held-out shoot is within 5 points, set `AUTO_ON = true` in Sets v7. Otherwise leave it false.
5. Write the before/after table and the final constants into Tools/culleval/RESULTS.md. Add a lumina-core-v4.test.mjs case per rule:
   - a single with no stack has no "soft";
   - a burst frame below 0.45× its sharpest frame is "soft";
   - a bracket never gets "blown";
   - a single at 6% clip in a row with a median of 1% is "blown", and in a row with a median of 4% it isn't.
