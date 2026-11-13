// Lumina Ingest's sources without Finder, in headless Chromium with a stand-in for the Mac side (IngestHost):
// the cards that are in and the usual folders under Drop, the C key, a card going in, Forget these; a folder
// with no photo or clip in it is still copied (nothing is turned away for its kind); what the page says when
// the library goes away or its record can't be written. Synthetic files only.
//
//   node Tests/web/ingest-sources.mjs        (INGEST_SHOT=<file.png> also saves the Open screen)
import fs from 'fs';
import os from 'os';
import path from 'path';
import { pw, deadline, ROOT } from './lib.mjs';

deadline('ingest-sources', 90);
const DIR = path.join(ROOT, 'design/handoff/lumina-ingest'), CORE = path.join(ROOT, 'design/handoff/lumina-cull/lumina-core-v4.js');
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'lumina-ingest-sources-'));
process.on('exit', () => fs.rmSync(TMP, { recursive: true, force: true }));
let fails = 0; const check = (ok, what) => { console.log((ok ? '   ok   ' : '   FAIL ') + what); if (!ok) fails++; };

const browser = await pw.chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
const errs = []; page.on('pageerror', (e) => errs.push(e.message));
await page.route('http://ingest.test/**', (r) => {
  const f = decodeURIComponent(new URL(r.request().url()).pathname.slice(1));
  const p = f === 'lumina-core-v4.js' ? CORE : path.join(DIR, f);
  if (!fs.existsSync(p)) return r.fulfill({ status: 404 });
  r.fulfill({ body: fs.readFileSync(p), contentType: p.endsWith('.js') ? 'text/javascript' : 'text/html' });
});
// The Mac side: what IngestHost answers, and a log of what the page asked.
await page.addInitScript(() => {
  const SRC = [
    { id: 'card:UUID-A', name: 'Untitled', card: true, there: true, read: false },
    { id: 'folder:/trips/dv', name: 'Death Valley', card: false, there: true, read: false },
    { id: 'folder:/Volumes/T7/x', name: 'T7 exports', card: false, there: false, read: false }
  ];
  window.__asked = [];
  window.webkit = { messageHandlers: { lumina: { postMessage: async (m) => {
    window.__asked.push(m);
    if (m.op === 'ingestLibrary') return { folder: 'Library', count: 0, keys: [] };
    if (m.op === 'ingestSources') return SRC;
    if (m.op === 'ingestOpen') return { ok: true };
    if (m.op === 'ingestForgetPlaces') return SRC.filter((s) => s.card);
    if (m.op === 'ingestCopy') return { queued: m.items.length, unresolved: 0, folder: 'Library' };
    return null;
  } } } };
});
await page.goto('http://ingest.test/' + encodeURIComponent('Lumina Ingest v1.html'));
await page.waitForFunction(() => document.querySelector('#places').textContent.includes('Untitled'));
const asked = (op) => page.evaluate((o) => window.__asked.filter((m) => m.op === o), op);
const text = (sel) => page.evaluate((s) => document.querySelector(s).innerText, sel);

console.log('== sources under Drop');
let t = await text('#places');
check(/Card\s+Untitled/.test(t) && /Usual folders\s+Death Valley\s+T7 exports\s+Forget these/.test(t), `the card and the usual folders are listed: "${t.replace(/\s+/g, ' ')}"`);
check(await page.evaluate(() => document.querySelectorAll('#places [data-open]').length) === 2, 'a folder that is not connected is named, not clickable');
check(/C\s*read Untitled/.test(await text('#keys')), 'the key bar offers C for the card');
if (process.env.INGEST_SHOT) await page.screenshot({ path: process.env.INGEST_SHOT });
await page.keyboard.press('c');
await page.waitForFunction(() => window.__asked.some((m) => m.op === 'ingestOpen'));
check((await asked('ingestOpen'))[0].id === 'card:UUID-A', 'C asks the Mac to open the card');
await page.waitForFunction(() => !/read Untitled/.test(document.querySelector('#keys').innerText));
check(true, 'once read, C is no longer offered for it');
await page.click('#places [data-open="folder:/trips/dv"]');
await page.waitForFunction(() => window.__asked.filter((m) => m.op === 'ingestOpen').length === 2);
check((await asked('ingestOpen'))[1].id === 'folder:/trips/dv', 'a usual folder opens with one click');

console.log('== a card goes in');
await page.evaluate(() => window.luminaIngest.sources([{ id: 'card:UUID-B', name: 'A7IV', card: true, there: true, read: false }, { id: 'folder:/trips/dv', name: 'Death Valley', card: false, there: true, read: false }]));
check(/A7IV is in/.test(await text('#say')), 'the page says so');
check(/C\s*read A7IV/.test(await text('#keys')), 'and offers C for it');
await page.click('#places [data-forget]');
await page.waitForFunction(() => !document.querySelector('#places').textContent.includes('Death Valley'));
check((await asked('ingestForgetPlaces')).length === 1, 'Forget these forgets the folders');

console.log('== nothing is turned away for its kind');
const d = path.join(TMP, 'Notes'); fs.mkdirSync(path.join(d, 'sub'), { recursive: true });
fs.writeFileSync(path.join(d, 'shotlist.pdf'), 'pdf'); fs.writeFileSync(path.join(d, 'sub', 'track.gpx'), 'gpx'); fs.writeFileSync(path.join(d, 'lonely.xmp'), '<x/>');
await page.setInputFiles('#pick', d);
await page.waitForFunction(() => window.__asked.some((m) => m.op === 'ingestCopy'));
const sent = (await asked('ingestCopy'))[0].items;
check(sent.length === 3 && sent.every((i) => i.key === '' && i.folder.startsWith('Other/Notes')), `the PDF, the GPX and the sidecar with no photo are sent to be copied: ${sent.map((i) => i.folder + ' ← ' + i.path).join(', ')}`);
check(/No photos or clips there · 3 other files copied as they are/.test(await text('#say')), 'and the page says what happened to them');

console.log('== the library goes away; its record is not written');
await page.evaluate(() => window.luminaIngest.copied({ key: '', src: 'Notes', ok: false, why: 'destination gone', files: 0, bytes: 0 }));
check(/Copy stopped: the library Library can't be reached/.test(await text('#say')), 'a lost library is said once and stays said');
await page.evaluate(() => window.luminaIngest.saveFailed('disk full'));
check(/Library record not saved \(disk full\)/.test(await text('#say')), 'a record that could not be written is said');
check(!errs.length, 'no page errors ' + errs.join('; '));

await browser.close();
console.log(fails ? `\nFAIL  ${fails} failed` : '\nPASS  ingest-sources');
process.exit(fails ? 1 : 0);
