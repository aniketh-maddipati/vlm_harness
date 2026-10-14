// Runs share a row on the Skim time canvas (geo.flow): a sparse shoot fills the width instead of one clip per row,
// tiles never get smaller than the stacked layout made them, runs stay whole and in capture order. The layout
// functions are read out of the page the way skim-elastic.test.mjs reads zlFit.
//
//   node --test Tests/web/skim-flow.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const C = {};
for (const f of ['ZL', 'ZL_LINES', 'FIT_MAX', 'TI_GAP', 'TI_GUT', 'FLOW_IN']) {
  const m = src.match(new RegExp('\\n  static ' + f + ' = ([^;]*);'));
  assert.ok(m, 'in the page: ' + f); C[f] = new Function('return ' + m[1])();
}
for (const name of ['zlGeo', 'zlCols', 'zlFit', 'layFlow', 'flowAt', 'laySecs', 'laySecAt', 'laySecNav']) {
  const m = src.match(new RegExp('\\n  static ' + name + '\\(([^)]*)\\) \\{'));
  assert.ok(m, 'in the page: ' + name);
  C[name] = new Function('Component', 'return ' + extractMethod(src, name, 'static ' + name + '(' + m[1] + ') {').replace(/^static /, 'function '))(C);
}

// As cvGeo builds it: the grid right of the rod's gutter, runs TI_GAP apart, runs sharing rows.
const base = (zl, vw = 1728, flow = true) => ({...C.zlGeo({vw, cw:vw - C.TI_GUT, zl}), hh:C.TI_GAP, flow});
const secsOf = ns => ns.map(n => ({n, head:true}));
const tiles = (geo, secs) => C.laySecs({geo, secs}).items.filter(i => i.kind === 't');

test('seven clips a few hours apart share rows and keep the order they were shot in', () => {
  const g = base(2), secs = secsOf([1, 1, 1, 1, 1, 1, 1]), T = tiles(g, secs), F = C.layFlow(g, secs);
  assert.equal(T.length, 7);
  assert.ok(F.Y.length < 7 && F.Y.length <= 2, 'rows: ' + F.Y.length);
  for (let i = 1; i < T.length; i++) assert.ok(T[i].y > T[i - 1].y || (T[i].y === T[i - 1].y && T[i].x > T[i - 1].x), 'reading order at ' + i);
  T.forEach(t => assert.ok(t.x >= 0 && t.x + t.w <= g.W + 0.5, 'inside the width'));
  F.P.forEach((p, s) => { if (s && p.x) { const prev = F.P[s - 1], e = C.flowAt(g, prev, prev.n - 1).x + g.tw; assert.ok(p.x - e >= C.FLOW_IN - 1e-6, 'a gutter for its mark'); } });
});

test('a run is never split to share a row, and one longer than a row takes whole rows from the left', () => {
  const g = base(2), cols = g.cols, secs = secsOf([2, cols + 2, 3, cols - 1, 1]), F = C.layFlow(g, secs);
  F.P.forEach(p => { if (p.x) assert.equal(p.rows, 1); const rows = new Set(); for (let k = 0; k < p.n; k++) rows.add(C.flowAt(g, p, k).row); assert.equal(rows.size, p.x ? 1 : Math.ceil(p.n / cols)); });
  const long = F.P[1]; assert.equal(long.x, 0, 'the long run starts a row'); assert.equal(C.flowAt(g, long, cols).x, 0, 'and wraps to the left');
});

test('runs that fill their rows are laid out exactly as stacked', () => {
  const g = base(2), cols = g.cols, secs = secsOf([cols, 2 * cols, cols, cols * 3]);
  assert.deepEqual(tiles(g, secs).map(t => [t.x, t.y]), tiles({...g, flow:false}, secs).map(t => [t.x, t.y]));
  assert.equal(C.laySecs({geo:g, secs}).height, C.laySecs({geo:{...g, flow:false}, secs}).height);
});

test('the fit never makes a tile smaller than the stacked layout did', () => {
  for (const ns of [[1], [1, 1, 1, 1, 1, 1, 1], [3, 1, 2], [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], [12, 3, 40, 7], [2, 1, 3, 1, 1]])
    for (const vw of [1728, 1440, 2560]) for (const h of [900, 700, 500, 300]) {
      const g = base(2, vw), stacked = C.zlFit({...g, flow:false}, secsOf(ns), h), f = C.zlFit(g, secsOf(ns), h);
      assert.ok(f.flow && f.tw >= stacked.tw - 1e-9, ns + ' at ' + vw + ' × ' + h + ': ' + f.tw + ' < ' + stacked.tw);
      assert.ok(f.tw <= C.FIT_MAX + 1e-9);
    }
});

test('the seven clips fit one screen at the size they had stacked', () => {
  const g = base(2), secs = secsOf([1, 1, 1, 1, 1, 1, 1]), h = 640, stacked = C.zlFit({...g, flow:false}, secs, h), f = C.zlFit(g, secs, h);
  assert.equal(f.tw, stacked.tw);
  assert.ok(C.layFlow(f, secs).height + 14 <= h + f.pitch, 'about a screen');
  assert.ok(C.laySecs({geo:{...stacked, flow:false}, secs}).height > 3 * h, 'stacked, it was more than three screens');
});

test('the window, laySecAt and ↑ ↓ agree with the whole layout', () => {
  const g = base(2, 1440), ns = Array.from({length:80}, (_, i) => 1 + (i * 5) % 4), secs = secsOf(ns), all = tiles(g, secs), H = C.laySecs({geo:g, secs}).height;
  all.forEach(t => { const a = C.laySecAt(g, secs, t.g); assert.equal(a.x, t.x); assert.equal(a.y, t.y); assert.equal(a.s, t.s); });
  for (let top = 0; top < H; top += 333) {
    const cur = Math.floor(top / H * all.length), L = C.laySecs({geo:g, secs, top, h:700, cur}).items.filter(i => i.kind === 't');
    assert.ok(L.some(t => t.g === cur), 'the current tile is laid out');
    L.forEach(t => { const a = all[t.g]; assert.equal(t.x, a.x); assert.equal(t.y, a.y); });
  }
  const rowOf = k => C.laySecAt(g, secs, k).row, rows = C.layFlow(g, secs).Y.length;
  for (const t of all) {
    const dn = C.laySecNav(g, secs, t.g, 1), up = C.laySecNav(g, secs, t.g, -1), r = rowOf(t.g);
    if (r === rows - 1) assert.equal(dn, t.g, 'the bottom row stays'); else assert.equal(rowOf(dn), r + 1);
    if (r === 0) assert.equal(up, t.g, 'the top row stays'); else assert.equal(rowOf(up), r - 1);
    if (r < rows - 1) { const best = Math.min(...all.filter(o => rowOf(o.g) === r + 1).map(o => Math.abs(o.x - t.x))); assert.equal(Math.abs(all[dn].x - t.x), best, 'nearest across'); }
  }
});

test('the page lays the time canvas out flowed, each shared run with its own mark and rod', () => {
  assert.match(src, /const t = \{\.\.\.g, hh:Component\.TI_GAP, flow:true\};/, 'cvGeo asks for flow');
  assert.match(src, /data-lumina="time-mark"[^>]*left:\{\{ h\.x \}\}px/, 'a mark sits beside its own run');
  assert.match(src, /<sc-for list="\{\{ fr \}\}"[^>]*><div data-lumina="time-rod-run"/, 'a short rod beside a shared run');
});
