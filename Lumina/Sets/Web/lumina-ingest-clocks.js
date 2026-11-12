// Lumina Ingest: camera clocks aligned from the photos themselves.
//
// Two cameras (or a camera and a phone) that shot the same moment hold two photos that look alike, with
// capture times that differ by however far apart their clocks are. So, per clock (a body: serial, else
// model; a phone on its own), every photo looks for its nearest look-alike on each other clock within
// ±15 h, and the time differences of those pairs vote: the difference most pairs agree on (within 150 s)
// is that clock's offset. No agreement, no shift. A body whose time runs backwards between consecutive
// file numbers had its clock set mid-card; each side is then a clock of its own.
//
// Similarity is a 12 × 8 luma grid (normalised correlation) plus mean colour, from the thumbnail the page
// already draws. It finds the same frame (or a near twin from another body beside it); two bodies at
// different angles need something like Vision's feature print (SetsNear, `lumina.near`), which this page,
// running without plumbing, does not have.
//
// Plain JS, no DOM except `sigOf` (a canvas); Node-testable (lumina-ingest-clocks.test.mjs).
(function (root) {
  'use strict';
  const GW = 12, GH = 8;
  const O = {
    window: 15 * 3600e3,   // a pair may be this far apart on the two clocks (time zones reach ±14 h)
    near: 0.06,            // largest distance for "the same moment"
    agree: 150e3,          // pairs agreeing within this make one vote
    minPairs: 3,           // at least this many agreeing pairs
    minShare: 0.5,         // and at least this share of a clock's pairs
    minShift: 120e3,       // a smaller offset is left as shot
    jump: 10 * 60e3        // time running back this much between consecutive file numbers = clock set mid-card
  };

  // ---- the look of a photo ----------------------------------------------------------------------
  function sigFromRGBA(px) {
    // px: RGBA bytes of a GW × GH image
    const g = new Array(GW * GH); let m = 0, r = 0, gg = 0, b = 0;
    for (let i = 0; i < GW * GH; i++) { const a = i * 4; g[i] = px[a] * 0.299 + px[a + 1] * 0.587 + px[a + 2] * 0.114; m += g[i]; r += px[a]; gg += px[a + 1]; b += px[a + 2]; }
    const n = GW * GH; m /= n; let v = 0;
    for (let i = 0; i < n; i++) { g[i] -= m; v += g[i] * g[i]; }
    const s = Math.sqrt(v) || 1;
    return { g: g.map((x) => Math.round((x / s) * 1e4) / 1e4), c: [r / n, gg / n, b / n].map(Math.round), flat: v / n < 4 };
  }
  function sigOf(source) {
    // source: a canvas or image bitmap (the page's thumbnail canvas)
    const c = (typeof OffscreenCanvas !== 'undefined') ? new OffscreenCanvas(GW, GH) : Object.assign(document.createElement('canvas'), { width: GW, height: GH });
    const x = c.getContext('2d', { willReadFrequently: true });
    x.imageSmoothingQuality = 'high'; x.drawImage(source, 0, 0, GW, GH);
    return sigFromRGBA(x.getImageData(0, 0, GW, GH).data);
  }
  function dist(a, b) {
    if (!a || !b || a.flat || b.flat || a.g.length !== b.g.length) return Infinity;
    let dot = 0; for (let i = 0; i < a.g.length; i++) dot += a.g[i] * b.g[i];
    const col = (Math.abs(a.c[0] - b.c[0]) + Math.abs(a.c[1] - b.c[1]) + Math.abs(a.c[2] - b.c[2])) / 765;
    return (1 - dot) / 2 + col;
  }

  // ---- clocks: one per body, split where its time runs backwards ------------------------------------
  const fileNo = (name) => { const m = /(\d{3,})(?!.*\d)/.exec(String(name || '').replace(/\.[^.]+$/, '')); return m ? +m[1] : null; };
  function clocks(items, o) {
    const by = new Map();
    for (const it of items) { if (it.t == null || !it.body) continue; if (!by.has(it.body)) by.set(it.body, []); by.get(it.body).push(it); }
    const out = [];
    for (const [body, list] of by) {
      // consecutive file numbers in the order the camera wrote them (per source folder)
      const ord = list.slice().sort((a, b) => String(a.src || '').localeCompare(String(b.src || '')) || (fileNo(a.name) ?? 0) - (fileNo(b.name) ?? 0) || a.t - b.t);
      let seg = [], segs = [seg], jumps = [];
      for (let i = 0; i < ord.length; i++) {
        const p = ord[i - 1], q = ord[i];
        if (p && p.src === q.src && fileNo(p.name) != null && fileNo(q.name) != null && fileNo(q.name) > fileNo(p.name) && p.t - q.t > o.jump) {
          jumps.push({ after: String(p.name).replace(/\.[^.]+$/, ''), at: q.name, by: q.t - p.t }); seg = []; segs.push(seg);
        }
        seg.push(q);
      }
      // a body that went back and forth: the segments with the same clock are found again by the pairs
      segs.forEach((s, i) => out.push({ key: segs.length > 1 ? body + ' from ' + String(s[0].name).replace(/\.[^.]+$/, '') : body, body, seg: i, jump: i ? jumps[i - 1] : null, items: s, phone: s.some((x) => x.phone) }));
    }
    return out;
  }

  // ---- votes: B's clock minus A's clock, from look-alike pairs --------------------------------------
  function vote(B, A, o) {
    const at = A.items.filter((x) => x.sig).sort((x, y) => x.t - y.t), offs = [];
    for (const b of B.items) {
      if (!b.sig) continue;
      let best = Infinity, bt = null;
      // A sorted by time: only the ones inside the window
      let lo = 0, hi = at.length;
      while (lo < hi) { const mid = (lo + hi) >> 1; if (at[mid].t < b.t - o.window) lo = mid + 1; else hi = mid; }
      for (let i = lo; i < at.length && at[i].t <= b.t + o.window; i++) { const d = dist(b.sig, at[i].sig); if (d < best) { best = d; bt = at[i]; } }
      if (best <= o.near) offs.push({ off: b.t - bt.t, b, a: bt, d: best });
    }
    if (!offs.length) return null;
    offs.sort((x, y) => x.off - y.off);
    let bi = 0, bn = 0;
    for (let i = 0, j = 0; i < offs.length; i++) { while (offs[i].off - offs[j].off > o.agree) j++; if (i - j + 1 > bn) { bn = i - j + 1; bi = j; } }
    const agree = offs.slice(bi, bi + bn);
    if (bn < o.minPairs || bn < o.minShare * offs.length) return { off: null, n: bn, of: offs.length };
    return { off: agree[Math.floor(agree.length / 2)].off, n: bn, of: offs.length, pairs: agree };
  }

  // ---- align: each clock's shift onto a reference clock -----------------------------------------------
  function align(items, opts) {
    const o = Object.assign({}, O, opts || {});
    const U = clocks(items, o);
    const edges = [];
    for (let i = 0; i < U.length; i++) for (let j = i + 1; j < U.length; j++) {
      if (U[i].body === U[j].body && !o.sameBody) continue; // one camera can't shoot one moment twice
      const v = vote(U[j], U[i], o);
      if (v && v.off != null) edges.push({ a: i, b: j, off: v.off, n: v.n, of: v.of });
    }
    // components; reference = a phone (its clock sets itself), else the clock with most photos
    const shift = new Array(U.length).fill(null), via = new Array(U.length).fill(null), refOf = new Array(U.length).fill(null);
    const order = U.map((u, i) => i).sort((x, y) => (U[y].phone - U[x].phone) || (U[y].items.length - U[x].items.length) || U[x].key.localeCompare(U[y].key));
    for (const r of order) {
      if (shift[r] != null) continue;
      shift[r] = 0; refOf[r] = r;
      // grow by the strongest edge first (most agreeing pairs)
      for (;;) {
        let best = null;
        for (const e of edges) {
          const ia = shift[e.a] != null && refOf[e.a] === r, ib = shift[e.b] != null && refOf[e.b] === r;
          if (ia === ib) continue;
          if (!best || e.n > best.n) best = e;
        }
        if (!best) break;
        // off = t(b) − t(a) for the same moment; a clock reads true after its shift
        if (shift[best.a] != null && refOf[best.a] === r) { shift[best.b] = shift[best.a] - best.off; refOf[best.b] = r; via[best.b] = best; }
        else { shift[best.a] = shift[best.b] + best.off; refOf[best.a] = r; via[best.a] = best; }
      }
    }
    const out = U.map((u, i) => {
      const s = shift[i] || 0, applied = via[i] && Math.abs(s) >= o.minShift ? s : 0;
      const h = Math.round(s / 3600e3), tz = applied && Math.abs(h) >= 1 && Math.abs(s - h * 3600e3) <= o.agree ? h : null;
      return {
        key: u.key, body: u.body, n: u.items.length, phone: u.phone, jump: u.jump,
        ref: refOf[i] === i && edges.some((e) => e.a === i || e.b === i), refKey: U[refOf[i]].key,
        shift: applied, small: !!via[i] && !applied ? s : 0, tz, matches: via[i] ? via[i].n : 0,
        ids: u.items.map((x) => x.id)
      };
    });
    const shiftOf = new Map();
    for (const c of out) if (c.shift) for (const id of c.ids) shiftOf.set(id, c.shift);
    return { clocks: out, shiftOf, edges: edges.map((e) => ({ a: U[e.a].key, b: U[e.b].key, off: e.off, n: e.n, of: e.of })) };
  }

  // −1 h 03 min, +8 h, −40 s
  function fmtShift(ms) {
    const s = Math.round(Math.abs(ms) / 1000), sg = ms < 0 ? '−' : '+', h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60);
    if (s < 60) return sg + s + ' s';
    if (!h) return sg + m + ' min';
    if (m === 60) return sg + (h + 1) + ' h';
    return sg + h + ' h' + (m ? ' ' + String(m).padStart(2, '0') + ' min' : '');
  }

  const API = { align, vote, clocks, dist, sigOf, sigFromRGBA, fmtShift, fileNo, defaults: O, GW, GH };
  root.LuminaIngestClocks = API;
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
})(typeof window !== 'undefined' ? window : globalThis);
