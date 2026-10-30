# 18 · Heal, clone, remove

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-heal-clone-remove` from origin/main.

**Goal.** Manual spot heal, clone and object removal, next to the automatic dust that exists.

**Now.** `LookDust`: dust found across the shoot, a divide-out lift, a clone + Poisson patch for deep spots; Save writes XMP spot heals. Still inpainting (LaMa / MI-GAN) is parked.

**Build.**
- **Heal / clone:** click a spot → source found automatically (best patch by texture match, nearby) → Poisson blend (reuse `LookDust.patch`). Drag the source to change it. Clone = no blend. Keys: a list of `heal:x,y,r,sx,sy,mode` in the look string.
- **Remove:** brush an object → inpaint. LaMa (Apache-2.0) as Core ML is a model file: `TRUST.md` row plus an owner ruling. **Stop and ask.** Without it: patch-based synthesis (exemplar inpainting) for small areas.
- All of it is rendered per tier, identically; export reproduces it.
- **UI:**
  - **J** heal, **⇧J** clone, a remove brush in the Masks rail (Sort editor grammar: Heal is key 3 there).
  - The loupe shows at the cursor.
  - **⌥** shows all heals as rings; click a ring to edit it, Delete removes it.

**Done when.** On 20 photos with dust or small distractions, the owner prefers the result over Lightroom's in the A/B (`ab.html`); canvas ≡ export.

**Depends on:** 14 (rail), 15 (brush).
