// Export's Files in a browser when the clips were picked one by one ("Imported clips", no folder): the tree still lists
// them with their marks, with no click, and the note says the browser sees the clips you opened (round 2, LOCAL-CHANGES 300).
// Bounded (240 s).   node Tests/web/skim-files-browser.mjs        # needs ffmpeg and Playwright's Chromium
import fs from 'node:fs'; import os from 'node:os'; import path from 'node:path'; import { execFileSync } from 'node:child_process';
import { pw, ROOT, deadline } from './lib.mjs';

deadline('skim-files-browser', 240);
const T = fs.mkdtempSync(path.join(os.tmpdir(), 'skim-files-')), page = path.join(T, 'preview.html');
execFileSync('python3', [path.join(ROOT, 'Scripts/build-skim-preview.py'), page], {stdio:'ignore'});
const dir = path.join(T, 'picked'); fs.mkdirSync(dir);
const files = [1, 2, 3, 4].map(i => { const f = path.join(dir, 'C000' + i + '.webm'); execFileSync('ffmpeg', ['-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=320x180:rate=24:duration=2', '-vf', 'hue=h=' + i * 40, '-c:v', 'libvpx-vp9', '-deadline', 'realtime', '-cpu-used', '8', f]); return f; });
let fails = 0; const ok = (c, what) => { console.log((c ? 'ok    ' : 'FAIL  ') + what); if (!c) fails++; };
const b = await pw.chromium.launch({executablePath:process.env.CHROMIUM || undefined}), p = await (await b.newContext({viewport:{width:1440, height:1000}})).newPage(), errs = [];
p.on('pageerror', e => errs.push(String(e)));
try {
  await p.goto('file://' + page + '?debug=1');   // Files is in Export's debug part (LOCAL-CHANGES 314) await p.waitForTimeout(1000);
  await p.setInputFiles('input[type=file]:not([webkitdirectory]):not([data-lumina])', files);
  for (let k = 0; k < 40 && !(await p.evaluate(() => /Imported clips/.test(document.body.innerText))); k++) await p.waitForTimeout(250);
  await p.waitForTimeout(1500); await p.keyboard.press('k'); await p.waitForTimeout(150);
  await p.keyboard.press('Meta+e'); await p.waitForTimeout(1200);
  const rows = await p.$$eval('[data-lumina="ws-row"]', es => es.map(e => [e.getAttribute('data-kind'), e.innerText.replace(/\s+/g, ' ').trim()]));
  ok(rows.length === 5 && /^\W*Imported clips/.test(rows[0][1]) && rows.filter(r => r[0] === 'clip').length === 4, 'clips picked one by one are listed in Files, unfurled, with no click: ' + rows.map(r => r[1]).join(' | '));
  ok(rows.some(r => r[0] === 'clip' && /kept/.test(r[1])) && rows.filter(r => /undecided/.test(r[1])).length === 3, 'each clip shows its mark');
  ok(/sees only the clips you opened/.test(await p.evaluate(() => document.body.innerText)), 'the note says the browser sees the clips you opened');
} finally { await b.close(); fs.rmSync(T, {recursive:true, force:true}); }
ok(!errs.length, 'no page errors' + (errs.length ? ': ' + errs.join(' | ') : ''));
console.log(fails ? fails + ' failed' : 'all ok'); process.exit(fails ? 1 : 0);
