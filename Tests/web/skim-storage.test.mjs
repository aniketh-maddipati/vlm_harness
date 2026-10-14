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
const lowSay = stat('lowSay', 'static lowSay(dr, fmtB) {');
const trashPick = stat('trashPick', 'static trashPick(clips, marks, at, inScope) {');
const driveSay = stat('driveSay', 'static driveSay(dr, fmtB) {');
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
  assert.equal(dumpSay('frames', 180e6, 37, fmtB), 'Free frames · 180 MB');
  assert.equal(dumpSay('frames', 1.4e9, 300, fmtB), 'Free frames · 1.4 GB');
  assert.equal(dumpSay('frames', 0, 0, fmtB), 'Free frames · nothing to free');
  assert.equal(dumpSay('frames', 5e6, 0, fmtB), 'Free frames · nothing to free');
  assert.equal(dumpSay('saved', 120e6, 3, fmtB), 'Clear other shoots · 120 MB');
  assert.equal(dumpSay('saved', 0, 0, fmtB), 'Clear other shoots · nothing to free');
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
  const drop = src.slice(src.indexOf('  dropFar = '), src.indexOf('  // Saved covers, the page\'s side.'));
  assert.ok(drop.length > 0 && !/marks/.test(drop.replace('Previews and marks stay', '')));
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
  assert.match(src, /if \(st\.storeOn && k === 'Escape'\) return this\.storeShut\(\)/);   // Escape closes it (it drops back down, then goes)
  assert.match(src, /storeShut\(\) \{ this\.foldShut\('\[data-lumina="storage-rows"\]', \(\) => \{ this\.storeSaid = null; this\.setState\(\{storeOn:false\}\)/);
  assert.match(template, /data-lumina="memory-pill"/);    // the debug panel stays as it is
});

test('neutral words only', () => {
  const code = src.slice(src.indexOf('  static storeLine('), src.indexOf('  storeRemake = ')) + src.slice(src.indexOf('    // storage: the line and its rows'), src.indexOf('    // hints'));
  const words = (code.match(/'(?:[^'\\\n]|\\.)*'/g) || []).join(' ');          // what is said on screen: the quoted strings
  assert.ok(words.length > 2000);
  assert.ok(!/reject|keeper|delet/i.test(words), words.match(/.{0,40}(reject|keeper|delet).{0,40}/i));
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
  assert.match(load, /for \(let a = 0; a < C\.length; a \+= 60\)/);                 // 60 clips at a time
  assert.match(load, /this\.bump\(\); await new Promise\(res => setTimeout\(res, 0\)\);/);   // with a breath between
  assert.ok(!/marks/.test(load) && !/marks/.test(src.slice(src.indexOf('  async coverFlush()'), src.indexOf('  coverStat()'))));
});

test('the 20 % line: one plain line under it, nothing at or over it, nothing when the drive was not read', () => {
  assert.equal(lowSay({name:'T7', free:150e9, total:1e12}, fmtB), 'Under 20% free on T7: 150.0 GB left.');
  assert.equal(lowSay({name:'T7', free:200e9, total:1e12}, fmtB), '');
  assert.equal(lowSay({name:'T7', free:500e9, total:1e12}, fmtB), '');
  assert.equal(lowSay({free:1e9, total:1e12}, fmtB), 'Under 20% free on this drive: 1.0 GB left.');
  assert.equal(lowSay(null, fmtB), '');
  assert.equal(lowSay({name:'T7', free:null, total:1e12}, fmtB), '');
  assert.equal(lowSay({name:'T7', free:1e9}, fmtB), '');                 // no size, no share
});

test('the drive\'s figure: plain free space first, purgeable named so it agrees with Finder', () => {
  assert.equal(driveSay({free:52e9, total:1e12, purgeable:8e9}, fmtB), '52.0 GB free of 1000.0 GB · 8.0 GB purgeable');
  assert.equal(driveSay({free:52e9, total:1e12, purgeable:0}, fmtB), '52.0 GB free of 1000.0 GB');
  assert.equal(driveSay({free:52e9}, fmtB), '52.0 GB free');
  assert.equal(driveSay({free:null, total:1e12}, fmtB), '');
  assert.equal(driveSay(null, fmtB), '');
});

test('Move cut to Trash: cut only, never maybe, never the clip on screen or its neighbours, only what is still on the drive', () => {
  const C = Array.from({length:60}, (_, i) => ({id:'c' + i, _i:i, bytes:1e9, _file:{}, t:(i < 30 ? '2026-10-01' : '2026-10-02') + 'T10:00:00'}));
  const marks = {}; C.forEach((c, i) => { marks[c.id] = i % 3 === 0 ? 'cut' : i % 3 === 1 ? 'maybe' : 'keep'; });
  const all = trashPick(C, marks, 30, () => true);
  assert.ok(all.list.every(c => marks[c.id] === 'cut'));
  assert.ok(all.list.every(c => Math.abs(c._i - 30) > 12));
  assert.equal(all.list.length + all.near, 20);                       // every cut clip is either moved or held back as near
  assert.equal(all.near, C.filter(c => marks[c.id] === 'cut' && Math.abs(c._i - 30) <= 12).length);
  assert.equal(all.bytes, all.list.length * 1e9);
  const day1 = trashPick(C, marks, 30, c => c.t.startsWith('2026-10-01'));
  assert.ok(day1.list.every(c => c._i < 30) && day1.list.length > 0);
  C[0].trashed = true; C[3]._file = null;                              // in the Trash already; a sample clip with no file
  const again = trashPick(C, marks, 30, () => true);
  assert.ok(!again.list.includes(C[0]) && !again.list.includes(C[3]));
  assert.equal(trashPick(C, {}, 30, () => true).list.length, 0);
  assert.equal(dumpSay('cut', 3.5e9, 3, fmtB), 'Move cut to Trash · 3.5 GB');
  assert.equal(dumpSay('cut', 0, 0, fmtB), 'Move cut to Trash · nothing to free');
});

test('cut clips move only after the Final Cut file is saved, and only with two clicks', () => {
  const go = src.slice(src.indexOf('  trashGo = () => {'), src.indexOf('  trashBack = () => {'));
  assert.match(go, /!this\.isSent\(\)/);
  assert.match(go, /this\.drv && this\.drv\.refusal/);
  assert.match(go, /if \(!st\.trConfirm\) \{/);
  assert.match(src, /this\.persist\(this\.sentKey\(\), new Date\(\)\.toISOString\(\)\);/);   // noted when the .fcpxml is saved
  assert.match(src, /'Only cut clips move, never maybe\./);
  assert.match(src, /fillNeed\(c\) \{ return c\.facts && c\.facts\.state === 'ready' && \(c\._file \|\| c\._mock\) && !c\.trashed/);
});
