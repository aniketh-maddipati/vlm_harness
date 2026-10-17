// Outlines in the Skim Viewer (O): the web preview build in headless Chromium over clips made here with ffmpeg,
// with a stand-in for the app's lumina.video.masks (the bridge's skimMasks) that answers a disc in the middle of
// the frame, the subject, and the rest of the frame. Bounded (LUMINA_WEB_LIMIT, 180 s).
//   1. Without lumina.video.masks (Safari, Chrome) there is no Outlines switch and O does nothing.
//   2. O reads the frame on show once: a JPEG of it goes to masks, and the chips say what is there.
//   3. The pointer holds the frame while outlines are on; a click on the disc chooses the subject, a click
//      beside it the background, a chip lets one go. O again puts them away.
//
//   node Tests/web/skim-outlines-browser.mjs        # needs ffmpeg and Playwright's Chromium
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { pw, ROOT, deadline } from './lib.mjs';

deadline('skim-outlines-browser', 180);
const T = fs.mkdtempSync(path.join(os.tmpdir(), 'skim-outlines-')), page = path.join(T, 'preview.html'), dir = path.join(T, 'shoot');
execFileSync('python3', [path.join(ROOT, 'Scripts/build-skim-preview.py'), page], {stdio:'ignore'});
fs.mkdirSync(dir, {recursive:true});
for (let i = 1; i <= 4; i++) execFileSync('ffmpeg', ['-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24:duration=2', '-vf', 'hue=h=' + i * 11,
  '-c:v', 'libvpx-vp9', '-b:v', '300k', path.join(dir, 'C000' + i + '.MP4')]);

let fails = 0; const ok = (c, what) => { console.log((c ? 'ok    ' : 'FAIL  ') + what); if (!c) fails++; };
const disc = (cx, cy, r) => [Array.from({length:24}, (_, i) => [cx + r * Math.cos(i / 24 * 2 * Math.PI) * 9 / 16, cy + r * Math.sin(i / 24 * 2 * Math.PI)])];
const SHAPES = [{id:'subject', kind:'subject', score:0.9, area:0.1, box:[0.4, 0.3, 0.2, 0.4], outline:disc(0.5, 0.5, 0.2)},
  {id:'background', kind:'background', score:1, area:0.9, box:[0, 0, 1, 1], outline:[[[0, 0], [1, 0], [1, 1], [0, 1]], disc(0.5, 0.5, 0.2)[0].slice().reverse()]}];

async function open(host) {
  const b = await pw.chromium.launch({executablePath:process.env.CHROMIUM || undefined}), ctx = await b.newContext({viewport:{width:1440, height:900}}), errs = [];
  if (host) await ctx.addInitScript(shapes => {
    window.__asks = [];
    window.lumina = {video:{masks:frame => { window.__asks.push(frame); return new Promise(r => setTimeout(() => r(/^\/9j\//.test(frame) ? shapes : null), 20)); }}};
  }, SHAPES);
  const p = await ctx.newPage(); p.on('pageerror', e => errs.push(String(e)));
  await p.goto('file://' + page); await p.waitForTimeout(800);
  await p.setInputFiles('input[type=file]', dir);
  for (let k = 0; k < 60; k++) { await p.waitForTimeout(500); if (await p.evaluate(() => { try { const a = JSON.parse(localStorage.getItem('lumina-skim:clock') || '[]')[0]; return !!(a && a.done != null); } catch (x) { return false; } })) break; }
  await p.waitForTimeout(800);
  for (let k = 0; k < 4 && !(await p.$('[data-lumina="viewer-top"]')); k++) { await p.keyboard.press('Enter'); await p.waitForTimeout(600); }
  await p.waitForTimeout(1200);
  return {b, p, errs};
}
const say = p => p.evaluate(() => document.querySelector('[data-lumina="viewer-selections"]')?.innerText || '');
const pressed = p => p.evaluate(() => [...document.querySelectorAll('[data-ol]')].map(b => b.getAttribute('data-ol') + ':' + b.getAttribute('aria-pressed')).join(' '));

{ // 1. the browser alone
  const {b, p, errs} = await open(false);
  ok(!!(await p.$('[data-lumina="viewer-top"]')), 'the Viewer is open');
  ok(!(await p.$('[data-lumina="outlines"]')), 'no Outlines switch without the app');
  await p.keyboard.press('o'); await p.waitForTimeout(400);
  ok(!(await p.$('[data-lumina="viewer-outlines"]')) && !(await p.$('[data-lumina="viewer-selections"]')), 'O does nothing');
  ok(errs.length === 0, 'no page errors: ' + errs.join(' | '));
  await b.close();
}
{ // 2, 3. the app's way
  const {b, p, errs} = await open(true);
  ok(!!(await p.$('[data-lumina="outlines"]')), 'the Outlines switch is there');
  await p.keyboard.press('o');
  for (let k = 0; k < 20 && !/click a shape/.test(await say(p)); k++) await p.waitForTimeout(250);
  ok(/click a shape to choose it/.test(await say(p)), 'the line under the picture: ' + JSON.stringify(await say(p)));
  ok(await pressed(p) === 'subject:false background:false', 'one chip per shape: ' + await pressed(p));
  const asks = await p.evaluate(() => window.__asks.length);
  ok(asks === 1, 'the frame was read once: ' + asks);
  ok(await p.evaluate(() => /^\/9j\//.test(window.__asks[0]) && window.__asks[0].length > 2000), 'it went as a JPEG, base64');
  const ov = await p.$('[data-lumina="viewer-outlines"]'), r = await ov.boundingBox();
  ok(r && r.width > 300, 'the outlines lie over the picture: ' + JSON.stringify(r));
  const lit = await p.evaluate(() => { const c = document.querySelector('[data-lumina="viewer-outlines"]'), d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data; let n = 0; for (let i = 3; i < d.length; i += 4) if (d[i]) n++; return n; });
  ok(lit > 200, 'the outline is drawn: ' + lit + ' pixels');
  const tc = () => p.evaluate(() => document.querySelector('[data-lumina="clip-row"]')?.innerText.match(/\d+:\d+[:.]\d+ of/)?.[0] || '');
  const t0 = await tc();
  await p.mouse.move(r.x + r.width * 0.15, r.y + r.height * 0.5, {steps:6}); await p.mouse.move(r.x + r.width * 0.85, r.y + r.height * 0.5, {steps:6}); await p.waitForTimeout(300);
  ok(await tc() === t0, 'the pointer holds the frame: ' + t0 + ' → ' + await tc());
  await p.mouse.click(r.x + r.width * 0.5, r.y + r.height * 0.5); await p.waitForTimeout(300);
  ok(await pressed(p) === 'subject:true background:false', 'a click on the disc chooses the subject: ' + await pressed(p));
  ok(/1 chosen/.test(await say(p)), 'and says so: ' + JSON.stringify(await say(p)));
  await p.mouse.click(r.x + r.width * 0.1, r.y + r.height * 0.15); await p.waitForTimeout(300);
  ok(await pressed(p) === 'subject:true background:true', 'a click beside it chooses the background: ' + await pressed(p));
  await p.click('[data-ol="subject"]'); await p.waitForTimeout(300);
  ok(await pressed(p) === 'subject:false background:true', 'a chip lets one go: ' + await pressed(p));
  ok(await tc() === t0, 'the frame never moved: ' + await tc());
  ok(await p.evaluate(() => window.__asks.length) === 1, 'nothing was read again');
  await p.screenshot({path:path.join(T, 'outlines.png')});
  await p.keyboard.press('o'); await p.waitForTimeout(400);
  ok(!(await p.$('[data-lumina="viewer-outlines"]')), 'O again puts them away');
  ok(errs.length === 0, 'no page errors: ' + errs.join(' | '));
  console.log('screenshot ' + path.join(T, 'outlines.png'));
  await b.close();
}
console.log(fails ? fails + ' failed' : 'all ok');
process.exit(fails ? 1 : 0);
