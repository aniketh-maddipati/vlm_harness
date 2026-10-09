// The Skim page's Final Cut export (buildX), runnable outside a browser.
//
// The page is the one implementation of the export for both the app and the browser, so the
// tests read buildX out of the page itself rather than keeping a second copy of it here.
//
//   node Tests/web/skim-export.mjs            # print the .fcpxml for the six-clip fixture
//   node --test Tests/web/skim-export.test.mjs
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

export const PAGE = new URL('../../design/handoff/lumina-skim/Lumina Skim v3.dc.html', import.meta.url);
export const FIXTURE = new URL('./fixtures/skim-export-six.json', import.meta.url);

/** Pull a class method's source out of the page by brace-matching.
 *  Skips strings, template literals, comments and regex literals: the page contains /"/g, which
 *  a naive scanner reads as the start of a string and then loses the brace count. */
export function extractMethod(src, name){
  const at = src.indexOf('\n  '+name+'() {');
  if (at < 0) throw new Error('method not found: '+name);
  const from = src.indexOf(name+'() {', at);   // skip the newline and the indent
  let i = src.indexOf('{', at), depth = 0, prev = '';
  const regexOk = c => c === '' || '([{,;:=!&|?+-*%~^<>'.includes(c);
  for (; i < src.length; i++){
    const ch = src[i], nx = src[i+1];
    if (ch === '/' && nx === '/'){ const e = src.indexOf('\n', i); if (e < 0) break; i = e; continue; }
    if (ch === '/' && nx === '*'){ i = src.indexOf('*/', i) + 1; continue; }
    if (ch === '"' || ch === "'" || ch === '`'){
      for (i++; i < src.length; i++){
        if (src[i] === '\\'){ i++; continue; }
        if (src[i] === ch) break;
      }
      prev = ch; continue;
    }
    if (ch === '/' && regexOk(prev)){
      let cls = false;
      for (i++; i < src.length; i++){
        if (src[i] === '\\'){ i++; continue; }
        if (src[i] === '[') cls = true;
        else if (src[i] === ']') cls = false;
        else if (src[i] === '/' && !cls) break;
      }
      prev = '/'; continue;
    }
    if (ch === '{') depth++;
    else if (ch === '}'){ depth--; if (!depth) return src.slice(from, i+1); }
    if (!/\s/.test(ch)) prev = ch;
  }
  throw new Error('unbalanced braces in '+name);
}

export function loadBuildX(pagePath = PAGE){
  const src = fs.readFileSync(pagePath, 'utf8');
  const source = extractMethod(src, 'buildX');
  return { fn: new Function('return function '+source)(), source };
}

export const fixture = (p = FIXTURE) => JSON.parse(fs.readFileSync(p, 'utf8'));

/** fixture -> the { state, d } that a buildX call reads. */
export function ctxFromFixture(fx, over = {}){
  return {
    d: {
      shoot: { name: fx.shoot.name, rate: fx.shoot.rate },
      clips: fx.clips.map(c => ({
        id: c.id, name: c.name, path: c.path,
        dur: c.durF * c.fpsDen / c.fpsNum, fps: c.fps, w: c.w, h: c.h,
      })),
    },
    state: {
      marks: Object.fromEntries(fx.clips.filter(c => c.mark).map(c => [c.id, c.mark])),
      ex: { ...fx.export, ...over },
    },
  };
}

export const buildFixture = (over = {}, fx = fixture()) => loadBuildX().fn.call(ctxFromFixture(fx, over));

/** Sony LtcChangeTable @value -> "HH:MM:SS:FF", or null when it cannot be trusted.
 *
 *  Eight digits, read as decimal pairs in the order frames, seconds, minutes, hours. (They are
 *  BCD, but Sony writes them as decimal-looking digits: reading "16324420" as hex gives
 *  32:68:50:22, which is nonsense, while reading it as decimal pairs gives 20:44:32:16 — the
 *  timecode the file itself reports.)
 *
 *  Verified against the clips' own embedded timecode for 12 clips spread across a 401-clip
 *  ILCE-7M3 card: 12/12, all tcFps=24 halfStep=false.
 *
 *  An earlier version of this masked the frames pair with 0x3f when it read >= 40, on the theory
 *  that the LTC drop-frame and colour-frame flag bits were in there. That was speculation, and it
 *  was wrong twice over: the flag bits cannot be addressed that way once the byte has been written
 *  as decimal digits (a flagged frame 6 would be "46", and 46 & 0x3f is 46, not 6), and a7S III
 *  60p material legitimately carries frame numbers up to 59. With no drop-frame sample to check
 *  against, guessing is worse than declining: pass tcFps and an out-of-range frame returns null
 *  for the caller to handle, rather than a plausible wrong number.  */
export function decodeLtc(value, tcFps = null){
  const s = String(value).padStart(8, '0');
  if (!/^\d{8}$/.test(s)) return null;
  const [ff, ss, mm, hh] = [s.slice(0,2), s.slice(2,4), s.slice(4,6), s.slice(6,8)].map(Number);
  if (hh > 23 || mm > 59 || ss > 59) return null;
  if (tcFps != null && ff >= tcFps) return null;
  const p = n => String(n).padStart(2, '0');
  return `${p(hh)}:${p(mm)}:${p(ss)}:${p(ff)}`;
}


/** Final Cut ships the FCPXML DTDs inside Interchange.framework. The app's folder name is not
 *  fixed (12.4 installs as "Final Cut Pro Creator Studio.app"), so find it rather than hardcode it.
 *  Returns null when Final Cut is not installed, so the test can skip instead of failing. */
export function findDTD(version, roots = dtdRoots()){
  const rel = `Contents/Frameworks/Interchange.framework/Versions/A/Resources/FCPXMLv${version.replace('.','_')}.dtd`;
  for (const root of roots){
    let apps = [];
    try { apps = fs.readdirSync(root).filter(n => n.endsWith('.app')); } catch { continue; }
    for (const app of apps){
      const p = path.join(root, app, rel);
      try { if (fs.statSync(p).isFile()) return p; } catch {}
    }
  }
  return null;
}

/** Where to look for the Final Cut bundle. FCPXML_DTD_APPS overrides it; the mnt path is where a
 *  linked Mac's /Applications shows up when these tests run off the Mac itself. */
function dtdRoots(){
  return [process.env.FCPXML_DTD_APPS, '/Applications', path.join(os.homedir(), 'mnt/Applications')]
    .filter(Boolean);
}

/** xmllint takes its arguments as URIs, so a path with spaces in it (every Final Cut bundle) has
 *  to be copied somewhere without them before the DTD can be read. */
export function validateAgainstDTD(text, version = '1.10'){
  const dtd = findDTD(version);
  if (!dtd) return { skipped: 'Final Cut Pro is not installed' };
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fcpxml-'));
  try {
    const d = path.join(dir, `FCPXMLv${version.replace('.','_')}.dtd`), x = path.join(dir, 'export.fcpxml');
    fs.copyFileSync(dtd, d); fs.writeFileSync(x, text);
    const r = spawnSync('xmllint', ['--noout', '--dtdvalid', d, x], { encoding: 'utf8' });
    if (r.error) return { skipped: 'xmllint is not available' };
    return { ok: r.status === 0, errors: (r.stderr || '').trim(), dtd };
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
}

if (import.meta.url === 'file://'+process.argv[1]) process.stdout.write(buildFixture().text);
