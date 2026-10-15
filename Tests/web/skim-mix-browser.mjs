// Clips from several places, and Add clips (LOCAL-CHANGES 282), in a real browser: the web preview build in headless
// Chromium over clips made here with ffmpeg. Open with clips in two folders a week apart shows the notice by day and
// folder, as rows that light when they go in (Export's look); a click on a day leaves it out; a Live Photo's movie starts unticked; one folder opens with no notice.
// During Skim, Add clips and a drop on the window put more clips in the shoot with the marks kept, and clips already
// there are left out. Bounded (LUMINA_WEB_LIMIT, 150 s).
//
//   node Tests/web/skim-mix-browser.mjs        # needs ffmpeg and Playwright's Chromium
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { pw, ROOT, deadline } from './lib.mjs';

deadline('skim-mix-browser', 180);
const T = fs.mkdtempSync(path.join(os.tmpdir(), 'skim-mix-')), page = path.join(T, 'preview.html');
execFileSync('python3', [path.join(ROOT, 'Scripts/build-skim-preview.py'), page], {stdio:'ignore'});
const clip = (file, hue, when) => { fs.mkdirSync(path.dirname(file), {recursive:true}); execFileSync('ffmpeg', ['-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24:duration=2', '-vf', 'hue=h=' + hue, '-c:v', 'libvpx-vp9', '-b:v', '300k', '-f', 'webm', file]); const t = new Date(when); fs.utimesSync(file, t, t); };
const dump = path.join(T, 'dump');
for (let i = 1; i <= 3; i++) clip(path.join(dump, 'day1', 'A00' + i + '.webm'), i * 40, '2026-10-01T10:0' + i + ':00');
for (let i = 1; i <= 2; i++) clip(path.join(dump, 'day9', 'B00' + i + '.webm'), 200 + i * 30, '2026-10-09T15:0' + i + ':00');
// a Live Photo: a still and its movie side by side
clip(path.join(dump, 'day9', 'IMG_0001.mov'), 300, '2026-10-09T15:30:00'); fs.writeFileSync(path.join(dump, 'day9', 'IMG_0001.HEIC'), 'x');
const phone = path.join(T, 'phone'); for (let i = 1; i <= 2; i++) clip(path.join(phone, 'IMG_10' + i + '.webm'), 90 + i * 20, '2026-10-01T12:0' + i + ':00');

let fails = 0; const ok = (c, what) => { console.log((c ? 'ok    ' : 'FAIL  ') + what); if (!c) fails++; };
const b = await pw.chromium.launch({executablePath:process.env.CHROMIUM || undefined}), p = await (await b.newContext({viewport:{width:1440, height:1000}})).newPage(), errs = [];
p.on('pageerror', e => errs.push(String(e)));
await p.goto('file://' + page); await p.waitForTimeout(1000);
const until = async (fn, ms = 20000) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { if (await p.evaluate(fn).catch(() => false)) return true; await p.waitForTimeout(150); } return false; };
const rows = () => p.evaluate(() => [...document.querySelectorAll('[data-lumina="mix-row"]')].map(r => ({kind:r.getAttribute('data-kind'), text:r.innerText.replace(/\s+/g, ' ').trim(), tick:r.querySelector('[data-lumina="mix-toggle"]').getAttribute('aria-checked'), on:r.getAttribute('data-on')})));
const nClips = () => p.evaluate(() => (document.querySelector('[data-lumina="shoot-line"]') || {}).innerText || '');

// 1. two folders a week apart: the notice, by day then folder
await p.setInputFiles('input[type=file][webkitdirectory]:not([data-lumina])', dump);
ok(await until(() => !!document.querySelector('[data-lumina="mix"]')), 'clips from two folders a week apart: the notice shows');
const head = await p.evaluate(() => document.querySelector('[data-lumina="mix-head"]').innerText);
ok(/^6 clips from 2 folders and 2 days, Oct 2026$/.test(head), 'it says how: ' + head);
let r = await rows();
ok(r.filter(x => x.kind === 'day').length === 2 && !r.some(x => x.kind === 'folder'), 'a row per day, no folder row when a day has one folder: ' + r.map(x => x.kind[0]).join(''));
ok(!/\bapart\b|\b\d{4} apart/.test(head) && r.every(x => !/undefined|NaN/.test(x.text)), 'no stray numbers in the wording');
const f9 = r.find(x => x.kind === 'day' && /day9/.test(x.text));
ok(f9 && f9.tick === 'mixed' && f9.on === 'mixed' && /1 Live Photo/.test(f9.text) && /2 of 3/.test(f9.text), 'the Live Photo movie starts left out, the day half lit: ' + (f9 && f9.text));
ok(r.find(x => x.kind === 'day' && /day1/.test(x.text)).on === 'true', 'a day that goes in whole is lit');
ok(!(await p.$('[data-lumina="mix-row"] input[type=checkbox]')), 'no checkboxes');
ok(/Open 5 clips/.test(await p.innerText('[data-lumina="mix-go"]')), 'the button says what goes in');
// unfurl day9 and see its clips
await p.locator('[data-lumina="mix-row"][data-kind="day"]').nth(1).locator('[data-lumina="mix-open"]').click(); await p.waitForTimeout(150);
r = await rows(); ok(r.filter(x => x.kind === 'clip').length === 3 && r.some(x => x.kind === 'clip' && /IMG_0001/.test(x.text) && x.on === 'false'), '› unfurls the day to its clips');
// a click on the Live Photo's clip row lights it
await p.locator('[data-lumina="mix-row"][data-kind="clip"]').filter({hasText:'IMG_0001'}).locator('[data-lumina="mix-toggle"]').click(); await p.waitForTimeout(150);
ok(/Open 6 clips/.test(await p.innerText('[data-lumina="mix-go"]')), 'a click on a clip puts it in');
await p.locator('[data-lumina="mix-row"][data-kind="clip"]').filter({hasText:'IMG_0001'}).locator('[data-lumina="mix-toggle"]').click(); await p.waitForTimeout(150);
// dim day1
await p.locator('[data-lumina="mix-row"][data-kind="day"]').nth(0).locator('[data-lumina="mix-toggle"]').click(); await p.waitForTimeout(150);
ok(/Open 2 clips/.test(await p.innerText('[data-lumina="mix-go"]')), 'a click on a day takes its clips out');
ok((await rows()).find(x => x.kind === 'day' && /day1/.test(x.text)).on === 'false', 'and dims it');
// esc goes back, nothing opened
await p.keyboard.press('Escape'); await p.waitForTimeout(200);
ok(!(await p.$('[data-lumina="mix"]')) && !(await p.$('[data-lumina="shoot-close"]')), 'esc goes back to Open with nothing opened');
// again, keep only day9 (2 clips), ⏎
await p.setInputFiles('input[type=file][webkitdirectory]:not([data-lumina])', dump);
await until(() => !!document.querySelector('[data-lumina="mix"]'));
await p.locator('[data-lumina="mix-row"][data-kind="day"]').nth(0).locator('[data-lumina="mix-toggle"]').click(); await p.waitForTimeout(100);
await p.keyboard.press('Enter');
ok(await until(() => !document.querySelector('[data-lumina="mix"]') && !!document.querySelector('[data-lumina="shoot-close"]')), '⏎ opens what is ticked');
ok(await until(() => { try { const a = JSON.parse(localStorage.getItem('lumina-skim:clock') || '[]')[0]; return !!(a && a.done != null); } catch (x) { return false; } }, 40000), 'the clips are read');
ok(/\b2 clips\b/.test(await nClips()), 'the shoot holds the 2 ticked clips: ' + await nClips());

// 2. mark one, then Add clips (two phone clips, one folder, one day: no notice)
await p.evaluate(() => { const k = window.luminaSkimKeep && JSON.parse(window.luminaSkimKeep.take() || 'null'); return k; });
await p.keyboard.press('k'); await p.waitForTimeout(400);
const marks0 = await p.evaluate(() => JSON.parse(window.luminaSkimKeep.take()).marks);
ok(Object.keys(marks0).length === 1, 'one clip marked before adding');
ok(!!(await p.$('[data-lumina="add-clips"]')), 'Add clips is in the top bar during Skim');
const [chooser] = await Promise.all([p.waitForEvent('filechooser'), p.click('[data-lumina="add-clips"]')]);
await chooser.setFiles(fs.readdirSync(phone).map(n => path.join(phone, n)));
ok(await until(() => /\b4 clips\b/.test((document.querySelector('[data-lumina="shoot-line"]') || {}).innerText || '')), 'two phone clips added: ' + await nClips());
const kept = await p.evaluate(() => JSON.parse(window.luminaSkimKeep.take()));
ok(JSON.stringify(kept.marks) === JSON.stringify(marks0), 'the mark is still there');
ok(kept.ks.length === 4, 'the shoot lists its 4 clips for a reload');
ok(await until(() => /2 clips added/.test(document.body.innerText)), 'the bar says 2 clips added');

// 2b. a clip there by mistake: ⌘⌫ takes it out of the shoot (not a cut), ⌘Z puts it back with its mark
await p.keyboard.press('m'); await p.waitForTimeout(300);
const marked = JSON.parse(await p.evaluate(() => window.luminaSkimKeep.take())), curK = marked.cur;
await p.keyboard.press('Control+Backspace');
ok(await until(() => /\b3 clips\b/.test((document.querySelector('[data-lumina="shoot-line"]') || {}).innerText || '')), '⌘⌫ takes the clip out of the shoot: ' + await nClips());
const outK = JSON.parse(await p.evaluate(() => window.luminaSkimKeep.take()));
ok(outK.ks.length === 3 && outK.ks.indexOf(curK) < 0 && !outK.marks[curK], 'it leaves the shoot list and its mark goes with it');
ok(/out of the shoot/.test(await p.evaluate(() => document.body.innerText)), 'the bar says so, and that the file stays');
await p.keyboard.press('Control+z');
ok(await until(() => /\b4 clips\b/.test((document.querySelector('[data-lumina="shoot-line"]') || {}).innerText || '')), '⌘Z puts it back');
ok(!!marked.marks[curK] && JSON.parse(await p.evaluate(() => window.luminaSkimKeep.take())).marks[curK] === marked.marks[curK], 'with its mark: ' + marked.marks[curK]);
// 3. the same clips dropped on the window: already here, nothing added
const drop = async files => {
  const dt = await p.evaluateHandle(async fs => { const d = new DataTransfer(); for (const f of fs) d.items.add(new File([new Uint8Array(f.b)], f.n, {type:'video/webm', lastModified:f.t})); return d; },
    files.map(f => ({n:path.basename(f), b:[...fs.readFileSync(f)], t:fs.statSync(f).mtimeMs})));
  await p.dispatchEvent('[data-screen-label="Skim"]', 'dragenter', {dataTransfer:dt});
  await p.dispatchEvent('[data-screen-label="Skim"]', 'dragover', {dataTransfer:dt});
  const hot = !!(await p.$('[data-lumina="add-drop"]'));
  await p.dispatchEvent('[data-screen-label="Skim"]', 'drop', {dataTransfer:dt});
  return hot;
};
ok(await drop(fs.readdirSync(phone).map(n => path.join(phone, n))), 'dragging files over Skim shows where they will go');
ok(await until(() => /already in this shoot/.test(document.body.innerText)), 'clips already in the shoot are left out');
// 4. new clips dropped: added
const extra = path.join(T, 'extra'); clip(path.join(extra, 'C0009.webm'), 30, '2026-10-09T16:00:00');
await drop([path.join(extra, 'C0009.webm')]);
ok(await until(() => /\b5 clips\b/.test((document.querySelector('[data-lumina="shoot-line"]') || {}).innerText || '')), 'a dropped clip is added: ' + await nClips());
ok(!(await p.$('[data-lumina="add-drop"]')), 'the drop outline goes');
ok(JSON.parse(await p.evaluate(() => window.luminaSkimKeep.take())).dropped === true, 'with dropped clips in it the app does not reload the shoot (they can’t be reopened)');
// 5. Safari's Pick up where you were, with some of the clips not in the folder chosen: the same view, with what is missing
await p.evaluate(() => window.dispatchEvent(new Event('pagehide'))); await p.reload(); await p.waitForTimeout(1000);
ok(!!(await p.$('[data-lumina="resume"]')), 'after a reload Open offers the shoot back');
await p.setInputFiles('input[type=file][webkitdirectory]:not([data-lumina])', path.join(dump, 'day9'));
ok(await until(() => !!document.querySelector('[data-lumina="mix"]')), 'clips missing from the folder chosen: the view shows');
const rh = await p.evaluate(() => document.querySelector('[data-lumina="mix-head"]').innerText);
ok(/^Found 2 of the 5 clips in this shoot$/.test(rh), 'it says how many were found: ' + rh);
ok((await rows()).filter(x => x.kind === 'missing').length === 3, 'the missing clips are listed');
await p.keyboard.press('Enter');
ok(await until(() => /\b2 clips\b/.test((document.querySelector('[data-lumina="shoot-line"]') || {}).innerText || '')), 'the found clips open: ' + await nClips());
ok(!errs.length, 'no page errors' + (errs.length ? ': ' + errs.join(' | ') : ''));
await b.close(); fs.rmSync(T, {recursive:true, force:true});
process.exit(fails ? 1 : 0);
