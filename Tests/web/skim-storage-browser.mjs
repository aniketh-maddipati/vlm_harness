// The storage line in a real browser (STORAGE.md steps 1 and 2): the web preview build in headless Chromium,
// over clips made here with ffmpeg (VP9 in .MP4, which Chromium plays). Bounded (LUMINA_WEB_LIMIT, 240 s).
//   1. Drop frames gives back what it said and Esc closes the rows.
//   2. Saved covers: a reopen reads nothing; Clear for shoots not open and Re-measure bring the full read back.
//   3. A full quota (IndexedDB puts refused) says so in the row and the shoot still reads.
//   4. The Mac app's way (a stand-in for the skimCover* bridge ops, kept in localStorage): a reopen reads nothing.
//
//   node Tests/web/skim-storage-browser.mjs        # needs ffmpeg and Playwright's Chromium
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { pw, ROOT, deadline } from './lib.mjs';

deadline('skim-storage-browser', 240);
const T = fs.mkdtempSync(path.join(os.tmpdir(), 'skim-storage-')), page = path.join(T, 'preview.html');
execFileSync('python3', [path.join(ROOT, 'Scripts/build-skim-preview.py'), page], {stdio:'ignore'});
const clips = (dir, n, src) => { fs.mkdirSync(dir, {recursive:true}); for (let i = 1; i <= n; i++) execFileSync('ffmpeg', ['-loglevel', 'error', '-y', '-f', 'lavfi', '-i', src + '=size=640x360:rate=24:duration=2', '-vf', 'hue=h=' + i * 11, '-c:v', 'libvpx-vp9', '-b:v', '200k', '-deadline', 'realtime', '-cpu-used', '8', path.join(dir, 'C' + String(i).padStart(4, '0') + '.MP4')]); };
clips(path.join(T, 'shoot'), 30, 'testsrc2'); clips(path.join(T, 'other'), 6, 'testsrc');

let fails = 0; const ok = (c, what) => { console.log((c ? 'ok    ' : 'FAIL  ') + what); if (!c) fails++; };
async function run(quota, host) {
  const b = await pw.chromium.launch({executablePath:process.env.CHROMIUM || undefined}), ctx = await b.newContext({viewport:{width:1440, height:900}}), errs = [];
  // videos the page makes (its readers): what "reads nothing" counts
  await ctx.addInitScript(() => { window.__vids = 0; const ce = Document.prototype.createElement; Document.prototype.createElement = function (t, o) { if (String(t).toLowerCase() === 'video') window.__vids++; return ce.call(this, t, o); }; });
  if (host) await ctx.addInitScript(() => {
    const db = () => JSON.parse(localStorage.getItem('fake-covers') || '{}'), save = o => localStorage.setItem('fake-covers', JSON.stringify(o)), ask = v => new Promise(r => setTimeout(() => r(v), 5));
    window.lumina = {video:{
      coverGet: keys => { const o = db(), out = {}; for (const s of Object.values(o)) for (const k of keys) if (s.recs[k]) out[k] = s.recs[k]; return ask(out); },
      coverPut: (sh, recs) => { const o = db(), s = o[sh.k] || {k:sh.k, name:sh.name, at:0, recs:{}}; s.at = Date.now(); recs.forEach(r => s.recs[r.k] = {meta:r.meta, cover:r.cover}); o[sh.k] = s; save(o); return ask('saved'); },
      coverTouch: sh => { const o = db(); o[sh.k] = o[sh.k] || {k:sh.k, name:sh.name, recs:{}}; o[sh.k].at = Date.now(); save(o); return ask(true); },
      coverStat: () => { const o = db(); let bytes = 0; const shoots = Object.values(o).map(s => { const b = Object.values(s.recs).reduce((a, r) => a + r.cover.length * 0.75 + r.meta.length, 0); bytes += b; return {k:s.k, name:s.name, at:s.at, bytes:b, n:Object.keys(s.recs).length}; }); return ask({bytes, shoots}); },
      coverDrop: keys => { const o = db(); keys.forEach(k => delete o[k]); save(o); return ask(true); }}};
  });
  if (quota) await ctx.addInitScript(() => { const put = IDBObjectStore.prototype.put; IDBObjectStore.prototype.put = function (v, k) { if (this.name === 'clip') throw new DOMException('full', 'QuotaExceededError'); return put.call(this, v, k); }; });
  const open = async dir => {
    const p = await ctx.newPage(); p.on('pageerror', e => errs.push(String(e)));
    await p.goto('file://' + page); await p.waitForTimeout(1000); const base = await p.evaluate(() => window.__vids);
    await p.setInputFiles('input[type=file]', dir);
    for (let k = 0; k < 120; k++) { await p.waitForTimeout(500); if (await p.evaluate(() => { try { const a = JSON.parse(localStorage.getItem('lumina-skim:clock') || '[]')[0]; return !!(a && a.done != null); } catch (x) { return false; } })) break; }
    const read = await p.evaluate(() => window.__vids) - base; await p.waitForTimeout(2200); return {p, read};
  };
  const rows = p => p.evaluate(() => document.querySelector('[data-lumina="storage-rows"]')?.innerText || '');
  const line = p => p.evaluate(() => document.querySelector('[data-lumina="storage"]')?.textContent || '');
  const tap = async (p, sel) => { await p.click(sel); await p.waitForTimeout(700); };

  let {p, read} = await open(path.join(T, 'shoot'));
  if (host) {
    const first = read; await p.close(); ({p, read} = await open(path.join(T, 'shoot')));
    ok(first >= 30 && read <= first - 30, 'through the app\'s store, a reopen reads nothing: ' + first + ' videos the first time, ' + read + ' again');
    await tap(p, '[data-lumina="storage"]'); const r = await rows(p);
    ok(/30 of 30 clips opened from saved covers/.test(r) && !/Kept until Lumina quits/.test(r), 'the row says where they came from, and nothing about a quit');
  } else if (!quota) {
    ok(/^storage · in memory \d+ MB of \d+ MB/.test(await line(p)), 'the line outside debug mode: ' + await line(p));
    await tap(p, '[data-lumina="storage"]'); ok(/Frames in memory/.test(await rows(p)), 'a click opens the rows');
    await p.keyboard.press('Escape'); await p.waitForTimeout(150); ok(!(await rows(p)), 'Esc closes them');
    const first = read; await p.close(); ({p, read} = await open(path.join(T, 'shoot')));
    ok(first >= 30 && read <= first - 30, 'a reopen reads nothing: ' + first + ' videos the first time, ' + read + ' again');
    await tap(p, '[data-lumina="storage"]'); ok(/30 of 30 clips opened from saved covers/.test(await rows(p)), 'the row says the covers came from saved');
    await p.close(); ({p, read} = await open(path.join(T, 'other')));
    await tap(p, '[data-lumina="storage"]'); ok(/· 2 shoots/.test(await rows(p)) && /Clear for shoots not open · \d+ MB/.test(await rows(p)), 'two shoots held, the clear says what it frees');
    await tap(p, '[data-lumina="storage-clear"]'); ok(/Cleared \d+ MB from 1 shoot/.test(await rows(p)) && /· 1 shoot/.test(await rows(p)), 'cleared, and the row follows');
    await p.close(); ({p, read} = await open(path.join(T, 'shoot')));
    ok(read >= 30, 'after the clear the full read comes back: ' + read + ' videos');
    await tap(p, '[data-lumina="storage"]'); const v0 = await p.evaluate(() => window.__vids);
    await tap(p, '[data-lumina="storage-remeasure"]'); await p.waitForTimeout(6000);
    ok(await p.evaluate(() => window.__vids) - v0 >= 30, 'Re-measure this shoot reads it again');
  } else {
    await tap(p, '[data-lumina="storage"]');
    ok(/Storage here is full, so covers are not being saved now/.test(await rows(p)), 'a full quota says so');
    ok(read >= 30 && /in memory/.test(await line(p)), 'and the shoot still reads: ' + read + ' videos');
  }
  ok(!errs.length, 'no page errors' + (errs.length ? ': ' + errs.slice(0, 3).join(' | ') : ''));
  await b.close();
}
await run(false); await run(true); await run(false, true);
fs.rmSync(T, {recursive:true, force:true});
console.log(fails ? fails + ' failed' : 'all passed'); process.exit(fails ? 1 : 0);
