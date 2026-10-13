// The Mac app's reload in place (LOCAL-CHANGES 257): keepTake and keepApply, read out of the page itself and run on a
// stand-in for the page. The kept shoot is by clip (name and time), so it lands on the same clips after a new read.
//
//   node --test Tests/web/skim-keep.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const method = (name, head) => new Function('return function ' + extractMethod(src, name, head))();
const keepTake = method('keepTake', 'keepTake() {'), keepApply = method('keepApply', 'keepApply() {'), keepReopen = method('keepReopen', 'keepReopen(kept) {');
const clipKey = c => (c.name || '').toUpperCase() + '@' + (c.t || '').slice(0, 19);

const page = (ids, state = {}) => {
  const clips = ids.map((id, i) => ({id, name:'C000' + i + '.MP4', t:'2026-10-0' + (i + 1) + 'T10:00:00'}));
  const byId = {}; clips.forEach(c => { byId[c.id] = c; });
  return {d:{shoot:{real:true, name:'Day 1'}, clips}, byId, clipKey, keepTake, keepApply, keepReopen,
    state:{marks:{}, dis:{}, cuts:null, nCut:3, cur:ids[0], step:'skim', lv:0, gi:0, zl:3, ex:{event:'', kw:'maybe'}, ...state},
    setState(o, cb) { Object.assign(this.state, o); if (cb) cb(); }};
};

test('marks and view come back on the same clips under new ids', () => {
  const a = page(['F0001', 'F0002', 'F0003'], {marks:{F0002:'keep', F0003:'cut'}, dis:{F0001:['scene']}, cuts:['F0003'], cur:'F0002', step:'export', lv:2, gi:1, zl:5, ex:{event:'Wedding', kw:'maybe'}});
  a.d.shoot.name = 'Renamed'; a.userCut = true;
  const kept = a.keepTake();
  // the reload reads the clips again in another order: other ids
  const b = page(['F0003', 'F0001', 'F0002']); b.d.clips = [a.d.clips[2], a.d.clips[0], a.d.clips[1]].map((c, i) => ({...c, id:['F0003', 'F0001', 'F0002'][i]}));
  b.d.clips.forEach(c => { b.byId[c.id] = c; });
  const fileEl = {clicks:0, click() { this.clicks++; }}; b.fileEl = fileEl;
  assert.equal(b.keepReopen(kept), true); assert.equal(fileEl.clicks, 1); assert.equal(b.keepAt, 'opening');
  b.keepApply();
  const id = name => b.d.clips.find(c => c.name === name).id;
  assert.deepEqual(b.state.marks, {[id('C0001.MP4')]:'keep', [id('C0002.MP4')]:'cut'});
  assert.deepEqual(b.state.dis, {[id('C0000.MP4')]:['scene']});
  assert.deepEqual(b.state.cuts, [id('C0002.MP4')]);
  assert.equal(b.state.cur, id('C0001.MP4'));
  assert.equal(b.state.step, 'export'); assert.equal(b.state.lv, 2); assert.equal(b.state.gi, 1); assert.equal(b.state.zl, 5);
  assert.equal(b.state.ex.event, 'Wedding'); assert.equal(b.d.shoot.name, 'Renamed'); assert.equal(b.userCut, true);
  assert.equal(b.keepAt, 'done'); assert.equal(b.kept, null);
});

test('a clip that is gone takes its marks with it', () => {
  const a = page(['F0001', 'F0002'], {marks:{F0001:'keep', F0002:'keep'}, cur:'F0002'});
  const b = page(['F0001']); b.fileEl = {click() {}}; b.keepReopen(a.keepTake()); b.keepApply();
  assert.deepEqual(b.state.marks, {F0001:'keep'}); assert.equal(b.state.cur, 'F0001');
});

test('nothing is kept from the sample shoot or an empty page', () => {
  const s = page(['A']); s.d.shoot.real = false; assert.equal(s.keepTake(), null);
  const e = page([]); assert.equal(e.keepTake(), null);
  const r = page(['A']); r.fileEl = {click() { throw new Error('no'); }};
  assert.equal(r.keepReopen(null), false); assert.equal(r.keepAt, 'done');
});

test('the page offers the hook and applies it after the reopened clips are listed', () => {
  assert.match(src, /window\.luminaSkimKeep = \{take:/);
  assert.match(src, /this\.loadData\(d, 'skim'\);[^\n]*\n    if \(this\.kept\) this\.keepApply\(\);/);
  assert.match(src, /if \(!vids\.length\) \{ this\.kept = null; this\.keepAt = 'done';/);
});

test('a reload while the last one is coming back keeps the shoot as it was kept', () => {
  const a = page(['F0001'], {marks:{F0001:'keep'}});
  const b = page([]); b.fileEl = {click() {}}; b.keepReopen(a.keepTake());
  assert.deepEqual(JSON.parse(b.keepTake()).marks, {'C0000.MP4@2026-10-01T10:00:00':'keep'});
});

test('dropped clips are not reloaded', () => {
  const a = page(['F0001'], {marks:{F0001:'keep'}}); a.picked = false;
  assert.deepEqual(JSON.parse(a.keepTake()), {dropped:true});
  assert.match(src, /this\.picked = !!this\.pickNext;/);
  assert.match(src, /this\.pickNext = true; this\.importFiles\(fs\);/);
  assert.match(src, /dropHot:false\}\); this\.pickNext = false;/);
});
