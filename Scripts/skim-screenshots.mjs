#!/usr/bin/env node
// The README's three Skim screenshots, taken from the web preview instead of by hand: the preview is built
// (Scripts/build-skim-preview.py, what lumina-skim.pages.dev serves), a folder of clips is opened through
// the page's own file input, the clips are marked keep, maybe, (left), keep, cut, (left) in turn, and three screens are
// written as JPEGs:
//   skim-marked.jpg   Skim with the clips marked and sorted into the dock
//   skim-viewer.jpg   the Viewer on the first clip, with its measures
//   skim-export.jpg   Export for Final Cut
//
//   node Scripts/skim-screenshots.mjs <clips folder>                         → docs/screenshots, 1440 × 900
//   node Scripts/skim-screenshots.mjs <clips> --out <dir> --scale 2          → 2880 × 1800 (the App Store size)
//
// The README's set is taken on 20-second copies of the T7 clips. Clips are read in the browser, as a visitor's
// would be; nothing is uploaded. Google Chrome by default (H.264); LUMINA_BROWSER=chromium uses Playwright's
// Chromium, which plays WebM only. The page's build stamp is hidden in the images. Bounded (LUMINA_WEB_LIMIT, 180 s).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { ROOT, deadline, pw } from '../Tests/web/lib.mjs';

deadline('skim-screenshots', 180);
const args = process.argv.slice(2), opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args.splice(i, 2)[1] : d; };
const out = path.resolve(opt('--out', path.join(ROOT, 'docs/screenshots')));
const scale = +opt('--scale', 1);
const clips = args[0] && path.resolve(args[0]);
if (!clips || !fs.statSync(clips, {throwIfNoEntry: false})?.isDirectory()) {
  console.error('usage: node Scripts/skim-screenshots.mjs <clips folder> [--out dir] [--scale n]'); process.exit(2);
}

const T = fs.mkdtempSync(path.join(os.tmpdir(), 'skim-shots-')), html = path.join(T, 'preview.html');
execFileSync('python3', [path.join(ROOT, 'Scripts/build-skim-preview.py'), html], {stdio: 'ignore'});
const browser = await pw.chromium.launch(process.env.LUMINA_BROWSER === 'chromium' ? {} : {channel: 'chrome'});
const page = await (await browser.newContext({viewport: {width: 1440, height: 900}, deviceScaleFactor: scale})).newPage();
const errors = [];
page.on('pageerror', e => errors.push(String(e)));
const wait = ms => page.waitForTimeout(ms);
const press = async (k, ms = 250) => { await page.keyboard.press(k); await wait(ms); };
const until = async (fn, ms, what) => {
  for (const end = Date.now() + ms; Date.now() < end; await wait(250)) if (await page.evaluate(fn).catch(() => false)) return;
  throw new Error('gave up waiting for ' + what);
};
const shoot = async name => {
  await wait(600); // thumbnails and the dock settle
  const f = path.join(out, name);
  await page.screenshot({path: f, type: 'jpeg', quality: 88});
  console.log(f);
};

try {
  await page.goto('file://' + html);
  await until(() => !!document.querySelector('[data-lumina="drop"]'), 15000, 'the Open screen');
  await page.addStyleTag({content: '[data-lumina="build"]{display:none!important}'});
  await page.setInputFiles('input[type=file]', clips);
  await until(() => { try { const c = JSON.parse(localStorage.getItem('lumina-skim:clock') || '[]')[0]; return !!(c && c.done != null); } catch (e) { return false; } }, 120000, 'the clips to be read');
  const n = await page.evaluate(() => document.querySelectorAll('[data-gi]').length);
  if (!n) throw new Error('no clips listed from ' + clips);
  fs.mkdirSync(out, {recursive: true});

  // Clips level (one tile per clip), first clip current, then keep / keep / maybe / cut down the folder.
  const tab = page.locator('[data-lumina="levels"] [role=tab]').nth(1);
  if (await tab.count()) await tab.click(); else await page.click('[data-gi="0"]');
  await wait(300);
  await page.click('[data-gi="0"]'); await wait(300);
  for (let i = 0; i < n; i++) { const k = ['k', 'm', '', 'k', 'c', ''][i % 6]; if (k) await press(k); if (i < n - 1) await press('ArrowRight'); }
  // the page measures each clip after the read ("filling in detail · 6 of 12"): shoot once that is done
  await until(() => !/filling in detail/.test(document.body.innerText), 120000, 'the clips\' detail').catch(() => {});
  await page.click('[data-gi="0"]');
  await shoot('skim-marked.jpg');

  await page.dblclick('[data-gi="0"]'); await wait(1500); // the Viewer: wait for the frame and the measures
  await shoot('skim-viewer.jpg');
  await press('Escape', 400);

  const ex = page.locator('[data-lumina="steps"] >> text=Export').last();
  await ex.click(); await wait(800);
  await shoot('skim-export.jpg');
} catch (e) {
  console.error('FAIL  ' + (e && e.message || e));
  errors.push('screenshots: ' + (e && e.message || e));
}
await browser.close();
fs.rmSync(T, {recursive: true, force: true});
if (errors.length) { console.error(errors.join('\n')); process.exit(1); }
