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
      prompt:(key, frame, points, stroke) => {
        window.__prompts.push({key, jpeg:/^\/9j\//.test(frame) && frame.length > 2000, points:points.map(p => ({x:+p.x.toFixed(3), y:+p.y.toFixed(3), in:p.in})), stroke:stroke ? stroke.length : 0});
        const c = points[0] || (stroke && stroke[Math.floor(stroke.length / 2)]), r = Math.max(0.05, 0.12 + 0.06 * (points.filter(p => p.in).length - 1) - 0.04 * points.filter(p => !p.in).length);
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
  ok(/click or brush over the thing you mean/.test(await say(p)), 'the line says to click: ' + JSON.stringify(await say(p)));
  await until(p, async () => /q:subject/.test(await pressed(p)));
  ok(await pressed(p) === 'q:subject:false q:background:false', 'one-tap chips from Vision\'s shapes, nothing chosen: ' + JSON.stringify(await pressed(p)));
  const r = await (await p.$('[data-lumina="viewer-outlines"]')).boundingBox();
  const at = (fx, fy) => p.mouse.click(r.x + r.width * fx, r.y + r.height * fy);
  await at(0.3, 0.5);
  ok(/first time/.test(await say(p)) || (await prompts(p)).length === 1, 'the first click says it is getting ready: ' + JSON.stringify(await say(p)));
  await until(p, async () => /outlined/.test(await say(p)));
  let q = await prompts(p);
  ok(q.length === 1 && q[0].jpeg && q[0].points.length === 1 && q[0].points[0].in === true, 'one click, one prompt, the frame as a JPEG: ' + JSON.stringify(q.map(x => x.points)));
  ok(Math.abs(q[0].points[0].x - 0.3) < 0.02 && Math.abs(q[0].points[0].y - 0.5) < 0.02, 'where it was clicked: ' + JSON.stringify(q[0].points[0]));
  ok(/^f[0-9a-z]+-\d+$/.test(q[0].key) && q[0].key.length <= 64, 'the frame\'s key: ' + q[0].key);
  ok(await pressed(p) === 'pick:true q:subject:false q:background:false', 'the outline is chosen: ' + await pressed(p));
  ok(/outlined · click outside to add, inside to take away · drag along the edge to redraw it · esc to undo/.test(await say(p)), 'the line says what a click does: ' + JSON.stringify(await say(p)));
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
  ok(/^pick:true/.test(await pressed(p)) && (await prompts(p)).length === 3, 'without asking again: ' + (await prompts(p)).length);
  await p.keyboard.press('Escape'); await p.waitForTimeout(300);
  await p.keyboard.press('Escape'); await p.waitForTimeout(300);
  ok(await pressed(p) === 'q:subject:false q:background:false', 'esc at the first click lets it go: ' + JSON.stringify(await pressed(p)));
  ok(/click or brush over the thing you mean/.test(await say(p)), 'and the line says to click again: ' + JSON.stringify(await say(p)));
  await at(0.6, 0.4);
  await until(p, async () => (await prompts(p)).length === 4 && /outlined/.test(await say(p)));
  q = await prompts(p);
  ok(q.length === 4 && q[3].points.length === 1, 'a click after that starts a new outline: ' + JSON.stringify(q[3] && q[3].points));
  // one tap: the Subject chip chooses Vision's subject in place of the outline; again lets it go; a click outlines again
  await p.click('[data-ol="q:subject"]'); await p.waitForTimeout(250);
  ok(await pressed(p) === 'q:subject:true q:background:false', 'Subject in one tap, the outline let go: ' + JSON.stringify(await pressed(p)));
  ok(/^Subject chosen · click the picture to outline something else instead/.test(await say(p)), 'the line says so: ' + JSON.stringify(await say(p)));
  await p.click('[data-ol="q:subject"]'); await p.waitForTimeout(250);
  ok(await pressed(p) === 'q:subject:false q:background:false', 'the same chip again lets it go: ' + JSON.stringify(await pressed(p)));
  await p.click('[data-ol="q:background"]'); await p.waitForTimeout(250);
  await at(0.6, 0.4);
  await until(p, async () => (await prompts(p)).length === 5 && /outlined/.test(await say(p)));
  ok(await pressed(p) === 'pick:true q:subject:false q:background:false' && (await prompts(p))[4].points.length === 1, 'a click after a chip outlines afresh: ' + JSON.stringify(await pressed(p)));
  // drawing by hand: a drag out from the outline's edge and back adds a bump; esc takes it back
  const pick = () => p.evaluate(() => { const b = [...document.querySelectorAll('[data-ol]')].find(x => x.getAttribute('data-ol') === 'pick'); return b ? b.getAttribute('aria-pressed') : ''; });
  const drag = async pts => { await p.mouse.move(r.x + r.width * pts[0][0], r.y + r.height * pts[0][1]); await p.mouse.down();
    for (const q of pts.slice(1)) await p.mouse.move(r.x + r.width * q[0], r.y + r.height * q[1], {steps:8}); await p.mouse.up(); await p.waitForTimeout(300); };
  const before = await area(), nb = (await prompts(p)).length;
  // the disc around (0.6, 0.4) has radius 0.12: its right edge is near x = 0.6 + 0.12 * 9/16
  const ex = 0.6 + 0.12 * 9 / 16;
  await drag([[ex, 0.36], [ex + 0.12, 0.3], [ex + 0.16, 0.4], [ex + 0.12, 0.5], [ex, 0.44]]);
  const bump = await area();
  ok(bump > before * 1.15, 'a drag out from the edge and back adds to the outline: ' + before + ' → ' + bump);
  ok((await prompts(p)).length === nb, 'drawing asks nothing of the Mac');
  ok(await pick() === 'true', 'the outline stays chosen: ' + await pick());
  await p.keyboard.press('Escape'); await p.waitForTimeout(300);
  const back = await area();
  ok(Math.abs(back - before) < before * 0.05, 'esc takes the drag back: ' + bump + ' → ' + back);
  // into the shape and back takes away
  await drag([[ex, 0.33], [ex - 0.05, 0.36], [ex - 0.08, 0.4], [ex - 0.05, 0.44], [ex, 0.47]]);
  const bay = await area();
  ok(bay !== before, 'a drag in from the edge redraws that stretch: ' + before + ' → ' + bay);
  await p.keyboard.press('Escape'); await p.waitForTimeout(200); await p.keyboard.press('Escape'); await p.waitForTimeout(300);
  ok(await pick() === '', 'esc again lets it go');
  // with nothing outlined, a drag draws a shape of its own
  await drag([[0.15, 0.2], [0.35, 0.2], [0.35, 0.45], [0.15, 0.45], [0.16, 0.22]]);
  ok(await pick() === 'true' && await area() > 3000, 'a drag on its own draws a shape: ' + await pick() + ' ' + await area());
  ok(/outlined/.test(await say(p)), 'and the line says it is outlined: ' + JSON.stringify(await say(p)));
  await p.screenshot({path:path.join(T, 'drawn.png')});
  // with nothing outlined, a stroke that doesn't come back round is a brush over the thing: the model outlines it
  await p.keyboard.press('Escape'); await p.waitForTimeout(300);
  const nbr = (await prompts(p)).length;
  await drag([[0.6, 0.3], [0.68, 0.36], [0.76, 0.32], [0.84, 0.38]]);
  await until(p, async () => (await prompts(p)).length === nbr + 1 && /outlined/.test(await say(p)));
  let bq = (await prompts(p))[nbr];
  ok(bq && bq.stroke >= 2 && bq.points.length === 0 && await pick() === 'true', 'a brush stroke outlines what it went over: ' + JSON.stringify(bq));
  // a click inside then takes away, sent with the same stroke
  await p.mouse.click(r.x + r.width * 0.72, r.y + r.height * 0.34);
  await until(p, async () => (await prompts(p)).length === nbr + 2);
  bq = (await prompts(p))[nbr + 1];
  ok(bq && bq.stroke >= 2 && bq.points.length === 1 && bq.points[0].in === false, 'a click after the stroke takes away, with the stroke: ' + JSON.stringify(bq));
  await p.screenshot({path:path.join(T, 'brushed.png')});
  ok(errs.length === 0, 'no page errors: ' + errs.join(' | '));
  console.log('screenshot ' + path.join(T, 'prompt.png'));
  await b.close();
}
{ // 3. the stretch a drag replaces (the page's own drSplice, on a disc): out and back adds, in and back takes away
  const src = fs.readFileSync(path.join(ROOT, 'design/handoff/lumina-skim/Lumina Skim v3.dc.html'), 'utf8');
  const m = /static drSplice\(L, i, j, path\) \{([\s\S]*?)\n  \}\n/.exec(src);
  ok(!!m, 'drSplice is in the page');
  if (m) {
    const splice = new Function('L', 'i', 'j', 'path', m[1]);
    const area = L => { let s = 0; for (let k = 0; k < L.length; k++) { const p = L[k], q = L[(k + 1) % L.length]; s += p[0] * q[1] - q[0] * p[1]; } return Math.abs(s) / 2; };
    const D = Array.from({length:24}, (_, i) => [0.5 + 0.1 * Math.cos(i / 24 * 2 * Math.PI), 0.5 + 0.1 * Math.sin(i / 24 * 2 * Math.PI)]);
    const near = p => D.reduce((b, q, i) => Math.hypot(q[0] - p[0], q[1] - p[1]) < Math.hypot(D[b][0] - p[0], D[b][1] - p[1]) ? i : b, 0);
    const run = P => area(splice(D, near(P[0]), near(P[P.length - 1]), P));
    ok(run([[0.6, 0.45], [0.7, 0.5], [0.6, 0.55]]) > area(D) * 1.1, 'out and back adds');
    ok(run([[0.6, 0.45], [0.55, 0.5], [0.6, 0.55]]) < area(D) * 0.97, 'in and back takes away');
    ok(Math.abs(run([[0.6, 0.55], [0.55, 0.5], [0.6, 0.45]]) - run([[0.6, 0.45], [0.55, 0.5], [0.6, 0.55]])) < 1e-9, 'either way round');
    ok(splice(D, 3, 3, [[0.6, 0.53], [0.62, 0.55]]).length === 25, 'a drag that starts and ends at one point keeps the rest');
  }
}
console.log(fails ? fails + ' failed' : 'all ok');
process.exit(fails ? 1 : 0);
