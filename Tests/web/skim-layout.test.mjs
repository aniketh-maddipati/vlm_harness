// Layout as maths (canvas plan 1.2): the functions in the page place the Clips and Scenes tiles with no DOM.
//   node --test Tests/web/skim-layout.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { performance } from 'node:perf_hooks';
import { loadLayout, groupsOf, NAMES } from './skim-layout.mjs';

const { Component: L, sources } = loadLayout();

// The page's layout before 1.2, word for word (tileGeo, sceneGrid and the Clips windowing in renderVals), so the
// functions that replaced it are held to the same numbers.
function oldGeo(vw, cw, z1){
  const z = z1 || 1, gy = Math.round(20 * Math.min(1, z + 0.2)), gx = Math.round(18 * Math.min(1, z + 0.2));
  const pad = Math.min(40, Math.max(16, vw * 0.022)), W = Math.max(200, (cw ? cw : vw) - 2 * pad), tmin = Math.min(W, Math.round(272 * z));
  const cols = Math.max(1, Math.floor((W + gx) / (tmin + gx))), tw = (W - (cols - 1) * gx) / cols, fh = (tw - 6) / 4 * 9 / 16;
  const th = 2 * fh + 2 + 7 + 18 + 7 + 20; return {cols, tw, th, gy, gx, pitch:th + gy};
}
function oldSceneGrid(vw){ const pad = Math.min(40, Math.max(16, vw * 0.022)), W = Math.max(250, vw - 2 * pad), cols = Math.max(1, Math.floor((W + 22) / 272)), tw = (W - (cols - 1) * 22) / cols; return {cols, tw}; }
function oldSecs(geo, scTop, scH, groups, cur){
  const vTop = scTop - scH, vBot = scTop + 2 * scH; let y = 10; const out = [];
  for (const g of groups.filter(g => g.n)){
    const bndOk = g.i > 0;
    const rows = Math.ceil(g.n / geo.cols), gTop = y + (bndOk ? 44 : 0) + 6 + 26 + 12; y = gTop + rows * geo.pitch - geo.gy + 10;
    let r0 = Math.max(0, Math.floor((vTop - gTop) / geo.pitch)), r1 = Math.min(rows, Math.ceil((vBot - gTop) / geo.pitch));
    const ci = cur && cur.gi === g.i ? cur.k : -1; if (ci >= 0) { const cr = Math.floor(ci / geo.cols); r0 = r1 > r0 ? Math.min(r0, Math.max(0, cr - 2)) : Math.max(0, cr - 2); r1 = Math.max(r1, Math.min(rows, cr + 3)); }
    if (r1 <= r0) { r0 = rows; r1 = rows; }
    const padT = r1 > r0 ? r0 * geo.pitch : Math.max(0, rows * geo.pitch - geo.gy), padB = r1 > r0 ? (rows - r1) * geo.pitch : 0;
    out.push({gi:g.i, r0, r1, padT:Math.round(padT), padB:Math.round(padB)});
  }
  return out;
}
const rng = seed => { let s = seed >>> 0; return () => (s = (s * 1664525 + 1013904223) >>> 0) / 4294967296; };
const median = a => a.slice().sort((x, y) => x - y)[Math.floor(a.length / 2)];

test('the functions are pure: no DOM, no state, no clock, no randomness in their source', () => {
  for (const n of NAMES){
    assert.doesNotMatch(sources[n], /\bthis\b|document|window|\bDate\b|Math\.random|performance|querySelector|getBoundingClientRect|clientWidth/, n);
  }
});

test('clips geometry equals the page before 1.2 across window sizes and zooms', () => {
  const r = rng(1);
  for (let k = 0; k < 2000; k++){
    const vw = 320 + Math.floor(r() * 3200), cw = r() < 0.3 ? 0 : vw - Math.floor(r() * 16), z = [0.35, 0.5, 0.75, 1, 1.4, 2, 3][Math.floor(r() * 7)];
    const a = oldGeo(vw, cw, z), b = L.layGeo({vw, cw, z});
    for (const f of ['cols', 'tw', 'th', 'gy', 'gx', 'pitch']) assert.equal(b[f], a[f], f + ' at ' + JSON.stringify({vw, cw, z}));
    assert.ok(Math.abs(b.pad * 2 + b.cols * b.tw + (b.cols - 1) * b.gx - Math.max(200 + 2 * b.pad, cw || vw)) < 1e-6, 'tiles fill the width');
    const s = oldSceneGrid(vw), t = L.laySceneGeo({vw});
    assert.equal(t.cols, s.cols); assert.equal(t.tw, s.tw);
  }
});

test('clips windowing (rows laid out, spacers) equals the page before 1.2', () => {
  const r = rng(2);
  for (let k = 0; k < 1500; k++){
    const vw = 600 + Math.floor(r() * 2400), z = 0.4 + r() * 2, n = 1 + Math.floor(r() * 700), sc = 1 + Math.floor(r() * Math.min(n, 60));
    const groups = groupsOf(n, sc, k + 1); if (r() < 0.2) groups[Math.floor(r() * groups.length)].n = 0;
    const geo = L.layGeo({vw, z}), h = 400 + Math.floor(r() * 1200), top = Math.floor(r() * 30000);
    const live = groups.filter(g => g.n), cg = live[Math.floor(r() * live.length)], cur = r() < 0.7 && cg ? {gi:cg.i, k:Math.floor(r() * cg.n)} : null;
    const want = oldSecs(geo, top, h, groups, cur), got = L.layClips({geo, top, h, groups, cur, rects:false}).secs;
    assert.equal(got.length, want.length);
    got.forEach((s, i) => { for (const f of ['gi', 'r0', 'r1', 'padT', 'padB']) assert.equal(s[f], want[i][f], f); });
  }
});

test('clips rects: every clip once when the window is everything, in order, on the grid, never overlapping', () => {
  const groups = groupsOf(500, 23), all = L.layout({lv:1, z:1, win:{vw:1440, cw:1440, top:0, h:1e7}, groups});
  assert.equal(all.rects.length, 500);
  const geo = all.geo; let i = 0;
  for (const g of groups) for (let k = 0; k < g.n; k++, i++){
    const t = all.rects[i], sec = all.secs.find(s => s.gi === g.i);
    assert.equal(t.g, g.i); assert.equal(t.k, k);
    assert.ok(Math.abs(t.x - (geo.pad + (k % geo.cols) * (geo.tw + geo.gx))) < 1e-9);
    assert.ok(Math.abs(t.y - (sec.top + Math.floor(k / geo.cols) * geo.pitch)) < 1e-9);
    assert.ok(t.x >= geo.pad - 1e-9 && t.x + t.w <= 1440 - geo.pad + 1e-6, 'inside the side padding');
    assert.ok(t.y + t.h <= all.height);
  }
  for (let a = 1; a < all.rects.length; a++){ const p = all.rects[a - 1], q = all.rects[a]; assert.ok(q.y > p.y - 1e-9 && (q.y > p.y + p.h - 1e-9 || q.x >= p.x + p.w - 1e-9), 'tiles do not overlap'); }
  // sections stack: each grid starts below the one before
  for (let a = 1; a < all.secs.length; a++) assert.ok(all.secs[a].y >= all.secs[a - 1].top + all.secs[a - 1].rows * geo.pitch - geo.gy);
});

test('clips rects: a window gives only tiles near it, and all the tiles on screen', () => {
  const groups = groupsOf(500, 12), full = L.layClips({vw:1440, z:1, top:0, h:1e7, groups}), h = 800;
  for (const top of [0, 500, 2500, 6000, full.height - h]){
    const w = L.layClips({vw:1440, z:1, top, h, groups});
    assert.ok(w.rects.length < 500 && w.rects.length > 0);
    assert.equal(w.height, full.height);
    for (const t of w.rects) assert.ok(t.y + t.h > top - h - w.geo.pitch && t.y < top + 2 * h + w.geo.pitch, 'near the window');
    const onScreen = full.rects.filter(t => t.y + t.h > top && t.y < top + h);
    for (const t of onScreen) assert.ok(w.rects.some(q => q.g === t.g && q.k === t.k && q.x === t.x && q.y === t.y), 'tile on screen is laid out');
  }
});

test('scenes rects: n tiles on the grid, windowed, and the same for the same input', () => {
  const a = L.layout({lv:0, win:{vw:1440, top:0, h:0}, groups:groupsOf(500, 500), head:40});
  assert.equal(a.rects.length, 500); assert.equal(a.geo.cols, 5);
  a.rects.forEach((t, g) => { assert.equal(t.g, g); assert.ok(Math.abs(t.x - (a.geo.pad + (g % 5) * (a.geo.tw + 22))) < 1e-9); assert.ok(Math.abs(t.y - (58 + Math.floor(g / 5) * a.geo.pitch)) < 1e-9); });
  assert.ok(Math.abs(a.geo.ph - a.geo.tw * 9 / 16) < 1e-9);
  const w = L.layScenes({vw:1440, n:500, head:40, top:3000, h:800});
  assert.ok(w.rects.length > 0 && w.rects.length < 100); assert.equal(w.height, a.height);
  for (const t of a.rects.filter(t => t.y + t.h > 3000 && t.y < 3800)) assert.ok(w.rects.some(q => q.g === t.g && q.y === t.y));
  assert.deepEqual(L.layout({lv:0, win:{vw:1440, top:0, h:0}, groups:groupsOf(500, 500), head:40}), a);
  const g12 = groupsOf(500, 12), o = {lv:1, z:0.8, win:{vw:1728, cw:1713, top:1200, h:900}, groups:g12, cur:{gi:3, k:5}};
  assert.deepEqual(L.layout(o), L.layout(JSON.parse(JSON.stringify(o))));
  assert.equal(L.layout({lv:0, win:{vw:1440}, groups:[]}).rects.length, 0);
  assert.equal(L.layout({lv:1, win:{vw:1440, h:800}, groups:[]}).rects.length, 0);
});

test('hit: a point inside a tile finds it, a point in a gap finds nothing', () => {
  const a = L.layClips({vw:1440, z:1, top:0, h:1e7, groups:groupsOf(60, 3)}), t = a.rects[17];
  assert.equal(L.layHit(a.rects, t.x + 1, t.y + 1), t);
  assert.equal(L.layHit(a.rects, t.x + t.w + a.geo.gx / 2, t.y + 1), null);
  assert.equal(L.layHit(a.rects, t.x + 1, t.y + t.h + a.geo.gy / 2), null);
  assert.equal(L.layHit(a.rects, 2, 2), null);
});

// Node's clock on this machine, not a browser's: the budget in CANVAS.md is 2 ms for 500 clips.
test('500 clips lay out in under 2 ms (Node)', () => {
  const pre = {a:groupsOf(500, 12), b:groupsOf(500, 500)};
  const timed = {
    'clips, every one of 500 (12 scenes)': () => L.layout({lv:1, z:1, win:{vw:1440, cw:1440, top:0, h:1e7}, groups:pre.a}),
    'clips, window of 900 px in 500 (12 scenes)': () => L.layout({lv:1, z:1, win:{vw:1440, cw:1440, top:2400, h:900}, groups:pre.a, cur:{gi:4, k:9}}),
    'clips, 500 scenes of one clip': () => L.layout({lv:1, z:1, win:{vw:1440, cw:1440, top:0, h:1e7}, groups:pre.b}),
    'scenes, 500 tiles': () => L.layout({lv:0, win:{vw:1440, top:0, h:0}, groups:pre.b}),
  };
  for (const name of Object.keys(timed)){
    const f = timed[name]; for (let i = 0; i < 300; i++) f();
    const ms = []; let worst = 0;
    for (let i = 0; i < 400; i++){ const t = performance.now(); f(); const d = performance.now() - t; ms.push(d); if (d > worst) worst = d; }
    const med = median(ms);
    console.log(`layout ${name}: median ${med.toFixed(4)} ms, slowest of 400 ${worst.toFixed(4)} ms (Node ${process.version})`);
    assert.ok(med < 2, name + ' median ' + med.toFixed(3) + ' ms');
  }
});
