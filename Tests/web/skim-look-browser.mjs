// Color in the Skim Viewer: the web preview build in headless Chromium over clips made here with ffmpeg.
// Bounded (LUMINA_WEB_LIMIT, 180 s).
//   1. The Viewer has the Color hub (325: Light · Color · Shadows · Mids · Highs); dragging up on Light's pad grades the real
//      picture (a WebGL canvas over the video, brighter than the clip as shot), one undo step per drag.
//   2. ⌘C on one clip and ⌘V on the next gives it the same look; ⌘Z takes the paste back.
//   3. The keys: 1–5 switch the hub and give it the arrows, ⌫ resets, held E moves Light's dot.
//   4. More holds the rest: Mix opens on Blue; a move there marks the chip. Shadows' wheel tints. Looks outlast a reload.
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
const drag = async (sel, dx) => { const el0 = await p.$(sel); await el0.evaluate(e => e.scrollIntoView({block:'end'})); await p.waitForTimeout(100); const r = await el0.boundingBox(); const y = r.y + r.height / 2, x = r.x + 30;
  await p.mouse.move(x, y); await p.mouse.down(); for (let i = 1; i <= 6; i++) await p.mouse.move(x + dx * i / 6, y); await p.mouse.up(); await p.waitForTimeout(250); };

ok(!!(await p.$('[data-lumina="look"]')), 'the Viewer has the Color card');
ok((await p.$$eval('[data-lkhub]', b => b.map(x => x.getAttribute('data-lkhub')))).join(' ') === 'light color sh mid hi', 'the hub: Light · Color · Shadows · Mids · Highs');
const hubBox = async () => { const h = await p.$('[data-lumina="look-hub"]'); await h.scrollIntoViewIfNeeded(); await p.waitForTimeout(80); return h.boundingBox(); };
ok((await hubBox()).width >= 220, 'the hub is large: ' + (await hubBox()).width + ' px');
const hubText = () => p.$eval('[data-lumina="look-hub-text"]', e => e.innerText);
ok(await say() === 'as shot', 'a clip starts as shot: ' + JSON.stringify(await say()));
ok(await lookOp() === '0', 'no grade canvas while the clip is as shot');
const m0 = await mean();
{ const r = await hubBox(); await p.mouse.move(r.x + r.width / 2, r.y + r.height / 2); await p.mouse.down(); for (let i = 1; i <= 6; i++) await p.mouse.move(r.x + r.width / 2, r.y + r.height * (0.5 - 0.2 * i / 6)); await p.mouse.up(); await p.waitForTimeout(250); }
const s1 = await say();
ok(/^Exposure \+1\.\d\d$/.test(s1), 'dragging up on Light: about +1.6: ' + JSON.stringify(s1));
await p.waitForTimeout(400);
ok(await lookOp() === '1', 'the grade canvas is on the picture: ' + await p.evaluate(() => document.querySelector('[data-lumina="viewer-look"]')?.dataset.look));
const m1 = await mean();
ok(m1 > m0 + 12, 'the picture is brighter: ' + m0.toFixed(1) + ' → ' + m1.toFixed(1));
// a double-click off the middle: the reset, and one ⌘Z goes back to before both presses
{ const r = await hubBox(); await p.mouse.dblclick(r.x + r.width * 0.85, r.y + r.height * 0.8); await p.waitForTimeout(250); }
ok(await say() === 'as shot', 'double-click resets the target');
await p.keyboard.press('Meta+z'); await p.waitForTimeout(250);
ok(await say() === s1, 'one ⌘Z brings the exposure back: ' + JSON.stringify(await say()));

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

// keys: 2 is Color and takes the arrows; one held arrow is one undo step; ⌫ resets; esc gives ← → back to the clips
await p.keyboard.press('2'); await p.waitForTimeout(200);
ok(await p.$eval('[data-lkhub="color"]', b => b.getAttribute('aria-selected')) === 'true', '2 switches the hub to Color');
ok(await p.evaluate(() => document.activeElement?.getAttribute('data-lumina')) === 'look-hub', 'the hub has the keys');
await p.keyboard.down('ArrowRight'); for (let i = 0; i < 3; i++) await p.keyboard.down('ArrowRight'); await p.keyboard.up('ArrowRight'); await p.waitForTimeout(150);
ok(/^Temp \+20 · Tint 0$/.test(await hubText()), 'four → presses (held): Temp +20: ' + await hubText());
await p.keyboard.press('Meta+z'); await p.waitForTimeout(200);
ok(/^Temp 0 /.test(await hubText()), 'one ⌘Z takes the held arrow back: ' + await hubText());
await p.keyboard.press('ArrowUp'); await p.waitForTimeout(150);
ok(/Tint \+5$/.test(await hubText()), '↑ is magenta (+tint): ' + await hubText());
await p.keyboard.press('Alt+ArrowUp'); await p.waitForTimeout(150);
ok(/^Saturation \+5$/.test(await p.$eval('[data-lumina="look-strip-text"]', e => e.innerText)), '⌥↑ moves Color\'s Saturation strip');
await p.keyboard.press('Backspace'); await p.waitForTimeout(150);
ok(/^Temp 0 · Tint 0$/.test(await hubText()) && /^Saturation 0$/.test(await p.$eval('[data-lumina="look-strip-text"]', e => e.innerText)), '⌫ resets the whole target: ' + await hubText());
// a wheel: ⇧↑ leaves the middle (strength 1), → turns the hue
await p.keyboard.press('3'); await p.waitForTimeout(150);
await p.keyboard.press('Shift+ArrowUp'); await p.waitForTimeout(150);
ok(/^Tint 0° · Strength 1$/.test(await hubText()), '⇧↑ on an untinted wheel: strength 1: ' + await hubText());
await p.keyboard.press('ArrowRight'); await p.waitForTimeout(150);
ok(/^Tint 5° · Strength 1$/.test(await hubText()), '→ turns the hue: ' + await hubText());
await p.keyboard.press('Backspace'); await p.waitForTimeout(150);
await p.keyboard.press('Escape'); await p.waitForTimeout(150);
ok(await p.evaluate(() => document.activeElement?.getAttribute('data-lumina')) !== 'look-hub', 'esc lets go of the hub');
// held E: the hub turns to Light and its dot moves
await p.keyboard.down('e'); await p.waitForTimeout(150); await p.keyboard.press('ArrowRight'); await p.waitForTimeout(150);
ok(await p.$eval('[data-lkhub="light"]', b => b.getAttribute('aria-selected')) === 'true', 'held E shows Light');
ok(!!(await p.$('[data-lumina="hub-tip"]')), 'the readout sits by the dot while E is held');
await p.keyboard.up('e'); await p.waitForTimeout(200);
ok(/^Exposure \+\d\.\d\d · Contrast 0$/.test(await hubText()), 'E → moved Light: ' + await hubText());
await p.keyboard.press('Meta+z'); await p.waitForTimeout(200);

// More: Mix, blue first
await p.click('[data-lumina="look-more"]'); await p.waitForTimeout(200);
await p.waitForTimeout(500);
{ const vis = await p.evaluate(() => { const h = document.querySelector('[data-lumina="look-hub"]').getBoundingClientRect(), r = document.querySelector('[data-lumina="info"]').getBoundingClientRect(), m = document.querySelector('[data-lumina="look-more-body"]').getBoundingClientRect();
    return h.top >= r.top - 1 && h.bottom <= r.bottom + 1 && m.top < r.bottom - 40; });
  ok(vis, 'More opens under the hub: the hub stays in view and More shows'); }
ok(await p.$eval('[data-lkhue="blue"]', b => b.getAttribute('aria-pressed')) === 'true', 'Mix opens on Blue');
ok((await p.$$eval('[data-lkp^="mix."]', r => r.map(x => x.getAttribute('data-lkp')))).join(' ') === 'mix.blue.h mix.blue.s mix.blue.l', 'hue · saturation · luminance of blue');
await drag('[data-lkp="mix.blue.s"]', -80);
ok(/Blue saturation -\d+/.test(await say()), 'blue saturation down: ' + JSON.stringify(await say()));
ok(await p.$eval('[data-lkhue="blue"]', b => b.children.length > 1), 'the Blue chip shows it is moved');

// Shadows: the hub's wheel tints the shadows
await p.click('[data-lkhub="sh"]'); await p.waitForTimeout(150);
const w = await hubBox();
await p.mouse.move(w.x + w.width * 0.5, w.y + w.height * 0.5); await p.mouse.down(); await p.mouse.move(w.x + w.width * 0.2, w.y + w.height * 0.8, {steps:5}); await p.mouse.up(); await p.waitForTimeout(250);
ok(/^Tint 2\d\d° · Strength \d+$/.test(await hubText()), 'the wheel reads a hue and a strength: ' + await hubText());
// a scroll over More's Global wheel scrolls the rail, it doesn't tint (More is still open)
{ const gw = await p.$('[data-lumina="look-wheel"]'); await gw.scrollIntoViewIfNeeded(); const g = await gw.boundingBox(); await p.mouse.move(g.x + g.width / 2, g.y + g.height / 2); await p.mouse.wheel(0, 120); await p.waitForTimeout(250); }
ok(await p.$eval('[data-lumina="look-wheel-say"]', e => e.innerText) === 'No tint', 'scrolling over Global leaves its tint alone');

// looks are kept per shoot (and outlast a reload)
await p.waitForTimeout(500);
const saved = await p.evaluate(() => Object.keys(localStorage).filter(k => k.indexOf('lumina-skim:looks:') === 0).map(k => localStorage.getItem(k)).join(''));
ok(/mix\.blue\.s/.test(saved) && /grade\.sh\.s/.test(saved), 'the looks are saved with the shoot: ' + saved.slice(0, 80));

// a clicked tab does not take ← →: they are still the clips
{ await p.click('[data-lkhub="mid"]'); await p.waitForTimeout(150); const n0 = await p.evaluate(() => document.querySelector('[data-lumina="info-head"] span')?.innerText);
  await p.keyboard.press('ArrowLeft'); await p.waitForTimeout(700); const n1 = await p.evaluate(() => document.querySelector('[data-lumina="info-head"] span')?.innerText);
  ok(n1 !== n0 && await p.$eval('[data-lkhub="mid"]', b => b.getAttribute('aria-selected')) === 'true', '← after clicking a tab goes to the clip before (' + n0 + ' → ' + n1 + '), the tab stays'); }
// a short window (1280 × 720): More open, a Mix row scrolled into view is not under the hub
{ await p.setViewportSize({width:1280, height:720}); await p.waitForTimeout(400);
  if (await p.$eval('[data-lumina="look-more"]', b => b.getAttribute('aria-expanded')) !== 'true') { await p.click('[data-lumina="look-more"]'); await p.waitForTimeout(400); }
  const r = await p.evaluate(async () => { const row = document.querySelector('[data-lkp="mix.blue.s"]'); row.scrollIntoView({block:'nearest'}); await new Promise(f => setTimeout(f, 300));
    const a = row.getBoundingClientRect(), b = document.querySelector('[data-lumina="look-hub-block"]').getBoundingClientRect(), i = document.querySelector('[data-lumina="info"]').getBoundingClientRect(), h = document.querySelector('[data-lumina="look-hub"]').getBoundingClientRect();
    return {free:a.top >= Math.min(b.bottom, i.top + 1) - 1 || a.top >= b.bottom - 1, inRail:a.bottom <= i.bottom + 1, hub:Math.round(h.width), top:Math.round(a.top), blk:Math.round(b.bottom)}; });
  ok(r.free && r.inRail, 'at 1280 × 720 a Mix row comes into view clear of the hub: ' + JSON.stringify(r));
  ok(r.hub >= 220, 'the hub keeps 220 px at 720 tall: ' + r.hub); }
ok(!errs.length, 'no page errors' + (errs.length ? ': ' + errs.join(' | ') : ''));
await b.close();
console.log(fails ? fails + ' failed' : 'all ok');
process.exit(fails ? 1 : 0);
