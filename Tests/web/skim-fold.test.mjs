// The one grid (Scenes and Clips fused): folding by break strength, what a folded tile sums up, marking a folded
// tile, and where the tiles sit. The page is the one implementation; the functions are read out of it the way
// skim-export.mjs reads buildX, and the break scores come from the page's own regap.
//
//   node --test Tests/web/skim-fold.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const C = {};
const NAMES = ['isCanvas', 'foldTiles', 'foldCut', 'foldSum', 'foldMark', 'foldSplit', 'foldStep', 'foldPinch', 'foldWord', 'layFuseGeo', 'layFuse', 'markStep'];
for (const name of NAMES){
  const m = src.match(new RegExp('\\n  static ' + name + '\\(([^)]*)\\) \\{'));
  assert.ok(m, 'in the page: ' + name);
  C[name] = new Function('Component', 'return ' + extractMethod(src, name, 'static ' + name + '(' + m[1] + ') {').replace(/^static /, 'function '))(C);
}
const regap = new Function('return function ' + extractMethod(src, 'regap', 'regap(d) {'))();

// A shoot in capture order: bursts of clips a few seconds apart, minutes between bursts, one new day, one change
// of frame rate, one change of look. Times are unique and rising.
function shoot(n, seed = 5){
  let s = seed >>> 0; const R = () => (s = (s * 1664525 + 1013904223) >>> 0) / 4294967296;
  const clips = []; let t = Date.UTC(2026, 9, 3, 9, 0, 0), left = 0, col = [0.4, 0.4, 0.4], day = false;
  for (let k = 0; k < n; k++){
    if (left <= 0){ left = 2 + Math.floor(R() * 9); t += (120 + R() * 2400) * 1000; if (!day && k >= n * 0.6) { day = true; t += 20 * 3600 * 1000; } if (R() < 0.3) col = [R(), R(), R()]; }
    left--;
    const dur = 3 + Math.round(R() * 20);
    clips.push({id:'c' + String(k).padStart(4, '0'), t:new Date(t).toISOString().slice(0, 19), dur, bytes:dur * 12e6, fps:k > n * 0.8 ? 60 : 24, w:3840, col:col.slice()});
    t += (dur + 2 + R() * 25) * 1000;
  }
  return clips;
}
function breaks(clips){ const d = {clips}, self = {d}; regap.call(self, d); return {sorted:self.gapsSorted.map(g => g.after), gaps:d.gaps, why:self.whyBy}; }
const tilesAt = (ids, sorted, n) => C.foldTiles(ids, C.foldCut(sorted, n)).map(([a, b]) => ids.slice(a, b));

test('the switch: ?canvas=1 or #canvas, and nothing else', () => {
  for (const [q, h] of [['?canvas=1', ''], ['?debug=1&canvas=1', ''], ['?canvas=1&x=2', ''], ['', '#canvas'], ['', '#debug&canvas'], ['', '#canvas&debug']]) assert.equal(C.isCanvas(q, h), true, q + h);
  for (const [q, h] of [['', ''], ['?canvas=0', ''], ['?canvas=10', ''], ['?mycanvas=1', ''], ['', '#canvassing'], ['', '#debug'], [undefined, undefined]]) assert.equal(C.isCanvas(q, h), false, String(q) + h);
});

test('every fold value: each clip in exactly one tile, capture order kept', () => {
  for (const n of [1, 2, 7, 60, 401]){
    const clips = shoot(n), ids = clips.map(c => c.id), { sorted } = breaks(clips);
    assert.equal(sorted.length, n - 1);
    for (let k = 0; k <= sorted.length; k++){
      const T = tilesAt(ids, sorted, k);
      assert.deepEqual(T.flat(), ids, 'order and membership at ' + k);
      assert.equal(T.length, k + 1, 'tiles at ' + k);
      assert.ok(T.every(t => t.length > 0));
    }
  }
});

test('each unfold step splits exactly one tile in two, until every tile is one clip; each fold step joins two', () => {
  const clips = shoot(120), ids = clips.map(c => c.id), { sorted } = breaks(clips);
  let prev = tilesAt(ids, sorted, 0); assert.equal(prev.length, 1);
  for (let k = 1; k <= sorted.length; k++){
    const now = tilesAt(ids, sorted, k), key = t => t[0] + '>' + t[t.length - 1];
    const gone = prev.filter(t => !now.some(u => key(u) === key(t))), born = now.filter(t => !prev.some(u => key(u) === key(t)));
    assert.equal(gone.length, 1, 'one tile splits at ' + k); assert.equal(born.length, 2, 'into two at ' + k);
    assert.deepEqual(born.flat(), gone[0], 'the two halves are the tile, in order');
    assert.equal(born[0][born[0].length - 1], C.foldStep(sorted, k - 1, 1), 'at the break the strip named');
    assert.equal(C.foldStep(sorted, k, -1), born[0][born[0].length - 1], 'and folding back takes the same break away');
    prev = now;
  }
  assert.ok(prev.every(t => t.length === 1)); assert.equal(prev.length, 120);
  assert.equal(C.foldStep(sorted, sorted.length, 1), null); assert.equal(C.foldStep(sorted, 0, -1), null);
});

test('the strongest breaks go first: a new day before a long gap before a short one', () => {
  const clips = shoot(200), { sorted, gaps, why } = breaks(clips), sc = {}; gaps.forEach(g => sc[g.after] = g);
  for (let k = 1; k < sorted.length; k++) assert.ok(sc[sorted[k - 1]].sc >= sc[sorted[k]].sc);
  const day = Object.keys(why).find(id => why[id] === 'new day'); assert.ok(day, 'the shoot has a new day');
  assert.equal(sorted[0], day);
});

test('unfolding one tile: the smallest fold value that splits it', () => {
  const clips = shoot(90), ids = clips.map(c => c.id), { sorted } = breaks(clips);
  for (const n of [0, 3, 10, 40]){
    for (const t of tilesAt(ids, sorted, n)){
      const k = C.foldSplit(t, sorted, n);
      if (t.length === 1){ assert.equal(k, null); continue; }
      assert.ok(k > n);
      const after = tilesAt(ids, sorted, k), before = tilesAt(ids, sorted, k - 1);
      assert.ok(!after.some(u => u.length === t.length && u[0] === t[0]), 'split at ' + k);
      assert.ok(before.some(u => u.length === t.length && u[0] === t[0]), 'still whole one step earlier');
    }
  }
});

test('a tile sums up what it holds: marks, undecided, length, size, notes, not measured yet', () => {
  const clips = [
    {id:'a', dur:10, bytes:100, notes:['dark', 'soft']}, {id:'b', dur:5, bytes:50, notes:[]}, {id:'c', dur:7, bytes:70, notes:['dark']},
    {id:'d', dur:1, bytes:10, notes:[], pending:true}, {id:'e', dur:2, bytes:20, notes:['can’t read']}];
  const s = C.foldSum(clips, {a:'keep', b:'cut', c:'cut', e:'maybe', zz:'keep'});
  assert.deepEqual(s, {n:5, keep:1, maybe:1, cut:2, und:1, dur:25, bytes:250, noted:3, notes:{dark:2, soft:1, 'can’t read':1}, pending:1});
  assert.equal(s.keep + s.maybe + s.cut + s.und, s.n, 'every clip is counted once');
  assert.deepEqual(C.foldSum([], {}), {n:0, keep:0, maybe:0, cut:0, und:0, dur:0, bytes:0, noted:0, notes:{}, pending:0});
  // the tiles' sums add up to the shoot's at any fold value
  const sh = shoot(77), ids = sh.map(c => c.id), { sorted } = breaks(sh), marks = {}; sh.forEach((c, i) => { if (i % 3 === 0) marks[c.id] = ['keep', 'maybe', 'cut'][i % 9 / 3]; });
  const all = C.foldSum(sh, marks);
  for (const n of [0, 5, 30, 76]){
    const parts = C.foldTiles(ids, C.foldCut(sorted, n)).map(([a, b]) => C.foldSum(sh.slice(a, b), marks));
    for (const f of ['n', 'keep', 'maybe', 'cut', 'und', 'dur', 'bytes']) assert.equal(parts.reduce((x, p) => x + p[f], 0), all[f], f + ' at ' + n);
  }
});

// A press on a folded tile as the page does it (cvMark → areaMark → doMark): one step over all its clips.
function press(s, ids, m){ const next = C.foldMark(ids, s.marks, m), prev = {}; ids.forEach(id => prev[id] = s.marks[id] || null); const step = {k:'mark', ids, prev, next}; return {marks:C.markStep(s.marks, step, false), undo:[...s.undo, step]}; }
function undo(s){ const step = s.undo.at(-1); return {marks:C.markStep(s.marks, step, true), undo:s.undo.slice(0, -1)}; }

test('marking a folded tile: sets the mark on every clip, the mark they all have turns off, undo gives each its own back', () => {
  const ids = ['a', 'b', 'c', 'd'], s0 = {marks:{a:'keep', b:'cut', x:'maybe'}, undo:[]};
  assert.equal(C.foldMark(ids, s0.marks, 'cut'), 'cut');
  const s1 = press(s0, ids, 'cut');
  assert.deepEqual(s1.marks, {a:'cut', b:'cut', c:'cut', d:'cut', x:'maybe'});
  assert.equal(C.foldMark(ids, s1.marks, 'cut'), null, 'all cut: C clears');
  assert.equal(C.foldMark(ids, s1.marks, 'keep'), 'keep', 'another mark switches');
  const s2 = press(s1, ids, 'cut');
  assert.deepEqual(s2.marks, {x:'maybe'}, 'cleared, clips outside the tile untouched');
  const s3 = undo(s2); assert.deepEqual(s3.marks, s1.marks);
  const s4 = undo(s3); assert.deepEqual(s4.marks, s0.marks, 'each clip has the mark it had: a selected, b cut, c and d undecided');
  assert.equal(C.foldMark(['a', 'b'], {a:'maybe'}, 'maybe'), 'maybe', 'only some have it: it is set on all');
  assert.equal(C.foldMark([], {}, 'cut'), 'cut');
});

test('a pinch moves the fold: bigger pinch, more steps; a slow one adds up; stops at both ends', () => {
  assert.deepEqual(C.foldPinch(3, 400, 0.05), {n:3, acc:0.05}, 'a touch on a few tiles does nothing yet');
  assert.equal(C.foldPinch(17, 400, 0.7).n, 35, '18 tiles × e^0.7 ≈ 36 tiles');
  assert.equal(C.foldPinch(17, 400, -0.7).n, 8);
  assert.deepEqual(C.foldPinch(0, 400, 0.3), {n:1, acc:0}, 'from one tile a slow pinch still takes a step');
  assert.deepEqual(C.foldPinch(1, 400, -0.3), {n:0, acc:0});
  assert.equal(C.foldPinch(399, 400, 2).n, 400); assert.equal(C.foldPinch(400, 400, 2).n, 400); assert.equal(C.foldPinch(0, 400, -2).n, 0);
  let n = 0, acc = 0, seen = new Set([0]); for (let i = 0; i < 200 && n < 400; i++){ const r = C.foldPinch(n, 400, acc + 0.1); assert.ok(r.n >= n); n = r.n; acc = r.acc; seen.add(n); }
  assert.equal(n, 400, 'pinching out reaches single clips'); assert.ok(seen.size > 20);
});

test('the strip says what the tiles are', () => {
  assert.equal(C.foldWord([4, 33, 18]), '3 scenes · 55 clips');
  assert.equal(C.foldWord([4, 1, 18, 1]), '2 scenes + 2 single clips · 24 clips');
  assert.equal(C.foldWord([401]), '1 scene · 401 clips');
  assert.equal(C.foldWord([1, 1, 1]), '3 clips · each its own tile');
  assert.equal(C.foldWord([2, 1]), '1 scene + 1 single clip · 3 clips');
});

test('layout: folded and single tiles share one grid; every tile once, no overlap, inside the padding', () => {
  const clips = shoot(300), ids = clips.map(c => c.id), { sorted } = breaks(clips);
  for (const n of [0, 12, 150, 299]){
    const tiles = C.foldTiles(ids, C.foldCut(sorted, n)).map(([a, b]) => b - a);
    for (const vw of [1280, 1440, 1728]){
      const L = C.layFuse({vw, tiles}), g = L.geo;
      assert.equal(L.rects.length, tiles.length);
      assert.ok(g.tw >= 280 && g.cols >= 4, 'four columns or more from 1280 px');
      L.rects.forEach((r, i) => {
        assert.equal(r.g, i); assert.equal(r.n, tiles[i]); assert.equal(r.fold, tiles[i] > 1);
        assert.equal(r.w, g.tw); assert.equal(r.h, g.th); assert.equal(r.ph, g.ph);
        assert.ok(Math.abs(r.x - (g.pad + (i % g.cols) * (g.tw + 22))) < 1e-9); assert.equal(r.y, 14 + Math.floor(i / g.cols) * g.pitch);
        assert.ok(r.x >= g.pad - 1e-9 && r.x + r.w <= vw - g.pad + 1e-6); assert.ok(r.y + r.h <= L.height);
        if (i) { const p = L.rects[i - 1]; assert.ok(r.y >= p.y + p.h || r.x >= p.x + p.w - 1e-9); }
      });
      assert.equal(L.padT, 0); assert.equal(L.padB, 0);
    }
  }
});

test('layout: a window lays out the rows near it and the current tile; spacers stand in for the rest', () => {
  const tiles = Array.from({length:401}, (_, i) => i % 7 ? 1 : 3), full = C.layFuse({vw:1440, tiles}), g = full.geo;
  for (const [top, cur] of [[0, 0], [1800, 30], [5000, 2], [full.height - 800, 400], [2500, null]]){
    const L = C.layFuse({vw:1440, tiles, top, h:800, cur});
    assert.equal(L.height, full.height);
    assert.equal(L.padT + (L.r1 - L.r0) * g.pitch + L.padB, L.rows * g.pitch, 'spacers and rows make the whole height');
    assert.equal(L.rects.length, Math.min(401, L.r1 * g.cols) - L.r0 * g.cols);
    for (const r of full.rects.filter(r => r.y + r.h > top && r.y < top + 800)) assert.ok(L.rects.some(q => q.g === r.g && q.x === r.x && q.y === r.y), 'tile on screen is laid out');
    if (cur != null) assert.ok(L.rects.some(q => q.g === cur), 'the current tile is laid out');
    assert.ok(L.rects.length < 401);
  }
  assert.deepEqual(C.layFuse({vw:1440, tiles, top:900, h:700, cur:5}), C.layFuse({vw:1440, tiles:tiles.slice(), top:900, h:700, cur:5}), 'same in, same out');
  assert.equal(C.layFuse({vw:1440, tiles:[]}).rects.length, 0);
});

test('the one grid is opt-in: off unless the address asks, and Scenes / Clips are what shows when it is off', () => {
  assert.match(src, /cv:typeof window !== 'undefined' && Component\.isCanvas\(location\.search, location\.hash\)/, 'the switch starts from the address only');
  assert.match(src, /lv0:sk && !empty && !st\.cv && st\.lv === 0, lv1:sk && !empty && !st\.cv && st\.lv === 1/, 'Scenes and Clips show when it is off');
  assert.match(src, /lvF:sk && !empty && !!st\.cv && st\.lv === 0/, 'the one grid shows only when it is on');
  const dbg = src.indexOf('<sc-if value="{{ dbgOn }}"'), tog = src.indexOf('data-lumina="canvas-toggle"'), end = src.indexOf('</sc-if>', dbg);
  assert.ok(dbg > 0 && tog > dbg && tog < end, 'the toggle is inside the debug switch');
});

test('the one grid: its strip, its tiles and its words', () => {
  const a = src.indexOf('<sc-if value="{{ lvF }}"'), b = src.indexOf('<sc-if value="{{ lv0 }}"'); assert.ok(a > 0 && b > a);
  const tpl = src.slice(a, b);
  for (const part of ['fold-strip', 'fold-less', 'fold-more', 'fold slider', 'fold-count', 'fold-where', 'fold-next', 'data-gi', 'data-fold', 'tile-marks', 'tile-notes', 'tile-why', 'tile-wait', 'fold-badge']) assert.ok(tpl.includes(part), part);
  // in the script, 'keep' on its own is the stored key and is never shown
  const js = src.slice(src.indexOf('  cvGrid() {'), src.indexOf('  index() {'));
  for (const text of [tpl.replace(/<[^>]*>/g, ' ').replace(/\{\{[^}]*\}\}/g, ' '), (js.match(/'[^']*'/g) || []).filter(q => q !== "'keep'").join(' ')]) assert.doesNotMatch(text, /\b(keep|kept|keepers?|reject\w*|flag\w*)\b/i, 'neutral words only');
  assert.match(js, /'undecided'/); assert.match(js, /this\.W\('keep'\)/, 'marks are named through WORD (selected / maybe / cut)');
});
