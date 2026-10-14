// Stop here and Cancel beside Go on while reading is paused (LOCAL-CHANGES 273): Stop here keeps what was read and goes on
// with it; Cancel asks, then throws the load away and goes back to Open. Read out of the page, run on a stand-in.
//
//   node --test Tests/web/skim-stop.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const arrow = (name, head) => new Function('Component', 'localStorage', 'return function () ' + extractMethod(src, name, head).slice(head.length - 1));
const Component = {readKept:new Function('return function ' + extractMethod(src, 'readKept', 'static readKept(clips) {').replace(/^static /, ''))()};
const readStop = arrow('readStop', 'readStop = () => {')(Component), cancelYes = arrow('cancelYes', 'cancelYes = () => {');

const page = (states, extra = {}) => {
  const clips = states.map((s, i) => ({id:'F' + i, _i:i, bytes:100, facts:{state:s}, frames:[s === 'pending' ? null : 'blob:x']}));
  const p = {d:{shoot:{real:true, name:'T7', bytes:clips.length * 100}, clips}, state:{marks:{F0:'keep', F3:'cut'}, dis:{}, cur:'F3', sel:['F0', 'F3'], imp:{n:clips.length, done:2}},
    mp:{pace:'paused'}, reading:new Set(['F2']), dropped:[], filled:null, saved:0, persisted:[], cleared:0,
    setState(o, cb) { Object.assign(this.state, typeof o === 'function' ? o(this.state) : o); if (cb) cb(); }, realReading() { return !!(this.state.imp && this.state.imp.done < this.state.imp.n); },
    storeKey(d) { return 'lumina-skim:' + d.shoot.name + '-' + d.clips.length; }, dropFrames(cs) { this.dropped.push(...cs.map(c => c.id)); }, regap() {}, fitCut: n => n, plural:(n, w) => n + ' ' + w + (n === 1 ? '' : 's'),
    save() { this.saved++; }, fillStart(list) { this.filled = list.map(c => c.id); }, persist(k, v) { this.persisted.push([k, v]); }, clearMemory() { this.cleared++; this.state.step = 'import'; }, ...extra};
  return p;
};

test('Stop here keeps the clips read so far, lets the rest go, and goes on with them', () => {
  const p = page(['ready', 'unreliable', 'pending', 'pending']);
  readStop.call(p);
  assert.deepEqual(p.d.clips.map(c => c.id), ['F0', 'F1']); assert.deepEqual(p.dropped, ['F2', 'F3']);
  assert.equal(p.d.shoot.key, 'lumina-skim:T7-4', 'the shoot keeps the entry its marks were saved under');
  assert.deepEqual(p.state.marks, {F0:'keep'}); assert.equal(p.state.cur, 'F0'); assert.deepEqual(p.state.sel, ['F0']);
  assert.equal(p.state.imp, null); assert.equal(p.mp.pace, 'auto'); assert.equal(p.reading.size, 0);
  assert.deepEqual(p.filled, ['F0', 'F1'], 'their other frames fill in behind'); assert.equal(p.saved, 1);
  assert.equal(p.recNote.t, 'Stopped · kept 2 of 4 clips'); assert.equal(p.d.shoot.bytes, 200);
});

test('Stop here does nothing before a clip is read, or once reading is over', () => {
  const p = page(['pending', 'pending']); readStop.call(p); assert.equal(p.d.clips.length, 2);
  const q = page(['ready', 'pending']); q.state.imp = null; readStop.call(q); assert.equal(q.d.clips.length, 2);
});

test('Cancel throws the load away and says so on Open; with no marks it leaves no card behind', () => {
  const p = page(['ready', 'pending']); p.state.marks = {};
  cancelYes(Component, {getItem:() => null}).call(p);
  assert.equal(p.cleared, 1); assert.deepEqual(p.persisted, [['lumina-skim:T7-2', null]]); assert.equal(p.mp.pace, 'auto');
  assert.equal(p.state.impMsg, 'Stopped loading “T7”. Nothing on the drive was touched.');
});

test('Cancel keeps marks already saved for that shoot', () => {
  const p = page(['ready', 'pending']); p.state.marks = {};
  cancelYes(Component, {getItem:() => JSON.stringify({km:{'a':'keep'}})}).call(p);
  assert.equal(p.cleared, 1); assert.deepEqual(p.persisted, []);
  const q = page(['ready', 'pending']); cancelYes(Component, {getItem:() => null}).call(q); assert.deepEqual(q.persisted, [], 'marks made in this load stay saved too');
});

test('the buttons: only while paused or stopped on a bad card, Cancel asks first', () => {
  assert.match(src, /\(running && n > 0 && \(this\.mp\.pace === 'paused' \|\| !!this\.halt\), running \? Component\.readKept\(C\)\.length : 0\)/);
  assert.match(src, /readCancel = \(\) => \{ if \(this\.realReading\(\)\) this\.setState\(\{cancelAsk:true\}\); \};/);
  assert.match(src, /data-lumina="cancel-yes"[^>]*>Throw away<\/button>/); assert.match(src, /data-lumina="cancel-no"[^>]*>Keep loading<\/button>/);
});
