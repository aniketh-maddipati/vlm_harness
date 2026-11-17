// Skim's ⇧E run from the page itself: `sceneSl`, `evAutoMap` and `prof` are read out of
// design/handoff/lumina-skim/Lumina Skim v3.dc.html by brace-matching (as Tests/web/skim-rec709.test.mjs reads its
// methods), so there is no second copy to drift. rule.py is the numpy cross-check of this.
//
//   node Tools/exposeval/page.mjs <in.bin> [--page <html>] [--patch <patches.json>]   → JSON on stdout
//
// in.bin: a 4-byte little-endian header length, a JSON header, then the frames' bytes.
//   header {clips: [{id, slog3: bool, frames: [{off, w, h, ch, sampled}]}]}
//   A frame is w·h·ch bytes at `off` (ch 3 or 4, row-major, 8-bit, as a canvas gives them). `sampled`: the bytes are
//   only the pixels sceneSl reads (every 8th); the frame is rebuilt with each one at its place, the rest left 0.
// patches.json: [[old, new], …] replaced in the page's text first (each `old` must occur exactly once): how a round's
//   candidate changes the page before the change is made in the page.
// Out: {sl: {id: [frame values]}, ev: {id: stops}, page: sha256 of the text run}. Numbers are JavaScript doubles.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export const PAGE = path.join(ROOT, 'design/handoff/lumina-skim/Lumina Skim v3.dc.html');
export const METHODS = ['prof', 'sceneSl', 'evAutoMap'];

/** A class method by name, brace-matched with strings skipped. */
export function method(src, name) {
  const at = src.indexOf('\n  ' + name + '(');
  if (at < 0) throw new Error('method not found in the page: ' + name);
  let i = src.indexOf('{', src.indexOf(')', at)), depth = 0;
  for (; i < src.length; i++) {
    const ch = src[i];
    if (ch === '"' || ch === "'" || ch === '`') { for (i++; i < src.length; i++) { if (src[i] === '\\') { i++; continue; } if (src[i] === ch) break; } continue; }
    if (ch === '{') depth++;
    else if (ch === '}') { depth--; if (!depth) return src.slice(at + 3, i + 1); }
  }
  throw new Error('unbalanced braces in ' + name);
}

export function patch(src, patches = []) {
  for (const [a, b] of patches) {
    const n = src.split(a).length - 1;
    if (n !== 1) throw new Error(`patch must match exactly once, matched ${n}: ${a.slice(0, 80)}`);
    src = src.replace(a, () => b);
  }
  return src;
}

/** The page's ⇧E as a small object: sceneSl(img, clip), evAutoMap() over `d.clips` with `_px[i].sl`. */
export function load({ page = PAGE, patches = [] } = {}) {
  const src = patch(fs.readFileSync(page, 'utf8'), patches);
  const body = METHODS.map(n => method(src, n)).join('\n');
  const Skim = new Function('return class {\n' + body + '\n}')();
  return { Skim, sha: crypto.createHash('sha256').update(body).digest('hex') };
}

const SLOG3 = { profile: { gamma: 'S-Log3', primaries: 's-gamut3.cine', source: 'sidecar' } };
const OTHER = { profile: { gamma: 'none', primaries: '', source: 'sidecar' } };

/** Runs ⇧E on clips [{id, slog3, frames: [Uint8ClampedArray RGBA]}]. cal: the engine's calibration (null: none). */
export function run(Skim, clips, cal = null) {
  const s = Object.assign(new Skim(), { cal, state: { tick: 0 }, d: { clips: [] } });
  const sl = {};
  for (const c of clips) {
    const clip = { id: c.id, ...(c.slog3 ? SLOG3 : OTHER), _px: {} };
    // as the page's measure sites do: pp.sl = this.sceneSl(im, c, pp) (a page whose sceneSl takes two arguments ignores pp)
    sl[c.id] = c.frames.map((data, i) => { const pp = {}; pp.sl = s.sceneSl({ data }, clip, pp); clip._px[i] = pp; return pp.sl; });
    s.d.clips.push(clip);
  }
  return { sl, ev: s.evAutoMap() };
}

/** One frame's bytes → the RGBA a canvas would give sceneSl. */
export function rgba(buf, { w, h, ch, sampled }) {
  const n = w * h;
  if (buf.length !== n * ch) throw new Error(`frame is ${buf.length} bytes, expected ${n * ch}`);
  const step = sampled ? 8 : 1, out = new Uint8ClampedArray(n * step * 4);
  for (let p = 0; p < n; p++) {
    const o = p * step * 4, q = p * ch;
    out[o] = buf[q]; out[o + 1] = buf[q + 1]; out[o + 2] = buf[q + 2]; out[o + 3] = 255;
  }
  return out;
}

export function readInput(file) {
  const b = fs.readFileSync(file), n = b.readUInt32LE(0), head = JSON.parse(b.subarray(4, 4 + n).toString('utf8')), base = 4 + n;
  return head.clips.map(c => ({
    id: String(c.id), slog3: !!c.slog3,
    frames: c.frames.map(f => rgba(b.subarray(base + f.off, base + f.off + f.w * f.h * f.ch), f)),
  }));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const a = process.argv.slice(2), opt = k => { const i = a.indexOf(k); return i >= 0 ? a.splice(i, 2)[1] : null; };
  const page = opt('--page') || PAGE, pf = opt('--patch');
  if (a.length !== 1) { console.error('usage: node Tools/exposeval/page.mjs <in.bin> [--page html] [--patch json]'); process.exit(2); }
  const { Skim, sha } = load({ page, patches: pf ? JSON.parse(fs.readFileSync(pf, 'utf8')) : [] });
  const out = run(Skim, readInput(a[0]));
  process.stdout.write(JSON.stringify({ ...out, page: sha }));
}
