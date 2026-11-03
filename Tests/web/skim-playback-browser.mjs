// Playback with the mask (L) and the mask's graph: the web preview build in headless Chromium over clips made here with ffmpeg, with
// stand-ins for the app's lumina.video.masks, .track, .trackPoll, .trackEnd and .matte (the bridge's skimMasks,
// skimTrack, skimTrackPoll and skimMatte). The stand-in track answers every frame of a 2 s clip at 24p (48), a disc,
// in pages, the last quarter second shaky. Bounded (LUMINA_WEB_LIMIT, 180 s).
//   1. After a follow, the line sums up the mask (how sure, jumps, size, frame to frame) and the scrub bar draws it.
//   2. L plays the clip: the video runs, the button says Pause, the outline drawn moves with the frames shown.
//   3. L again pauses where it is: the playhead is there, and the outline is the one at that frame.
//   node Tests/web/skim-playback-browser.mjs        # needs ffmpeg and Playwright's Chromium
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { pw, ROOT, deadline } from './lib.mjs';

deadline('skim-playback-browser', 180);
const T = fs.mkdtempSync(path.join(os.tmpdir(), 'skim-playback-')), page = path.join(T, 'preview.html'), dir = path.join(T, 'shoot');
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
  // every frame of 2 s at 24p, a disc; the last six frames shaky
  const disc = (cx, cy, r) => [Array.from({length:24}, (_, i) => [cx + r * Math.cos(i / 24 * 2 * Math.PI) * 9 / 16, cy + r * Math.sin(i / 24 * 2 * Math.PI)])];
  const frames = Array.from({length:48}, (_, k) => { const cx = 0.2 + 0.6 * k / 47, r = k === 24 ? 0.2 : 0.1; return {t:k / 24, box:[cx - r * 9 / 16, 0.5 - r, r * 9 / 8, 2 * r], held:true, sure:k >= 42 ? 'shaky' : 'sure', outline:disc(cx, 0.5, r)}; });
  let polls = 0;
  window.lumina = {video:{
    masks:frame => later(/^\/9j\//.test(frame) ? shapes : null),
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
const say = () => p.evaluate(() => document.querySelector('[data-lumina="follow"]')?.innerText || '');
// where the drawn outline's middle is: the mean x of its gold pixels, 0 … 1
const mid = () => p.evaluate(() => { const c = document.querySelector('[data-lumina="viewer-outlines"]'), d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data; let n = 0, sx = 0;
  for (let i = 0; i < d.length; i += 4) if (d[i + 3] > 200 && d[i] > 230 && d[i + 1] > 190 && d[i + 2] < 150) { n++; sx += (i / 4) % c.width; } return n ? sx / n / c.width : null; });
const vid = () => p.evaluate(() => { const v = document.querySelector('video'); return v ? {t:v.currentTime, paused:v.paused} : null; });
await p.keyboard.press('o');
for (let k = 0; k < 20 && !(await p.$('[data-ol="subject"]')); k++) await p.waitForTimeout(250);
await p.click('[data-ol="subject"]'); await p.waitForTimeout(300);
await p.keyboard.press('Enter');
for (let k = 0; k < 120 && !/ followed/.test(await say()); k++) await p.waitForTimeout(250);
// 1. the summary and the graph
ok(/mask · 88% sure · 2 jumps · size ±\d+% · frame to frame \d+%/.test(await say()), 'the line sums up the mask: ' + JSON.stringify(await say()));
const g = await p.evaluate(() => { const c = document.querySelector('[data-lumina="follow-graph"]'); if (!c) return null; const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data; let red = 0, ink = 0; for (let i = 0; i < d.length; i += 4) { if (d[i + 3] > 200 && d[i] > 240 && d[i + 1] < 160) red++; if (d[i + 3]) ink++; } return {red, ink}; });
ok(g && g.ink > 200 && g.red > 10, 'the scrub bar draws the mask, its jumps in red: ' + JSON.stringify(g));
// 2. L plays
const x0 = await mid(), v0 = await vid();
await p.keyboard.press('l'); await p.waitForTimeout(900);
const v1 = await vid(), label = await p.evaluate(() => document.querySelector('[data-lumina="viewer-play"]')?.innerText || '');
ok(v1 && !v1.paused && v1.t > v0.t + 0.3, 'L plays the clip: ' + JSON.stringify([v0, v1]));
ok(/Pause/.test(label), 'the button says Pause: ' + JSON.stringify(label));
const x1 = await mid();
ok(x0 != null && x1 != null && Math.abs(x1 - x0) > 0.05, 'the outline moves with the frames: ' + x0 + ' → ' + x1);
// 3. L pauses
await p.keyboard.press('l'); await p.waitForTimeout(500);
const v2 = await vid(), x2 = await mid(); await p.waitForTimeout(400); const v3 = await vid();
ok(v2.paused && Math.abs(v3.t - v2.t) < 0.05, 'L again pauses where it is: ' + JSON.stringify([v2, v3]));
const want = 0.2 + 0.6 * Math.min(47, Math.round(v3.t * 24)) / 47;
ok(x2 != null && Math.abs(x2 - want) < 0.08, 'and the outline is the one at that frame: ' + x2 + ' vs ' + want);
ok(/Play/.test(await p.evaluate(() => document.querySelector('[data-lumina="viewer-play"]')?.innerText || '')), 'the button says Play again');
await p.screenshot({path:path.join(T, 'playback.png')});
ok(errs.length === 0, 'no page errors: ' + errs.join(' | '));
console.log('screenshot ' + path.join(T, 'playback.png'));
await b.close();
if (fails) { console.log(fails + ' failed'); process.exit(1); }
console.log('all ok');
