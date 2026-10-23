// Save a report in a real browser (design/handoff/lumina-skim/BETA.md item 5): the web preview build in headless
// Chromium. Open offers the line; a click downloads one .txt; it names the build, the shoot, its marks and the
// page's own errors; with the app's host (a stand-in for window.lumina.video) it says it ran in the app.
// Bounded (LUMINA_WEB_LIMIT, 180 s).
//
//   node Tests/web/skim-report-browser.mjs        # needs ffmpeg and Playwright's Chromium
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { pw, ROOT, deadline } from './lib.mjs';

deadline('skim-report-browser', 180);
const T = fs.mkdtempSync(path.join(os.tmpdir(), 'skim-report-')), page = path.join(T, 'preview.html'), dir = path.join(T, 'shoot');
execFileSync('python3', [path.join(ROOT, 'Scripts/build-skim-preview.py'), page], {stdio:'ignore'});
fs.mkdirSync(dir);
for (let i = 1; i <= 4; i++) execFileSync('ffmpeg', ['-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24:duration=2', '-c:v', 'libvpx-vp9', '-b:v', '200k', '-deadline', 'realtime', '-cpu-used', '8', path.join(dir, 'C' + String(i).padStart(4, '0') + '.MP4')]);

let fails = 0; const ok = (c, what) => { console.log((c ? 'ok    ' : 'FAIL  ') + what); if (!c) fails++; };
const b = await pw.chromium.launch({executablePath:process.env.CHROMIUM || undefined});
async function save(p) {
  const [dl] = await Promise.all([p.waitForEvent('download', {timeout:10000}), p.click('[data-lumina="report-save"]')]);
  const to = path.join(T, dl.suggestedFilename()); await dl.saveAs(to); await p.waitForTimeout(200);
  return {name:dl.suggestedFilename(), text:fs.readFileSync(to, 'utf8'), said:await p.evaluate(() => document.querySelector('[data-lumina="report-said"]')?.textContent || '')};
}

{ // the web preview, nothing open, then a shoot
  const ctx = await b.newContext({viewport:{width:1440, height:900}, acceptDownloads:true}), p = await ctx.newPage(), errs = [];
  p.on('pageerror', e => errs.push(String(e)));
  await p.goto('file://' + page); await p.waitForTimeout(1000);
  const line = await p.evaluate(() => document.querySelector('[data-lumina="report"]')?.innerText || '');
  ok(/Something not right\?\s*Save a report\s*a text file of what Lumina saw, for you to send\. Nothing is sent from here\./.test(line), 'Open offers it: ' + JSON.stringify(line));
  let r = await save(p);
  ok(/^Lumina Skim report \d{4}-\d\d-\d\d \d\d\.\d\d\.txt$/.test(r.name), 'one .txt named by the date: ' + r.name);
  ok(/^Shoot {7}none open$/m.test(r.text), 'nothing open: it says so');
  ok(/^Running in {2}(the web preview|a browser)$/m.test(r.text), 'where it ran');
  ok(/^Build {7}\S/m.test(r.text) && !/^Build {7}not stamped$/m.test(r.text), 'the preview\'s build stamp: ' + (r.text.match(/^Build .*$/m) || [''])[0]);
  ok(/Saved “Lumina Skim report .*” to your downloads\./.test(r.said), 'the line says where it went: ' + r.said);

  await p.setInputFiles('input[type=file]', dir);
  for (let k = 0; k < 60; k++) { await p.waitForTimeout(500); if (await p.evaluate(() => { try { const a = JSON.parse(localStorage.getItem('lumina-skim:clock') || '[]')[0]; return !!(a && a.done != null); } catch (x) { return false; } })) break; }
  await p.evaluate(() => { setTimeout(() => { throw new Error('report test: a thrown error'); }, 0); Promise.reject(new Error('report test: a refused promise')); });
  await p.waitForTimeout(300);
  await p.keyboard.press('Meta+1'); await p.waitForTimeout(400);
  if (!await p.$('[data-lumina="report-save"]')) { await p.keyboard.press('Control+1'); await p.waitForTimeout(400); }
  r = await save(p);
  ok(/^Shoot {7}shoot · 4 clips · /m.test(r.text), 'the shoot: ' + (r.text.match(/^Shoot .*$/m) || [''])[0]);
  ok(/^Marks {7}0 selected · 0 maybe · 0 cut · 4 undecided$/m.test(r.text), 'its marks');
  ok(/^Read {8}4 of 4 clips with a cover/m.test(r.text), 'what was read: ' + (r.text.match(/^Read .*$/m) || [''])[0]);
  ok(/Last loads \(newest first\)\n {2}\{"/.test(r.text), 'the clock\'s last loads');
  ok(/report test: a thrown error/.test(r.text) && /unhandled: report test: a refused promise/.test(r.text), 'the page\'s own errors since it opened');
  ok(!r.text.includes(T), 'no folder path in it');
  ok(!errs.some(e => !/report test/.test(e)), 'no other page errors: ' + errs.filter(e => !/report test/.test(e)).join(' | '));
  await ctx.close();
}

{ // the Mac app's host: a stand-in for window.lumina.video and the app's build stamp
  const ctx = await b.newContext({viewport:{width:1440, height:900}, acceptDownloads:true});
  await ctx.addInitScript(() => { window.lumina = {video:{storeAll:() => Promise.resolve({}), storeSet:() => Promise.resolve(true)}}; window.luminaBuild = 'Lumina Skim 1.0.0 (999)'; });
  const p = await ctx.newPage(); await p.goto('file://' + page); await p.waitForTimeout(1000);
  const ran = await p.evaluate(() => window.luminaSkimReport.text());
  ok(/^Running in {2}the Lumina Skim app$/m.test(ran), 'luminaSkimReport.text() (the Help menu\'s way) says it ran in the app');
  const r = await save(p);
  ok(/^Build {7}\S/m.test(r.text) && !/^Build {7}not stamped$/m.test(r.text), 'a build line (the preview stamps its own over the app\'s): ' + (r.text.match(/^Build .*$/m) || [''])[0]);
  ok(/Choose where to save “Lumina Skim report .*”/.test(r.said), 'in the app the line asks where to save it: ' + r.said);
  await ctx.close();
}
await b.close();
fs.rmSync(T, {recursive:true, force:true});
console.log(fails ? fails + ' failed' : 'all ok'); process.exit(fails ? 1 : 0);
