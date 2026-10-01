// The page's own culling logic (design/handoff/lumina-cull/lumina-core-v4.js, shipped byte for byte),
// loaded as it is and asked for its rows, stacks, flags and keeps. Nothing here re-implements it.
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
export const DESIGN = path.join(ROOT, 'design/handoff/lumina-cull');
const names = fs.readFileSync(path.join(ROOT, 'Scripts/page_files.sh'), 'utf8');
export const CORE_FILE = path.join(DESIGN, /^CORE="(.*)"$/m.exec(names)[1]);
export const PAGE_FILE = path.join(DESIGN, /^PAGE="(.*)"$/m.exec(names)[1]);
export const LuminaCore = createRequire(import.meta.url)(CORE_FILE);
export const sha = s => crypto.createHash('sha256').update(s).digest('hex').slice(0, 16);
export const coreHash = () => sha(fs.readFileSync(CORE_FILE));

// list: what the page's readOne returns per photo ({name, path, date, exp, fl, ev, iso, lens, serial,
// program, wb, flash, seqImage, seqLength, releaseMode2, portrait, dhash, lum, focus, clip, nopv}).
// Returns, keyed by path:
//   stack    Map path → stack label (a single is its own stack)      row   Map path → row label
//   stacks   [{ids, kind, pick, sug}]  pick = what P on the closed stack keeps (the sharpest;
//            a bracket keeps all, pick = null), sug = the core's suggested keep(s) in it
//   sug      Set of paths the core suggests keeping (sugKeep)
//   pagePick Set of paths P keeps when pressed once on every unit (stack → sharpest, bracket → all, single → itself)
//   flags    Map path → {soft, blown, shake, dark, sharp, focus, rank, bn, kind}
export function run(list, cuts = {}) {
  const d = LuminaCore.buildShoot(list, cuts), P = id => d.byId[id].path;
  const stack = new Map(), row = new Map(), flags = new Map(), sug = new Set(), pagePick = new Set(), stacks = [];
  for (const m of d.M) for (const f of m.fr) row.set(f.path, m.id);
  for (const g of Object.values(d.G)) {
    const ids = g.frames.map(f => f.path), bracket = g.kind === 'bracket';
    const pick = bracket ? null : g.ranked[0].path, s = g.frames.filter(f => d.sugKeep[f.id]).map(f => f.path);
    stacks.push({ ids, kind: g.kind, pick, sug: s });
    (bracket ? ids : [pick]).forEach(p => pagePick.add(p));
    for (const f of g.frames) {
      stack.set(f.path, g.gid);
      flags.set(f.path, { soft: !!f.soft, blown: !!f.blown, shake: !!f.shake, dark: !!f.dark, sharp: f.sharp, focus: f.focus, rank: f.rank, bn: f.bn, kind: g.kind });
    }
  }
  Object.keys(d.sugKeep).forEach(id => sug.add(P(id)));
  return { stack, row, stacks, sug, pagePick, flags, order: d.order.map(P), rows: d.M.length, idOf: new Map(Object.values(d.byId).map(f => [f.path, f.id])) };
}

// The photographer's own stacking, said the way the page hears it (B / ⇧B, a drop onto a stack):
// cuts that make each truth group one stack. Then run(list, cuts) answers "had these been stacked,
// which frame would Lumina keep". first: a plain run(list) for the page's ids. A row boundary inside
// a truth group still splits it (a row cut and a stack cut share one key); the caller counts those.
export function cutsFor(first, truth, inOrder) {
  const cuts = {}; let prev;
  for (const p of inOrder) {
    const t = truth.get(p);
    cuts[first.idOf.get(p)] = t !== prev;        // true: a stack starts here · false: joins the frame before
    prev = t;
  }
  return cuts;
}
