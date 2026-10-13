// Clips that can't be played leave the shoot (LOCAL-CHANGES 249): skipBad, read out of the page itself and run on a
// stand-in for the page, after the first read marked some clips 'unsupported' or 'no video'.
//
//   node --test Tests/web/skim-skip.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const skipBad = new Function('return function ' + extractMethod(src, 'skipBad', 'skipBad(list) {'))();

const page = (whys, extra = {}) => {
  const clips = whys.map((why, i) => ({id:'c' + i, _i:i, bytes:100, why}));
  const p = {d:{shoot:{real:true, bytes:clips.length * 100}, clips}, state:{marks:{}, cur:'c0', sel:[]}, dropped:[], regapped:0,
    setState(o) { Object.assign(this.state, o); }, dropFrames(cs) { this.dropped.push(...cs.map(c => c.id)); }, regap() { this.regapped++; }, ...extra};
  return {p, clips};
};

test('unplayable clips leave the shoot, slow ones stay', () => {
  const {p, clips} = page([null, 'unsupported', 'timeout', 'no video', null]);
  p.state.marks = {c1:'keep', c4:'cut'}; p.state.cur = 'c1'; p.state.sel = ['c1', 'c2'];
  const left = skipBad.call(p, clips.slice());
  assert.deepEqual(p.d.clips.map(c => c.id), ['c0', 'c2', 'c4']);
  assert.deepEqual(left.map(c => c.id), ['c0', 'c2', 'c4']);
  assert.deepEqual(p.dropped, ['c1', 'c3']);
  assert.deepEqual(p.d.clips.map(c => c._i), [0, 1, 2]);
  assert.deepEqual(Object.keys(p.byId), ['c0', 'c2', 'c4']);
  assert.equal(p.d.shoot.bytes, 300);
  assert.equal(p.skipped, 2);
  assert.deepEqual(p.state.marks, {c4:'cut'});
  assert.equal(p.state.cur, 'c0');
  assert.deepEqual(p.state.sel, ['c2']);
  assert.equal(p.regapped, 1);
});

test('nothing to skip changes nothing', () => {
  const {p, clips} = page([null, 'timeout']);
  const left = skipBad.call(p, clips);
  assert.equal(left, clips); assert.equal(p.d.clips.length, 2); assert.equal(p.skipped, undefined);
});

test('the sample shoot is never trimmed', () => {
  const {p, clips} = page([null, 'unsupported']); p.d.shoot.real = false;
  skipBad.call(p, clips); assert.equal(p.d.clips.length, 2);
});

test('when nothing can be played, back to Open with a line saying so', () => {
  globalThis.window = {luminaPreview:true};
  const {p, clips} = page(['unsupported', 'no video']);
  const left = skipBad.call(p, clips);
  assert.deepEqual(left, []); assert.equal(p.d.clips.length, 0); assert.equal(p.state.step, 'import');
  assert.equal(p.state.impMsg, 'None of those 2 clips are in a format this browser can play.');
  delete globalThis.window;
});

test('runQueue skips after the retry pass, and the status line names what was skipped', () => {
  const rq = extractMethod(src, 'runQueue', 'async runQueue(list, tok) {');
  assert.ok(rq.indexOf('this.skipBad(list)') > rq.indexOf('runPass(again'));
  assert.match(src, /this\.plural\(this\.skipped, 'clip'\) \+ ' skipped'/);
});
