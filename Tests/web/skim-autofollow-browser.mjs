// Following starts by itself (Lightroom-ease, OUTLINING.md): the web preview build in headless Chromium over clips made here with ffmpeg, with
// stand-ins for the app's lumina.video.masks, .track, .trackPoll, .trackEnd and .matte (the bridge's skimMasks,
// skimTrack, skimTrackPoll and skimMatte). The stand-in track answers every frame of a 2 s clip at 24p (48), a disc,
// in pages, the last quarter second shaky. Bounded (LUMINA_WEB_LIMIT, 180 s).
//   1. A click outlines the thing (stand-in .prompt), and the track starts by itself a moment later, prompted, once.
//   2. Clicks in quick succession restart the wait: one track, after the last click.
//   node Tests/web/skim-autofollow-browser.mjs        # needs ffmpeg and Playwright's Chromium
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { pw, ROOT, deadline } from './lib.mjs';

deadline('skim-autofollow-browser', 180);
const T = fs.mkdtempSync(path.join(os.tmpdir(), 'skim-autofollow-')), page = path.join(T, 'preview.html'), dir = path.join(T, 'shoot');
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
  window.__f = []; window.__track = []; window.__poll = []; window.__end = []; window.__matte = [];
  const later = v => new Promise(r => setTimeout(() => r(v), 5));
  const disc = (cx, cy, r) => [Array.from({length:24}, (_, i) => [cx + r * Math.cos(i / 24 * 2 * Math.PI) * 9 / 16, cy + r * Math.sin(i / 24 * 2 * Math.PI)])];
  // every frame of 2 s at 24p, a disc; the last six frames shaky
  const frames = Array.from({length:48}, (_, k) => ({t:k / 24, box:shapes[0].box, held:true, sure:k >= 42 ? 'shaky' : 'sure', outline:shapes[0].outline}));
  let polls = 0;
  window.lumina = {video:{
    masks:frame => later(/^\/9j\//.test(frame) ? shapes : null),
    promptReady:() => later('ready'),
    prompt:(key, frame, points, stroke) => { window.__prompts = (window.__prompts || 0) + 1; const c = points[0]; return later({id:'pick', kind:'object', score:1, area:0.05, box:[c.x - 0.07, c.y - 0.12, 0.14, 0.24], outline:disc(c.x, c.y, 0.12)}); },
    follow:(id, frame, start) => { window.__f.push({id}); return later(null); },
    followEnd:id => later(true),
    track:(id, path, start, t, fix) => { window.__track.push({id, path, start, t, fix}); return later(true); },
    trackPoll:(id, from) => {
      const fx = window.__track.find(x => x.id === id && x.fix); window.__poll.push({id, from});
      if (fx) { const fr = frames.filter(f => f.t >= fx.fix.from - 1e-6 && f.t <= fx.fix.to + 1e-6).map(f => ({...f, sure:'sure'})), page = fr.slice(from, from + 16);
        return later({state:from + page.length >= fr.length ? 'done' : 'run', done:(from + page.length) / fr.length, n:fr.length, from, frames:page}); } window.__poll.push({id, from}); polls++; const n = Math.min(48, polls * 20), page = frames.slice(from, Math.min(n, from + 16));
      return later({state:n >= 48 && from + page.length >= 48 ? 'done' : 'run', done:n / 48, n, from, frames:page,
        strip:n >= 48 ? [{t0:0, t1:41 / 24, sure:'sure'}, {t0:42 / 24, t1:47 / 24, sure:'shaky'}] : undefined}); },
    trackEnd:id => { window.__end.push(id); return later(true); },
    remove:m => { window.__remove = (window.__remove || []).concat([m]); return later(window.__remove.length === 1 ? {ok:false, why:'The camera moves in this clip. Removing from the clip\'s own frames needs a still camera.'}
      : {ok:true, path:'/Users/me/Export/C0001 patch.mov', name:'C0001 patch.mov'}); },
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
const tracks = () => p.evaluate(() => window.__track.filter(x => !x.fix));
await p.keyboard.press('o');
const cv = await (await p.$('[data-lumina="viewer-outlines"]')).boundingBox(), at = (fx, fy) => p.mouse.click(cv.x + cv.width * fx, cv.y + cv.height * fy);
for (let k = 0; k < 20 && !(await p.evaluate(() => /click or brush/.test(document.querySelector('[data-lumina="viewer-selections"]')?.innerText || ''))); k++) await p.waitForTimeout(250);
// 1. a click, then nothing: following starts by itself, prompted
await at(0.3, 0.5); await p.waitForTimeout(500);
ok((await tracks()).length === 0, 'not straight away');
await p.waitForTimeout(1300);
let tr = await tracks();
ok(tr.length === 1 && tr[0].start && tr[0].start.prompted === true, 'then by itself, prompted: ' + JSON.stringify(tr.map(x => x.start)));
// 2. on the next clip, quick clicks restart the wait
await p.keyboard.press('ArrowRight'); await p.waitForTimeout(1500);
for (let k = 0; k < 20 && !(await p.evaluate(() => /click or brush/.test(document.querySelector('[data-lumina="viewer-selections"]')?.innerText || ''))); k++) await p.waitForTimeout(250);
await at(0.3, 0.5); await p.waitForTimeout(600); await at(0.8, 0.5); await p.waitForTimeout(600); await at(0.8, 0.2); await p.waitForTimeout(700);
ok((await tracks()).length === 1, 'clicks a moment apart keep it waiting: ' + (await tracks()).length);
await p.waitForTimeout(1000);
tr = await tracks();
ok(tr.length === 2 && (await p.evaluate(() => window.__prompts)) >= 4, 'one track after the last click: ' + tr.length);
ok(errs.length === 0, 'no page errors: ' + errs.join(' | '));
await b.close();
if (fails) { console.log(fails + ' failed'); process.exit(1); }
console.log('all ok');
