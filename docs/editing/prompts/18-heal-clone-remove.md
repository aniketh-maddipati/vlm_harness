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

**UX** (from `docs/editing/UX.md`; this section is the UI spec, and where the UI bullets above differ, it wins). Built on the shared hand kit (prompt 00c: puck, detents with haptics, pinch / rotate / pressure, chrome dim, hover handles, select-then-touch carry, the fan); use its pieces, don't rebuild them. Everything follows UX.md's grammar and polish tokens.

*Retouch: heal, clone, remove (18)*

- **Do:** J, then click a blemish: healed at once, with the source found for you. Paint over a
  distraction with the remove brush; release and it is gone.
- **Hands:**
  - Drag from the heal ring to move its source; a hairline thread shows the source.
  - ⇧J = clone.
  - Hold ⌥ to see every ring; click one to edit it, ⌫ to remove it.
- **Repeat:** sensor dust carries across the shoot and every clip from the body, by itself (the spots
  sit in the same place). Other heals don't carry, and the chip says so.

**Skim (video) mirror.** Two direct mirrors:
- **Sensor dust on video:** a spot is fixed in the frame across every clip from that body and day. `LookDust`'s across-the-shoot search fits video better than stills; heal it per clip and export it as a patch over the clip (the `SkimPlate` patch path).
- **Remove** already exists in Skim (`SkimPlate`, clean plate for a still camera). The heal/clone UI grammar (J, ⇧J, rings) should match it.
