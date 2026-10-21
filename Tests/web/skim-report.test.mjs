// Save a report (design/handoff/lumina-skim/BETA.md item 5): the text file a tester saves from Open or the app's
// Help ▸ Save a Report… and sends by hand. Read out of the page itself (Component.reportText), with the line on
// Open that offers it. Nothing is sent from the page; the report holds names and numbers, never a folder path.
//
//   node --test Tests/web/skim-report.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PAGE, extractMethod } from './skim-export.mjs';

const src = fs.readFileSync(PAGE, 'utf8');
const reportText = new Function('return function ' + extractMethod(src, 'reportText', 'static reportText(r) {').replace(/^static /, ''))();
const stamp = new Function('return function ' + extractMethod(src, 'stamp', 'static stamp(d, sep) {').replace(/^static /, ''))();
const noteErr = new Function('return function ' + extractMethod(src, 'noteErr', 'noteErr(msg, at) {'))();

const base = {
  at: '2026-10-21 19:40 (2026-10-21T19:40:00.000Z)', build: 'Lumina Skim 1.0.0 (412)', where: 'the Lumina Skim app',
  agent: 'Mozilla/5.0 (Macintosh) AppleWebKit/605.1.15', window: '1440 × 900 at 2×', loads: [], errors: [], shoot: null,
};
const shoot = {
  name: 'Lisbon day 2', clips: 401, size: '113.0 GB', days: 1, selected: 40, maybe: 12, cut: 120, undecided: 229,
  covered: 399, short: 1, skipped: 0,
  failed: [{ name: 'C0248.MP4', why: 'timeout', tries: 2 }, { name: 'C0301.MP4', why: '', tries: 1 }],
};

test('the report comes out of the page', () => {
  for (const f of [reportText, stamp, noteErr]) assert.equal(typeof f, 'function');
});

test('a shoot: build, where it ran, marks in neutral words, clips that did not read', () => {
  const t = reportText({ ...base, shoot, mac: 'heat normal · Lumina 812 MB · 16 GB memory' });
  const lines = t.split('\n');
  assert.equal(lines[0], 'Lumina Skim report');
  assert.match(t, /^Build {7}Lumina Skim 1\.0\.0 \(412\)$/m);
  assert.match(t, /^Running in {2}the Lumina Skim app$/m);
  assert.match(t, /^Mac {9}heat normal · Lumina 812 MB · 16 GB memory$/m);
  assert.match(t, /^Shoot {7}Lisbon day 2 · 401 clips · 113\.0 GB · 1 day$/m);
  assert.match(t, /^Marks {7}40 selected · 12 maybe · 120 cut · 229 undecided$/m);
  assert.match(t, /^Read {8}399 of 401 clips with a cover · 2 didn’t read · 1 cut short · 0 skipped$/m);
  assert.ok(lines.includes('  C0248.MP4  timeout · tried 2 times'));
  assert.ok(lines.includes('  C0301.MP4  unreadable · tried 1 time'));
  assert.doesNotMatch(t, /\bkeep|\bkept/i, 'marks are selected / maybe / cut on anything the user reads');
  assert.ok(t.endsWith('\n'));
});

test('no shoot open, no loads, no errors: it says so', () => {
  const t = reportText(base);
  assert.match(t, /^Shoot {7}none open$/m);
  assert.match(t, /Last loads \(newest first\)\n {2}none\n/);
  assert.match(t, /Errors on this page\n {2}none since the page opened\n/);
  assert.doesNotMatch(t, /^Mac /m, 'no Mac line in a browser');
});

test('loads and errors are listed as kept by the page', () => {
  const loads = [{ name: 'card', n: 401, done: 86000 }];
  const errors = [{ t: '19:33:12', msg: 'TypeError: x is undefined', at: 'Lumina Skim v3.dc.html:4912' }];
  const t = reportText({ ...base, loads, errors });
  assert.ok(t.includes('  {"name":"card","n":401,"done":86000}\n'));
  assert.ok(t.includes('  19:33:12  TypeError: x is undefined (Lumina Skim v3.dc.html:4912)\n'));
});

test('a long list of clips that did not read is cut at 200', () => {
  const failed = Array.from({ length: 230 }, (_, i) => ({ name: 'C' + String(i).padStart(4, '0') + '.MP4', why: 'error', tries: 1 }));
  const t = reportText({ ...base, shoot: { ...shoot, failed } });
  assert.equal(t.split('\n').filter(l => /^ {2}C\d{4}\.MP4/.test(l)).length, 200);
  assert.ok(t.includes('  and 30 more\n'));
});

test('the page keeps the last 50 errors, each cut at 300 characters', () => {
  const ctx = {};
  for (let i = 0; i < 60; i++) noteErr.call(ctx, 'e' + i + 'x'.repeat(400), 'f.js:' + i);
  assert.equal(ctx.errLog.length, 50);
  assert.ok(ctx.errLog[0].msg.startsWith('e10'));
  assert.equal(ctx.errLog[49].msg.length, 300);
  noteErr.call(ctx, undefined, '');
  assert.equal(ctx.errLog[49].msg, '?');
});

test('the file name is a date and a time, no colons', () => {
  assert.equal(stamp(new Date(2026, 9, 21, 9, 5), '.'), '2026-10-21 09.05');
});

test('Open offers it, and the app reaches it', () => {
  assert.match(src, /data-lumina="report-save" onClick="\{\{ reportSave \}\}"[^>]*>Save a report</);
  assert.match(src, /reportSave:this\.reportSave/);
  assert.match(src, /window\.luminaSkimReport = \{text:/);
  // the info the report is built from names clips, never their folders
  const info = extractMethod(src, 'reportInfo');
  assert.doesNotMatch(info, /\.path\b/);
  // nothing in it reaches the network
  assert.doesNotMatch(extractMethod(src, 'reportSave', 'reportSave = () => {'), /fetch\(|XMLHttpRequest|sendBeacon|postMessage/);
});
