// Truth for the culling eval, from the camera's own metadata (read by exiftool, a parser that shares
// nothing with the page's parseHead) and from the photographer's finished exports. Pure functions.

// "2026:02:08 13:00:16" → seconds (whole seconds: the α7 III writes no sub-second time).
export function seconds(date) {
  const m = /^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})/.exec(date || '');
  return m ? Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]) / 1000 : 0;
}

// Capture order: time, then the shutter count (the camera's own frame counter), then the name.
export function inOrder(frames) {
  return frames.slice().sort((a, b) => a.t - b.t || (a.shutter ?? 0) - (b.shutter ?? 0) || String(a.name).localeCompare(String(b.name)));
}

// Same framing: same lens, focal length within 5 %, same camera orientation.
export function sameFraming(a, b) {
  if ((a.lens || '') !== (b.lens || '') || (a.orient || 1) !== (b.orient || 1)) return false;
  if (!a.fl || !b.fl) return a.fl === b.fl;
  return Math.max(a.fl, b.fl) / Math.min(a.fl, b.fl) <= 1.05;
}

// Three truth groupings, each coarser than the one before. frames: [{id, t, seq, shutter, lens, fl, orient}].
//   drive   what the camera recorded as one continuous sequence: SequenceImageNumber goes up by one
//           (it restarts at 1 for every press) within driveGap seconds.
//   repeat  drive, or the next frame within repeatGap seconds with the same framing: a burst by hand.
//   scene   repeat, or the next frame within sceneGap seconds with the same framing: tries at one picture.
// Returns {drive, repeat, scene}: Map id → group label.
export function truthGroups(frames, { driveGap = 5, repeatGap = 2, sceneGap = 10 } = {}) {
  const F = inOrder(frames), out = { drive: new Map(), repeat: new Map(), scene: new Map() }, cur = {};
  F.forEach((f, i) => {
    const p = F[i - 1], gap = p ? f.t - p.t : Infinity, same = p && sameFraming(p, f);
    const drive = !!p && p.seq != null && f.seq != null && f.seq === p.seq + 1 && gap <= driveGap;
    const link = { drive, repeat: drive || (same && gap <= repeatGap), scene: drive || (same && gap <= Math.max(repeatGap, sceneGap)) };
    for (const k of Object.keys(out)) { if (!link[k]) cur[k] = k[0] + ':' + f.id; out[k].set(f.id, cur[k]); }
  });
  return out;
}

// Which RAWs have a finished export. An export names its RAW (crs:RawFileName); card files that were
// renamed are found by capture time to the second, then by exposure. A RAW is ambiguous when several
// share the export's second and exposure; ambiguous frames are left out of the keep / reject scoring.
// raws: [{id, name, date, exp, fnum, iso, fl}], exports: [{name, raw, date, exp, fnum, iso, fl}].
export function matchExports(raws, exports) {
  const stem = s => String(s || '').replace(/\.[^.]+$/, '').toLowerCase();
  const byStem = new Map(), byDate = new Map();
  for (const r of raws) {
    byStem.set(stem(r.name), r);
    if (!byDate.has(r.date)) byDate.set(r.date, []);
    byDate.get(r.date).push(r);
  }
  const near = (a, b) => a == null || b == null || Math.abs(a - b) <= 1e-6 + 0.02 * Math.max(Math.abs(a), Math.abs(b));
  const kept = new Set(), ambiguous = new Set(), unmatched = [], rule = { name: 0, time: 0 };
  for (const e of exports) {
    const n = byStem.get(stem(e.raw));
    if (n && (!e.date || n.date === e.date)) { kept.add(n.id); rule.name++; continue; }
    let c = byDate.get(e.date) || [];
    if (c.length > 1) { const x = c.filter(r => near(r.exp, e.exp) && near(r.fnum, e.fnum) && near(r.iso, e.iso) && near(r.fl, e.fl)); if (x.length) c = x; }
    if (c.length === 1) { kept.add(c[0].id); rule.time++; }
    else if (c.length > 1) c.forEach(r => ambiguous.add(r.id));
    else unmatched.push(e.name);
  }
  for (const id of ambiguous) kept.delete(id);
  return { kept, ambiguous, unmatched, rule };
}
