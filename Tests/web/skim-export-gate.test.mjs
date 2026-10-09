// When the Export screen's Final Cut download may write a file, and what its button says
// (Component.exGate and download, read out of the page). The rule: a file is written only when the
// .fcpxml would hold at least one clip under the current options, and the button says what it holds.
//
//   node --test Tests/web/skim-export-gate.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod, loadBuildX } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const exGate = new Function('return function ' + extractMethod(src, 'exGate', 'static exGate(markN, total, ex) {').replace(/^static /, ''))();
const buildX = loadBuildX().fn;
// download is an arrow property in the page; run it with a stand-in component and a stand-in browser
const downloadSrc = extractMethod(src, 'download', 'download = () => {').replace(/^download = /, '');
const runDownload = new Function('document', 'Blob', 'URL', 'setTimeout', 'return (' + downloadSrc + ')();');

const OPTS = { default: { all: false, maybes: true }, 'maybes off': { all: false, maybes: false }, everything: { all: true, maybes: true } };
const shoot = marks => {            // five clips, marked as given: e.g. 'cc...' = two cut, three undecided
  const key = { k: 'keep', m: 'maybe', c: 'cut' };
  const clips = [...marks].map((ch, i) => ({ id: 'F' + i, name: 'C000' + i + '.MP4', path: 'card/C000' + i + '.MP4', dur: 2, fps: 24, w: 3840, h: 2160, mark: key[ch] }));
  return { clips, marks: Object.fromEntries(clips.filter(c => c.mark).map(c => [c.id, c.mark])) };
};
/** Press the button (or ⌘⏎) on a stand-in page: the files it would have written. */
function press(sh, ex){
  const saved = [], said = [];
  const comp = {
    d: { shoot: { name: 'card', rate: 24 }, clips: sh.clips }, state: { marks: sh.marks, ex: { event: 'card', kw: 'maybe', ...ex } },
    buildX, api(){}, plural: (n, w) => n + ' ' + w + (n === 1 ? '' : 's'), setState(s){ said.push(s); },
  };
  const a = { click(){ saved.push(this.download); }, remove(){} };
  const doc = { createElement: () => a, body: { appendChild(){} } };
  runDownload.call(comp, doc, class { constructor(p){ this.p = p; } }, { createObjectURL: () => 'blob:x', revokeObjectURL(){} }, () => {});
  const markN = { keep: 0, maybe: 0, cut: 0 }; Object.values(sh.marks).forEach(m => markN[m]++);
  return { saved, said, n: buildX.call(comp).n, gate: exGate(markN, sh.clips.length, comp.state.ex) };
}

test('exGate and download come out of the page', () => {
  assert.equal(typeof exGate, 'function');
  assert.match(downloadSrc, /^\(\) => \{/);
});

test('only cut clips, default options: the button is off and nothing is written', () => {
  const r = press(shoot('cc...'), OPTS.default);
  assert.equal(r.gate.n, 0);
  assert.equal(r.gate.label, 'Nothing selected yet');
  assert.deepEqual(r.saved, []);
  assert.deepEqual(r.said, [], 'and nothing claims a file was saved');
});

test('nothing marked at all: off under default and maybes off', () => {
  for (const o of [OPTS.default, OPTS['maybes off']]) {
    const r = press(shoot('.....'), o);
    assert.equal(r.gate.label, 'Nothing selected yet');
    assert.deepEqual(r.saved, []);
  }
});

test('one selected turns it on', () => {
  const r = press(shoot('kcc..'), OPTS.default);
  assert.equal(r.gate.label, 'Download for Final Cut · 1 selected');
  assert.deepEqual(r.saved, ['card.fcpxml']);
});

test('maybes and nothing selected: the label says the file holds maybes, never "0 selected"', () => {
  const on = press(shoot('mmc..'), OPTS.default);
  assert.equal(on.gate.label, 'Download for Final Cut · 2 maybes only');
  assert.deepEqual(on.saved, ['card.fcpxml']);
  assert.equal(press(shoot('mc...'), OPTS.default).gate.label, 'Download for Final Cut · 1 maybe only');
  const off = press(shoot('mmc..'), OPTS['maybes off']);
  assert.equal(off.gate.label, 'Nothing selected yet');
  assert.deepEqual(off.saved, []);
});

test('Everything on with only cut clips: a file is written and the label says every clip', () => {
  const r = press(shoot('cc...'), OPTS.everything);
  assert.equal(r.gate.label, 'Download for Final Cut · 5 clips');
  assert.deepEqual(r.saved, ['card.fcpxml']);
});

test('across every combination the button, the file and buildX agree', () => {
  for (const marks of ['.....', 'cc...', 'ccccc', 'k....', 'kkmcc', 'm....', 'mmmmm', 'kmc..', 'kkkkk'])
    for (const [name, ex] of Object.entries(OPTS)) {
      const r = press(shoot(marks), ex), at = marks + ' / ' + name;
      assert.equal(r.gate.n, r.n, 'the gate counts the clips buildX takes: ' + at);
      assert.equal(r.saved.length, r.n > 0 ? 1 : 0, 'a file only when it would hold a clip: ' + at);
      assert.equal(r.gate.label === 'Nothing selected yet', r.n === 0, at);
      assert.doesNotMatch(r.gate.label, /· 0 /, at);
    }
  assert.equal(press(shoot(''), OPTS.everything).saved.length, 0, 'no clips at all: nothing, even with Everything on');
});
