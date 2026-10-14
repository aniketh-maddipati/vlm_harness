// Elastic tiles and the double-click grammar in the Skim page. zlFit is read out of the page the way skim-grid.test.mjs
// reads zlGeo; the double-click hooks are checked in the page's text.
//
//   node --test Tests/web/skim-elastic.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const C = {};
for (const f of ['ZL', 'ZL_LINES', 'FIT_MAX', 'TI_GAP']) {
  const m = src.match(new RegExp('\\n  static ' + f + ' = ([^;]*);'));
  assert.ok(m, 'in the page: ' + f); C[f] = new Function('return ' + m[1])();
}
for (const name of ['zlGeo', 'zlCols', 'zlFit', 'laySecs', 'dblSkip', 'tileNear']) {
  const m = src.match(new RegExp('\\n  static ' + name + '\\(([^)]*)\\) \\{'));
  assert.ok(m, 'in the page: ' + name);
  C[name] = new Function('Component', 'return ' + extractMethod(src, name, 'static ' + name + '(' + m[1] + ') {').replace(/^static /, 'function '))(C);
}

// As cvGeo builds it: the grid right of the rod's gutter, runs TI_GAP apart.
const base = (zl, vw = 1440) => ({...C.zlGeo({vw, cw:vw - 100, zl}), hh:C.TI_GAP});
const secsOf = ns => ns.map(n => ({n, head:true}));
const height = (geo, secs) => C.laySecs({geo, secs}).height + 14;

test('a few clips that fit grow into fewer, larger tiles and still fit on the screen', () => {
  const g = base(2), secs = secsOf([3, 1]), f = C.zlFit(g, secs, 684);
  assert.ok(f.cols < g.cols && f.tw > g.tw, 'larger tiles');
  assert.ok(height(f, secs) <= 684, 'still fits');
  const one = {...f, cols:f.cols - 1, tw:(f.W - (f.cols - 2) * f.gx) / (f.cols - 1)};
  one.ph = Math.round(one.tw * 9 / 16); one.th = one.ph + f.lines; one.pitch = one.th + f.gy;
  assert.ok(f.cols === 1 || one.tw > C.FIT_MAX || height(one, secs) > 684, 'one column fewer would not fit');
});

test('one clip: as wide as FIT_MAX allows, with the larger size\'s lines', () => {
  const f = C.zlFit(base(2), secsOf([1]), 684);
  assert.ok(f.tw <= C.FIT_MAX && f.tw > 520);
  assert.equal(f.zl, 5); assert.equal(f.lines, C.ZL_LINES[5]); assert.equal(f.th, f.ph + f.lines);
});

test('runs that don\'t fit but leave columns empty widen into them, two rows a screen at least', () => {
  const g = base(2), secs = secsOf([1, 1, 1, 1, 1, 1, 1, 1, 1, 1]), f = C.zlFit(g, secs, 684);
  assert.ok(f.tw > g.tw); assert.ok(f.pitch * 2 <= 684);
});

test('a full shoot (a run fills a row) is laid out exactly as before', () => {
  const g = base(2), secs = secsOf([12, 3, 40, 7]);
  assert.equal(C.zlFit(g, secs, 684), g);
  assert.equal(C.zlFit(g, [], 684), g); assert.equal(C.zlFit(g, secs, 0), g);
});

test('a phone (one column already) is unchanged', () => {
  const g = base(2, 390); assert.equal(g.cols, 1);
  assert.equal(C.zlFit(g, secsOf([2]), 448), g);
});

test('the fit never shrinks a tile, and a smaller screen never gets larger tiles', () => {
  for (const ns of [[1], [2], [3, 1], [5], [4, 4], [1, 1, 1], [2, 1, 3, 1, 1]]) {
    let prev = Infinity;
    for (const h of [900, 700, 500, 300]) {
      const g = base(2), f = C.zlFit(g, secsOf(ns), h);
      assert.ok(f.tw >= g.tw - 1e-9 && f.tw <= prev + 1e-9, ns + ' at ' + h); prev = f.tw;
    }
  }
});

test('double-click in, double-click out: the hooks are wired', () => {
  assert.match(src, /viewDbl = e => \{[\s\S]{0,400}?this\.furl\(\); \};/, 'the Viewer goes back to the clips');
  assert.doesNotMatch(src, /viewDbl = [^\n]*setStep\('export'\)/, 'not to Export');
  assert.match(src, /data-screen-label="Clip"[^>]*onDoubleClick="\{\{ viewDbl \}\}"/, 'the whole Viewer takes it');
  assert.match(src, /viewDbl = e => \{[^\n]*\[data-lumina="info"\]/, 'not the info beside the picture');
  for (const scr of ['Grid', 'Chapters', 'Takes']) assert.match(src, new RegExp('data-screen-label="' + scr + '"[^>]*onDoubleClick="\\{\\{ gridDbl \\}\\}"'), scr + ' takes a double-click around its tiles');
  assert.match(src, /dockDbl = e => \{[^\n]*st\.lv === 2 && st\.cur === id\) return this\.furl\(\)/, 'the dock clip open in the Viewer goes back');
  assert.match(src, /data-screen-label="Takes"[^>]*onDoubleClick="\{\{ gridDbl \}\}"/, 'Takes goes back to Chapters');
  assert.match(src, /hasAttribute\('data-pic'\)[\s\S]{0,400}this\.furl\(\)/, 'a double tap on a phone');
  const el = sel => ({closest:s => s.split(',').some(x => x.trim() === sel) ? {} : null});
  assert.equal(C.dblSkip(el('button')), true); assert.equal(C.dblSkip(el('div')), false); assert.equal(C.dblSkip(null), false);
});

test('a double-click on a tile\'s frame (its rounded corner, the ring around it) finds that tile', () => {
  const tile = (left, top) => ({getBoundingClientRect:() => ({left, top, right:left + 200, bottom:top + 150})});
  const a = tile(100, 100), b = tile(320, 100), root = {querySelectorAll:() => [a, b]};
  assert.equal(C.tileNear(root, 101, 101), a, 'the corner');
  assert.equal(C.tileNear(root, 200, 98), a, 'the ring above');
  assert.equal(C.tileNear(root, 304, 120), a, 'just right of it');
  assert.equal(C.tileNear(root, 316, 120), b, 'nearer the next one');
  assert.equal(C.tileNear(root, 310, 300), null, 'the space between rows');
  assert.equal(C.tileNear(null, 0, 0), null);
});

test('letting go of Space puts the grid back at the scroll it was opened from', () => {
  assert.match(src, /this\.pvAt = st\.cv && st\.lv === 0 && this\.sc \? \{top:this\.sc\.scrollTop, cur\} : null;/);
  const back = src.slice(src.indexOf('  pvBack(from) {'), src.indexOf('  takeStep(d) {'));
  assert.match(back, /this\.state\.cur === at\.cur\) this\.wantScroll = \['@top', at\.top\]/, 'only when the Viewer is still on that clip');
  assert.equal((src.match(/this\.pvBack\(from\)/g) || []).length, 2, 'Space up after a hold and Space again after a tap');
  assert.match(src, /if \(w\[0\] === '@top'\) \{ if \(this\.sc\) \{ this\.sc\.scrollTop = w\[1\];/);
});
