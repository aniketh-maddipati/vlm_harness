// The Color hub (LOCAL-CHANGES 326) in headless Chromium: screenshots of the rail on each of its five targets with a look
// set through the hub itself, and with More open. Evidence only (no gate); used by the colour-hub review rounds.
//   node Tests/web/skim-hub-shots.mjs <out-dir>        # needs ffmpeg and Playwright's Chromium
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { pw, ROOT, deadline } from './lib.mjs';

deadline('skim-hub-shots', 180);
const OUT = process.argv[2] || fs.mkdtempSync(path.join(os.tmpdir(), 'skim-hub-shots-')); fs.mkdirSync(OUT, {recursive:true});
const T = fs.mkdtempSync(path.join(os.tmpdir(), 'skim-hub-')), page = path.join(T, 'preview.html'), dir = path.join(T, 'shoot');
execFileSync('python3', [path.join(ROOT, 'Scripts/build-skim-preview.py'), page], {stdio:'ignore'});
fs.mkdirSync(dir, {recursive:true});
for (let i = 1; i <= 2; i++) execFileSync('ffmpeg', ['-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24:duration=2', '-vf', 'hue=h=' + i * 11,
  '-c:v', 'libvpx-vp9', '-b:v', '300k', path.join(dir, 'C000' + i + '.MP4')]);
const b = await pw.chromium.launch({executablePath:process.env.CHROMIUM || undefined, args:['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader']});
const ctx = await b.newContext({viewport:{width:1440, height:900}, deviceScaleFactor:2}), errs = [];
const p = await ctx.newPage(); p.on('pageerror', e => errs.push(String(e)));
await p.goto('file://' + page); await p.waitForTimeout(800);
await p.setInputFiles('input[type=file]', dir);
for (let k = 0; k < 60; k++) { await p.waitForTimeout(500); if (await p.evaluate(() => { try { const a = JSON.parse(localStorage.getItem('lumina-skim:clock') || '[]')[0]; return !!(a && a.done != null); } catch (x) { return false; } })) break; }
await p.waitForTimeout(800);
for (let k = 0; k < 4 && !(await p.$('[data-lumina="viewer-top"]')); k++) { await p.keyboard.press('Enter'); await p.waitForTimeout(600); }
await p.waitForTimeout(1200);
const hub = async () => { const h = await p.$('[data-lumina="look-hub"]'); await h.scrollIntoViewIfNeeded(); return h.boundingBox(); };
const drag = async (fx, fy, hold) => { const r = await hub(); await p.mouse.move(r.x + r.width * 0.5, r.y + r.height * 0.5); await p.mouse.down();
  await p.mouse.move(r.x + r.width * fx, r.y + r.height * fy, {steps:6}); if (!hold) { await p.mouse.up(); await p.waitForTimeout(250); } };
const rail = async name => { const el = await p.$('[data-lumina="info"]'); await el.screenshot({path:path.join(OUT, name + '.png')}); };
const look = [['light', 0.68, 0.38], ['color', 0.62, 0.55], ['sh', 0.3, 0.7], ['mid', 0.5, 0.5], ['hi', 0.62, 0.3]];
for (const [t, fx, fy] of look) { await p.click('[data-lkhub="' + t + '"]'); await p.waitForTimeout(150); if (t !== 'mid') await drag(fx, fy); }
// Color's Saturation strip
await p.click('[data-lkhub="color"]'); await p.waitForTimeout(150);
{ const el = await p.$('[data-lumina="look-strip"]'); await el.scrollIntoViewIfNeeded(); const s = await el.boundingBox(); await p.mouse.click(s.x + s.width / 2, s.y + s.height * 0.42); await p.waitForTimeout(200); }
// a shadows luminance move through the strip
await p.click('[data-lkhub="sh"]'); await p.waitForTimeout(150);
{ const s = await (await p.$('[data-lumina="look-strip"]')).boundingBox(); await p.mouse.click(s.x + s.width / 2, s.y + s.height * 0.4); await p.waitForTimeout(200); }
for (const [t] of look) { await p.click('[data-lkhub="' + t + '"]'); await p.waitForTimeout(200); await p.mouse.move(5, 5); await rail('tab-' + t); }
// moving: the readout by the dot
await p.click('[data-lkhub="light"]'); await p.waitForTimeout(150); await drag(0.7, 0.36, true); await p.waitForTimeout(150); await rail('light-moving'); await p.mouse.up(); await p.waitForTimeout(200);
// the keys: 2 gives the hub the arrows, and it says so
await p.keyboard.press('2'); await p.waitForTimeout(250); await rail('keys-focused'); await p.keyboard.press('Escape'); await p.waitForTimeout(150);
// More open, with a move in it
await p.click('[data-lumina="look-more"]'); await p.waitForTimeout(250);
await rail('more-open');
await p.screenshot({path:path.join(OUT, 'whole.png')});
await p.click('[data-lumina="look-more"]'); await p.waitForTimeout(200);
await p.screenshot({path:path.join(OUT, 'whole-closed.png')});
// a short window, More open
await p.setViewportSize({width:1280, height:720}); await p.waitForTimeout(300); await p.click('[data-lumina="look-more"]'); await p.waitForTimeout(500); await rail('short-720-more-open'); await p.click('[data-lumina="look-more"]');
const say = await p.evaluate(() => document.querySelector('[data-lumina="look-say"]')?.innerText || '');
console.log('look: ' + say); console.log('shots: ' + OUT);
if (errs.length) console.log('page errors: ' + errs.join(' | '));
await b.close();
