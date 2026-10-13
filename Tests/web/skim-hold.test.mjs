// The Skim page across the Mac app's own reload: hold() keeps the marks for the clips that are open, and
// heldBack() gives them back once, to the same clips only. Both are read out of the page, as skim-export.mjs
// reads buildX.
//
//   node --test Tests/web/skim-hold.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const Component = {HELD:'lumina-skimheld'};
const method = (name, args) => new Function('Component', 'sessionStorage', 'return function ' + extractMethod(src, name, name + '(' + args + ') {'));
function page(store, clips, state, rel = null){
  const d = clips ? {clips:clips.map(([id, path, bytes]) => ({id, path, bytes, _file:{}}))} : null;
  const p = {d, rel, userCut:false, byId:{}, state:{marks:{}, dis:{}, cuts:null, nCut:3, lv:0, gi:0, cur:null, fx:0, step:'skim', pv:true, zl:3, ...state}};
  if (d) d.clips.forEach(c => p.byId[c.id] = c);
  p.setState = o => Object.assign(p.state, o);
  for (const [n, a] of [['heldSig', 'd'], ['hold', ''], ['heldBack', 'd']]) p[n] = method(n, a)(Component, store);
  return p;
}
const storage = () => { const m = new Map(); return {getItem:k => m.has(k) ? m.get(k) : null, setItem:(k, v) => m.set(k, String(v)), removeItem:k => m.delete(k), size:() => m.size}; };
const CLIPS = [['F0001', 'A/C0001.MP4', 100], ['F0002', 'A/C0002.MP4', 200]];

test('the marks, the place and the step come back to the same clips, once', () => {
  const s = storage();
  const before = page(s, CLIPS, {marks:{F0002:'keep'}, dis:{F0001:['soft']}, lv:2, cur:'F0002', step:'export'});
  assert.equal(before.hold(), 'pick');
  const after = page(s, CLIPS, {cur:'F0001'});
  after.heldBack(after.d);
  assert.deepEqual(after.state.marks, {F0002:'keep'}); assert.deepEqual(after.state.dis, {F0001:['soft']});
  assert.equal(after.state.lv, 2); assert.equal(after.state.cur, 'F0002'); assert.equal(after.state.step, 'export');
  assert.equal(s.size(), 0);
  const again = page(s, CLIPS, {}); again.heldBack(again.d); assert.deepEqual(again.state.marks, {});
});

test('other clips do not get the marks, and what was held is gone', () => {
  const s = storage();
  page(s, CLIPS, {marks:{F0001:'cut'}}).hold();
  const other = page(s, [['F0001', 'B/C0009.MP4', 100]], {});
  other.heldBack(other.d);
  assert.deepEqual(other.state.marks, {}); assert.equal(s.size(), 0);
});

test('dropped clips answer drop and hold nothing; nothing open answers false', () => {
  const s = storage();
  assert.equal(page(s, CLIPS, {marks:{F0001:'cut'}}, new Map()).hold(), 'drop'); assert.equal(s.size(), 0);
  assert.equal(page(s, null, {}).hold(), false);
});

test('a second reload before the clips are back keeps what the first one held', () => {
  const s = storage();
  page(s, CLIPS, {marks:{F0001:'maybe'}}).hold();
  assert.equal(page(s, null, {}).hold(), 'pick');
  const after = page(s, CLIPS, {}); after.heldBack(after.d);
  assert.deepEqual(after.state.marks, {F0001:'maybe'});
});

test('what was held more than 90 s ago is not given back', () => {
  const s = storage();
  page(s, CLIPS, {marks:{F0001:'keep'}}).hold();
  const h = JSON.parse(s.getItem('lumina-skimheld')); h.at -= 91000; s.setItem('lumina-skimheld', JSON.stringify(h));
  assert.equal(page(s, null, {}).hold(), false);
  const after = page(s, CLIPS, {}); after.heldBack(after.d);
  assert.deepEqual(after.state.marks, {});
});
