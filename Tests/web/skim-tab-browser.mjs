// Tab and ⇧Tab in a real browser: the web preview build in headless Chromium over clips made here with ffmpeg.
// On Skim, Tab does what → does and ⇧Tab what ← does (Clips and the Viewer), and focus stays where it was.
// Bounded (LUMINA_WEB_LIMIT, 120 s).
//
//   node Tests/web/skim-tab-browser.mjs        # needs ffmpeg and Playwright's Chromium
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { pw, ROOT, deadline } from './lib.mjs';

deadline('skim-tab-browser', 120);
const T = fs.mkdtempSync(path.join(os.tmpdir(), 'skim-tab-')), page = path.join(T, 'preview.html');
execFileSync('python3', [path.join(ROOT, 'Scripts/build-skim-preview.py'), page], {stdio:'ignore'});
const dir = path.join(T, 'dump'); fs.mkdirSync(dir, {recursive:true});
for (let i = 1; i <= 6; i++) execFileSync('ffmpeg', ['-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24:duration=2', '-vf', 'hue=h=' + i * 37, '-c:v', 'libvpx-vp9', '-b:v', '300k', path.join(dir, 'C000' + i + '.webm')]);

let fails = 0; const ok = (c, what) => { console.log((c ? 'ok    ' : 'FAIL  ') + what); if (!c) fails++; };
const b = await pw.chromium.launch({executablePath:process.env.CHROMIUM || undefined}), p = await (await b.newContext({viewport:{width:1440, height:1000}})).newPage(), errs = [];
p.on('pageerror', e => errs.push(String(e)));
await p.goto('file://' + page); await p.waitForTimeout(1000);
await p.setInputFiles('input[type=file]', dir);
for (let k = 0; k < 60; k++) { await p.waitForTimeout(500); if (await p.evaluate(() => { try { const a = JSON.parse(localStorage.getItem('lumina-skim:clock') || '[]')[0]; return !!(a && a.done != null); } catch (x) { return false; } })) break; }
const clipsTab = p.locator('[data-lumina="levels"] [role=tab]').nth(1); if (await clipsTab.count()) { await clipsTab.click(); await p.waitForTimeout(200); } else { await p.click('[data-gi="0"]'); await p.waitForTimeout(200); }
await p.mouse.click(2, 600); await p.waitForTimeout(200);
// the clip the page names as current
const look = () => p.evaluate(() => [...document.querySelectorAll('[data-lumina="where"],[data-lumina="strip-where"],[data-lumina="info-head"]')].map(e => e.innerText).join(' | '));
const press = async k => { await p.keyboard.press(k); await p.waitForTimeout(600); };
const focus = () => p.evaluate(() => { const a = document.activeElement; return a ? a.tagName + (a.getAttribute('data-lumina') || '') : ''; });

for (const where of ['Clips', 'Viewer']) {
  if (where === 'Viewer') await press('Enter');
  const at0 = await look(), f0 = await focus();
  await press('ArrowRight'); const right = await look(); await press('ArrowLeft');
  ok(await look() === at0 && right !== at0, where + ': → moves on and ← comes back');
  await press('Tab'); const tab = await look();
  ok(tab === right, where + ': Tab does what → does (' + at0 + ' to ' + tab + ')');
  ok(await focus() === f0, where + ': Tab leaves the focus where it was (' + f0 + ')');
  await press('Shift+Tab');
  ok(await look() === at0, where + ': ⇧Tab does what ← does');
}
ok(!errs.length, 'no page errors' + (errs.length ? ': ' + errs.join(' | ') : ''));
await b.close(); fs.rmSync(T, {recursive:true, force:true});
process.exit(fails ? 1 : 0);
