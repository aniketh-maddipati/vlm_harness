// Click to outline in the Skim Viewer (macOS 27, docs/masking/OUTLINING.md): the web preview build in headless
// Chromium over clips made here with ffmpeg, with stand-ins for the app's lumina.video.masks, .promptReady and .prompt
// (the bridge's skimMasks, skimPromptReady and skimPrompt). The prompt stand-in outlines a disc around the first
// click, wider for each click that adds and narrower for each one that takes away. Bounded (LUMINA_WEB_LIMIT, 180 s).
//   1. promptReady says 'no' (before macOS 27): a click chooses one of Vision's shapes, as before.
//   2. promptReady says 'download': O reads the frame once and skips Vision's finders; the line says to click.
//      A click outlines (one prompt, with the frame as a JPEG and one adding point); a click outside the outline adds
//      (two points, the second adding), one inside takes away (the third taking away); modifiers change nothing.
//      Esc undoes the last click without asking the Mac again; esc at the first click lets the outline go.
//   node Tests/web/skim-prompt-browser.mjs        # needs ffmpeg and Playwright's Chromium
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { pw, ROOT, deadline } from './lib.mjs';

deadline('skim-prompt-browser', 180);
const T = fs.mkdtempSync(path.join(os.tmpdir(), 'skim-prompt-')), page = path.join(T, 'preview.html'), dir = path.join(T, 'shoot');
execFileSync('python3', [path.join(ROOT, 'Scripts/build-skim-preview.py'), page], {stdio:'ignore'});
fs.mkdirSync(dir, {recursive:true});
for (let i = 1; i <= 4; i++) execFileSync('ffmpeg', ['-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24:duration=2', '-vf', 'hue=h=' + i * 11,
  '-c:v', 'libvpx-vp9', '-b:v', '300k', path.join(dir, 'C000' + i + '.MP4')]);

let fails = 0; const ok = (c, what) => { console.log((c ? 'ok    ' : 'FAIL  ') + what); if (!c) fails++; };
const disc = (cx, cy, r) => [Array.from({length:24}, (_, i) => [cx + r * Math.cos(i / 24 * 2 * Math.PI) * 9 / 16, cy + r * Math.sin(i / 24 * 2 * Math.PI)])];
const SHAPES = [{id:'subject', kind:'subject', score:0.9, area:0.1, box:[0.4, 0.3, 0.2, 0.4], outline:disc(0.5, 0.5, 0.2)},
  {id:'background', kind:'background', score:1, area:0.9, box:[0, 0, 1, 1], outline:[[[0, 0], [1, 0], [1, 1], [0, 1]], disc(0.5, 0.5, 0.2)[0].slice().reverse()]}];

async function open(ready) {
  const b = await pw.chromium.launch({executablePath:process.env.CHROMIUM || undefined}), ctx = await b.newContext({viewport:{width:1440, height:900}}), errs = [];
  await ctx.addInitScript(([shapes, ready]) => {
    window.__masks = 0; window.__prompts = [];
    const disc = (cx, cy, r) => [Array.from({length:24}, (_, i) => [cx + r * Math.cos(i / 24 * 2 * Math.PI) * 9 / 16, cy + r * Math.sin(i / 24 * 2 * Math.PI)])];
    window.lumina = {video:{
      masks:frame => { window.__masks++; return new Promise(r => setTimeout(() => r(/^\/9j\//.test(frame) ? shapes : null), 20)); },
      promptReady:() => Promise.resolve(ready),
      prompt:(key, frame, points) => {
        window.__prompts.push({key, jpeg:/^\/9j\//.test(frame) && frame.length > 2000, points:points.map(p => ({x:+p.x.toFixed(3), y:+p.y.toFixed(3), in:p.in}))});
        const c = points[0], r = Math.max(0.05, 0.12 + 0.06 * (points.filter(p => p.in).length - 1) - 0.04 * points.filter(p => !p.in).length);
        return new Promise(res => setTimeout(() => res({id:'pick', kind:'object', score:1, area:Math.PI * r * r * 9 / 16, box:[c.x - r * 9 / 16, c.y - r, r * 9 / 8, 2 * r], outline:disc(c.x, c.y, r)}), 30));
      }}};
  }, [SHAPES, ready]);
  const p = await ctx.newPage(); p.on('pageerror', e => errs.push(String(e)));
  await p.goto('file://' + page); await p.waitForTimeout(800);
  await p.setInputFiles('input[type=file]', dir);
  for (let k = 0; k < 60; k++) { await p.waitForTimeout(500); if (await p.evaluate(() => { try { const a = JSON.parse(localStorage.getItem('lumina-skim:clock') || '[]')[0]; return !!(a && a.done != null); } catch (x) { return false; } })) break; }
  await p.waitForTimeout(800);
  for (let k = 0; k < 4 && !(await p.$('[data-lumina="viewer-top"]')); k++) { await p.keyboard.press('Enter'); await p.waitForTimeout(600); }
  await p.waitForTimeout(1200);
  return {b, p, errs};
}
const say = p => p.evaluate(() => (document.querySelector('[data-lumina="viewer-selections"]')?.innerText || '').split('\n')[0]);
const pressed = p => p.evaluate(() => [...document.querySelectorAll('[data-ol]')].map(b => b.getAttribute('data-ol') + ':' + b.getAttribute('aria-pressed')).join(' '));
const prompts = p => p.evaluate(() => window.__prompts);
const until = async (p, test) => { for (let k = 0; k < 24; k++) { if (await test()) return true; await p.waitForTimeout(125); } return false; };

{ // 1. before macOS 27
  const {b, p, errs} = await open('no');
  await p.keyboard.press('o');
  await until(p, async () => /click a shape/.test(await say(p)));
  ok(/click a shape to choose it/.test(await say(p)), 'without the outliner, the line is as before: ' + JSON.stringify(await say(p)));
  const r = await (await p.$('[data-lumina="viewer-outlines"]')).boundingBox();
  await p.mouse.click(r.x + r.width * 0.5, r.y + r.height * 0.5); await p.waitForTimeout(300);
  ok(await pressed(p) === 'subject:true background:false', 'a click chooses Vision\'s shape: ' + await pressed(p));
  ok((await prompts(p)).length === 0, 'nothing was asked of the outliner');
  ok(errs.length === 0, 'no page errors: ' + errs.join(' | '));
  await b.close();
}
{ // 2. macOS 27
  const {b, p, errs} = await open('download');
  await p.keyboard.press('o');
  await until(p, async () => /click the thing/.test(await say(p)));
  ok(/click the thing you mean/.test(await say(p)), 'the line says to click: ' + JSON.stringify(await say(p)));
  ok(await p.evaluate(() => window.__masks) === 0, 'Vision\'s finders were not asked');
  ok(await pressed(p) === '', 'no chips before a click: ' + JSON.stringify(await pressed(p)));
  const r = await (await p.$('[data-lumina="viewer-outlines"]')).boundingBox();
  const at = (fx, fy) => p.mouse.click(r.x + r.width * fx, r.y + r.height * fy);
  await at(0.3, 0.5);
  ok(/first time/.test(await say(p)) || (await prompts(p)).length === 1, 'the first click says it is getting ready: ' + JSON.stringify(await say(p)));
  await until(p, async () => /outlined/.test(await say(p)));
  let q = await prompts(p);
  ok(q.length === 1 && q[0].jpeg && q[0].points.length === 1 && q[0].points[0].in === true, 'one click, one prompt, the frame as a JPEG: ' + JSON.stringify(q.map(x => x.points)));
  ok(Math.abs(q[0].points[0].x - 0.3) < 0.02 && Math.abs(q[0].points[0].y - 0.5) < 0.02, 'where it was clicked: ' + JSON.stringify(q[0].points[0]));
  ok(/^f[0-9a-z]+-\d+$/.test(q[0].key) && q[0].key.length <= 64, 'the frame\'s key: ' + q[0].key);
  ok(await pressed(p) === 'pick:true', 'the outline is chosen: ' + await pressed(p));
  ok(/outlined · click outside to add, inside to take away · esc to undo/.test(await say(p)), 'the line says what a click does: ' + JSON.stringify(await say(p)));
  const lit = await p.evaluate(() => { const c = document.querySelector('[data-lumina="viewer-outlines"]'), d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data; let n = 0; for (let i = 3; i < d.length; i += 4) if (d[i]) n++; return n; });
  ok(lit > 500, 'the outline and the click are drawn: ' + lit + ' pixels');
  // outside: adds (⌥ held, which changes nothing now)
  await p.keyboard.down('Alt'); await at(0.75, 0.5); await p.keyboard.up('Alt');
  await until(p, async () => (await prompts(p)).length === 2 && /outlined/.test(await say(p)));
  q = await prompts(p);
  ok(q.length === 2 && q[1].key === q[0].key && q[1].points.length === 2 && q[1].points[1].in === true, 'a click outside adds, ⌥ or not: ' + JSON.stringify(q[1] && q[1].points));
  // inside: takes away
  await at(0.3, 0.5);
  await until(p, async () => (await prompts(p)).length === 3 && /outlined/.test(await say(p)));
  q = await prompts(p);
  ok(q.length === 3 && q[2].points.length === 3 && q[2].points[2].in === false, 'a click inside takes away: ' + JSON.stringify(q[2] && q[2].points));
  await p.screenshot({path:path.join(T, 'prompt.png')});
  // esc: undo, then let go
  const area = () => p.evaluate(() => { const c = document.querySelector('[data-lumina="viewer-outlines"]'), d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data; let n = 0; for (let i = 0; i < d.length; i += 4) if (d[i + 3] > 30 && d[i] > 150 && d[i + 1] > 120 && d[i + 2] < 140) n++; return n; });
  const a3 = await area();
  await p.keyboard.press('Escape'); await p.waitForTimeout(300);
  const a2 = await area();
  ok(a2 > a3, 'esc undoes the last click (the outline grows back): ' + a3 + ' → ' + a2);
  ok(await pressed(p) === 'pick:true' && (await prompts(p)).length === 3, 'without asking again: ' + (await prompts(p)).length);
  await p.keyboard.press('Escape'); await p.waitForTimeout(300);
  await p.keyboard.press('Escape'); await p.waitForTimeout(300);
  ok(await pressed(p) === '', 'esc at the first click lets it go: ' + JSON.stringify(await pressed(p)));
  ok(/click the thing you mean/.test(await say(p)), 'and the line says to click again: ' + JSON.stringify(await say(p)));
  await at(0.6, 0.4);
  await until(p, async () => (await prompts(p)).length === 4 && /outlined/.test(await say(p)));
  q = await prompts(p);
  ok(q.length === 4 && q[3].points.length === 1, 'a click after that starts a new outline: ' + JSON.stringify(q[3] && q[3].points));
  ok(errs.length === 0, 'no page errors: ' + errs.join(' | '));
  console.log('screenshot ' + path.join(T, 'prompt.png'));
  await b.close();
}
console.log(fails ? fails + ' failed' : 'all ok');
process.exit(fails ? 1 : 0);
