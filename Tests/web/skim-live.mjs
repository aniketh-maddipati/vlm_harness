// The Skim web preview as a visitor gets it: the deployed address (lumina-skim.pages.dev by default)
// opened in a real browser, with the same steps Tests/web/skim-engine-check.js runs on a local build:
// the Open screen draws, four clips handed to the page's file input are read, decoded and timed, K marks
// one, Export builds a Final Cut file the page checks as well formed, and no page error. On top of that,
// for the deployed site only: version.txt answers, the build stamp in the corner matches it, the page asks
// no host but its own for anything (the clips are given to it here, never fetched from anywhere), and the
// response carries the noindex header the deploy writes.
//
//   node Tests/web/skim-live.mjs [url]              default https://lumina-skim.pages.dev/
//   LUMINA_LIVE_EXPECT=<short hash> node …          also fail unless the address serves that commit
//   LUMINA_BROWSER=chromium node …                  Playwright's Chromium instead of Google Chrome
//   LUMINA_LIVE_CLIPS=<dir> node …                  other clips (Playwright's Chromium needs WebM)
//
// Google Chrome by default because the clips are H.264 and Playwright's own Chromium has no H.264.
// Bounded (LUMINA_WEB_LIMIT, 120 s).
import fs from 'node:fs';
import path from 'node:path';
import { ROOT, deadline, pw } from './lib.mjs';

deadline('skim-live', 120);
const url = new URL(process.argv[2] || 'https://lumina-skim.pages.dev/');
const expect = process.env.LUMINA_LIVE_EXPECT || '';
const CLIPS = process.env.LUMINA_LIVE_CLIPS || path.join(ROOT, 'Tests/web/fixtures/skim-clips');
const names = fs.readdirSync(CLIPS).filter(n => /\.(mp4|webm)$/i.test(n)).sort();

let fails = 0;
const ok = (c, what) => { console.log((c ? 'ok    ' : 'FAIL  ') + what); if (!c) fails++; return !!c; };

const version = await fetch(new URL('version.txt', url)).then(r => r.ok ? r.text() : '').catch(() => '');
const hash = version.trim().split(/\s+/)[0] || '';
ok(hash, 'version.txt answers: ' + (version.trim() || 'nothing'));
if (expect) ok(hash === expect, 'the address serves ' + expect + ' (it serves ' + (hash || 'nothing') + ')');

const browser = await pw.chromium.launch(process.env.LUMINA_BROWSER === 'chromium' ? {} : {channel: 'chrome'});
const page = await (await browser.newContext({viewport: {width: 1440, height: 900}})).newPage();
const errors = [], elsewhere = [];
page.on('pageerror', e => errors.push(String(e)));
// The check fetches clips/<name> to build File objects; answer those here, so no clip is ever on the site.
await page.route('**/*', route => {
  const u = new URL(route.request().url());
  if (u.origin === url.origin && u.pathname.startsWith('/clips/')) {
    const f = path.join(CLIPS, path.basename(u.pathname));
    return fs.existsSync(f) ? route.fulfill({status: 200, contentType: /\.webm$/i.test(f) ? 'video/webm' : 'video/mp4', body: fs.readFileSync(f)}) : route.fulfill({status: 404});
  }
  if (!['data:', 'blob:'].includes(u.protocol) && u.origin !== url.origin) { elsewhere.push(u.href); return route.abort(); }
  return route.continue();
});
const res = await page.goto(url.href, {waitUntil: 'load'});
ok(res && res.ok(), 'the page answers ' + (res ? res.status() : 'nothing'));
ok(res && /noindex/.test(res.headers()['x-robots-tag'] || ''), 'kept out of search results (X-Robots-Tag: ' + (res && res.headers()['x-robots-tag'] || 'none') + ')');
const stamp = await page.evaluate(() => window.luminaBuild || '');
ok(stamp && stamp === hash, 'the build stamp matches version.txt (' + (stamp || 'none') + ')');

await page.addScriptTag({content: fs.readFileSync(path.join(ROOT, 'Tests/web/skim-engine-check.js'), 'utf8')});
const r = await page.evaluate(n => window.__skimEngineCheck(n), names);
for (const [c, what] of r.steps) ok(c, what);
ok(!errors.length, 'no uncaught errors' + (errors.length ? ': ' + errors.slice(0, 5).join(' | ') : ''));
ok(!elsewhere.length, 'nothing asked of another host' + (elsewhere.length ? ': ' + [...new Set(elsewhere)].slice(0, 5).join(', ') : ''));
console.log(r.ua);
await browser.close();
console.log(fails ? `${fails} failed on ${url.href}` : `all passed on ${url.href}`);
process.exit(fails ? 1 : 0);
