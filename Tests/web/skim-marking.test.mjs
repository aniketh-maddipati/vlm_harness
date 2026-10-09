// Marking in the Skim page: which clip a mark moves on to, and what undo and redo put back.
// The page is the one implementation; nextUp, markStep and stepCur are read out of it the way
// skim-export.mjs reads buildX.
//
//   node --test Tests/web/skim-marking.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const C = {};
for (const [name, args] of [['nextUp', 'flat, marks, cur'], ['markStep', 'marks, step, back'], ['stepCur', 'step, back']]){
  const body = extractMethod(src, name, 'static ' + name + '(' + args + ') {').replace(/^static /, 'function ');
  C[name] = new Function('Component', 'return ' + body)(C);
}
const flat = ['a', 'b', 'c', 'd', 'e'];

// One tap as the page does it (quick): mark cur, record the step, move on.
function tap(s, m){
  const step = {k:'mark', ids:[s.cur], prev:{[s.cur]:s.marks[s.cur] || null}, next:m};
  const marks = C.markStep(s.marks, step, false);
  step.at = {from:s.cur, to:C.nextUp(flat, marks, s.cur)};
  return {marks, cur:step.at.to, undo:[...s.undo, step], redo:[]};
}
function undo(s){ const step = s.undo.at(-1); return {marks:C.markStep(s.marks, step, true), cur:C.stepCur(step, true) || s.cur, undo:s.undo.slice(0, -1), redo:[...s.redo, step]}; }
function redo(s){ const step = s.redo.at(-1); return {marks:C.markStep(s.marks, step, false), cur:C.stepCur(step, false) || s.cur, redo:s.redo.slice(0, -1), undo:[...s.undo, step]}; }
const start = () => ({marks:{}, cur:'a', undo:[], redo:[]});

test('a mark moves on to the next clip when nothing is decided', () => {
  assert.equal(C.nextUp(flat, {a:'keep'}, 'a'), 'b');
});

test('a mark skips clips that are already decided', () => {
  assert.equal(C.nextUp(flat, {a:'keep', b:'cut', c:'maybe'}, 'a'), 'd');
});

test('past the last undecided clip it goes back to the first undecided one', () => {
  assert.equal(C.nextUp(flat, {c:'keep', d:'cut', e:'cut'}, 'e'), 'a');
  assert.equal(C.nextUp(flat, {a:'keep', c:'keep', d:'cut', e:'cut'}, 'd'), 'b');
});

test('with every clip decided it is simply the next clip, and the last clip stays', () => {
  const all = {a:'keep', b:'keep', c:'cut', d:'maybe', e:'cut'};
  assert.equal(C.nextUp(flat, all, 'b'), 'c');
  assert.equal(C.nextUp(flat, all, 'e'), 'e');
});

test('one clip, or a clip that is not listed, stays where it is', () => {
  assert.equal(C.nextUp(['a'], {a:'cut'}, 'a'), 'a');
  assert.equal(C.nextUp(flat, {}, 'zz'), 'zz');
  assert.equal(C.nextUp([], {}, null), null);
});

test('a full pass is one tap a clip and ends with nothing undecided', () => {
  let s = start(); const seen = [];
  for (const m of ['keep', 'cut', 'maybe', 'cut', 'keep']){ seen.push(s.cur); s = tap(s, m); }
  assert.deepEqual(seen, flat);
  assert.deepEqual(s.marks, {a:'keep', b:'cut', c:'maybe', d:'cut', e:'keep'});
  assert.equal(s.cur, 'e');
});

test('undo steps back to the clip just marked and clears its mark', () => {
  let s = tap(tap(start(), 'keep'), 'cut');
  assert.equal(s.cur, 'c');
  s = undo(s);
  assert.equal(s.cur, 'b'); assert.deepEqual(s.marks, {a:'keep'});
  s = undo(s);
  assert.equal(s.cur, 'a'); assert.deepEqual(s.marks, {});
});

test('undo restores the mark a clip had before it was changed', () => {
  let s = {marks:{b:'keep'}, cur:'b', undo:[], redo:[]};
  s = tap(s, 'cut');
  assert.equal(s.marks.b, 'cut'); assert.equal(s.cur, 'c');
  s = undo(s);
  assert.equal(s.marks.b, 'keep'); assert.equal(s.cur, 'b');
});

test('redo marks the clip again and moves on again', () => {
  let s = redo(undo(tap(start(), 'maybe')));
  assert.deepEqual(s.marks, {a:'maybe'}); assert.equal(s.cur, 'b');
});

test('a step over several clips puts each earlier mark back and does not move', () => {
  const step = {k:'mark', ids:['a', 'b', 'c'], prev:{a:null, b:'keep', c:'maybe'}, next:'cut'};
  const after = C.markStep({b:'keep', c:'maybe', e:'keep'}, step, false);
  assert.deepEqual(after, {a:'cut', b:'cut', c:'cut', e:'keep'});
  assert.deepEqual(C.markStep(after, step, true), {b:'keep', c:'maybe', e:'keep'});
  assert.equal(C.stepCur(step, true), null); assert.equal(C.stepCur(step, false), null);
});

test('markStep leaves the marks it was given untouched', () => {
  const marks = {a:'keep'}, step = {k:'mark', ids:['a'], prev:{a:'keep'}, next:null};
  assert.deepEqual(C.markStep(marks, step, false), {});
  assert.deepEqual(marks, {a:'keep'});
});

test('the page moves on with nextUp and undoes through markStep and stepCur', () => {
  const quick = extractMethod(src, 'quick', 'quick(m) {'), apply = extractMethod(src, 'apply', 'apply(step, back) {');
  assert.match(quick, /Component\.nextUp\(this\.flat, \{\.\.\.st\.marks, \[st\.cur\]:m\}, st\.cur\)/);
  assert.match(quick, /step\.at = \{from:st\.cur, to:n\}/);
  assert.match(apply, /Component\.markStep\(st\.marks, step, back\)/);
  assert.match(apply, /this\.goClip\(Component\.stepCur\(step, back\)\)/);
  assert.doesNotMatch(quick + extractMethod(src, 'goClip', 'goClip(n) {'), /\bpv\b/);   // marking and moving on never touch the preview switch
});
