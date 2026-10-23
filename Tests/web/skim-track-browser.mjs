// Follow with the Mac's own track: the web preview build in headless Chromium over clips made here with ffmpeg, with
// stand-ins for the app's lumina.video.masks, .track, .trackPoll, .trackEnd and .matte (the bridge's skimMasks,
// skimTrack, skimTrackPoll and skimMatte). The stand-in track answers every frame of a 2 s clip at 24p (48), a disc,
// in pages, the last quarter second shaky. Bounded (LUMINA_WEB_LIMIT, 180 s).
//   1. ⏎ on the draft (Follow through the clip) starts one track, with the clip's path in the shoot, the shape's kind and box and the
//      time on show, and sends no frame from the page (no .follow).
//   2. The page fetches every followed frame, page by page; the line says every frame and how much is worth a look;
//      the outline is drawn; the facts say where the shape is.
//   3. Save matte names the track and sends no outlines.
//   4. The strip under the scrub bar shows the shaky stretch; } goes to it; with the shape chosen there, Fix this
//      stretch follows it again on the Mac from that frame through the stretch, and the strip is sure after.
//   5. Let go ends the track.
//
//   node Tests/web/skim-track-browser.mjs        # needs ffmpeg and Playwright's Chromium
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { pw, ROOT, deadline } from './lib.mjs';

deadline('skim-track-browser', 180);
const T = fs.mkdtempSync(path.join(os.tmpdir(), 'skim-track-')), page = path.join(T, 'preview.html'), dir = path.join(T, 'shoot');
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
  const frames = Array.from({length:48}, (_, k) => ({t:k / 24, box:shapes[0].box, held:true, sure:k >= 42 ? 'shaky' : 'sure', outline:shapes[0].outline}));
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

await p.keyboard.press('o');
for (let k = 0; k < 20 && !(await p.$('[data-ol="subject"]')); k++) await p.waitForTimeout(250);
await p.click('[data-ol="subject"]'); await p.waitForTimeout(300);
{ const sel = await p.evaluate(() => document.querySelector('[data-lumina="viewer-selections"]')?.innerText || ''); ok(/⏎ to follow, esc to let go/.test(sel), 'the draft says how to go on: ' + JSON.stringify(sel)); }
await p.keyboard.press('Enter');
for (let k = 0; k < 120 && !/ followed/.test(await say()); k++) await p.waitForTimeout(250);
const Tr = await p.evaluate(() => window.__track), Po = (await p.evaluate(() => window.__poll)), Fo = await p.evaluate(() => window.__f);
ok(Tr.length === 1 && /C0001\.MP4$/.test(Tr[0].path) && Tr[0].start.kind === 'subject' && Tr[0].start.box.join() === '0.4,0.3,0.2,0.4' && typeof Tr[0].t === 'number', 'one track, with the path, kind, box and time: ' + JSON.stringify(Tr));
ok(Fo.length === 0, 'no frame sent from the page: ' + Fo.length);
ok(Po.length >= 3 && Po.every(q => q.id === Tr[0].id) && Po[Po.length - 1].from >= 32, 'polled page by page: ' + Po.map(q => q.from).join(' '));
ok(/Subject followed · every frame · in 100% of the clip · 13% worth a look/.test(await say()), 'the line: ' + JSON.stringify(await say()));
const lit = await p.evaluate(() => { const c = document.querySelector('[data-lumina="viewer-outlines"]'), d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data; let n = 0; for (let i = 0; i < d.length; i += 4) if (d[i + 3] && d[i] > 200 && d[i + 1] > 150 && d[i + 2] < 160) n++; return n; });
ok(lit > 200, 'the followed outline is drawn: ' + lit + ' pixels');
const shapeLine = await p.evaluate(() => document.body.innerText.match(/shape\s*\n?\s*Subject · [^\n]+/)?.[0] || '');
ok(/Subject · in 100% of the clip · 13% worth a look/.test(shapeLine), 'the facts: ' + JSON.stringify(shapeLine));
await p.click('[data-lumina="follow-matte"]');
for (let k = 0; k < 20 && !/matte saved/.test(await say()); k++) await p.waitForTimeout(150);
const M = await p.evaluate(() => window.__matte);
ok(M.length === 1 && M[0].track === Tr[0].id && !('samples' in M[0]) && M[0].frames === 48, 'the matte names the track: ' + JSON.stringify(M));
ok(/matte saved · C0001 matte\.mov/.test(await say()), 'the line: ' + JSON.stringify(await say()));
ok((await p.evaluate(() => window.__end)).length === 0, 'the track is kept while the follow is');
const strip = await p.evaluate(() => [...document.querySelectorAll('[data-lumina="follow-strip"] [data-sure]')].map(e => e.getAttribute('data-sure')));
ok(strip.join() === 'sure,shaky', 'the strip under the scrub bar: ' + strip.join());
ok(!(await p.$('[data-lumina="follow-fix"]')), 'no fix on a sure frame');
await p.keyboard.press('}'); await p.waitForTimeout(900);
const sub = await p.evaluate(() => document.querySelector('[data-lumina="clip-row"]')?.innerText.match(/\d+:\d+[:.]\d+ of/)?.[0] || '');
ok(!!sub, '} went to the shaky stretch: ' + sub);
for (let k = 0; k < 20 && !(await p.$('[data-ol="subject"]')); k++) await p.waitForTimeout(250);
if (!(await p.evaluate(() => document.querySelector('[data-ol="subject"]')?.getAttribute('aria-pressed') === 'true'))) { await p.click('[data-ol="subject"]'); await p.waitForTimeout(300); }
for (let k = 0; k < 20 && !(await p.$('[data-lumina="follow-fix"]')); k++) await p.waitForTimeout(200);
ok(!!(await p.$('[data-lumina="follow-fix"]')), 'on the shaky frame with the shape chosen: Fix this stretch');
await p.screenshot({path:path.join(T, 'strip.png')});
await p.click('[data-lumina="follow-fix"]');
for (let k = 0; k < 40 && !(await p.evaluate(() => [...document.querySelectorAll('[data-lumina="follow-strip"] [data-sure]')].every(e => e.getAttribute('data-sure') === 'sure'))); k++) await p.waitForTimeout(200);
const Fx = (await p.evaluate(() => window.__track)).filter(x => x.fix);
ok(Fx.length === 1 && Fx[0].fix.patch === Tr[0].id && Math.abs(Fx[0].fix.from - 41 / 24) < 1e-3 && Fx[0].fix.to === 2 && Fx[0].t >= Fx[0].fix.from, 'the fix: the track, from the last sure frame to the end: ' + JSON.stringify(Fx));
const strip2 = await p.evaluate(() => [...document.querySelectorAll('[data-lumina="follow-strip"] [data-sure]')].map(e => e.getAttribute('data-sure')));
ok(strip2.join() === 'sure', 'after the fix the strip is sure: ' + strip2.join());
ok(/in 100% of the clip/.test(await say()) && !/worth a look/.test(await say()), 'the line: ' + JSON.stringify(await say()));
ok((await p.evaluate(() => window.__end)).length === 1, 'the fix is ended on the Mac once in');
await p.screenshot({path:path.join(T, 'track.png')});
await p.click('[data-lumina="follow-drop"]'); await p.waitForTimeout(300);
const E = await p.evaluate(() => window.__end);
ok(E.length === 2 && E[1] === Tr[0].id, 'Let go ends the track: ' + JSON.stringify(E));
ok(errs.length === 0, 'no page errors: ' + errs.join(' | '));
console.log('screenshot ' + path.join(T, 'track.png'));
await b.close();
console.log(fails ? fails + ' failed' : 'all ok');
process.exit(fails ? 1 : 0);
