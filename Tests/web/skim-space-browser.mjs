// Space in Skim, as the keep-sort wireframe has it: a tap opens the Viewer and a tap closes it; held, it plays the
// clip while held (in the Viewer it stays open after; from the grid, letting go goes back). Headless Chromium over
// ffmpeg clips. Bounded (LUMINA_WEB_LIMIT, 120 s).
//
//   node Tests/web/skim-space-browser.mjs        # needs ffmpeg and Playwright's Chromium
import fs from 'node:fs'; import os from 'node:os'; import path from 'node:path'; import { execFileSync } from 'node:child_process';
import { pw, ROOT, deadline } from './lib.mjs';
deadline('skim-space-browser', 120);
const T = fs.mkdtempSync(path.join(os.tmpdir(), 'skim-sp-')), page = path.join(T, 'preview.html'), dir = path.join(T, 'shoot');
execFileSync('python3', [path.join(ROOT, 'Scripts/build-skim-preview.py'), page], {stdio:'ignore'}); fs.mkdirSync(dir);
for (let i = 1; i <= 3; i++) execFileSync('ffmpeg', ['-loglevel','error','-y','-f','lavfi','-i','testsrc2=size=640x360:rate=24:duration=4','-c:v','libvpx-vp9','-b:v','200k', path.join(dir,'C000'+i+'.MP4')]);
const b = await pw.chromium.launch(); const p = await (await b.newContext({viewport:{width:1440,height:900}})).newPage();
const errs=[]; p.on('pageerror', e => errs.push(String(e)));
await p.goto('file://' + page); await p.waitForTimeout(800); await p.setInputFiles('input[type=file][webkitdirectory]', dir); await p.waitForTimeout(6000);
const viewer = () => p.$('[data-screen-label="Clip"]').then(Boolean);
const playing = () => p.evaluate(() => { const v = document.querySelector('[data-lumina="clip-row"] video'); return !!v && !v.paused; });
let fails = 0; const ok = (c, w) => { console.log((c ? 'ok    ' : 'FAIL  ') + w); if (!c) fails++; };
await p.mouse.click(5, 450); await p.keyboard.press('Space'); await p.waitForTimeout(900);
ok(await viewer(), 'tap Space opens the Viewer');
await p.keyboard.press('Space'); await p.waitForTimeout(700);
ok(!(await viewer()), 'tap Space again closes it');
await p.keyboard.press('Space'); await p.waitForTimeout(1500);
await p.keyboard.down('Space'); await p.waitForTimeout(900);
ok(await playing(), 'hold Space in the Viewer plays');
await p.keyboard.up('Space'); await p.waitForTimeout(400);
ok(await viewer() && !(await playing()), 'let go: still in the Viewer, paused');
await p.keyboard.press('Space'); await p.waitForTimeout(700);
ok(!(await viewer()), 'tap closes');
await p.keyboard.down('Space'); await p.waitForTimeout(2600);
ok(await viewer() && await playing(), 'hold from the grid: Viewer, playing');
await p.keyboard.up('Space'); await p.waitForTimeout(700);
ok(!(await viewer()), 'let go: back on the grid');
ok(!errs.length, 'no page errors ' + errs.join(' | '));
await b.close(); console.log(fails ? fails + ' failed' : 'all ok'); process.exit(fails ? 1 : 0);
