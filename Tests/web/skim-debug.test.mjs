// What a creator sees by default and what waits behind the developer switch, read out of the page itself:
// debug-mode detection (Component.isDebug), the footer's cut line (Component.cutLine), the Pause / Proceed
// step (Component.nextPace), and the page's template and defaults around the Working memory panel.
//
//   node --test Tests/web/skim-debug.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const stat = (name, head) => new Function('return function ' + extractMethod(src, name, head).replace(/^static /, ''))();
const isDebug = stat('isDebug', 'static isDebug(search, hash) {');
const cutLine = stat('cutLine', 'static cutLine(n, bytes, fmtB, vw) {');
const countsLine = stat('countsLine', 'static countsLine(kept, n, vw) {');
const nextPace = stat('nextPace', 'static nextPace(pace) {');
const fmtB = new Function('return function ' + extractMethod(src, 'fmtB', 'fmtB(b) {'))();
const template = src.slice(0, src.indexOf('class Component'));

test('a normal address is not debug mode', () => {
  for (const [q, h] of [['', ''], ['?exact=1', ''], ['?debug=0', ''], ['?debug', ''], ['?debug=10', ''], ['?nodebug=1', ''], ['', '#debugging'], ['', '#clip-debug'], [undefined, undefined]])
    assert.equal(isDebug(q, h), false, JSON.stringify([q, h]));
});

test('?debug=1 or #debug turns debug mode on', () => {
  for (const [q, h] of [['?debug=1', ''], ['?exact=1&debug=1', ''], ['?debug=1&exact=1', ''], ['', '#debug'], ['?exact=1', '#debug'], ['', '#debug=1']])
    assert.equal(isDebug(q, h), true, JSON.stringify([q, h]));
});

test('the cut line reads as space to get back, in the page\'s own sizes', () => {
  assert.equal(cutLine(3, 4_200_000_000, fmtB), 'cut: 3 clips · 4.2 GB you can free');
  assert.equal(cutLine(1, 700_000_000, fmtB), 'cut: 1 clip · 700 MB you can free');
  assert.equal(cutLine(0, 0, fmtB), 'cut: none yet');
});

test('Pause goes to paused from any pace, Proceed goes back to auto', () => {
  assert.equal(nextPace('auto'), 'paused');
  assert.equal(nextPace('eased'), 'paused');
  assert.equal(nextPace('slow'), 'paused');
  assert.equal(nextPace('paused'), 'auto');
});

test('the old wording is gone; the cut line is no longer on screen (Stills\' density, LOCAL-CHANGES 314)', () => {
  assert.ok(!/cut so far/.test(src));
  assert.ok(!template.includes('{{ cutSoFar }}'));
  assert.ok(!template.includes('data-lumina="footer-cut"') && !template.includes('data-lumina="viewer-cut"'));
});

test('the memory pill and its panel sit inside the debug switch', () => {
  const open = template.indexOf('<sc-if value="{{ dbgOn }}"'), pill = template.indexOf('data-lumina="memory-pill"'), panel = template.indexOf('data-lumina="memory"'), bar = template.indexOf('data-lumina="skim-bar"');
  assert.ok(open > 0 && open < pill && pill < panel && panel < bar);
  assert.equal(template.split('{{ dbgOn }}').length - 1, 1);
  // nothing between the switch and the pill closes it
  assert.ok(!template.slice(open, pill).includes('</sc-if>'));
  assert.match(src, /dbgOn:false/);                 // off before the page is ready
  assert.match(src, /memOn:st\.memOn && !!st\.dbg/); // the panel never opens outside debug mode
});

test('Close, Forget marks and Pause are in the page outside the panel', () => {
  const panelAt = template.indexOf('data-lumina="memory-pill"');
  for (const k of ['shoot-close', 'shoot-forget']) { const at = template.indexOf('data-lumina="' + k + '"'); assert.ok(at > 0 && at < panelAt, k); }
  assert.match(template, /data-lumina="read-pause"/);
  assert.match(src, /this\.setState\(\{closeConfirm:true, memConfirm:false\}\)/);
  assert.ok(!/memOn:true, closeConfirm:true/.test(src), 'Close no longer opens the panel to confirm');
});

test('the memory defaults are what they were', () => {
  assert.match(src, /static MEMDEF = \{budget:256, per:8, size:320, pace:'auto'\};/);
});

test('per-load timings are only shown in debug mode and are still recorded', () => {
  // the line reads "listed …, covers and flags …, detail …" since done came to mean covers and first measures (LOCAL-CHANGES 113)
  assert.match(src, /!running && st\.dbg \? ' · listed '/);
  assert.equal(src.split("', covers and flags '").length - 1, 1);
  assert.match(src, /lumina-skim:clock/);
});

test('the trust line is on the Open step and words stay neutral', () => {
  assert.match(src, /'Read only\. Nothing leaves ' \+ this\.devName\(\) \+ '\.'/);   // 'this Mac' on a Mac (skim-mobile.test.mjs)
  assert.match(template, /data-lumina="drop-note"[^>]*>\{\{ dropNote \}\}/);
  for (const k of ['closeOn:', 'closeTip:', 'forgetOn:', 'pauseOn:']) {
    const line = src.split('\n').find(l => l.includes('      ' + k)); assert.ok(line, k);
    const words = (line.match(/'[^']*'/g) || []).join(' ');
    assert.ok(words.length > 10 && !/\b(keep|kept|reject|flag)/i.test(words), k + ' ' + words);
  }
});

test('the bottom line counts what is kept, as Stills does, and says less in a narrow window', () => {
  assert.equal(cutLine(3, 4_200_000_000, fmtB, 1440), 'cut: 3 clips · 4.2 GB you can free');
  assert.equal(cutLine(0, 0, fmtB, 720), 'cut: none yet');
  assert.equal(countsLine(4, 32, 1440), '4 kept of 32 · 0 automatic');
  assert.equal(countsLine(4, 32, undefined), '4 kept of 32 · 0 automatic');
  assert.equal(countsLine(4, 32, 720), '4 kept of 32');
  assert.match(src, /vals\.counts = st\.flash \|\| Component\.countsLine\(markN\.keep, C\.length, st\.vw\);/);
});

test('the key hints are one plain line that shortens with …, as Stills\' bottom row', () => {
  const bar = /<div data-lumina="hints" role="status" aria-live="polite" style="([^"]*)">/.exec(src);
  assert.ok(bar, 'the hints are in the bottom line');
  for (const rule of ['flex:1', 'min-width:0', 'overflow:hidden', 'text-overflow:ellipsis']) assert.ok(bar[1].includes(rule), rule);
  assert.match(src, /vals\.hintText = \(vals\.hints \|\| \[\]\)\.map\(h => h\.k \+ ' ' \+ h\.t\)\.join\(' · '\);/);
  assert.ok(!template.includes('data-lumina="footer"'), 'one line, not a key bar and a footer');
});

test('no storage line outside debug mode: the memory pill and its panel are where it lives', () => {
  assert.ok(template.lastIndexOf('<sc-if value="{{ storeDbgOn }}"', template.indexOf('data-lumina="storage"')) > template.indexOf('data-lumina="counts"'));
  assert.match(template, /data-lumina="memory-pill"/);
});

