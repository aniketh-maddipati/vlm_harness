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
      coverDrop: keys => { const o = db(); keys.forEach(k => delete o[k]); save(o); return ask(true); },
      drive: () => ask({name:'T7', total:1e12, free:150e9, purgeable:8e9, readOnly:false, card:false, trash:3.5e9}),
      showTrash: () => { window.__trash = (window.__trash || 0) + 1; return ask(true); },
      trashList: sh => ask(JSON.parse(localStorage.getItem('fake-trash') || '[]')),
      trashMove: (sh, paths) => { window.__moved = paths; const out = paths.map(p => ({rel:p, ok:true, bytes:1e9, why:''})); localStorage.setItem('fake-trash', JSON.stringify(out)); return ask(out); },
      trashPutBack: sh => { const t = JSON.parse(localStorage.getItem('fake-trash') || '[]'); localStorage.setItem('fake-trash', '[]'); return ask(t); }}};
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
    ok(/drive 150\.0 GB free · under 20% free/.test(await line(p)), 'the drive in the line, with the 20 % words: ' + await line(p));
    ok(/Drive · T7\n150\.0 GB free of 1000\.0 GB · 8\.0 GB purgeable/.test(r) && /Under 20% free on T7: 150\.0 GB left\./.test(r), 'the drive row: free, purgeable, the one plain line');
    ok(/Trash on T7\n3\.5 GB waiting/.test(r) && /Skim never empties the Trash/.test(r), 'the Trash row');
    await tap(p, '[data-lumina="storage-trash"]'); ok(await p.evaluate(() => window.__trash) === 1, 'Show in Finder asks the app once');
    ok(/Cut clips on T7\nnone/.test(await rows(p)), 'no cut clips: the row says none');
    // five clips marked cut far from the first one, from the keyboard in Clips (C marks the clip you are on), then back to the first
    await p.keyboard.press('Escape'); await p.waitForTimeout(200);
    // Clips under the level tabs; on the one grid (video/skim-condensed) the clips are already the tiles
    const clipsTab = p.locator('[data-lumina="levels"] [role=tab]').nth(1); if (await clipsTab.count()) { await clipsTab.click(); await p.waitForTimeout(200); } else { await p.click('[data-gi="0"]'); await p.waitForTimeout(200); }
    for (let i = 0; i < 25; i++) await p.keyboard.press('ArrowRight');
    for (let i = 0; i < 5; i++) { await p.keyboard.press('c'); await p.waitForTimeout(50); await p.keyboard.press('ArrowRight'); }
    for (let i = 0; i < 30; i++) await p.keyboard.press('ArrowLeft');
    const sk = await p.evaluate(() => Object.keys(localStorage).find(k => /^lumina-skim:shoot/.test(k)) || '');
    ok(/5 decided/.test(await p.evaluate(() => document.querySelector('[data-lumina="counts"]')?.textContent || '')), 'five clips marked cut: ' + await p.evaluate(() => document.querySelector('[data-lumina="counts"]')?.textContent));
    await p.waitForTimeout(300); await tap(p, '[data-lumina="storage"]'); let r2 = await rows(p);
    ok(/Cut clips on T7\n5 clips · /.test(r2) && /Send to Final Cut first/.test(r2) && await p.evaluate(() => document.querySelector('[data-lumina="storage-trash-move"]').getAttribute('aria-disabled')) === 'true', 'five cut: the move waits for the Final Cut file');
    // the shoot's key: its marks' key where marks are kept, else the shoot the app's store saved last (marks are never stored on video/skim-condensed)
    await p.evaluate(() => {
      let k = Object.keys(localStorage).find(k => /^lumina-skim:/.test(k) && !/clock|sent|^lumina-skimprefs/.test(k));
      if (!k) k = Object.values(JSON.parse(localStorage.getItem('fake-covers') || '{}')).sort((a, b) => b.at - a.at)[0].k;   // the app's store, faked above
      localStorage.setItem('lumina-skim:sent:' + k.replace(/^lumina-skim:/, ''), '1');
    });
    await tap(p, '[data-lumina="storage-scope-day"]'); r2 = await rows(p);
    ok(/Move cut to Trash · 5\.\d MB|Move cut to Trash · \d/.test(r2) && /Drive would have .* free once you empty the Trash/.test(r2), 'after the Final Cut file: the yield and the forecast');
    await tap(p, '[data-lumina="storage-trash-move"]'); ok(/to Trash\? Click again/.test(await rows(p)) && !(await p.evaluate(() => window.__moved)), 'the first click only asks');
    await tap(p, '[data-lumina="storage-trash-move"]'); await p.waitForTimeout(300);
    ok((await p.evaluate(() => (window.__moved || []).length)) === 5 && /Moved 5 clips/.test(await rows(p)) && /Put back · 5 clips/.test(await rows(p)), 'the second click moves five, Put back offered');
    await tap(p, '[data-lumina="storage-trash-back"]'); await p.waitForTimeout(300);
    ok(/Put back 5 clips/.test(await rows(p)), 'Put back returns them');
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
