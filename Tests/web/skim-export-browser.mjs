// Export in a real browser: the web preview build in headless Chromium over clips made here with ffmpeg, as the
// browser runs it and as the Mac app runs it (a stand-in for the skimExport* and skimTrash* bridge ops).
// Bounded (LUMINA_WEB_LIMIT, 240 s). Screenshots go to SKIM_SHOTS when it is set.
//   1. The browser: Save to names its download folder, the plan line says what ⌘⏎ does, the result says it was done.
//   2. The app: Save to shows the folder, the switches change the file, ⌘⏎ saves, opens in Final Cut, moves the cut
//      clips and clears working memory, each said in the result; Put back and Show in Finder answer from there.
//
//   node Tests/web/skim-export-browser.mjs        # needs ffmpeg and Playwright's Chromium
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { pw, ROOT, deadline } from './lib.mjs';

deadline('skim-export-browser', 240);
const T = fs.mkdtempSync(path.join(os.tmpdir(), 'skim-export-')), page = path.join(T, 'preview.html'), shots = process.env.SKIM_SHOTS;
execFileSync('python3', [path.join(ROOT, 'Scripts/build-skim-preview.py'), page], {stdio:'ignore'});
const dir = path.join(T, 'dump'); fs.mkdirSync(dir, {recursive:true});
for (let i = 1; i <= 8; i++) execFileSync('ffmpeg', ['-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24:duration=2', '-vf', 'hue=h=' + i * 31, '-c:v', 'libvpx-vp9', '-b:v', '200k', '-deadline', 'realtime', '-cpu-used', '8', path.join(dir, 'C' + String(i).padStart(4, '0') + '.MP4')]);

let fails = 0; const ok = (c, what) => { console.log((c ? 'ok    ' : 'FAIL  ') + what); if (!c) fails++; };
async function run(host) {
  const b = await pw.chromium.launch({executablePath:process.env.CHROMIUM || undefined}), ctx = await b.newContext({viewport:{width:1440, height:1000}}), errs = [];
  if (host) await ctx.addInitScript(() => {
    const ask = v => new Promise(r => setTimeout(() => r(v), 5)); window.__calls = [];
    let place = {ask:true, finalCut:true, clips:'/Users/sam/Desktop/dump'};
    window.lumina = {video:{
      exportPlace: () => ask(place),
      exportChoose: () => { place = {...place, ask:false, path:'/Users/sam/Movies/Exports', name:'Exports'}; return ask(place); },
      exportAsk: () => { place = {ask:true, finalCut:true, clips:place.clips}; return ask(place); },
      exportSave: (name, text) => { window.__calls.push(['save', name, text]); return ask({ok:true, path:'/Users/sam/Movies/Exports/' + name, name, folder:'/Users/sam/Movies/Exports'}); },
      exportCheck: text => { window.__calls.push(['check']); const m = [...text.matchAll(/src="file:\/\/([^"]+)"/g)].map(x => decodeURIComponent(x[1])); return ask({dtd:'ok', errors:[], unchecked:0, missing:m.filter(p => /C0002/.test(p))}); },
      exportReveal: p => { window.__calls.push(['reveal', p]); return ask(true); },
      openInFinalCut: p => { window.__calls.push(['fcp', p]); return ask({ok:true, app:'Final Cut Pro'}); },
      drive: () => ask({name:'T7', total:1e12, free:150e9, readOnly:false, card:false, trash:0}),
      trashList: () => ask(JSON.parse(localStorage.getItem('fake-trash') || '[]')),
      trashMove: (sh, paths) => { window.__calls.push(['trash', paths]); const out = paths.map(p => ({rel:p, ok:true, bytes:1e9, why:''})); localStorage.setItem('fake-trash', JSON.stringify(out)); return ask(out); },
      trashPutBack: () => { const t = JSON.parse(localStorage.getItem('fake-trash') || '[]'); localStorage.setItem('fake-trash', '[]'); window.__calls.push(['putback', t.length]); return ask(t); }}};
  });
  const p = await ctx.newPage(); p.on('pageerror', e => errs.push(String(e)));
  await p.goto('file://' + page); await p.waitForTimeout(1000);
  await p.setInputFiles('input[type=file]', dir);
  for (let k = 0; k < 60; k++) { await p.waitForTimeout(500); if (await p.evaluate(() => { try { const a = JSON.parse(localStorage.getItem('lumina-skim:clock') || '[]')[0]; return !!(a && a.done != null); } catch (x) { return false; } })) break; }
  // mark through the page's own keys: two selected, one maybe, two cut
  const clipsTab = p.locator('[data-lumina="levels"] [role=tab]').nth(1); if (await clipsTab.count()) { await clipsTab.click(); await p.waitForTimeout(200); } else { await p.click('[data-gi="0"]'); await p.waitForTimeout(200); }
  for (const k of ['k', 'ArrowRight', 'k', 'ArrowRight', 'm', 'ArrowRight', 'ArrowRight', 'c', 'ArrowRight', 'c']) { await p.keyboard.press(k); await p.waitForTimeout(80); }
  await p.keyboard.press('Meta+Enter'); await p.waitForTimeout(900);
  const text = sel => p.evaluate(s => document.querySelector(s)?.innerText || '', sel);
  ok(await p.$('[data-lumina="export-plan"]'), (host ? 'app' : 'browser') + ': the Export controls are there');
  if (shots) await p.screenshot({path:path.join(shots, (host ? 'app' : 'browser') + '-export.png'), fullPage:true});
  if (!host) {
    ok(/Your browser’s download folder/.test(await text('[data-lumina="export-dest"]')), 'browser: Save to names the download folder');
    ok(/^⌘⏎ downloads .+\.fcpxml\.$/.test(await text('[data-lumina="export-then"]')), 'browser: the plan line: ' + await text('[data-lumina="export-then"]'));
    await p.click('[data-lumina="ex-mem"]'); await p.waitForTimeout(200);
    ok(/clears .+ of working memory/.test(await text('[data-lumina="export-then"]')) || /down to the covers|Nothing is held/.test(await text('[data-lumina="export-after"]')), 'browser: Clear working memory joins the plan');
    await p.click('[data-lumina="download"]'); await p.waitForTimeout(600);
    const r = await text('[data-lumina="export-result"]');
    ok(/Downloaded .+\.fcpxml · 3 clips/.test(r) && /working memory/.test(r), 'browser: the result says what was done: ' + r.replace(/\n/g, ' | '));
    ok(await p.$('[data-lumina="export-close"]'), 'browser: Close this shoot is offered');
    if (shots) { await p.evaluate(() => { const e = document.querySelector('[data-screen-label="Export"]'); if (e) e.scrollTop = 0; }); await p.screenshot({path:path.join(shots, 'browser-done.png')}); }
  } else {
    ok(/Asks each time/.test(await text('[data-lumina="export-dest"]')), 'app: Save to starts on asking each time');
    await p.click('[data-lumina="dest-choose"]'); await p.waitForTimeout(300);
    ok(/~\/Movies\/Exports/.test(await text('[data-lumina="export-dest"]')) && await p.$('[data-lumina="dest-ask"]'), 'app: a folder chosen shows, with Ask each time');
    for (const id of ['ex-scenes', 'ex-openfc', 'ex-trash', 'ex-mem']) await p.click('[data-lumina="' + id + '"]'), await p.waitForTimeout(150);
    await p.waitForTimeout(600);
    ok(/missing on disk: C0002/.test(await text('[data-lumina="sum-verify"]')), 'app: the background check flags the missing clip file before saving: ' + await text('[data-lumina="sum-verify"]'));
    const plan = await text('[data-lumina="export-then"]');
    ok(/saves .+\.fcpxml to ~\/Movies\/Exports, opens it in Final Cut, moves 2 cut clips .+ to the Trash and clears .+ of working memory\./.test(plan) || /saves .+ to ~\/Movies\/Exports, opens it in Final Cut and moves 2 cut clips/.test(plan), 'app: the plan line: ' + plan);
    if (shots) await p.screenshot({path:path.join(shots, 'app-export-on.png'), fullPage:true});
    await p.keyboard.press('Meta+Enter'); await p.waitForTimeout(900);
    const calls = await p.evaluate(() => window.__calls), r = await text('[data-lumina="export-result"]');
    const saved = calls.find(c => c[0] === 'save');
    ok(saved && /<keyword [^>]*value="[^"]*Scene 1/.test(saved[2]) && /file:\/\/\/Users\/sam\/Desktop\/dump\//.test(saved[2]), 'app: the file has scene keywords and points at the folder the app read');
    ok(calls.map(c => c[0]).filter(c => c !== 'check').join(' ') === 'save fcp trash', 'app: save, then Final Cut, then the Trash: ' + calls.map(c => c[0]).join(' '));
    ok(/clip file missing on disk: C0002\.MP4/.test(r) && /missing on disk/.test(await text('[data-lumina="sum-verify"]')), 'app: a missing clip file is flagged in the result and the summary');
    ok(/Saved .+ in ~\/Movies\/Exports/.test(r) && /Opened in Final Cut Pro/.test(r) && /Moved 2 cut clips/.test(r) && /working memory/.test(r), 'app: the result: ' + r.replace(/\n/g, ' | '));
    if (shots) { await p.evaluate(() => { const e = document.querySelector('[data-screen-label="Export"]'); if (e) e.scrollTop = 0; }); await p.screenshot({path:path.join(shots, 'app-done.png')}); }
    await p.click('[data-lumina="export-reveal"]'); await p.click('[data-lumina="export-putback"]'); await p.waitForTimeout(400);
    const c2 = await p.evaluate(() => window.__calls.map(c => c[0]).join(' '));
    ok(/reveal/.test(c2) && /putback/.test(c2) && /Put back 2 clips/.test(await text('[data-lumina="export-result"]')), 'app: Show in Finder and Put back answer from the result');
  }
  ok(!errs.length, 'no page errors' + (errs.length ? ': ' + errs.join(' | ') : ''));
  await b.close();
}
await run(false); await run(true);
fs.rmSync(T, {recursive:true, force:true});
console.log(fails ? fails + ' FAIL' : 'all ok'); process.exit(fails ? 1 : 0);
