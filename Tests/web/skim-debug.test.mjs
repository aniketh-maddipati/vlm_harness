// What a creator sees by default and what waits behind the developer switch, read out of the page itself:
// debug-mode detection (Component.isDebug), the footer's cut line (Component.cutLine), the Pause / Go on
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
const countsLine = stat('countsLine', 'static countsLine(decided, und, vw) {');
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

test('Pause goes to paused from any pace, Go on goes back to auto', () => {
  assert.equal(nextPace('auto'), 'paused');
  assert.equal(nextPace('eased'), 'paused');
  assert.equal(nextPace('slow'), 'paused');
  assert.equal(nextPace('paused'), 'auto');
});

test('the old wording is gone and the footer and the Viewer use the same line', () => {
  assert.ok(!/cut so far/.test(src));
  assert.equal(template.split('{{ cutSoFar }}').length - 1, 2);
  assert.match(template, /data-lumina="footer-cut"[^>]*>\{\{ cutSoFar \}\}/);
  assert.match(template, /data-lumina="viewer-cut"[^>]*>\{\{ cutSoFar \}\}/);
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
  for (const k of ['closeGo:', 'closeTip:', 'forgetOn:', 'pauseOn:']) {
    const line = src.split('\n').find(l => l.includes('      ' + k)); assert.ok(line, k);
    const words = (line.match(/'[^']*'/g) || []).join(' ');
    assert.ok(words.length > 10 && !/\b(keep|kept|reject|flag)/i.test(words), k + ' ' + words);
  }
});

test('in a narrow window the footer\'s two lines say less, so neither is cut', () => {
  assert.equal(cutLine(3, 4_200_000_000, fmtB, 1440), 'cut: 3 clips · 4.2 GB you can free');
  assert.equal(cutLine(3, 4_200_000_000, fmtB, 720), 'cut: 4.2 GB', 'under 800 the size alone: the cut mark beside it has the number');
  assert.equal(cutLine(3, 4_200_000_000, fmtB, 800), 'cut: 3 clips · 4.2 GB');
  assert.equal(cutLine(3, 4_200_000_000, fmtB, 1024), 'cut: 3 clips · 4.2 GB', 'the storage line sits beside it under 1280');
  assert.equal(cutLine(3, 4_200_000_000, fmtB, 1280), 'cut: 3 clips · 4.2 GB you can free');
  assert.equal(cutLine(0, 0, fmtB, 720), 'cut: none yet');
  assert.equal(countsLine(4, 32, 1440), '4 decided · 32 undecided · 0 automatic');
  assert.equal(countsLine(4, 32, undefined), '4 decided · 32 undecided · 0 automatic');
  assert.equal(countsLine(4, 32, 720), '4 decided · 32 undecided');
  // and what is left shortens with … instead of being cut by the edge
  assert.match(src, /data-lumina="counts" style="[^"]*min-width:0;overflow:hidden;text-overflow:ellipsis/);
  assert.match(src, /data-lumina="footer-cut" style="[^"]*min-width:0;overflow:hidden;text-overflow:ellipsis/);
});

test('a key hint that does not fit is left out whole, never cut mid-word', () => {
  // the hints wrap onto a second line that the 30 px bar does not show
  const bar = /<div data-lumina="hints" style="([^"]*)">/.exec(src);
  assert.ok(bar, 'the hints row is in the key bar');
  for (const rule of ['height:30px', 'flex-wrap:wrap', 'align-content:flex-start', 'overflow:hidden']) assert.ok(bar[1].includes(rule), rule);
  assert.match(src, /<span data-lumina="where" style="flex:none;height:30px;/);
  assert.match(src, /<sc-for list="\{\{ hints \}\}" as="hk"[^>]*>\s*<span style="flex:none;height:30px;display:flex;align-items:center;gap:6px">/);
});

test('the footer\'s storage line gives way before the cut line, and never runs over the marks', () => {
  const storeShort = stat('storeShort', 'static storeShort(line, vw) {');
  const line = 'storage · in memory 180 MB of 403 MB';
  assert.equal(storeShort(line, 1440), line); assert.equal(storeShort(line, undefined), line); assert.equal(storeShort(line, 1280), line);
  assert.equal(storeShort(line, 1180), 'in memory 180 MB of 403 MB');
  assert.equal(storeShort(line, 1024), 'storage'); assert.equal(storeShort(line, 720), 'storage');
  // the full line can shrink (four times as readily as the cut line) and shortens with … inside its own button;
  // the one word under 1100 px keeps its width
  assert.match(src, /<div style="position:relative;flex:\{\{ storeFlex \}\};min-width:0">\s*<button type="button" data-lumina="storage"/);   // a real button here (LOCAL-CHANGES 180)
  assert.match(src, /vals\.storeFlex = st\.vw < 1100 \? 'none' : '0 4 auto'/);
  assert.match(src, /storeFlex:'0 4 auto'/);
  // the line's colours are set, not left in a comment after storeFlex
  assert.match(src, /vals\.storeFlex = st\.vw < 1100 \? 'none' : '0 4 auto'; vals\.storeFg = /);
  assert.match(src, /data-lumina="storage"[^>]*min-width:0;max-width:100%;box-sizing:border-box;overflow:hidden"[^>]*><span style="min-width:0;overflow:hidden;text-overflow:ellipsis">\{\{ storeLine \}\}<\/span>/);
  assert.match(src, /<div style="flex:0 1 auto;min-width:0;display:flex;justify-content:flex-end;gap:14px;overflow:hidden"><span data-lumina="footer-cut"/);
});

test('an empty label beside the cut line takes no room', () => {
  assert.match(src, /\{\{ cutSoFar \}\}<\/span><sc-if value="\{\{ freeOn \}\}"[^>]*><span style="color:#9A958D">\{\{ freeTxt \}\}<\/span><\/sc-if>/);
  assert.match(src, /vals\.freeOn = !!vals\.freeTxt;/);
});
