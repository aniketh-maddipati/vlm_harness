// Every way clips come in (LOCAL-CHANGES 297): the same breathing status while they are looked through, listed or added,
// and the same too-big card for Add clips as for Open, against the room the shoot has left. Read out of the page.
//
//   node --test Tests/web/skim-loads.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const fmtB = b => b >= 1e9 ? (b / 1e9).toFixed(1) + ' GB' : Math.max(1, Math.round(b / 1e6)) + ' MB';
const Component = {BIG:{clips:1500, files:50000}, isClip:f => /\.(mp4|mov|mxf|m4v|3gp)$/i.test(f.name), liveSet:() => new Set()};
Component.bigSay = new Function('Component', 'return function ' + extractMethod(src, 'bigSay', 'static bigSay(b, fmtB) {').replace(/^static /, ''))(Component);
const addFiles = new Function('Component', 'window', 'return ' + extractMethod(src, 'addFiles', 'async addFiles(files, how) {').replace(/^async /, 'async function '))(Component, {});
const bigHost = new Function('Component', 'return function ' + extractMethod(src, 'bigHost', 'bigHost() {'))(Component);
const arrow = (name, head) => new Function('Component', 'window', 'return function () ' + extractMethod(src, name, head).slice(head.length - 1));

test('Add clips: the card says how many more the shoot takes', () => {
  const s = Component.bigSay({n:2210, bytes:1.2e12, cut:0, name:'T7', room:1100, have:400}, fmtB);
  assert.equal(s.h, 'Too many clips to add at once');
  assert.equal(s.line, '2,210 clips · 1.2 TB. This shoot has 400 and Skim takes up to 1,500 at a time, so 1,100 more fit.');
  assert.equal(s.go, 'Add the first 1,100'); assert.equal(s.pick, 'Pick fewer clips'); assert.ok(s.goOn);
});

test('Add clips: a full shoot offers the clips as a shoot of their own', () => {
  const s = Component.bigSay({n:12, bytes:5e9, cut:0, name:'day2', room:0, have:1500}, fmtB);
  assert.equal(s.h, 'This shoot is full'); assert.equal(s.goOn, false); assert.equal(s.pick, 'Open them as a new shoot');
  assert.match(s.line, /so no more fit\. Cut this shoot down, or open the rest as a shoot of its own\.$/);
});

test('Add clips: a drop cut short says how far it looked, and adds what was found when it fits', () => {
  const s = Component.bigSay({n:40, bytes:4e10, cut:50000, name:'Macintosh HD', room:900, have:600}, fmtB);
  assert.equal(s.h, 'Too many files to look through'); assert.equal(s.go, 'Add the 40 found');
  assert.match(s.line, /^Skim stopped looking after 50,000 files and found 40 clips \(40\.0 GB\) so far\. This shoot has 600/);
});

test('Open\'s card is unchanged', () => {
  const s = Component.bigSay({n:1600, bytes:1.9e12, cut:0, name:'CARD'}, fmtB);
  assert.equal(s.h, 'Too many clips to skim at once'); assert.equal(s.go, 'Open the first 1,500');
});

const files = n => Array.from({length:n}, (_, i) => ({name:'C' + String(n - i).padStart(5, '0') + '.MP4', size:1e8, webkitRelativePath:'DAY2/C' + String(n - i).padStart(5, '0') + '.MP4', lastModified:0}));
const shoot = n => {
  const d = {shoot:{real:true}, clips:Array.from({length:n}, (_, i) => ({id:'F' + i}))};
  return {d, state:{step:'skim'}, setState(o) { Object.assign(this.state, o); }, busy(t) { this.setState({impMsg:t, impBusyT:t}); }, bump() {}, plural:(n, w) => n + ' ' + w + (n === 1 ? '' : 's'),
    listed:null, inBatches(v) { this.listed = v; throw new Error('listed'); }};
};

test('Add clips past the room: nothing is listed, the card holds the files', async () => {
  const p = shoot(1400), fs = files(300);
  await addFiles.call(p, fs, {rel:null, dropped:false});
  assert.equal(p.listed, null); assert.deepEqual(p.state.bigAdd, {n:300, bytes:3e10, cut:0, name:'DAY2', room:100, have:1400});
  assert.equal(p.bigAddHeld.files, fs); assert.equal(p.bigAddHeld.room, 100);
});

test('Add clips within the room lists them with the breathing status', async () => {
  const p = shoot(10); await addFiles.call(p, files(5), {rel:null, dropped:false}).catch(() => {});
  assert.equal(p.listed.length, 5); assert.equal(p.state.impMsg, 'Adding 5 clips…'); assert.equal(p.state.impBusyT, 'Adding 5 clips…'); assert.equal(p.state.bigAdd, undefined);
});

test('Add the first N takes the first that fit, by path', async () => {
  const p = shoot(1400); await addFiles.call(p, files(300), {rel:null, dropped:false, cap:100}).catch(() => {});
  assert.equal(p.listed.length, 100); assert.equal(p.listed[0].name, 'C00001.MP4'); assert.equal(p.listed[99].name, 'C00100.MP4');
});

test('a dropped folder cut short asks even when its clips fit', async () => {
  const p = shoot(10); await addFiles.call(p, files(3), {rel:null, dropped:true, cut:50000});
  assert.equal(p.listed, null); assert.equal(p.state.bigAdd.cut, 50000);
  const q = shoot(10); await addFiles.call(q, [{name:'a.txt', size:1}], {rel:null, dropped:true, cut:50000});
  assert.equal(q.recNote.t, 'Nothing added · no clips in the first 50,000 files');
});

test('the card\'s buttons: the first that fit, a smaller pick, not now; a full shoot opens them on their own', () => {
  const go = arrow('bigAddGo', 'bigAddGo = () => {'), pick = arrow('bigAddPick', 'bigAddPick = () => {'), close = arrow('bigAddClose', 'bigAddClose = () => {');
  const p = shoot(1400); p.bigAddHeld = {files:files(300), how:{rel:null, dropped:false}, room:100}; p.state.bigAdd = {n:300}; p.added = null; p.addFiles = (fs, how) => { p.added = [fs.length, how.cap]; };
  go(Component, {}).call(p); assert.deepEqual(p.added, [300, 100]); assert.equal(p.state.bigAdd, null);
  const w = {}, el = {clicks:0, click() { this.clicks++; }}, h = shoot(1400); h.addDirEl = el; h.bigAddHeld = {host:true, room:100};
  go(Component, w).call(h); assert.equal(el.clicks, 1); assert.equal(h.bigWant, true); assert.equal(w.luminaSkimAdding, true);
  const f = shoot(1500); f.bigAddHeld = {files:files(3), how:{rel:null, dropped:true, cut:0}, room:0}; let opened = null, saved = 0, cleared = 0;
  Object.assign(f, {save() { saved++; }, clearMemory() { cleared++; }, importFiles(fs) { opened = fs.length; }});
  pick(Component, {}).call(f); assert.equal(saved, 1); assert.equal(cleared, 1); assert.equal(opened, 3); assert.equal(f.pickNext, false);
  const c = shoot(10); c.bigAddHeld = {}; c.bigWant = true; c.state.bigAdd = {n:1}; close(Component, {}).call(c); assert.equal(c.state.bigAdd, null); assert.equal(c.bigWant, false);
});

test('in the app: the room the shoot has, and the card over Skim', () => {
  const p = shoot(1200), h = bigHost.call(p);
  assert.equal(h.room(), 300);
  h.looking('T7', 4000, 120); assert.equal(p.state.impMsg, 'Looking through 4,000 files in “T7” · 120 clips so far…'); assert.equal(p.state.impBusyT, p.state.impMsg);
  h.showAdd({name:'T7', n:2210, bytes:1e12, cut:0});
  assert.equal(p.state.impMsg, null); assert.deepEqual(p.state.bigAdd, {n:2210, bytes:1e12, cut:0, name:'T7', room:300, have:1200}); assert.deepEqual(p.bigAddHeld, {host:true, room:300});
  const q = {state:{}, setState(o) { Object.assign(this.state, o); }}; assert.equal(bigHost.call(q).room(), 1500, 'no shoot open: the whole limit');
});

test('the status is busy only while it is the same line that was set as busy, on Open and in Skim\'s bar', () => {
  assert.match(src, /impBusy:!!st\.impMsg && st\.impMsg === st\.impBusyT, busyBarOn:!!st\.impMsg && st\.impMsg === st\.impBusyT && st\.step !== 'import'/);
  assert.match(src, /data-lumina="imp-msg" aria-busy="\{\{ impBusy \}\}"/); assert.match(src, /data-lumina="busy" role="status"/);
  for (const t of ["this.busy('Looking through '", "this.busy('Listing '", "this.busy('Adding '"]) assert.ok(src.includes(t), t);
});

test('a browser picker that is still listing a folder says so, until the files come or it is cancelled', () => {
  const pw = extractMethod(src, 'pickWait', 'pickWait(el) {');
  assert.match(pw, /if \(this\.exHostApi\(\) \|\| typeof window === 'undefined' \|\| !\('oncancel' in el\)\) return;/);
  assert.match(pw, /window\.addEventListener\('focus', back, \{once:true\}\); el\.addEventListener\('cancel', gone, \{once:true\}\); el\.addEventListener\('change', got, \{once:true\}\);/);
  assert.match(src, /if \(el\) \{ this\.pickWait\(el\); el\.click\(\); \}/); assert.match(src, /this\.pickWait\(el\); el\.click\(\);\n  \};/);
});

const hostRel = new Function('window', 'return function ' + extractMethod(src, 'hostRel', 'static hostRel(files) {').replace(/^static /, ''));

test('in the app the picker gets only clips and sidecars, and each keeps the place the Mac sent for it (292)', () => {
  const w = {luminaSkimRel:[['C0001.MP4', 10, 'T7/DCIM/A/C0001.MP4'], ['C0001.MP4', 10, 'T7/DCIM/B/C0001.MP4'], ['C0001M01.XML', 3, 'T7/DCIM/A/C0001M01.XML']]};
  const a = {name:'C0001.MP4', size:10}, b = {name:'C0001.MP4', size:10}, x = {name:'C0001M01.XML', size:3}, z = {name:'other.MP4', size:1};
  const m = hostRel(w)([a, b, x, z]);
  assert.equal(m.get(a), 'T7/DCIM/A/C0001.MP4'); assert.equal(m.get(b), 'T7/DCIM/B/C0001.MP4'); assert.equal(m.get(x), 'T7/DCIM/A/C0001M01.XML');
  assert.equal(m.has(z), false); assert.equal(w.luminaSkimRel, null, 'used once');
  assert.equal(hostRel({})([a]), null, 'a browser: the files carry their own paths');
  assert.match(src, /filesIn = e => \{ const fs = \[\.\.\.\(e\.target\.files \|\| \[\]\)\]; e\.target\.value = ''; this\.rel = Component\.hostRel\(fs\);/);
  assert.match(src, /this\.addFiles\(fs, \{rel:Component\.hostRel\(fs\), dropped:false\}\)/);
});

test('the breathing dot runs on the compositor, so it keeps moving while the page thread is held', () => {
  const dots = src.match(/animation:breathe 1\.2s[^"]*/g) || [];
  assert.ok(dots.length >= 2); for (const d of dots) assert.match(d, /will-change:opacity/);
});
