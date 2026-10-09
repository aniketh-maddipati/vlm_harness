// Marking in the Skim page: a mark is a toggle on the clip you are on, and undo and redo put it back.
// The page is the one implementation; markToggle, markStep and stepCur are read out of it the way
// skim-export.mjs reads buildX.
//
//   node --test Tests/web/skim-marking.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const C = {};
for (const [name, args] of [['markToggle', 'has, m'], ['markStep', 'marks, step, back'], ['stepCur', 'step'], ['clipAt', 'flat, cur, d']]){
  const body = extractMethod(src, name, 'static ' + name + '(' + args + ') {').replace(/^static /, 'function ');
  C[name] = new Function('Component', 'return ' + body)(C);
}

// One press as the page does it (quick): toggle the mark on cur, record the step, stay.
function press(s, m){
  const has = s.marks[s.cur] || null;
  const step = {k:'mark', ids:[s.cur], prev:{[s.cur]:has}, next:C.markToggle(has, m)};
  return {marks:C.markStep(s.marks, step, false), cur:s.cur, undo:[...s.undo, step], redo:[]};
}
function undo(s){ const step = s.undo.at(-1); return {marks:C.markStep(s.marks, step, true), cur:C.stepCur(step) || s.cur, undo:s.undo.slice(0, -1), redo:[...s.redo, step]}; }
function redo(s){ const step = s.redo.at(-1); return {marks:C.markStep(s.marks, step, false), cur:C.stepCur(step) || s.cur, redo:s.redo.slice(0, -1), undo:[...s.undo, step]}; }
const start = (marks = {}) => ({marks, cur:'a', undo:[], redo:[]});

test('toggle on: a press marks an undecided clip and stays on it', () => {
  for (const m of ['keep', 'maybe', 'cut']){
    const s = press(start(), m);
    assert.deepEqual(s.marks, {a:m}); assert.equal(s.cur, 'a');
  }
});

test('toggle off: the mark the clip already has turns off', () => {
  for (const m of ['keep', 'maybe', 'cut']){
    assert.equal(C.markToggle(m, m), null);
    const s = press(press(start(), m), m);
    assert.deepEqual(s.marks, {}); assert.equal(s.cur, 'a');
  }
});

test('switch: a different mark replaces the one the clip has', () => {
  assert.equal(C.markToggle('maybe', 'cut'), 'cut');
  assert.equal(C.markToggle(null, 'keep'), 'keep');
  assert.equal(C.markToggle(undefined, 'keep'), 'keep');
  const s = press(press(start(), 'maybe'), 'cut');
  assert.deepEqual(s.marks, {a:'cut'}); assert.equal(s.cur, 'a');
});

test('other clips are not touched', () => {
  const s = press(press(start({b:'keep', c:'cut'}), 'cut'), 'cut');
  assert.deepEqual(s.marks, {b:'keep', c:'cut'});
});

test('undo restores what was there: on, switched and off, one step at a time', () => {
  let s = press(press(press(start(), 'keep'), 'cut'), 'cut');       // on, switch, off
  assert.deepEqual(s.marks, {});
  s = undo(s); assert.deepEqual(s.marks, {a:'cut'});
  s = undo(s); assert.deepEqual(s.marks, {a:'keep'});
  s = undo(s); assert.deepEqual(s.marks, {});
  assert.equal(s.cur, 'a'); assert.equal(s.undo.length, 0); assert.equal(s.redo.length, 3);
});

test('redo does the press again', () => {
  let s = redo(undo(press(start(), 'maybe')));
  assert.deepEqual(s.marks, {a:'maybe'});
  s = redo(undo(press(s, 'maybe')));                                 // the toggle off, undone and redone
  assert.deepEqual(s.marks, {});
});

test('undo lands on the clip the step marked, wherever you have gone since', () => {
  let s = press(start(), 'cut');
  s = {...s, cur:'d'};
  s = undo(s);
  assert.equal(s.cur, 'a'); assert.deepEqual(s.marks, {});
  s = redo({...s, cur:'e'});
  assert.equal(s.cur, 'a'); assert.deepEqual(s.marks, {a:'cut'});
});

test('a step over several clips puts each earlier mark back and does not move', () => {
  const step = {k:'mark', ids:['a', 'b', 'c'], prev:{a:null, b:'keep', c:'maybe'}, next:'cut'};
  const after = C.markStep({b:'keep', c:'maybe', e:'keep'}, step, false);
  assert.deepEqual(after, {a:'cut', b:'cut', c:'cut', e:'keep'});
  assert.deepEqual(C.markStep(after, step, true), {b:'keep', c:'maybe', e:'keep'});
  assert.equal(C.stepCur(step), null);
});

test('markStep leaves the marks it was given untouched', () => {
  const marks = {a:'keep'}, step = {k:'mark', ids:['a'], prev:{a:'keep'}, next:null};
  assert.deepEqual(C.markStep(marks, step, false), {});
  assert.deepEqual(marks, {a:'keep'});
});

test('the page toggles in quick, never moves on a mark, and undoes through markStep and stepCur', () => {
  const quick = extractMethod(src, 'quick', 'quick(m) {'), apply = extractMethod(src, 'apply', 'apply(step, back) {'), doMark = extractMethod(src, 'doMark', 'doMark(ids, m) {');
  assert.match(quick, /this\.doMark\(\[st\.cur\], Component\.markToggle\(st\.marks\[st\.cur\] \|\| null, m\)\)/);
  assert.doesNotMatch(quick + doMark, /goClip|takeStep|this\.move\(|cur:/);   // a mark never changes the clip you are on
  assert.doesNotMatch(quick + doMark, /\bpv\b/);                             // nor the preview switch
  assert.doesNotMatch(src, /nextUp/);
  assert.match(apply, /Component\.markStep\(st\.marks, step, back\)/);
  assert.match(apply, /this\.goClip\(Component\.stepCur\(step\)\)/);
});

// ⏎ and ⇧⏎ in the Viewer: one clip on or back in capture order, straight across scenes, stopping at the ends.
const scenes = [['a', 'b'], ['c'], ['d', 'e']], order = scenes.flat();   // the page's flat: each scene's clips, scene after scene

test('next and back move one clip each', () => {
  assert.equal(C.clipAt(order, 'a', 1), 'b');
  assert.equal(C.clipAt(order, 'e', -1), 'd');
});

test('they cross scene boundaries in capture order', () => {
  assert.equal(C.clipAt(order, 'b', 1), 'c'); assert.equal(C.clipAt(order, 'c', 1), 'd');
  assert.equal(C.clipAt(order, 'd', -1), 'c'); assert.equal(C.clipAt(order, 'c', -1), 'b');
  let cur = 'a'; const seen = [cur];
  for (let n; (n = C.clipAt(order, cur, 1)); cur = n) seen.push(n);
  assert.deepEqual(seen, order);
});

test('they stop at the first and the last clip, no wrap', () => {
  assert.equal(C.clipAt(order, 'e', 1), null);
  assert.equal(C.clipAt(order, 'a', -1), null);
  assert.equal(C.clipAt(['a'], 'a', 1), null); assert.equal(C.clipAt(['a'], 'a', -1), null);
});

test('a clip that is not listed goes nowhere', () => {
  assert.equal(C.clipAt(order, 'zz', 1), null); assert.equal(C.clipAt(order, null, -1), null); assert.equal(C.clipAt([], 'a', 1), null);
});

test('the page moves on Enter through takeStep, after the held-mark Enter, and never marks', () => {
  const kd = extractMethod(src, 'kd', 'kd(e) {'), takeStep = extractMethod(src, 'takeStep', 'takeStep(d) {');
  assert.match(takeStep, /Component\.clipAt\(this\.flat, this\.state\.cur, d\)/);
  assert.doesNotMatch(takeStep, /marks|\bpv\b|doMark/);
  const held = kd.indexOf('if (st.held) { e.preventDefault(); return this.decide(); }'), nav = kd.indexOf('return this.takeStep(e.shiftKey ? -1 : 1)');
  assert.ok(held > 0 && nav > held);
  assert.match(kd, /const nav = k === 'Enter' && st\.lv >= 2 && !st\.prop;/);
});
