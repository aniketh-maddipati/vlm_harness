// The Stills web preview (what lumina-still.pages.dev serves), built by Scripts/build-stills-preview.sh
// and opened in headless Chromium from a plain static server: the page draws, Edit mounts, nothing
// throws, nothing is asked of any other host, and the content policy the build writes refuses nothing
// the page needs. Babel is not in the site: a page that grew JSX fails here, not in front of a viewer.
//
//   node Tests/web/stills-preview.mjs
import { execFileSync } from 'child_process';
import fs from 'fs';
import http from 'http';
import os from 'os';
import path from 'path';
import { ROOT, deadline, pw } from './lib.mjs';

deadline('stills-preview', 120);
const site = fs.mkdtempSync(path.join(os.tmpdir(), 'lumina-stills-site-'));
execFileSync('bash', [path.join(ROOT, 'Scripts/build-stills-preview.sh'), site], { stdio: 'pipe' });

// The design's sample stills (uploads/…) are not in the repo. The server leaves them out at first, as the real site does
// (Open must then offer a folder, not the sample card), then serves one small JPEG for every name (Edit needs a shoot).
let stills = false;
const STILL = Buffer.from('/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=', 'base64');
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.txt': 'text/plain' };
const server = http.createServer((req, res) => {
  let rel = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (rel.endsWith('/')) rel += 'index.html';
  if (stills && /^\/uploads\/[^/]+\.jpe?g$/i.test(rel)) { res.writeHead(200, { 'Content-Type': 'image/jpeg' }); res.end(STILL); return; }
  const file = path.join(site, path.normalize(rel));
  if (!file.startsWith(site) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream' });
  res.end(fs.readFileSync(file));
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const origin = 'http://127.0.0.1:' + server.address().port;

let failed = 0;
const check = (ok, what, detail = '') => { console.log((ok ? 'ok    ' : 'FAIL  ') + what + (ok || !detail ? '' : '\n      ' + detail)); if (!ok) failed++; };

const browser = await pw.chromium.launch();
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
const errors = [], outside = [], missing = [], asked = [];
page.on('pageerror', (e) => errors.push(String(e)));
// The design's sample photos (uploads/DSC….jpg) are not in the repo: the sample shoot draws without them.
const sample = (u) => /\/uploads\/[^/]+\.jpe?g$/i.test(u);
page.on('console', (m) => { if (m.type() === 'error' && !sample(m.location().url || '')) errors.push(m.text()); });
page.on('request', (r) => { const u = r.url(); asked.push(u); if (!u.startsWith(origin) && !/^(blob|data):/.test(u)) outside.push(u); });
page.on('response', (r) => { if (r.status() >= 400 && !sample(r.url())) missing.push(r.status() + ' ' + r.url()); });
await page.addInitScript(() => {
  window.__refused = [];
  document.addEventListener('securitypolicyviolation', (e) => window.__refused.push(e.violatedDirective + ' ' + e.blockedURI));
});

await page.goto(origin + '/', { waitUntil: 'load' });
await page.waitForFunction(() => /Lumina/.test(document.body.innerText) && /Open a card/.test(document.body.innerText), null, { timeout: 30000 })
  .then(() => check(true, 'the page draws'), (e) => check(false, 'the page draws', String(e).split('\n')[0]));
check(await page.evaluate(() => !!(window.luminaPreview && window.luminaBuild)), 'it knows it is the web preview and which build');
check((await page.locator('[data-lumina="build"]').innerText()).startsWith('build '), 'the build mark is in the corner');
check(await page.locator('meta[http-equiv="Content-Security-Policy"]').count() === 1, 'the content policy is in the page');

// No stills on the site: the page finds out in the background and Open offers a folder, not the sample card.
await page.waitForFunction(() => /Folder or card/.test(document.body.innerText) && !/SONY-A7M4/.test(document.body.innerText), null, { timeout: 5000 })
  .then(() => check(true, 'without the sample stills Open drops the sample card'), () => check(false, 'without the sample stills Open drops the sample card'));
// Every visitor's browser is missing them, so the notice saying so is for the developer only (?debug).
check(await page.locator('[data-lumina="no-sample"]').count() === 0, 'and shows visitors no notice about it');
await page.goto(origin + '/?debug=1', { waitUntil: 'load' });
await page.locator('[data-lumina="no-sample"]').waitFor({ state: 'visible', timeout: 5000 })
  .then(() => check(true, 'with ?debug it says why'), () => check(false, 'with ?debug it says why'));

// Shoots are remembered for the day only: a stamp from another day forgets every shoot's storage, and keeps prefs.
await page.goto(origin + '/', { waitUntil: 'load' });
await page.evaluate(() => {
  localStorage.setItem('lumina-v4-day', '2000-01-01');
  for (const k of ['lumina-sets-v7', 'lumina-v4-shoot:a|1|x|y', 'lumina-v4-recents', 'lumina-v4-names', 'lumina-v4-seen',
    'lumina-v4-moves:lumina-sets-v7', 'lumina-edit.sample', 'lumina.edit.v21.state']) localStorage.setItem(k, '{}');
  for (const k of ['lumina-prefs', 'lumina-v4-handoff', 'lumina-v4-toured', 'lumina.edit.intro.v1']) localStorage.setItem(k, '{}');
});
await page.reload({ waitUntil: 'load' });
await page.waitForFunction(() => /Folder or card/.test(document.body.innerText), null, { timeout: 10000 }).catch(() => {});
const kept = await page.evaluate(() => Object.keys(localStorage).sort());
const today = await page.evaluate(() => { const d = new Date(); return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); });
check(!kept.some((k) => /^(lumina-sets-v|lumina-v4-(shoot|recents|names|seen|moves)\b|lumina-edit\.|lumina\.edit\.v21\.state)/.test(k)), 'a new day forgets every shoot', kept.join(', '));
check(['lumina-prefs', 'lumina-v4-handoff', 'lumina-v4-toured', 'lumina.edit.intro.v1'].every((k) => kept.includes(k)), 'and keeps prefs and first-run flags', kept.join(', '));
check(await page.evaluate((t) => localStorage.getItem('lumina-v4-day') === t, today), 'and stamps today');
await page.evaluate(() => localStorage.setItem('lumina-v4-shoot:b|1|x|y', '{}'));
await page.reload({ waitUntil: 'load' });
check(await page.evaluate(() => localStorage.getItem('lumina-v4-shoot:b|1|x|y') === '{}'), 'the same day keeps a shoot');

stills = true;
await page.reload({ waitUntil: 'load' });
await page.waitForFunction(() => /SONY-A7M4/.test(document.body.innerText), null, { timeout: 10000 })
  .then(() => check(true, 'with them it keeps the sample card'), () => check(false, 'with them it keeps the sample card'));
await page.waitForTimeout(800);
check(/SONY-A7M4/.test(await page.evaluate(() => document.body.innerText)), 'and still has it once they have loaded');
check(await page.locator('[data-lumina="no-sample"]').count() === 0, 'with no notice');

// Pick: ⇧⏎ opens the shoot card (with its keys), ⇧⏎ again closes it, holding ⇧ opens nothing.
await page.keyboard.press('Escape');
await page.evaluate(() => window.luminaCommand && window.luminaCommand('stepCull'));
await page.waitForTimeout(600);
const card = page.locator('[data-lumina="sources"]');
await page.keyboard.press('Shift+Enter'); await page.waitForTimeout(300);
check(await card.isVisible() && await page.locator('[data-lumina="sources-keys"]').isVisible(), '⇧⏎ in Pick opens the shoot card, with ⇧⏎ and esc on it');
await page.keyboard.press('Shift+Enter'); await page.waitForTimeout(300);
check(!(await card.count()), '⇧⏎ again closes it');
await page.keyboard.down('Shift'); await page.waitForTimeout(700);
check(!(await card.count()), 'holding ⇧ opens nothing');
await page.keyboard.up('Shift');

// Edit is its own page, fetched when the step is first shown: ⌘3 as in the app's menu, after the first-run card.
await page.keyboard.press('Escape');
await page.evaluate(() => window.luminaCommand && window.luminaCommand('stepEdit'));
await page.keyboard.press('Meta+3');
await page.keyboard.press('Control+3');
const editAsked = () => asked.some((u) => decodeURIComponent(u).endsWith('/Lumina Edit v23.dc.html'));
for (let i = 0; i < 40 && !editAsked(); i++) await page.waitForTimeout(250);
check(editAsked(), 'Edit is fetched from the site when its step opens');
await page.waitForTimeout(1500);

// A newer build on the site: the notice shows, Later hides it until a newer one still, Refresh reloads.
const stale = page.locator('[data-lumina="stale"]');
check(!(await stale.isVisible()), 'no new-build notice while the site has this build');
fs.writeFileSync(path.join(site, 'version.txt'), 'deadbeef 2026-01-01T00:00:00Z\n');
await page.evaluate(() => window.luminaStaleCheck());
await stale.waitFor({ state: 'visible', timeout: 5000 }).then(() => check(true, 'a newer build on the site shows the notice'), () => check(false, 'a newer build on the site shows the notice'));
await page.locator('[data-lumina="stale-later"]').click();
await page.evaluate(() => window.luminaStaleCheck()); await page.waitForTimeout(500);
check(!(await stale.isVisible()), 'Later hides it while that build is the newest');
fs.writeFileSync(path.join(site, 'version.txt'), 'feedface 2026-01-02T00:00:00Z\n');
await page.evaluate(() => window.luminaStaleCheck());
await stale.waitFor({ state: 'visible', timeout: 5000 }).then(() => check(true, 'a newer build still shows it again'), () => check(false, 'a newer build still shows it again'));
const reloaded = page.waitForEvent('load', { timeout: 10000 }).then(() => true, () => false);
await page.locator('[data-lumina="stale-go"]').click();
check(await reloaded, 'Refresh reloads the page');

check(errors.length === 0, 'no page error', errors.slice(0, 5).join('\n      '));
check(missing.length === 0, 'every file it asks for is there', missing.slice(0, 5).join('\n      '));
check(outside.length === 0, 'nothing asked of another host', outside.slice(0, 5).join('\n      '));
const refused = await page.evaluate(() => window.__refused);
check(refused.length === 0, 'the content policy refuses nothing the page needs', refused.slice(0, 5).join('\n      '));
check(!fs.existsSync(path.join(site, 'vendor', 'babel.min.js')) && !asked.some((u) => /babel/.test(u)), 'Babel is neither shipped nor asked for');

await browser.close();
server.close();
fs.rmSync(site, { recursive: true, force: true });
console.log(failed ? `\n${failed} FAILED` : '\nall ok');
process.exit(failed ? 1 : 0);
