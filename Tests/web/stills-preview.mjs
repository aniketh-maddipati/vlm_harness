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

const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.txt': 'text/plain' };
const server = http.createServer((req, res) => {
  let rel = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (rel.endsWith('/')) rel += 'index.html';
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

// Edit is its own page, fetched when the step is first shown: ⌘3 as in the app's menu, after the first-run card.
await page.keyboard.press('Escape');
await page.evaluate(() => window.luminaCommand && window.luminaCommand('stepEdit'));
await page.keyboard.press('Meta+3');
await page.keyboard.press('Control+3');
const editAsked = () => asked.some((u) => decodeURIComponent(u).endsWith('/Lumina Edit v23.dc.html'));
for (let i = 0; i < 40 && !editAsked(); i++) await page.waitForTimeout(250);
check(editAsked(), 'Edit is fetched from the site when its step opens');
await page.waitForTimeout(1500);

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
