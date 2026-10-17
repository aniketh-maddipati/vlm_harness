// Follow in the Skim Viewer: the web preview build in headless Chromium over clips made here with ffmpeg, with
// stand-ins for the app's lumina.video.masks, .follow, .followEnd and .matte (the bridge's skimMasks, skimFollow and
// skimMatte) that answer a disc in the middle of the frame. Bounded (LUMINA_WEB_LIMIT, 180 s).
//   1. With one shape chosen, Follow through the clip sends every followed frame as a JPEG, the first with the
//      shape's kind and box, forward from the frame on show and then back, and ends both follows.
//   2. The Viewer keeps its frame; the followed outline is drawn; the clip's facts gain the shape's own measures.
//   3. Save matte sends the clip's length in frames and every followed outline, and the path that comes back is kept
//      for the next .fcpxml. Let go clears the follow.
//
//   node Tests/web/skim-follow-browser.mjs        # needs ffmpeg and Playwright's Chromium
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { pw, ROOT, deadline } from './lib.mjs';

deadline('skim-follow-browser', 180);
const T = fs.mkdtempSync(path.join(os.tmpdir(), 'skim-follow-')), page = path.join(T, 'preview.html'), dir = path.join(T, 'shoot');
execFileSync('python3', [path.join(ROOT, 'Scripts/build-skim-preview.py'), page], {stdio:'ignore'});
fs.mkdirSync(dir, {recursive:true});
for (let i = 1; i <= 2; i++) execFileSync('ffmpeg', ['-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24:duration=2', '-vf', 'hue=h=' + i * 11,
  '-c:v', 'libvpx-vp9', '-b:v', '300k', path.join(dir, 'C000' + i + '.MP4')]);

let fails = 0; const ok = (c, what) => { console.log((c ? 'ok    ' : 'FAIL  ') + what); if (!c) fails++; };
const disc = (cx, cy, r) => [Array.from({length:24}, (_, i) => [cx + r * Math.cos(i / 24 * 2 * Math.PI) * 9 / 16, cy + r * Math.sin(i / 24 * 2 * Math.PI)])];
const SHAPES = [{id:'subject', kind:'subject', score:0.9, area:0.1, box:[0.4, 0.3, 0.2, 0.4], outline:disc(0.5, 0.5, 0.2)},
  {id:'background', kind:'background', score:1, area:0.9, box:[0, 0, 1, 1], outline:[[[0, 0], [1, 0], [1, 1], [0, 1]], disc(0.5, 0.5, 0.2)[0].slice().reverse()]}];

const b = await pw.chromium.launch({executablePath:process.env.CHROMIUM || undefined}), ctx = await b.newContext({viewport:{width:1440, height:900}}), errs = [];
await ctx.addInitScript(shapes => {
  window.__f = []; window.__end = []; window.__matte = [];
  const later = v => new Promise(r => setTimeout(() => r(v), 5));
  window.lumina = {video:{
    masks:frame => later(/^\/9j\//.test(frame) ? shapes : null),
    follow:(id, frame, start) => { window.__f.push({id, jpeg:/^\/9j\//.test(frame), start}); return later(/^\/9j\//.test(frame) ? {box:shapes[0].box, held:true, shape:shapes[0]} : null); },
    followEnd:id => { window.__end.push(id); return later(true); },
    matte:m => { window.__matte.push(m); return later({ok:true, path:'/Users/me/Export/' + m.name.replace(/\.\w+$/, '') + ' matte.mov', name:m.name.replace(/\.\w+$/, '') + ' matte.mov', folder:'/Users/me/Export'}); },
  }};
}, SHAPES);
const p = await ctx.newPage(); p.on('pageerror', e => errs.push(String(e)));
await p.goto('file://' + page); await p.waitForTimeout(800);
await p.setInputFiles('input[type=file]', dir);
for (let k = 0; k < 60; k++) { await p.waitForTimeout(500); if (await p.evaluate(() => { try { const a = JSON.parse(localStorage.getItem('lumina-skim:clock') || '[]')[0]; return !!(a && a.done != null); } catch (x) { return false; } })) break; }
await p.waitForTimeout(800);
for (let k = 0; k < 4 && !(await p.$('[data-lumina="viewer-top"]')); k++) { await p.keyboard.press('Enter'); await p.waitForTimeout(600); }
await p.waitForTimeout(1200);
const say = () => p.evaluate(() => document.querySelector('[data-lumina="follow"]')?.innerText || '');
const tc = () => p.evaluate(() => document.querySelector('[data-lumina="clip-row"]')?.innerText.match(/\d+:\d+[:.]\d+ of/)?.[0] || '');

await p.keyboard.press('o');
for (let k = 0; k < 20 && !(await p.$('[data-ol="subject"]')); k++) await p.waitForTimeout(250);
ok(!(await p.$('[data-lumina="follow-go"]')), 'no Follow before a shape is chosen');
await p.click('[data-ol="subject"]'); await p.waitForTimeout(300);
ok(!!(await p.$('[data-lumina="follow-go"]')), 'one shape chosen: Follow through the clip');
const t0 = await tc();
await p.click('[data-lumina="follow-go"]');
for (let k = 0; k < 120 && !/ followed/.test(await say()); k++) await p.waitForTimeout(250);
const F = await p.evaluate(() => window.__f), E = await p.evaluate(() => window.__end);
ok(/Subject followed · in 100% of the clip/.test(await say()), 'the line says it is followed: ' + JSON.stringify(await say()));
ok(F.length >= 14 && F.length <= 18, 'eight frames a second of a 2 s clip: ' + F.length);
ok(F.every(f => f.jpeg), 'every frame went as a JPEG');
const starts = F.filter(f => f.start);
ok(starts.length >= 1 && starts.length <= 2 && starts.every(s => s.start.kind === 'subject' && s.start.box.join() === '0.4,0.3,0.2,0.4'), 'a start per direction, with the kind and box: ' + JSON.stringify(starts.map(s => s.start)));
ok(new Set(F.map(f => f.id)).size === starts.length && E.length === starts.length && E.every(id => F.some(f => f.id === id)), 'each follow is ended: ' + E.length);
ok(await tc() === t0, 'the Viewer kept its frame: ' + t0 + ' → ' + await tc());
const lit = await p.evaluate(() => { const c = document.querySelector('[data-lumina="viewer-outlines"]'), d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data; let n = 0; for (let i = 0; i < d.length; i += 4) if (d[i + 3] && d[i] > 200 && d[i + 1] > 150 && d[i + 2] < 160) n++; return n; });
ok(lit > 200, 'the followed outline is drawn: ' + lit + ' pixels');
const shapeLine = await p.evaluate(() => document.body.innerText.match(/shape\s*\n?\s*Subject · [^\n]+/)?.[0] || '');
ok(/Subject · [+−]?\d\.\d stops · (soft|sharp) \d\.\d\d lowest · clipped [\d.]+% · crushed [\d.]+% · in 100% of the clip/.test(shapeLine), 'the facts: ' + JSON.stringify(shapeLine));
ok(!!(await p.$('[data-lumina="follow-matte"]')), 'Save matte is offered');
await p.click('[data-lumina="follow-matte"]');
for (let k = 0; k < 20 && !/matte saved/.test(await say()); k++) await p.waitForTimeout(150);
const M = await p.evaluate(() => window.__matte);
ok(M.length === 1 && M[0].name === 'C0001.MP4' && M[0].frames === 48 && Math.abs(M[0].fd[1] / M[0].fd[0] - 24) < 0.1 && M[0].w === 640 && M[0].h === 360, 'the matte asked for: ' + JSON.stringify(M.map(m => ({...m, samples:m.samples.length}))));
ok(M.length === 1 && M[0].samples.length === F.length && M[0].samples.every(s => typeof s.t === 'number' && Array.isArray(s.outline) && s.outline.length === 1), 'every followed outline, in time order: ' + (M[0] && M[0].samples.map(s => s.t).join(' ')));
ok(M.length === 1 && M[0].samples.every((s, i, a) => !i || a[i - 1].t <= s.t), 'in time order');
ok(/matte saved · C0001 matte\.mov · in the next \.fcpxml/.test(await say()), 'the line: ' + JSON.stringify(await say()));
const kept = await p.evaluate(() => { for (let i = 0; i < localStorage.length; i++) { const k = localStorage.key(i); if (k.indexOf('lumina-skim:mattes:') === 0) return localStorage.getItem(k); } return ''; });
ok(/C0001 matte\.mov/.test(kept) && /"shape":"Subject"/.test(kept), 'the path is kept for the .fcpxml: ' + kept);
await p.screenshot({path:path.join(T, 'follow.png')});
await p.click('[data-lumina="follow-drop"]'); await p.waitForTimeout(300);
ok(!/ followed/.test(await say()) && !(await p.evaluate(() => /shape\s*\n?\s*Subject ·/.test(document.body.innerText))), 'Let go clears the follow: ' + JSON.stringify(await say()));
ok(errs.length === 0, 'no page errors: ' + errs.join(' | '));
console.log('screenshot ' + path.join(T, 'follow.png'));
await b.close();
console.log(fails ? fails + ' failed' : 'all ok');
process.exit(fails ? 1 : 0);
