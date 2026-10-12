// The storage line (STORAGE.md, step 1), read out of the page itself: the collapsed line's words
// (Component.storeLine), each button's yield (Component.dumpSay), what Drop frames gives back
// (Component.farFrames, the plan dropFar() carries out) and where the line sits in the footer.
//
//   node --test Tests/web/skim-storage.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const stat = (name, head) => new Function('return function ' + extractMethod(src, name, head).replace(/^static /, ''))();
const storeLine = stat('storeLine', 'static storeLine(parts, fmtB) {');
const dumpSay = stat('dumpSay', 'static dumpSay(kind, bytes, n, fmtB) {');
const farFrames = stat('farFrames', 'static farFrames(clips, at, cover) {');
const evictOrder = stat('evictOrder', 'static evictOrder(shoots, cur, bytes, cap) {');
const recBytes = stat('recBytes', 'static recBytes(r) {');
const coverKey = stat('coverKey', 'static coverKey(name, t, bytes) {');
const fmtB = new Function('return function ' + extractMethod(src, 'fmtB', 'fmtB(b) {'))();
const template = src.slice(0, src.indexOf('class Component'));
const MB = 1048576;

// n clips in capture order, each with eight frames made in this tab at 30 KB apiece
const shoot = (n, per = 8) => Array.from({length:n}, (_, i) => ({id:'c' + i, _i:i,
  frames:Array.from({length:8}, (_, k) => k < per ? 'blob:c' + i + '-' + k : null), frameSz:Array.from({length:8}, (_, k) => k < per ? 30000 : 0)}));

test('the line over an empty, a small and an over-limit shoot', () => {
  assert.equal(storeLine([], fmtB), 'storage · nothing held');
  assert.equal(storeLine([{t:'in memory', b:0, of:384 * MB}], fmtB), 'storage · in memory 0 MB of 403 MB');
  assert.equal(storeLine([{t:'in memory', b:180e6, of:384 * MB}], fmtB), 'storage · in memory 180 MB of 403 MB');
  assert.equal(storeLine([{t:'in memory', b:450e6, of:384 * MB}], fmtB), 'storage · in memory 450 MB of 403 MB · over');
  assert.equal(storeLine([{t:'in memory', b:2.3e9, of:null}], fmtB), 'storage · in memory 2.3 GB');
});

test('nothing is shown that was not measured', () => {
  assert.equal(storeLine([{t:'in memory', b:180e6, of:384 * MB}, {t:'drive', free:null}, {t:'saved', b:null}], fmtB), 'storage · in memory 180 MB of 403 MB');
  assert.equal(storeLine([{t:'drive', free:undefined}], fmtB), 'storage · nothing held');
  assert.equal(storeLine([{t:'in memory', b:180e6, of:384 * MB}, {t:'drive', free:52e9}], fmtB), 'storage · in memory 180 MB of 403 MB · drive 52.0 GB free');
});

test('a button says what it gives back before the click', () => {
  assert.equal(dumpSay('frames', 180e6, 37, fmtB), 'Drop frames · 180 MB');
  assert.equal(dumpSay('frames', 1.4e9, 300, fmtB), 'Drop frames · 1.4 GB');
  assert.equal(dumpSay('frames', 0, 0, fmtB), 'Drop frames · nothing to give back');
  assert.equal(dumpSay('frames', 5e6, 0, fmtB), 'Drop frames · nothing to give back');
  assert.equal(dumpSay('saved', 120e6, 3, fmtB), 'Clear for shoots not open · 120 MB');
  assert.equal(dumpSay('saved', 0, 0, fmtB), 'Clear for shoots not open · nothing to give back');
});

test('Drop frames keeps one cover per clip and the 24 around the current clip', () => {
  const C = shoot(100), at = 50, p = farFrames(C, at, 3);
  const near = C.filter(c => Math.abs(c._i - at) <= 12), far = C.filter(c => Math.abs(c._i - at) > 12);
  assert.equal(near.length, 25);                          // the clip you are on and 12 each side
  assert.equal(p.n, far.length);
  assert.equal(p.frames.length, far.length * 7);
  assert.equal(p.bytes, far.length * 7 * 30000);
  for (const [c, i] of p.frames) { assert.ok(Math.abs(c._i - at) > 12, c.id); assert.notEqual(i, 3, c.id); }
  // at the start of the shoot the 12 after the first are kept
  assert.equal(farFrames(C, 0, 3).n, 100 - 13);
});

test('a clip whose cover is gone keeps the frame nearest it; a clip of one frame is left alone', () => {
  const C = shoot(30); C[0].frames[3] = null; C[0].frameSz[3] = 0; C[1].frames = [null, null, null, null, 'blob:x', null, null, null];
  const p = farFrames(C, 29, 3), kept0 = [0, 1, 2, 4, 5, 6, 7].filter(i => !p.frames.some(([c, k]) => c === C[0] && k === i));
  assert.equal(kept0.length, 1); assert.ok(kept0[0] === 2 || kept0[0] === 4);
  assert.ok(!p.frames.some(([c]) => c === C[1]));
});

test('only frames made in this tab are dropped, and marks are not part of it', () => {
  const C = shoot(40); C[0].frames = C[0].frames.map(() => 'data:image/jpeg;base64,AAAA');
  const marks = {c0:'cut', c1:'keep'}, before = JSON.stringify(marks), p = farFrames(C, 39, 3);
  assert.ok(!p.frames.some(([c]) => c === C[0]));
  assert.equal(JSON.stringify(marks), before);
  assert.ok(!/marks|setMarks/.test(extractMethod(src, 'farFrames', 'static farFrames(clips, at, cover) {')));
  const drop = src.slice(src.indexOf('  dropFar = () => {'), src.indexOf('  storeRemake = '));
  assert.ok(drop.length > 0 && !/marks/.test(drop.replace('Covers and marks stay', '')));
});

test('working out the drop over a large shoot is quick', () => {
  const C = shoot(5000), t = performance.now(); farFrames(C, 2500, 3);
  assert.ok(performance.now() - t < 100);
});

test('the line sits in the footer outside debug mode, with its rows behind it', () => {
  const foot = template.indexOf('data-lumina="footer"'), line = template.indexOf('data-lumina="storage"'), rows = template.indexOf('data-lumina="storage-rows"'), dbg = template.indexOf('<sc-if value="{{ dbgOn }}"');
  assert.ok(foot > 0 && foot < line && line < rows);
  assert.ok(dbg < foot);                                   // the debug switch is in the top bar, closed before the footer
  assert.match(src, /storeOn:false/);                      // collapsed by default
  assert.match(src, /if \(st\.storeOn && k === 'Escape'\) return this\.setState\(\{storeOn:false\}\)/);
  assert.match(template, /data-lumina="memory-pill"/);    // the debug panel stays as it is
});

test('neutral words only', () => {
  const words = src.slice(src.indexOf('  static storeLine('), src.indexOf('  storeRemake = ')) + src.slice(src.indexOf('    // storage: the line and its rows'), src.indexOf('saidOn:!!(said'));
  assert.ok(!/reject|keeper|delete/i.test(words));
});

test('saved covers are keyed by what the clip is: name, capture time and size', () => {
  assert.equal(coverKey('c0001.mp4', '2026-10-01T10:00:00.123Z', 123456), 'C0001.MP4@2026-10-01T10:00:00#123456');
  assert.notEqual(coverKey('C0001.MP4', '2026-10-01T10:00:00', 1), coverKey('C0001.MP4', '2026-10-01T10:00:00', 2));
  assert.notEqual(coverKey('C0001.MP4', '2026-10-01T10:00:00', 1), coverKey('C0001.MP4', '2026-10-02T10:00:00', 1));
  assert.equal(recBytes({cover:{size:20000}}), 20512);
  assert.equal(recBytes({}), 512);
});

test('over the cap, the shoot opened longest ago goes first, never the one open', () => {
  const S = [{k:'a', at:3, bytes:50}, {k:'b', at:1, bytes:40}, {k:'cur', at:0, bytes:100}, {k:'c', at:2, bytes:30}];
  assert.deepEqual(evictOrder(S, 'cur', 220, 200), ['b']);
  assert.deepEqual(evictOrder(S, 'cur', 220, 160), ['b', 'c']);
  assert.deepEqual(evictOrder(S, 'cur', 220, 0), ['b', 'c', 'a']);       // only the open one is left
  assert.deepEqual(evictOrder(S, 'cur', 150, 200), []);
  assert.deepEqual(evictOrder([], 'cur', 1e9, 0), []);
});

test('the cache hooks: saved covers before the first pass, a new cover saved after it, never in the fill', () => {
  assert.match(src, /this\.coverLoad\(d\)\.then\(\(\) => \{ if \(tok === this\.qTok\) this\.runQueue\(clips\.slice\(\), tok\); \}\)/);
  assert.match(src, /if \(pass !== 2 && idx\.length && !c\.why\) this\.coverNote\(c\);/);
  const load = src.slice(src.indexOf('  async coverLoad(d) {'), src.indexOf('  // coverNote:'));
  assert.match(load, /if \(i % 60 === 59\) \{ this\.bump\(\); await new Promise/);   // gives the page a breath every 60 clips
  assert.ok(!/marks/.test(load) && !/marks/.test(src.slice(src.indexOf('  async coverFlush()'), src.indexOf('  coverStat()'))));
});
