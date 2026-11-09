// Color in the Skim Viewer: the web preview build in headless Chromium over clips made here with ffmpeg.
// Bounded (LUMINA_WEB_LIMIT, 180 s).
//   1. The Viewer has the Color card, its hub on five targets (Light · Color · Shadows · Mids · Highs, LOCAL-CHANGES 325);
//      dragging the Light pad up (Exposure) grades the real picture
//      (a WebGL canvas over the video, brighter than the clip as shot).
//   2. ⌘C on one clip and ⌘V on the next gives it the same look; ⌘Z takes the paste back.
//   3. More ▸ Mix opens on Blue; a move there marks the chip. The Shadows wheel tints. Looks outlast a reload.
//
//   node Tests/web/skim-look-browser.mjs        # needs ffmpeg and Playwright's Chromium
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { pw, ROOT, deadline } from './lib.mjs';

deadline('skim-look-browser', 180);
const T = fs.mkdtempSync(path.join(os.tmpdir(), 'skim-look-')), page = path.join(T, 'preview.html'), dir = path.join(T, 'shoot');
execFileSync('python3', [path.join(ROOT, 'Scripts/build-skim-preview.py'), page], {stdio:'ignore'});
fs.mkdirSync(dir, {recursive:true});
for (let i = 1; i <= 2; i++) execFileSync('ffmpeg', ['-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24:duration=2', '-vf', 'hue=h=' + i * 11,
  '-c:v', 'libvpx-vp9', '-b:v', '300k', path.join(dir, 'C000' + i + '.MP4')]);

let fails = 0; const ok = (c, what) => { console.log((c ? 'ok    ' : 'FAIL  ') + what); if (!c) fails++; };
const b = await pw.chromium.launch({executablePath:process.env.CHROMIUM || undefined, args:['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader']});
const ctx = await b.newContext({viewport:{width:1440, height:900}}), errs = [];
const p = await ctx.newPage(); p.on('pageerror', e => errs.push(String(e)));
const open = async () => {
  for (let k = 0; k < 4 && !(await p.$('[data-lumina="viewer-top"]')); k++) { await p.keyboard.press('Enter'); await p.waitForTimeout(600); }
  await p.waitForTimeout(1200);
};
await p.goto('file://' + page); await p.waitForTimeout(800);
await p.setInputFiles('input[type=file]', dir);
for (let k = 0; k < 60; k++) { await p.waitForTimeout(500); if (await p.evaluate(() => { try { const a = JSON.parse(localStorage.getItem('lumina-skim:clock') || '[]')[0]; return !!(a && a.done != null); } catch (x) { return false; } })) break; }
await p.waitForTimeout(800);
await open();

const say = () => p.evaluate(() => document.querySelector('[data-lumina="look-say"]')?.innerText || '');
const lookOp = () => p.evaluate(() => getComputedStyle(document.querySelector('[data-lumina="viewer-look"]') || document.body).opacity);
// Mean brightness of the picture as composited (a screenshot, decoded in the page), without the EV badge over it.
const mean = async () => {
  await p.evaluate(() => document.querySelectorAll('[data-lumina="ev-badge"]').forEach(b => { b.style.visibility = 'hidden'; }));
  const el = await p.$('[data-lumina="clip-row"] [data-pic="1"] > div'); const png = (await el.screenshot()).toString('base64');
  await p.evaluate(() => document.querySelectorAll('[data-lumina="ev-badge"]').forEach(b => { b.style.visibility = ''; }));
  return p.evaluate(async b64 => { const im = new Image(); im.src = 'data:image/png;base64,' + b64; await im.decode(); const c = document.createElement('canvas'); c.width = 64; c.height = 36;
    const x = c.getContext('2d'); x.drawImage(im, 0, 0, 64, 36); const d = x.getImageData(0, 0, 64, 36).data; let s = 0; for (let i = 0; i < d.length; i += 4) s += d[i] + d[i + 1] + d[i + 2]; return s / (d.length / 4) / 3; }, png);
};
const drag = async (sel, dx) => { await (await p.$(sel)).scrollIntoViewIfNeeded(); const r = await (await p.$(sel)).boundingBox(); const y = r.y + r.height / 2, x = r.x + 30;
  await p.mouse.move(x, y); await p.mouse.down(); for (let i = 1; i <= 6; i++) await p.mouse.move(x + dx * i / 6, y); await p.mouse.up(); await p.waitForTimeout(250); };

ok(!!(await p.$('[data-lumina="look"]')), 'the Viewer has the Color card');
ok((await p.$$eval('[data-lkt]', b => b.map(x => x.innerText.trim()))).join(' ') === 'Light Color Shadows Mids Highs', 'Light · Color · Shadows · Mids · Highs');
ok(await say() === 'as shot', 'a clip starts as shot: ' + JSON.stringify(await say()));
ok(await lookOp() === '0', 'no grade canvas while the clip is as shot');
const m0 = await mean();
{ const h = await (await p.$('[data-lumina="look-hub"]')).boundingBox(); ok(h.width >= 220, 'the hub is large: ' + Math.round(h.width) + ' px');
  await p.mouse.move(h.x + h.width / 2, h.y + h.height / 2); await p.mouse.down(); await p.mouse.move(h.x + h.width / 2, h.y + h.height * 0.28, {steps:6}); await p.mouse.up(); await p.waitForTimeout(250); }
const s1 = await say();
ok(/^Exposure \+1\.\d\d$/.test(s1), 'the Light pad up from the middle: Exposure about +1.8, Contrast left alone: ' + JSON.stringify(s1));
await p.waitForTimeout(400);
ok(await lookOp() === '1', 'the grade canvas is on the picture: ' + await p.evaluate(() => document.querySelector('[data-lumina="viewer-look"]')?.dataset.look));
const m1 = await mean();
ok(m1 > m0 + 12, 'the picture is brighter: ' + m0.toFixed(1) + ' → ' + m1.toFixed(1));
await p.dblclick('[data-lumina="look-hub"]'); await p.waitForTimeout(250);
ok(await say() === 'as shot', 'double-click resets Light');
await p.keyboard.press('Meta+z'); await p.waitForTimeout(250);
ok(await say() === s1, '⌘Z brings the exposure back');

// keys (326): 2 picks Color and gives the hub the keys; arrows step it, the burst is one ⌘Z; esc gives the keys back
await p.keyboard.press('2'); await p.waitForTimeout(200);
ok(await p.$eval('[data-lkt="color"]', b => b.getAttribute('aria-selected')) === 'true' && await p.evaluate(() => document.activeElement?.getAttribute('data-lumina')) === 'look-hub', '2: Color, the hub has the keys');
for (let i = 0; i < 3; i++) await p.keyboard.press('ArrowRight'); await p.waitForTimeout(150);
ok(/^Temp \+15 · Tint 0$/.test(await p.$eval('[data-lumina="look-hub-say"]', e => e.innerText)), 'three → warm it 15: ' + await p.$eval('[data-lumina="look-hub-say"]', e => e.innerText));
await p.waitForTimeout(600); await p.keyboard.press('Meta+z'); await p.waitForTimeout(250);
ok(await say() === s1, 'the arrows were one ⌘Z step: ' + JSON.stringify(await say()));
await p.keyboard.press('Escape'); await p.waitForTimeout(150);
ok(await p.evaluate(() => document.activeElement?.getAttribute('data-lumina')) !== 'look-hub' && !!(await p.$('[data-lumina="viewer-top"]')), 'esc gives the keys back and stays in the Viewer');
await p.keyboard.press('1'); await p.waitForTimeout(150); await p.keyboard.press('Escape'); await p.waitForTimeout(150);

// copy here, paste on the next clip
await p.keyboard.press('Meta+c'); await p.waitForTimeout(200);
const name0 = await p.evaluate(() => document.querySelector('[data-lumina="info-head"] span')?.innerText);
await p.keyboard.press('ArrowRight'); await p.waitForTimeout(900);
const name1 = await p.evaluate(() => document.querySelector('[data-lumina="info-head"] span')?.innerText);
ok(name1 && name1 !== name0, 'on the next clip: ' + name0 + ' → ' + name1);
ok(await say() === 'as shot', 'the next clip is as shot');
await p.keyboard.press('Meta+v'); await p.waitForTimeout(250);
ok(await say() === s1, '⌘V gives it the same look: ' + JSON.stringify(await say()));
await p.keyboard.press('Meta+z'); await p.waitForTimeout(250);
ok(await say() === 'as shot', '⌘Z takes the paste back');
await p.keyboard.press('Meta+Shift+z'); await p.waitForTimeout(250);

// More ▸ Mix: blue first
await p.click('[data-lumina="look-more"]'); await p.waitForTimeout(150);
await p.click('[data-lksec="mix"]'); await p.waitForTimeout(200);
ok(await p.$eval('[data-lkhue="blue"]', b => b.getAttribute('aria-pressed')) === 'true', 'Mix opens on Blue');
ok((await p.$$eval('[data-lkp]', r => r.map(x => x.getAttribute('data-lkp')))).join(' ') === 'mix.blue.h mix.blue.s mix.blue.l', 'hue · saturation · luminance of blue');
await drag('[data-lkp="mix.blue.s"]', -80);
ok(/Blue saturation -\d+/.test(await say()), 'blue saturation down: ' + JSON.stringify(await say()));
ok(await p.$eval('[data-lkhue="blue"]', b => b.children.length > 1), 'the Blue chip shows it is moved');

// the Shadows wheel tints the shadows
await p.click('[data-lkt="sh"]'); await p.waitForTimeout(200);
const w = await (await p.$('[data-lumina="look-hub"]')).boundingBox();
await p.mouse.move(w.x + w.width * 0.5, w.y + w.height * 0.5); await p.mouse.down(); await p.mouse.move(w.x + w.width * 0.2, w.y + w.height * 0.8, {steps:5}); await p.mouse.up(); await p.waitForTimeout(250);
ok(/^Hue 2\d\d° · strength \d+$/.test(await p.$eval('[data-lumina="look-hub-say"]', e => e.innerText)), 'the wheel reads a hue and a strength: ' + await p.$eval('[data-lumina="look-hub-say"]', e => e.innerText));

// looks are kept per shoot (and outlast a reload)
await p.waitForTimeout(500);
const saved = await p.evaluate(() => Object.keys(localStorage).filter(k => k.indexOf('lumina-skim:looks:') === 0).map(k => localStorage.getItem(k)).join(''));
ok(/mix\.blue\.s/.test(saved) && /grade\.sh\.s/.test(saved), 'the looks are saved with the shoot: ' + saved.slice(0, 80));

ok(!errs.length, 'no page errors' + (errs.length ? ': ' + errs.join(' | ') : ''));
await b.close();
console.log(fails ? fails + ' failed' : 'all ok');
process.exit(fails ? 1 : 0);
