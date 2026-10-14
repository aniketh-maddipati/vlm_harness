// A folder too big for one go (LOCAL-CHANGES 271): past BIG.clips clips, or a drop cut short past BIG.files files, Open
// says so (bigSay) and waits; the first BIG.clips by name, or a smaller folder. Read out of the page and run on a stand-in.
//
//   node --test Tests/web/skim-big.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const BIG = {clips:1500, files:50000};
const fmtB = b => b >= 1e9 ? (b / 1e9).toFixed(1) + ' GB' : Math.max(1, Math.round(b / 1e6)) + ' MB';
const Component = {BIG, isClip:f => /\.(mp4|mov|mxf|m4v|3gp)$/i.test(f.name)};
Component.bigSay = new Function('Component', 'return function ' + extractMethod(src, 'bigSay', 'static bigSay(b, fmtB) {').replace(/^static /, ''))(Component);
const importFiles = new Function('Component', 'return ' + extractMethod(src, 'importFiles', 'async importFiles(files, cap, walked) {').replace(/^async /, 'async function '))(Component);

test('the limits are the ones the page uses', () => {
  assert.match(src, /static BIG = \{clips:1500, files:50000\};/);
});

test('too many clips: the count, the size, and the first 1,500 offered', () => {
  const s = Component.bigSay({n:4812, bytes:1.93e12, cut:0, name:'DCIM'}, fmtB);
  assert.equal(s.h, 'Too many clips to skim at once');
  assert.equal(s.line, '4,812 clips · 1.9 TB. Skim takes up to 1,500 at a time; more would slow every key. Pick the card or the day you want, or open the first 1,500 by name.');
  assert.equal(s.go, 'Open the first 1,500');
});

test('a walk cut short: how far it looked, and what it found', () => {
  const s = Component.bigSay({n:212, bytes:61e9, cut:50000, name:'aniketh'}, fmtB);
  assert.equal(s.h, 'Too many files to look through');
  assert.equal(s.line, 'Skim stopped looking after 50,000 files and found 212 clips (61.0 GB) so far. Pick the card or the day you want, or open what was found.');
  assert.equal(s.go, 'Open the 212 found');
});

const files = n => Array.from({length:n}, (_, i) => ({name:'C' + String(n - i).padStart(5, '0') + '.MP4', size:1e8, webkitRelativePath:'CARD/' + 'C' + String(n - i).padStart(5, '0') + '.MP4'}));
const stand = () => ({state:{step:'skim'}, steps:[], listed:null, setState(o) { Object.assign(this.state, o); }, setStep(s) { this.steps.push(s); this.state.step = s; }, plural:(n, w) => n + ' ' + w + (n === 1 ? '' : 's'),
  // the listing is where a let-through import goes next: record what it was handed and stop there
  inBatches(v) { this.listed = v; throw new Error('listed'); }});

test('past the limit nothing is listed: Open shows the warning and holds the files', async () => {
  const p = stand(), fs = files(1501);
  await importFiles.call(p, fs);
  assert.equal(p.listed, null);
  assert.deepEqual(p.state.big, {n:1501, bytes:1501e8, cut:0, name:'CARD'});
  assert.equal(p.bigHeld.files, fs); assert.deepEqual(p.steps, ['import']); assert.equal(p.keepAt, 'done');
});

test('at the limit it opens as before', async () => {
  const p = stand(); await importFiles.call(p, files(1500)).catch(() => {});
  assert.equal(p.listed.length, 1500); assert.equal(p.state.big, undefined);
});

test('the first 1,500 are the first by name, and a new import clears the warning', async () => {
  const p = stand(); p.state.big = {n:1}; await importFiles.call(p, files(1600), 1500).catch(() => {});
  assert.equal(p.listed.length, 1500); assert.equal(p.state.big, null);
  assert.equal(p.listed[0].name, 'C00001.MP4'); assert.equal(p.listed[1499].name, 'C01500.MP4');
});

test('a reload in the app keeps the cap that was chosen', async () => {
  const p = stand(); p.kept = {cap:1500}; await importFiles.call(p, files(1600)).catch(() => {});
  assert.equal(p.listed.length, 1500);
});

test('a drop cut short asks even when it found few clips', async () => {
  const p = stand(); await importFiles.call(p, files(12), 0, {files:50000});
  assert.equal(p.listed, null); assert.equal(p.state.big.cut, 50000);
  const q = stand(); await importFiles.call(q, [{name:'a.txt', size:1}], 0, {files:50000});
  assert.equal(q.state.impMsg, 'No clips in the first 50,000 files. Pick the folder the clips are in.');
});

test('the drop walk counts as it goes, stops past BIG.files, and hands over what it found', () => {
  const d = extractMethod(src, 'dropIn', 'dropIn = async e => {');
  assert.match(d, /if \(n >= B\.files\) cut = true/);
  assert.match(d, /'Looking through ' \+ n\.toLocaleString\('en-US'\) \+ ' files · '/);
  assert.match(d, /this\.importFiles\(out, 0, cut \? \{files:n\} : null\)/);
});

// The app's side (SetsRootView.skimPick + SkimPickScan): the app counts the folder before WebKit lists it and drives the card.
const host = () => {
  const p = stand(); p.fileEl = {clicks:0, click() { this.clicks++; }};
  p.bigHost = new Function('return function ' + extractMethod(src, 'bigHost', 'bigHost() {'))();
  p.bigGo = new Function('Component', 'return function () ' + extractMethod(src, 'bigGo', 'bigGo = () => {').replace(/^bigGo = \(\) => /, ''))(Component);
  return {p, h:p.bigHost()};
};

test('in the app: the count while it looks, then the card, and Open the first asks the app for its clips', () => {
  const {p, h} = host();
  h.looking('T7', 0, 0); assert.equal(p.state.impMsg, 'Looking through “T7”…');
  h.looking('T7', 24000, 812); assert.equal(p.state.impMsg, 'Looking through 24,000 files in “T7” · 812 clips so far…');
  h.show({name:'T7', n:2210, bytes:1.2e12, cut:0});
  assert.equal(p.state.impMsg, null); assert.deepEqual(p.state.big, {n:2210, bytes:1.2e12, cut:0, name:'T7'}); assert.deepEqual(p.steps, ['import']);
  assert.equal(h.want(), false, 'Pick a smaller folder (or no answer) is the panel again');
  p.bigGo.call(p);
  assert.equal(p.fileEl.clicks, 1); assert.equal(h.want(), true); assert.equal(h.want(), false, 'asked once');
  assert.equal(p.bigCap, 1500); assert.equal(p.bigRoot, 'T7'); assert.equal(p.state.big, null);
  h.looking(null); assert.equal(p.state.impMsg, null);
});

test('in the app: a firehose with no clips says so instead of offering nothing', () => {
  const {p, h} = host(); h.show({name:'Macintosh HD', n:0, bytes:0, cut:50000});
  assert.equal(p.state.big, null); assert.equal(p.state.impMsg, 'No clips in the first 50,000 files of “Macintosh HD”. Pick the folder the clips are in.');
});

test('the clips the app hands back open under the folder\'s name, capped, as a reload keeps them', async () => {
  const p = stand(); p.bigCap = 1500; p.bigRoot = 'T7';
  const loose = files(3).map(f => ({...f, webkitRelativePath:''}));
  await importFiles.call(p, loose).catch(() => {});
  assert.equal(p.listed.length, 3); assert.equal(p.bigCap, 0);
  assert.match(src, /const root = \(\/\\\.\\w\+\$\/\.test\(rel\(vids\[0\]\)\.split\('\/'\)\[0\]\) && this\.bigRoot\)/);
  assert.match(src, /window\.luminaSkimBig = this\.bigHost\(\);/);
});
