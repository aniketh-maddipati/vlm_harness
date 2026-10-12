// The time axis of the one grid: clips grouped by the interval of capture time they start in, runs a little apart
// beside a rod, and a pinch (or − / =) that moves along the intervals and regroups. The functions are read out of the
// page the way skim-grid.test.mjs reads zlGeo and laySecs.
//
//   node --test Tests/web/skim-time.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const C = {};
for (const f of ['TI', 'TI_DEF', 'TI_GAP', 'TI_GUT', 'TI_PINCH', 'ZL', 'ZL_LINES']) {
  const m = src.match(new RegExp('\\n  static ' + f + ' = ([^;]*);'));
  assert.ok(m, 'in the page: ' + f); C[f] = new Function('return ' + m[1])();
}
for (const name of ['tiWord', 'tiSec', 'tiCuts', 'tiLabel', 'tiPinch', 'zlGeo', 'laySecs', 'rubber']) {
  const m = src.match(new RegExp('\\n  static ' + name + '\\(([^)]*)\\) \\{'));
  assert.ok(m, 'in the page: ' + name);
  C[name] = new Function('Component', 'return ' + extractMethod(src, name, 'static ' + name + '(' + m[1] + ') {').replace(/^static /, 'function '))(C);
}
const runs = (ts, iv) => { const cuts = C.tiCuts(ts, iv), out = []; let a = 0; for (const i of [...cuts, ts.length - 1]) { out.push(ts.slice(a, i + 1).length); a = i + 1; } return out; };
const at = s => C.tiSec('2026-10-08T' + s);

test('the intervals: a minute by default, shorter ones with larger tiles, every tile size one the grid has', () => {
  assert.equal(C.TI[C.TI_DEF][0], 60);
  for (let i = 1; i < C.TI.length; i++) { assert.ok(C.TI[i][0] > C.TI[i - 1][0], 'longer at ' + i); assert.ok(C.TI[i][1] <= C.TI[i - 1][1], 'tiles no larger at ' + i); }
  C.TI.forEach(([, zl]) => assert.ok(zl >= 1 && zl < C.ZL.length, 'a clip size, never scene tiles'));
  assert.deepEqual(C.TI.map(([s]) => C.tiWord(s)), ['5 s', '10 s', '30 s', '1 min', '2 min', '5 min', '10 min', '30 min', '1 h', '3 h', 'day']);
});

test('capture time reads as written, no zone; unreadable is NaN', () => {
  assert.equal(C.tiSec('2026-10-08T14:03:20') - C.tiSec('2026-10-08T14:03:00'), 20);
  assert.equal(C.tiSec('2026-10-08T14:03:20.500+02:00'), C.tiSec('2026-10-08T14:03:20'));
  assert.equal(C.tiSec('2026-10-08T00:00:00') % 86400, 0, 'a day starts at midnight on the camera clock');
  assert.ok(Number.isNaN(C.tiSec('')) && Number.isNaN(C.tiSec(null)) && Number.isNaN(C.tiSec('nonsense')));
});

test('grouping: clips that start in the same interval share a run, every clip in exactly one run, in capture order', () => {
  const ts = ['14:03:01', '14:03:20', '14:03:59', '14:04:00', '14:04:30', '14:07:10', '14:07:11', '15:00:00'].map(at);
  assert.deepEqual(runs(ts, 60), [3, 2, 2, 1]);
  assert.deepEqual(runs(ts, 30), [2, 1, 1, 1, 2, 1]);
  assert.deepEqual(runs(ts, 300), [5, 2, 1]);
  assert.deepEqual(runs(ts, 3600), [7, 1]);
  assert.deepEqual(runs(ts, 86400), [8]);
  assert.deepEqual(C.tiCuts([], 60), []); assert.deepEqual(C.tiCuts([at('10:00:00')], 60), []);
  // every interval: runs cover every clip once, and a longer interval never splits what a shorter one joined
  const rnd = Array.from({length:300}, (_, i) => at('08:00:00') + i * 17 + (i % 7) * 40 + (i % 50 === 0 ? 3600 : 0)).sort((a, b) => a - b);
  let prev = null;
  for (const [iv] of C.TI) {
    const cuts = C.tiCuts(rnd, iv); assert.equal(runs(rnd, iv).reduce((a, b) => a + b, 0), rnd.length);
    if (prev && iv % prev.iv === 0) for (const c of cuts) assert.ok(prev.cuts.includes(c), 'nested at ' + iv);
    prev = {iv, cuts};
  }
});

test('grouping: a clip whose time can’t be read stays with the clip before it', () => {
  const ts = [at('14:03:01'), NaN, at('14:04:10'), NaN, NaN, at('14:04:50'), at('14:05:00')];
  assert.deepEqual(C.tiCuts(ts, 60), [1, 5]);
  assert.deepEqual(C.tiCuts([NaN, NaN, at('14:00:00')], 60), [], 'leading unknown times join the first run');
});

test('the rod says each run’s time to its interval, with the date when a day starts', () => {
  assert.deepEqual(C.tiLabel('2026-10-08T14:03:41', 60, null), {date:'Oct 8', time:'14:03'});
  assert.deepEqual(C.tiLabel('2026-10-08T14:03:41', 60, '2026-10-08T13:59:00'), {date:'', time:'14:03'});
  assert.deepEqual(C.tiLabel('2026-10-09T00:00:12', 60, '2026-10-08T23:59:00'), {date:'Oct 9', time:'00:00'});
  assert.deepEqual(C.tiLabel('2026-10-08T14:03:41', 10, '2026-10-08T14:03:20'), {date:'', time:'14:03:40'});
  assert.deepEqual(C.tiLabel('2026-10-08T14:03:41', 300, '2026-10-08T13:59:00'), {date:'', time:'14:00'});
  assert.deepEqual(C.tiLabel('2026-10-08T14:03:41', 3600, '2026-10-08T13:00:00'), {date:'', time:'14:00'});
  assert.deepEqual(C.tiLabel('2026-12-31T14:03:41', 86400, null), {date:'Dec 31', time:''});
});

test('the pinch: out for shorter intervals, in for longer, every TI_PINCH, stops at both ends', () => {
  const P = C.TI_PINCH, top = C.TI.length - 1;
  assert.deepEqual(C.tiPinch(3, P * 0.9), {i:3, acc:P * 0.9}, 'a small pinch adds up');
  let r = C.tiPinch(3, P * 1.5); assert.equal(r.i, 2); assert.ok(Math.abs(r.acc - P * 0.5) < 1e-9, 'what is left carries on');
  r = C.tiPinch(3, -P * 1.2); assert.equal(r.i, 4);
  assert.deepEqual(C.tiPinch(0, 5), {i:0, acc:5}, 'the shortest interval only stretches');
  assert.deepEqual(C.tiPinch(top, -5), {i:top, acc:-5}, 'the longest interval only stretches');
  // the rubber band reads the time axis as the size axis turned round: shortest = the far end
  assert.equal(C.rubber(0.4, top - 0, top), 0.4 * 0.3); assert.equal(C.rubber(-0.4, top - top, top), -0.4 * 0.3); assert.equal(C.rubber(0.4, top - 3, top), 0.4);
});

test('layout: runs are TI_GAP apart, closer than a header, each starting its own row', () => {
  const g0 = C.zlGeo({vw:1440, cw:1440 - C.TI_GUT, zl:C.TI[C.TI_DEF][1]}), geo = {...g0, hh:C.TI_GAP};
  assert.ok(C.TI_GAP < g0.hh && C.TI_GAP > 0, 'a very small separation');
  const ns = [3, 9, 1, 14], L = C.laySecs({geo, secs:ns.map(n => ({n, head:true}))}), heads = L.items.filter(i => i.kind === 'h'), tiles = L.items.filter(i => i.kind === 't');
  assert.equal(tiles.length, 27);
  heads.forEach((h, s) => { const mine = tiles.filter(t => t.s === s); assert.equal(mine[0].x, 0); assert.equal(mine[0].y, h.y + C.TI_GAP); });
  for (let s = 1; s < heads.length; s++) { const lastPrev = Math.max(...tiles.filter(t => t.s === s - 1).map(t => t.y)); assert.equal(heads[s].y + C.TI_GAP - lastPrev, geo.pitch + C.TI_GAP, 'one row pitch and the gap'); }
  assert.ok(g0.W + C.TI_GUT <= 1440, 'the rod’s gutter comes out of the width');
});

test('the page: the grid groups by time, pinch and − / = move along the intervals, no strip over the grid', () => {
  assert.match(src, /this\.SC = this\.buildGroups\(new Set\(Component\.tiCuts\(ts, Component\.TI\[this\.cvTi\(\)\]\[0\]\)\.map\(i => C\[i\]\.id\)\)\)/);
  assert.match(src, /const t = Component\.tiPinch\(this\.cvTi\(\), this\.pz\);/);
  assert.match(src, /cvZoom\(d\) \{ this\.cvTiTo\(this\.cvTi\(\) - d, null\); \}/);
  const a = src.indexOf('<sc-if value="{{ lvF }}"'), b = src.indexOf('<sc-if value="{{ lv0 }}"'), tpl = src.slice(a, b);
  for (const part of ['data-lumina="time-rod"', 'data-lumina="time-mark"', 'data-lumina="time-step"', 'margin-left:{{ fGut }}px']) assert.ok(tpl.includes(part), part);
  assert.ok(!tpl.includes('fold-strip') && !tpl.includes('zoom-levels'), 'no size or scene menu');
  assert.match(tpl, /<button type="button" data-scene="\{\{ h\.s \}\}"[^>]*data-lumina="time-mark"[^>]*min-height:48px/, 'a run’s mark is a real button, 48 px tall at least');
});
