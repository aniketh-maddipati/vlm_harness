// The dock in the Skim page: every selected clip in capture order, and the arrows between it and the grid.
// dockList, dockStep, dockNear and dockOut are read out of the page the way skim-marking.test.mjs reads markToggle.
//
//   node --test Tests/web/skim-dock.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const C = {};
for (const [name, args] of [['dockList', 'clips, marks'], ['dockStep', 'ids, id, d'], ['dockNear', 'order, ids, cur'], ['dockOut', 'ids, id'], ['markToggle', 'has, m']]){
  const body = extractMethod(src, name, 'static ' + name + '(' + args + ') {').replace(/^static /, 'function ');
  C[name] = new Function('Component', 'return ' + body)(C);
}
const clips = [['a', 0], ['b', 0], ['c', 1], ['d', 1], ['e', 2], ['f', 3]].map(([id, g]) => ({id, g}));

test('the dock holds selected clips only, in capture order', () => {
  const L = C.dockList(clips, {f:'keep', b:'keep', c:'maybe', d:'keep', e:'cut'});
  assert.deepEqual(L.map(x => x.id), ['b', 'd', 'f']);
  assert.deepEqual(C.dockList(clips, {}), []);
});

test('a gap where the scene changes, none inside a scene and none before the first clip', () => {
  const L = C.dockList(clips, {a:'keep', b:'keep', c:'keep', f:'keep'});
  assert.deepEqual(L.map(x => x.brk), [false, false, true, true]);
});

test('← → step along the dock and stop at its ends', () => {
  const ids = ['b', 'd', 'f'];
  assert.equal(C.dockStep(ids, 'd', 1), 'f'); assert.equal(C.dockStep(ids, 'd', -1), 'b');
  assert.equal(C.dockStep(ids, 'f', 1), 'f'); assert.equal(C.dockStep(ids, 'b', -1), 'b');
  assert.equal(C.dockStep(ids, 'zz', 1), 'b'); assert.equal(C.dockStep([], 'b', 1), null);
});

test('↓ into the dock lands on the clip you are on, or the next selected one after it', () => {
  const order = clips.map(c => c.id), ids = ['b', 'd'];
  assert.equal(C.dockNear(order, ids, 'd'), 'd');
  assert.equal(C.dockNear(order, ids, 'a'), 'b');
  assert.equal(C.dockNear(order, ids, 'c'), 'd');
  assert.equal(C.dockNear(order, ids, 'f'), 'd', 'past the last selected clip: the last one');
  assert.equal(C.dockNear(order, [], 'a'), null);
});

test('a clip taken out hands the focus to the next one, else the one before, else none', () => {
  assert.equal(C.dockOut(['b', 'd', 'f'], 'd'), 'f');
  assert.equal(C.dockOut(['b', 'd', 'f'], 'f'), 'd');
  assert.equal(C.dockOut(['b'], 'b'), null);
  assert.equal(C.dockOut(['b'], 'x'), null);
});

test('K on a selected clip in the dock takes it out; M and C switch it out of the dock too', () => {
  assert.equal(C.markToggle('keep', 'keep'), null);
  assert.equal(C.markToggle('keep', 'maybe'), 'maybe');
  assert.equal(C.markToggle('keep', 'cut'), 'cut');
});

test('the page wires the dock in: one block above the key bar, the keys, the marks and esc', () => {
  const page = src;
  assert.equal((page.match(/<div data-lumina="dock"/g) || []).length, 1);
  assert.ok(page.indexOf('data-lumina="dock"') < page.indexOf('data-lumina="keybar"'));
  assert.match(page, /onDoubleClick="\{\{ dockDbl \}\}"/);
  assert.match(page, /if \(this\.dockKey\(e\)\) return;/);
  assert.match(page, /quick\(m\) \{\n    const st = this\.state;\n    if \(this\.dockMark\(m\)\) return;/);
  assert.match(page, /if \(this\.dockFoc\(\)\) return this\.dockLeave\(\);/);
  assert.match(page, /Object\.assign\(vals, this\.dockVals\(vals\)\);/);
});

test('neutral words: the dock says selected, never a verdict', () => {
  const i = src.indexOf('  // The dock: every selected clip'), j = src.indexOf('  clipKey(c) {');
  const block = src.slice(i, j);
  for (const w of ['AI', 'smart', 'intelligent', 'detects', 'suggest', 'recommended', 'magic', 'auto', 'learns', 'confidence', 'score', 'best'])
    assert.doesNotMatch(block.replace(/\/\/.*$/gm, ''), new RegExp("'[^']*\\b" + w + "\\b[^']*'", 'i'), w);
});
