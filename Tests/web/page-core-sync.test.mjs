// node Tests/web/page-core-sync.test.mjs
// The bundled design pages are in step with the scripts they load. Plain node: no browser, no window.
//   1. the seven page files are byte-identical in design/handoff/lumina-cull (authority) and Lumina/Sets/Web (bundle)
//   2. every <script src>, injected script, <dc-import> and fetch('./…') in the two pages names a bundled file that is
//      in Scripts/page_files.sh and in SetsSchemeHandler.pageFiles (both lists); nothing in PAGE_FILES is unreferenced
//   3. each script loads alone (none needs another's global at load time)
//   4. every LuminaCore / LuminaV4 / LuminaMeasure member the pages, the selftest and plumbing.js name exists in the
//      loaded script, as a function where it is called
//   5. the shapes the page leans on: buildShoot's result, the sample records, the ? sheet, the FAQ, facts
// Exports nothing references are listed, never failed. The selftest's key assertions are not run here.
import fs from 'node:fs'; import path from 'node:path'; import vm from 'node:vm'; import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const WEB = path.join(ROOT, 'Lumina/Sets/Web'), HANDOFF = path.join(ROOT, 'design/handoff/lumina-cull');
const read = (...p) => fs.readFileSync(path.join(...p), 'utf8');
let bad = 0;
const check = (name, ok, detail) => { console.log((ok ? 'ok  ' : 'FAIL') + ' ' + name + (ok || !detail ? '' : '\n     ' + detail)); if (!ok) bad++; };
const note = text => console.log('note ' + text);

// ——— the file lists ———
const sh = read(ROOT, 'Scripts/page_files.sh'), shVar = {};
for (const m of sh.matchAll(/^([A-Z_]+)="([^"]*)"/gm)) shVar[m[1]] = m[2];
const PAGE_FILES = [...(sh.match(/^PAGE_FILES=\(([^)]*)\)/m) || ['', ''])[1].matchAll(/"\$([A-Z_]+)"|"([^"]+)"|(\S+)/g)].map(m => m[1] ? shVar[m[1]] : m[2] || m[3]);
const PAGE = shVar.PAGE, EDIT = shVar.EDIT_PAGE;
check('Scripts/page_files.sh names the page, the Edit page and the page files', !!PAGE && !!EDIT && PAGE_FILES.length >= 5 && PAGE_FILES.every(Boolean), JSON.stringify(PAGE_FILES));

const swift = read(ROOT, 'Lumina/Sets/Core/SetsSchemeHandler.swift'), swConst = {};
for (const m of swift.matchAll(/static let (pageFile|editPageFile) = "([^"]+)"/g)) swConst[m[1]] = m[2];
const swLists = [...swift.matchAll(/static let pageFiles = \[([^\]]*)\]/g)].map(m => m[1].split(',').map(s => s.trim()).map(s => s.startsWith('"') ? s.slice(1, -1) : swConst[s]));
const same = (a, b) => JSON.stringify([...a].sort()) === JSON.stringify([...b].sort());
check('SetsSchemeHandler.pageFiles has a tools list and a Release list', swLists.length === 2, swLists.length + ' lists found');
const [swTools = [], swRelease = []] = swLists;
check('SetsSchemeHandler.pageFiles (DEBUG / LUMINA_TOOLS) = PAGE_FILES', same(swTools, PAGE_FILES), JSON.stringify(swTools) + ' vs ' + JSON.stringify(PAGE_FILES));
check('SetsSchemeHandler.pageFiles (Release) = PAGE_FILES without the selftest', same(swRelease, PAGE_FILES.filter(f => f !== 'lumina-selftest.js')), JSON.stringify(swRelease));

// ——— 1. bundle = handoff, byte for byte ———
for (const f of PAGE_FILES) {
  let ok = false, why = '';
  try { ok = fs.readFileSync(path.join(WEB, f)).equals(fs.readFileSync(path.join(HANDOFF, f))); if (!ok) why = 'the two copies differ'; } catch (e) { why = e.message; }
  check('byte-identical in handoff and bundle: ' + f, ok, why);
}

// ——— 2. what the pages load ———
// Asked for only by a prototype query or a prototype-only link; not part of the bundle.
const DEMO_ONLY = { 'data/lumina-shoot-unsplash.js': 'Edit, ?shoot=unsplash only', './uploads-index.json': 'the "open uploads" demo link', './uploads/': 'the "open uploads" demo link' };
const pages = { [PAGE]: read(WEB, PAGE), [EDIT]: read(WEB, EDIT) };
const referenced = new Set([PAGE]);
for (const [pg, text] of Object.entries(pages)) {
  const refs = [];
  for (const m of text.matchAll(/<script\b[^>]*\bsrc\s*=\s*["']([^"']+)["']/g)) refs.push(['<script src>', m[1]]);
  for (const m of text.matchAll(/\.src\s*=\s*(["'])([^"']+\.js)\1/g)) refs.push(['injected script', m[2]]);
  for (const m of text.matchAll(/<(?:dc|x)-import\b[^>]*\bname\s*=\s*"([^"{]+)"/g)) refs.push(['<dc-import>', './' + m[1] + '.dc.html']);
  for (const m of text.matchAll(/\bfetch\(\s*(["'`])(\.{0,2}\/?[^"'`]*)\1/g)) refs.push(['fetch', m[2]]);
  for (const m of text.matchAll(/\bimport\(\s*(["'`])([^"'`]+)\1/g)) refs.push(['import()', m[2]]);
  check(pg + ': loads something (' + refs.length + ' references found)', refs.length > 0);
  for (const [kind, ref] of refs) {
    if (DEMO_ONLY[ref]) { note(pg + ' ' + kind + ' ' + ref + ': prototype only (' + DEMO_ONLY[ref] + '), not bundled'); continue; }
    if (/^[a-z]+:/i.test(ref)) { check(pg + ' ' + kind + ' ' + ref + ': no absolute URL', false, 'the page has no network access'); continue; }
    const file = ref.replace(/^\.\//, '');
    referenced.add(file);
    check(pg + ' ' + kind + ' ' + ref + ': in the bundle, PAGE_FILES and pageFiles',
      fs.existsSync(path.join(WEB, file)) && PAGE_FILES.includes(file) && swTools.includes(file) && (file === 'lumina-selftest.js' || swRelease.includes(file)),
      'bundle ' + fs.existsSync(path.join(WEB, file)) + ' · PAGE_FILES ' + PAGE_FILES.includes(file) + ' · pageFiles tools ' + swTools.includes(file) + ' / release ' + swRelease.includes(file));
  }
}
for (const f of PAGE_FILES) check('PAGE_FILES entry is loaded by a page: ' + f, referenced.has(f));

// ——— 3. the scripts load, each alone ———
const SCRIPTS = { 'lumina-core-v4.js': 'LuminaCore', 'lumina-v4-data.js': 'LuminaV4', 'lumina-measure.js': 'LuminaMeasure' };
const sandbox = () => { const w = {}; w.window = w; w.document = { createElement: () => ({ getContext: () => ({}) }) }; return vm.createContext(w); };
const G = {};
for (const [file, name] of Object.entries(SCRIPTS)) {
  const ctx = sandbox(); let why = '';
  try { vm.runInContext(read(WEB, file), ctx, { filename: file }); } catch (e) { why = e.message; }
  G[name] = ctx[name];
  check(file + ' loads on its own and defines ' + name, !why && !!ctx[name] && typeof ctx[name] === 'object', why || name + ' is ' + typeof ctx[name]);
  check(file + ' defines no other Lumina global', Object.keys(ctx).filter(k => /^Lumina/.test(k)).join() === name);
}
// The order in the page: the page's class reads LuminaV4.SHOOTS when its script is compiled, so the three come first.
{ const t = pages[PAGE], at = s => t.indexOf(s), dc = at('data-dc-script');
  check(PAGE + ': the three scripts come before the page script', Object.keys(SCRIPTS).every(f => at('src="./' + f + '"') > 0 && at('src="./' + f + '"') < dc)); }

// ——— 4. every member the consumers name ———
const consumers = { [PAGE]: pages[PAGE], [EDIT]: pages[EDIT], 'lumina-selftest.js': read(WEB, 'lumina-selftest.js'), 'plumbing.js': read(WEB, 'plumbing.js') };
const used = new Set(); let nRefs = 0;
const lineOf = (text, i) => text.slice(0, i).split('\n').length;
for (const [file, text] of Object.entries(consumers)) {
  const seen = new Map();
  for (const m of text.matchAll(/\b(LuminaCore|LuminaV4|LuminaMeasure)\s*\.\s*([A-Za-z_$][\w$]*)(?:\s*\.\s*([A-Za-z_$][\w$]*))?(\s*\()?/g)) {
    const [, g, a, b, call] = m, top = G[g] && G[g][a], nested = b && top && typeof top === 'object' && !Array.isArray(top);
    const key = g + '.' + a + (nested ? '.' + b : ''), called = nested ? !!call : !!call && !b;
    used.add(g + '.' + a); if (nested) used.add(key);
    const k = key + (called ? '()' : ''); if (!seen.has(k)) seen.set(k, { g, a, b: nested ? b : null, called, line: lineOf(text, m.index) });
  }
  // const F = LuminaV4.fmt, then F.exp(…): the alias's calls (array and string methods are another F)
  if (/\bF\s*=\s*LuminaV4\.fmt\b/.test(text)) for (const m of text.matchAll(/\bF\.([A-Za-z_$][\w$]*)\s*\(/g)) {
    if (m[1] in Array.prototype || m[1] in String.prototype || m[1] in Set.prototype) continue;
    used.add('LuminaV4.fmt.' + m[1]); const k = 'LuminaV4.fmt.' + m[1] + '() via F'; if (!seen.has(k)) seen.set(k, { g: 'LuminaV4', a: 'fmt', b: m[1], called: true, line: lineOf(text, m.index) });
  }
  nRefs += seen.size;
  for (const [k, r] of seen) {
    const v = r.b ? G[r.g] && G[r.g][r.a] && G[r.g][r.a][r.b] : G[r.g] && G[r.g][r.a];
    check(file + ':' + r.line + ' ' + k + ' → ' + (r.called ? 'function' : 'defined'), r.called ? typeof v === 'function' : v !== undefined, 'the script gives ' + typeof v);
  }
}
check('the consumers name members of the globals (' + nRefs + ')', nRefs >= 20);
// Edit loads only support.js: mounted by the page it finds the globals there, opened on its own it would not.
if (/\bLumina(Core|V4|Measure)\b/.test(pages[EDIT]) && !/src="\.\/lumina-core-v4\.js"/.test(pages[EDIT])) note(EDIT + ' names the globals but loads none of the scripts itself');

// ——— 5. shapes the page leans on ———
const { LuminaCore: LC, LuminaV4: LV } = G;
const attempt = fn => { try { return fn(); } catch (e) { return { threw: e.message }; } };
{ const text = pages[PAGE];
  const sample = attempt(() => LV.sample()), big = attempt(() => LV.sampleBig(40)), many = attempt(() => LV.sampleN(250));
  check('LuminaV4.sample / sampleBig(40) / sampleN(250) return records', Array.isArray(sample) && sample.length > 0 && Array.isArray(big) && big.length === 40 && Array.isArray(many) && many.length === 250, JSON.stringify([sample, big, many].map(x => x && (x.threw || x.length))));
  const D = attempt(() => LC.buildShoot(sample, {})), E = attempt(() => LC.buildShoot([], {}));
  const dataKeys = [...new Set([...text.matchAll(/this\.data\.([A-Za-z_$][\w$]*)/g)].map(m => m[1]))];
  check('LuminaCore.buildShoot gives every this.data.* the page reads (' + dataKeys.join(', ') + '), for a shoot and for none',
    dataKeys.length > 0 && dataKeys.every(k => D && k in D && E && k in E), 'buildShoot → ' + Object.keys(D || {}));
  if (D && !D.threw) {
    const f = D.byId[D.order[0]], g = Object.values(D.G)[0], r = D.R[0];
    check('buildShoot: order of ids, byId frames with id / file / mi / gid, one row per mi', D.order.length === sample.length && !!f && ['id', 'file', 'mi', 'gid'].every(k => k in f) && D.order.every(id => D.R[D.byId[id].mi]));
    check('buildShoot: rows carry id, ids and m.time; groups carry kind, frames and ranked', !!r && typeof r.id === 'string' && Array.isArray(r.ids) && typeof r.m.time === 'string' && !!g && typeof g.kind === 'string' && Array.isArray(g.frames) && Array.isArray(g.ranked));
    const fx = attempt(() => LV.facts(D, []));
    check('LuminaV4.facts(data, failed) → [[label, text], …]', Array.isArray(fx) && fx.length > 0 && fx.every(x => Array.isArray(x) && x.length === 2 && x.every(s => typeof s === 'string')), JSON.stringify(fx).slice(0, 200));
  }
  const gs = attempt(() => LV.grammarSections());
  check('LuminaV4.grammarSections() → [{h, lines: [[keys, text], …]}, …]', Array.isArray(gs) && gs.length > 0 && gs.every(s => typeof s.h === 'string' && Array.isArray(s.lines) && s.lines.every(l => Array.isArray(l) && l.length === 2)));
  check('LuminaV4.GRAMMAR is text, FAQ is [[heading, [[question, answer], …]], …], SHOOTS is a list',
    typeof LV.GRAMMAR === 'string' && Array.isArray(LV.FAQ) && LV.FAQ.every(s => Array.isArray(s) && typeof s[0] === 'string' && Array.isArray(s[1]) && s[1].every(x => Array.isArray(x) && x.length === 2)) && Array.isArray(LV.SHOOTS));
  check('LuminaV4.fmt.base and fmt.exp take a missing value', attempt(() => LV.fmt.base(undefined)) === '' && typeof attempt(() => LV.fmt.exp(undefined)) === 'string');
  // me = LuminaCore.measure(bitmap): the fields the page reads off it are in the object the core returns
  const meReads = [...new Set([...text.matchAll(/\bme\.([A-Za-z_$][\w$]*)/g)].map(m => m[1]))], ret = (String(LC.measure).match(/return \{([^}]*)\}\s*;?\s*\}\s*$/) || ['', ''])[1];
  check('LuminaCore.measure returns what the page reads off it (' + meReads.join(', ') + ')', meReads.length > 0 && meReads.every(k => new RegExp('(^|[,{\\s])' + k + '\\s*[:,}]|(^|,)\\s*' + k + '\\s*$').test(ret)), 'measure returns {' + ret + '}');
  check('LuminaCore.freshXmp / mergeXmp return text, hasDevelop a boolean, phoneOf null or {short, zoom}',
    typeof attempt(() => LC.freshXmp(3, '', null)) === 'string' && typeof attempt(() => LC.mergeXmp(LC.freshXmp(1, '', null), 3, '')) === 'string' && attempt(() => LC.hasDevelop(undefined)) === false
    && attempt(() => LC.phoneOf({})) === null && typeof (attempt(() => LC.phoneOf({ make: 'Apple', model: 'iPhone 15 Pro', fl35: 24 })) || {}).short === 'string');
}

// ——— exports nothing names (a report, not a failure) ———
const all = [];
for (const [g, o] of Object.entries(G)) for (const k of Object.keys(o || {})) { all.push(g + '.' + k); if (o[k] && typeof o[k] === 'object' && !Array.isArray(o[k])) for (const k2 of Object.keys(o[k])) all.push(g + '.' + k + '.' + k2); }
const dead = all.filter(k => !used.has(k));
note('exports no page, selftest or plumbing.js names (' + dead.length + '): ' + dead.join(', '));

console.log(bad ? bad + ' FAILED' : 'page and scripts in step');
process.exit(bad ? 1 : 0);
