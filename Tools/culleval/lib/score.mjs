// Scoring for the culling eval. Pure: ids and group labels in, numbers out. No files, no photos.
//
// A grouping is a Map id → group label (every id has one; a frame on its own has its own label).
// "pred" is what Lumina made (stacks or rows), "truth" is what really happened (bursts, scenes).

const div = (a, b) => (b ? a / b : null);
const f1of = (p, r) => (p == null || r == null ? null : p + r ? (2 * p * r) / (p + r) : 0);
const pairs = n => (n * (n - 1)) / 2;

export function prf(tp, fp, fn) {
  const precision = div(tp, tp + fp), recall = div(tp, tp + fn);
  return { tp, fp, fn, precision, recall, f1: f1of(precision, recall) };
}

// Members of each group, in the order of ids.
export function members(of, ids) {
  const m = new Map();
  for (const id of ids) { const k = of.get(id); if (!m.has(k)) m.set(k, []); m.get(k).push(id); }
  return m;
}

// Pairwise precision / recall / F1: a pair counts when both frames share a group.
// tp = together in both, fp = together only in pred, fn = together only in truth.
export function pairwise(pred, truth, ids) {
  const P = new Map(), T = new Map(), B = new Map();
  for (const id of ids) {
    const p = pred.get(id), t = truth.get(id), k = p + '\u0000' + t;
    P.set(p, (P.get(p) || 0) + 1); T.set(t, (T.get(t) || 0) + 1); B.set(k, (B.get(k) || 0) + 1);
  }
  const sum = m => { let s = 0; for (const n of m.values()) s += pairs(n); return s; };
  const tp = sum(B);
  return prf(tp, sum(P) - tp, sum(T) - tp);
}

// How truth groups of two or more came out.
//   exact      Lumina made exactly this group
//   overSplit  the group is spread over more than one Lumina group
//   merged     the group is whole but shares its Lumina group with other frames
// underSplit counts Lumina groups that hold frames from more than one truth group.
// bySize breaks the truth groups down by size (2, 3–5, 6+) with the pair recall inside each.
export function splits(pred, truth, ids) {
  const T = members(truth, ids), P = members(pred, ids);
  const bucket = n => (n === 2 ? '2' : n <= 5 ? '3-5' : '6+');
  const out = { truthGroups: 0, exact: 0, overSplit: 0, merged: 0, underSplit: 0, predGroups: 0, bySize: {} };
  for (const g of T.values()) {
    if (g.length < 2) continue;
    const b = (out.bySize[bucket(g.length)] ||= { groups: 0, exact: 0, overSplit: 0, pairs: 0, pairsKept: 0 });
    const parts = new Map(); g.forEach(id => parts.set(pred.get(id), (parts.get(pred.get(id)) || 0) + 1));
    out.truthGroups++; b.groups++; b.pairs += pairs(g.length);
    for (const n of parts.values()) b.pairsKept += pairs(n);
    if (parts.size > 1) { out.overSplit++; b.overSplit++; }
    else if (P.get(pred.get(g[0])).length === g.length) { out.exact++; b.exact++; }
    else out.merged++;
  }
  for (const g of P.values()) {
    if (g.length < 2) continue;
    out.predGroups++;
    if (new Set(g.map(id => truth.get(id))).size > 1) out.underSplit++;
  }
  for (const b of Object.values(out.bySize)) b.recall = div(b.pairsKept, b.pairs);
  return out;
}

// Truth groups cut by a coarser Lumina grouping (rows): a row boundary inside a burst or a scene.
export function cutBy(pred, truth, ids) {
  let groups = 0, cut = 0;
  for (const g of members(truth, ids).values()) {
    if (g.length < 2) continue;
    groups++; if (new Set(g.map(id => pred.get(id))).size > 1) cut++;
  }
  return { groups, cut, whole: div(groups - cut, groups) };
}

// Auto keeps against the photographer's keeps, over ids (the frames that have a truth).
export function picks(auto, kept, ids) {
  let tp = 0, fp = 0, fn = 0, tn = 0;
  for (const id of ids) {
    const a = auto.has(id), k = kept.has(id);
    if (a && k) tp++; else if (a) fp++; else if (k) fn++; else tn++;
  }
  const n = ids.length;
  return { ...prf(tp, fp, fn), tn, frames: n, kept: tp + fn, auto: tp + fp, keepRate: div(tp + fn, n), autoRate: div(tp + fp, n) };
}

// Best of stack: in groups where the photographer kept exactly one frame, did Lumina pick it?
// groups: [{ids, pick}] (pick = the frame Lumina keeps for the group). chance = picking at random.
export function bestOf(groups, kept) {
  const bucket = n => (n === 2 ? '2' : n <= 5 ? '3-5' : '6+');
  const out = { groups: 0, oneKeeper: 0, agree: 0, agreement: null, chance: null, noKeeper: 0, manyKeepers: 0, bySize: {}, misses: [] };
  let chance = 0;
  for (const g of groups) {
    if (g.ids.length < 2) continue;
    out.groups++;
    const k = g.ids.filter(id => kept.has(id));
    if (k.length === 0) { out.noKeeper++; continue; }
    if (k.length > 1) { out.manyKeepers++; continue; }
    const b = (out.bySize[bucket(g.ids.length)] ||= { oneKeeper: 0, agree: 0 });
    out.oneKeeper++; b.oneKeeper++; chance += 1 / g.ids.length;
    if (g.pick === k[0]) { out.agree++; b.agree++; } else out.misses.push({ ids: g.ids, pick: g.pick, kept: k[0] });
  }
  out.agreement = div(out.agree, out.oneKeeper); out.chance = div(chance, out.oneKeeper);
  for (const b of Object.values(out.bySize)) b.agreement = div(b.agree, b.oneKeeper);
  return out;
}

// Sum of several picks() / pairwise() results (their counts), ratios recomputed.
export function pool(list) {
  const s = { tp: 0, fp: 0, fn: 0, tn: 0, frames: 0 };
  for (const x of list) for (const k of Object.keys(s)) s[k] += x[k] || 0;
  return { ...prf(s.tp, s.fp, s.fn), tn: s.tn, frames: s.frames, kept: s.tp + s.fn, auto: s.tp + s.fp, keepRate: div(s.tp + s.fn, s.frames), autoRate: div(s.tp + s.fp, s.frames) };
}
