// Lumina Ingest's shoots and folder pattern, in headless Chromium with a stand-in for the Mac side: shoots
// proposed from gaps, split here / merge with next and their undo, a shoot named, the pattern set and kept,
// the exact folders listed before the copy, and the copy sending those same folders. Synthetic PNGs dated by
// their file time (the page dates a file without EXIF that way).
//
//   node Tests/web/ingest-shoots.mjs        (INGEST_SHOT=<file.png> also saves the page with the folders listed)
import fs from 'fs';
import os from 'os';
import path from 'path';
import { pw, deadline, ROOT } from './lib.mjs';

deadline('ingest-shoots', 120);
const DIR = path.join(ROOT, 'design/handoff/lumina-ingest'), CORE = path.join(ROOT, 'design/handoff/lumina-cull/lumina-core-v4.js');
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'lumina-ingest-shoots-'));
process.on('exit', () => fs.rmSync(TMP, { recursive: true, force: true }));
let fails = 0; const check = (ok, what) => { console.log((ok ? '   ok   ' : '   FAIL ') + what); if (!ok) fails++; };

// A trip of two days (Oct 28 and 29), then another afternoon five days later.
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==', 'base64');
const trip = path.join(TMP, 'Trip'); fs.mkdirSync(trip);
let n = 0;
const shoot = (y, mo, d, h, count) => { for (let i = 0; i < count; i++) { const f = path.join(trip, `IMG_${String(++n).padStart(4, '0')}.PNG`); fs.writeFileSync(f, Buffer.concat([PNG, Buffer.from('#' + n)])); const t = new Date(y, mo - 1, d, h, i * 10); fs.utimesSync(f, t, t); } };
shoot(2026, 10, 28, 9, 5); shoot(2026, 10, 29, 8, 4); shoot(2026, 11, 3, 14, 3);
fs.writeFileSync(path.join(trip, 'notes.txt'), 'x');

const browser = await pw.chromium.launch();
async function open(pattern) {
  const page = await browser.newPage({ viewport: { width: 1280, height: 860 } });
  page.errs = []; page.on('pageerror', (e) => page.errs.push(e.message));
  await page.route('http://ingest.test/**', (r) => {
    const f = decodeURIComponent(new URL(r.request().url()).pathname.slice(1));
    const p = f === 'lumina-core-v4.js' ? CORE : path.join(DIR, f);
    if (!fs.existsSync(p)) return r.fulfill({ status: 404 });
    r.fulfill({ body: fs.readFileSync(p), contentType: p.endsWith('.js') ? 'text/javascript' : 'text/html' });
  });
  await page.addInitScript((pattern) => {
    window.__asked = [];
    window.webkit = { messageHandlers: { lumina: { postMessage: async (m) => {
      window.__asked.push(m);
      if (m.op === 'ingestLibrary') return { folder: 'Library', count: 0, keys: [], pattern };
      if (m.op === 'ingestSources') return [];
      if (m.op === 'ingestSetPattern') return { pattern: m.pattern || null };
      if (m.op === 'ingestCopy') return { queued: m.items.length, unresolved: 0, folder: 'Library' };
      return null;
    } } } };
  }, pattern);
  await page.goto('http://ingest.test/' + encodeURIComponent('Lumina Ingest v1.html'));
  await page.setInputFiles('#pick', trip);
  await page.waitForFunction(() => { const s = window.__ingest.state(); return s.total === 12 && s.done >= s.total; }, null, { timeout: 60000 });
  await page.waitForFunction(() => window.__ingest.days().length === 3);   // the first draw (the page draws at most twice a second while it reads)
  return page;
}
const shape = (page) => page.evaluate(() => window.__ingest.shoots().map((s) => s.parts));
const asked = (page, op) => page.evaluate((o) => window.__asked.filter((m) => m.op === o), op);
const J = JSON.stringify;

console.log('== no pattern: shoots are proposed, plain dated folders, the copy starts at once');
let page = await open(null);
check(J(await shape(page)) === '[[5,4],[3]]', 'two shoots: the trip holding its two days, and the later afternoon ' + J(await shape(page)));
let heads = await page.evaluate(() => ({ blocks: document.querySelectorAll('.head.blk').length, rows: window.__ingest.days(), names: [...document.querySelectorAll('.head.blk .nm')].map((e) => e.placeholder) }));
check(heads.blocks === 2 && heads.rows.length === 3, `two shoot headings over three day rows: ${heads.rows.join(' | ')}`);
check(J(heads.names) === J(['Oct 28 – 29, 2026', 'Nov 3, 2026']), 'each shoot is drafted a name from its dates: ' + heads.names.join(' | '));
let sent = (await asked(page, 'ingestCopy'))[0];
check(sent && J([...new Set(sent.items.map((i) => i.folder))].sort()) === J(['2026-10-28', '2026-10-29', '2026-11-03', 'Other/Trip']), 'copied at once into the plain dated folders, the text file into Other');
check(!(await page.evaluate(() => window.__ingest.state().held)), 'nothing waits');

console.log('== split here, merge with next, undo');
await page.hover('.row:has([data-cut])'); await page.click('[data-cut]');
await page.waitForFunction(() => window.__ingest.shoots().length === 3);
check(J(await shape(page)) === '[[5],[4],[3]]', 'split here: day 2 starts its own shoot');
await page.waitForSelector('[data-uncut]');
check(await page.evaluate(() => document.querySelectorAll('[data-uncut]').length) === 1, 'the new shoot offers undo split');
await page.click('[data-uncut]');
await page.waitForFunction(() => window.__ingest.shoots().length === 2);
check(J(await shape(page)) === '[[5,4],[3]]', 'undo split: as proposed');
await page.hover('.head.blk'); await page.click('[data-join]');
await page.waitForFunction(() => window.__ingest.shoots().length === 1);
check(J(await shape(page)) === '[[5,4,3]]', 'merge with next: one shoot');
await page.waitForFunction(() => document.querySelectorAll('.head.blk').length === 0, null, { timeout: 3000 }).catch(() => {});
check(await page.evaluate(() => document.querySelectorAll('.head.blk').length) === 0, 'one shoot alone has no heading of its own (the top bar names it)');
await page.evaluate(() => { window.__ingest.shoots(); });
// one shoot shows no heading, so the merge is undone from the split that is offered where it was made
await page.hover('.row:has([data-cut])');
const cuts = await page.evaluate(() => [...document.querySelectorAll('[data-cut]')].length);
check(cuts === 2, 'each later part offers split here');
await page.evaluate(() => [...document.querySelectorAll('[data-cut]')].pop().click());
await page.waitForFunction(() => window.__ingest.shoots().length === 2);
check(J(await shape(page)) === '[[5,4],[3]]', 'split at the merged place: two shoots again');
check(!page.errs.length, 'no page errors ' + page.errs.join('; '));
await page.close();

console.log('== a pattern kept with the library: the copy waits, the folders are listed, then copied as listed');
page = await open('{year}/{start} {shoot}/{kind}');
check(await page.evaluate(() => window.__ingest.state().held) && !(await asked(page, 'ingestCopy')).length, 'the copy waits for the go');
check(/I\s*copy/.test(await page.evaluate(() => document.querySelector('#keys').innerText)), 'the key bar offers I');
await page.fill('.head.blk .nm', 'Death Valley'); await page.keyboard.press('Enter');
await page.waitForFunction(() => window.__ingest.shoots()[0].name === 'Death Valley');
let listed = await page.evaluate(() => window.__ingest.folders());
check(J(listed) === J([['2026/2026-10-28 Death Valley/Photos', 9], ['2026/2026-11-03 Nov 3, 2026/Photos', 3], ['Other/Trip', 1]]), 'the folders, with the name typed: ' + listed.map(([f, c]) => `${f} (${c})`).join(', '));
let notes = await page.evaluate(() => document.querySelector('#notes').innerText);
check(/Goes into 2026\/2026-10-28 Death Valley\/Photos \(9\), 2026\/2026-11-03 Nov 3, 2026\/Photos \(3\), Other\/Trip \(1\)/.test(notes), 'Details lists exactly those');
check(/Copy 13 into 3 folders/.test(await page.evaluate(() => document.querySelector('#foot').innerText)), 'the foot says how many into how many folders');
if (process.env.INGEST_SHOT) await page.screenshot({ path: process.env.INGEST_SHOT });

// the pattern changed by hand: tokens, a wrong one refused, Enter keeps it
await page.click('#patEdit');
await page.fill('#pat', '{year}/{nope}');
check(/not a token: \{nope\}/.test(await page.evaluate(() => document.querySelector('#patEg').textContent)), 'a wrong token is named');
await page.keyboard.press('Enter');
check(!(await asked(page, 'ingestSetPattern')).length, 'and not kept');
await page.fill('#pat', '{shoot}/{date}');
check(/→ Death Valley\/2026-10-28/.test(await page.evaluate(() => document.querySelector('#patEg').textContent)), 'a pattern shows the folder it makes as it is typed');
await page.keyboard.press('Enter');
await page.waitForFunction(() => window.__asked.some((m) => m.op === 'ingestSetPattern'));
check((await asked(page, 'ingestSetPattern'))[0].pattern === '{shoot}/{date}', 'Enter keeps it with the library');
listed = await page.evaluate(() => window.__ingest.folders());
check(J(listed.map((f) => f[0])) === J(['Death Valley/2026-10-28', 'Death Valley/2026-10-29', 'Nov 3, 2026/2026-11-03', 'Other/Trip']), 'the list follows: ' + listed.map((f) => f[0]).join(', '));
await page.keyboard.press('i');
await page.waitForFunction(() => window.__asked.some((m) => m.op === 'ingestCopy'));
sent = (await asked(page, 'ingestCopy'))[0];
const by = {}; for (const i of sent.items) by[i.folder] = (by[i.folder] || 0) + 1;
check(J(Object.entries(by).sort((a, b) => a[0].localeCompare(b[0]))) === J(listed), 'I copies into exactly the folders that were listed');
check(!(await page.evaluate(() => window.__ingest.state().held)), 'nothing waits any more');
// a changed pattern is for new imports only: what was sent is not sent again
await page.evaluate(() => window.__ingest.setPattern('{year}/{kind}'));
await page.waitForTimeout(200);
check((await asked(page, 'ingestCopy')).length === 1 && (await page.evaluate(() => window.__ingest.folders())).length === 0, 'a pattern changed afterwards moves nothing that was copied');
check(!page.errs.length, 'no page errors ' + page.errs.join('; '));

await browser.close();
console.log(fails ? `\nFAIL  ${fails} failed` : '\nPASS  ingest-shoots');
process.exit(fails ? 1 : 0);
