// The key bar's glow: a key that arrives lights the hint that names it, and nothing else.
// kbTok and kbLit are read out of the page the way skim-marking.test.mjs reads markToggle.
//
//   node --test Tests/web/skim-keyglow.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const C = {};
for (const [name, args] of [['kbTok', 'e'], ['kbLit', 'hk, toks']]){
  const body = extractMethod(src, name, 'static ' + name + '(' + args + ') {').replace(/^static /, 'function ');
  C[name] = new Function('Component', 'return ' + body)(C);
}
const key = (key, mods = {}) => ({key, metaKey:false, ctrlKey:false, shiftKey:false, ...mods});
const lit = (hk, e) => C.kbLit(hk, C.kbTok(e));

test('a mark key lights K M C, and ⇧C lights only ⇧C', () => {
  for (const k of ['k', 'm', 'c', 'K']) assert.ok(lit('K M C', key(k)), k);
  assert.ok(!lit('K M C', key('C', {shiftKey:true})));
  assert.ok(lit('⇧C', key('C', {shiftKey:true})));
  assert.ok(!lit('⇧C', key('c')));
});

test('arrows, ⏎, esc, space and the size keys light their hints', () => {
  assert.ok(lit('← → ↑ ↓', key('ArrowLeft')));
  assert.ok(lit('← →', key('ArrowRight')));
  assert.ok(lit('↑', key('ArrowUp')));
  assert.ok(lit('⏎ 2×click', key('Enter')));
  assert.ok(lit('esc', key('Escape')));
  assert.ok(lit('space', key(' ')));
  assert.ok(lit('pinch − =', key('-')));
  assert.ok(lit('pinch − =', key('+', {shiftKey:true})));
});

test('shifted arrows and ⏎ light their own hint, or the plain one when only that is shown', () => {
  assert.ok(lit('⇧← ⇧→', key('ArrowRight', {shiftKey:true})));
  assert.ok(lit('⇧↓', key('ArrowDown', {shiftKey:true})));
  assert.ok(lit('↓', key('ArrowDown', {shiftKey:true})));
  assert.ok(lit('⇧⏎', key('Enter', {shiftKey:true})));
  assert.ok(!lit('⇧↓', key('ArrowDown')));
});

test('⌘ keys light only their ⌘ hint', () => {
  assert.ok(lit('⌘E', key('e', {metaKey:true})));
  assert.ok(lit('⌘O', key('o', {metaKey:true})));
  assert.ok(!lit('K M C', key('c', {metaKey:true})));
  assert.ok(!lit('⏎ 2×click', key('Enter', {metaKey:true})));
});

test('a key the bar does not name lights nothing', () => {
  for (const h of ['K M C', '← → ↑ ↓', 'esc', 'space', '⌘E']) {
    assert.ok(!lit(h, key('x')), h);
    assert.ok(!lit(h, key('F5')), h);
    assert.ok(!lit(h, key('z', {metaKey:true})), h);
  }
});
