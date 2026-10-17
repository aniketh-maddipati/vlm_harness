#!/usr/bin/env node
// The reject report: for one shoot, which frames Pick would set aside and why, in plain words,
// with one or two habits to change and how each day went. Measures only: the page's own measure and
// lumina-core's flags (soft / blown / shake / dark, stacks), the same as `make culleval`.
//
//   node Tools/culleval/rejects.mjs <folder> [--from 2024-11-23] [--to 2024-11-30] [--name nz]
//                                   [--out ~/LuminaEvidence/culleval] [--jobs 4]
//
// Writes <out>/rejects/<name>.md and .json. Photos and file names stay under --out, never in the repo.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { run } from './lib/core.mjs';
import { measureAll } from './lib/measure.mjs';

const arg = (n, d) => { const i = process.argv.indexOf('--' + n); return i > 0 ? process.argv[i + 1] : d; };
const home = p => (p.startsWith('~') ? path.join(os.homedir(), p.slice(1)) : p);
const DIR = home(process.argv[2] || ''), OUT = home(arg('out', '~/LuminaEvidence/culleval'));
const FROM = arg('from', '0000-00-00'), TO = arg('to', '9999-99-99'), NAME = arg('name', path.basename(DIR));
const log = s => console.error(s);
if (!DIR || !fs.existsSync(DIR)) { log('usage: rejects.mjs <folder of ARWs> [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--name id]'); process.exit(2); }

// Which frames: the ARWs shot between --from and --to, each real frame once (by shutter count).
const walk = d => fs.readdirSync(d, { withFileTypes: true }).flatMap(e => e.name.startsWith('.') ? [] : e.isDirectory() ? walk(path.join(d, e.name)) : /\.arw$/i.test(e.name) ? [path.join(d, e.name)] : []).sort();
const all = walk(DIR);
log(`exiftool: ${all.length} ARWs`);
const exif = JSON.parse(execFileSync('exiftool', ['-fast', '-q', '-json', '-n', '-DateTimeOriginal', '-ShutterCount', '-ExposureTime', '-FocalLength', '-FNumber', '-ISO', '-LensModel', ...all], { maxBuffer: 1 << 30 }).toString());
const day = d => (d || '').slice(0, 10).replace(/:/g, '-'), seen = new Set();
const ex = new Map(exif.map(e => [e.SourceFile, e]));
const files = all.filter(f => { const e = ex.get(f) || {}, d = day(e.DateTimeOriginal); if (d < FROM || d > TO) return false; const k = e.ShutterCount ?? f; if (seen.has(k)) return false; seen.add(k); return true; });
log(`${files.length} frames between ${FROM} and ${TO}`);
const measured = await measureAll(files, path.join(OUT, 'cache/measure.json'), { jobs: +arg('jobs', 4), log });
const list = files.map(f => measured.get(f)).filter(p => p && !p.err);
const core = run(list);

// One record per frame: what Pick would do with it, and why.
const frames = list.map(p => {
  const e = ex.get(p.path) || {}, f = core.flags.get(p.path), st = core.stacks.find(s => s.ids.includes(p.path));
  const multi = st && st.ids.length > 1, keep = core.sug.has(p.path);
  const why = [];
  // The page's shake rule (slower than 2 / focal length) says nothing of intent. At the lowest ISO
  // (100 or under) the camera had no room to go faster, so a slow shutter there was chosen: with
  // clipped highlights it was left too slow (overexposed), without them it looks deliberate (moving
  // water, a tripod) and is no reject. Above that ISO it is a handheld risk.
  const baseIso = (e.ISO || 0) <= 100;
  if (f.shake && baseIso && f.blown) why.push('slow+bright');
  else if (f.shake && baseIso) why.push('long');
  else if (f.shake) why.push('shake');
  if (f.soft) why.push('soft');
  if (f.blown) why.push('blown');
  if (f.dark) why.push('dark');
  if (!keep && !why.filter(w => w !== 'long').length && multi) why.push('extra');      // a sharper try of the same picture was kept
  return { path: p.path, day: day(e.DateTimeOriginal), exp: e.ExposureTime, fl: e.FocalLength, fnum: e.FNumber, iso: e.ISO, lens: e.LensModel || '', keep, why, stack: multi ? st.ids.length : 1 };
});

const n = frames.length, kept = frames.filter(f => f.keep || (f.why.length && f.why.every(w => w === 'long'))).length, aside = frames.filter(f => !(f.keep || (f.why.length && f.why.every(w => w === 'long'))));
const count = k => aside.filter(f => f.why.includes(k)).length;
const pct = (a, b) => (b ? Math.round((100 * a) / b) : 0) + ' %';
const ss = e => (!e ? '–' : e >= 1 ? e.toFixed(1) + ' s' : '1/' + Math.round(1 / e));
const median = a => { const s = [...a].sort((x, y) => x - y); return s.length ? s[Math.floor(s.length / 2)] : null; };

// Shake: the rule the page uses (exposure longer than 2 / focal length), per focal length.
const shake = frames.filter(f => f.why.includes('shake')), longs = frames.filter(f => f.why.includes('long')), slowBright = frames.filter(f => f.why.includes('slow+bright'));
const byFl = new Map();
for (const f of shake) { const k = Math.round(f.fl || 0); byFl.set(k, [...(byFl.get(k) || []), f]); }
const shakeRows = [...byFl.entries()].sort((a, b) => b[1].length - a[1].length).slice(0, 5)
  .map(([fl, fs_]) => `| ${fl} mm | ${fs_.length} | ${ss(median(fs_.map(f => f.exp)))} | 1/${fl} or faster |`);

// Soft: softer than half the sharpest try of the same picture. Does shutter speed explain it?
const inStacks = frames.filter(f => f.stack > 1), slow = f => f.exp && f.fl && f.exp > 1 / f.fl;
const softSlow = inStacks.filter(slow), softFast = inStacks.filter(f => !slow(f));
const softRate = g => pct(g.filter(f => f.why.includes('soft')).length, g.length);

// Tries per picture.
const stacks = core.stacks.filter(s => s.ids.length > 1), big = stacks.filter(s => s.ids.length >= 5);
const extra = count('extra');

// Habits: the two biggest reasons, said as what to do next time.
const habits = [];
const reasons = [['shake', shake.length], ['soft', count('soft')], ['blown', count('blown')], ['slow+bright', slowBright.length], ['dark', count('dark')], ['extra', extra]].sort((a, b) => b[1] - a[1]);
// A habit only when it is common: at least 2 % of the shoot.
for (const [k, v] of reasons.filter(r => r[1] >= Math.max(3, 0.02 * frames.length)).slice(0, 2)) {
  if (k === 'shake') { const [fl, g] = [...byFl.entries()].sort((a, b) => b[1].length - a[1].length)[0]; habits.push(`**Faster shutter when handheld.** ${v} frames were slower than 2 ÷ focal length with ISO to spare (most at ${fl} mm, around ${ss(median(g.map(f => f.exp)))}). Use 1/${fl} or faster at ${fl} mm: Auto ISO with a minimum shutter speed of 1/${fl} does it for you.`); }
  if (k === 'slow+bright') habits.push(`**Check exposure after changing the shutter.** ${v} frames were shot slow at the lowest ISO in bright light and came out overexposed: a slow shutter left on from a previous shot. A glance at the histogram after the first frame catches it.`);
  if (k === 'soft') habits.push(`**Check focus on the first try.** ${v} frames were well under half as sharp as the best try of the same picture. Soft rate was ${softRate(softSlow)} below 1 / focal length and ${softRate(softFast)} above it, so ${softSlow.length && softFast.length && parseInt(softRate(softSlow)) > parseInt(softRate(softFast)) + 5 ? 'shutter speed is part of it' : 'shutter speed is not the main cause: look at focus and subject movement'}.`);
  if (k === 'blown') habits.push(`**Protect highlights.** ${v} frames clipped more than their neighbours, mostly bright skies. Turn on zebras at 100+ or dial −0.3 to −0.7 EV in bright scenes.`);
  if (k === 'dark') habits.push(`**Expose a little brighter.** ${v} frames came out very dark.`);
  if (k === 'extra') habits.push(`**Fewer tries per picture.** ${v} frames were extra tries of a picture you already had sharp. ${big.length} ${big.length === 1 ? 'picture' : 'pictures'} got 5 or more tries; 2–3 is usually enough once the first is checked.`);
}

// The camera clock: bright frames between midnight and 5 a.m. mean it was set to another time zone.
const lum = new Map(list.map(p => [p.path, p.lum]));
const hourOf = f => { const e = ex.get(f.path) || {}; return +(e.DateTimeOriginal || '').slice(11, 13); };
const brightNight = frames.filter(f => hourOf(f) < 5 && (lum.get(f.path) ?? 0) > 0.35).length;
if (brightNight >= 10) habits.push(`**Set the camera clock to local time when travelling.** ${brightNight} frames are bright daylight at a clock time between midnight and 5 a.m., so the clock was on another time zone. Lumina groups and describes light by time of day; with the wrong clock, both are off.`);
if (!habits.length) habits.push('Nothing stands out: no reason covers more than 2 % of the shoot.');

// Day by day: the share set aside for a fixable reason (shake, soft, blown, dark), not extra tries.
const days = [...new Set(frames.map(f => f.day))].sort();
const fixable = f => f.why.some(w => w !== 'extra' && w !== 'long');
const dayRows = days.map(d => { const g = frames.filter(f => f.day === d); return `| ${d} | ${g.length} | ${pct(g.filter(fixable).length, g.length)} | ${pct(g.filter(f => f.why.includes('shake')).length, g.length)} | ${pct(g.filter(f => f.why.includes('soft')).length, g.length)} |`; });

const md = [
  `# What the ${NAME} shoot says (${days[0]} to ${days[days.length - 1]})`,
  '',
  `${n} frames. Pick would keep ${kept} (${pct(kept, n)}) and set ${aside.length} aside. Of those, ${aside.filter(fixable).length} are fixable next time, ${extra} are extra tries of a picture you already had.`,
  '',
  '## What to change',
  '',
  ...habits.map((h, i) => `${i + 1}. ${h}`),
  '',
  '## Why frames were set aside',
  '',
  '| reason | frames | what it means |',
  '|---|---|---|',
  `| shake | ${shake.length} | handheld slower than 2 ÷ focal length, with ISO to spare |`,
  `| slow and bright | ${slowBright.length} | slow shutter at the lowest ISO in bright light: overexposed |`,
  `| soft | ${count('soft')} | under half as sharp as the best try of the same picture |`,
  `| blown | ${count('blown')} | clipped highlights, more than the neighbouring frames |`,
  `| dark | ${count('dark')} | very dark preview |`,
  `| extra try | ${extra} | the same picture again, a sharper try was kept |`,
  '',
  `A frame can have more than one reason. Not counted as rejects: ${longs.length} slow frames at the lowest ISO without clipping, which look deliberate (moving water, a tripod). Soft is judged only against another try of the same picture, so single frames are never called soft.`,
  '',
  shakeRows.length ? ['## Shake by focal length', '', '| focal length | frames | typical shutter | next time |', '|---|---|---|---|', ...shakeRows, ''].join('\n') : '',
  '## Tries per picture',
  '',
  `${stacks.length} ${stacks.length === 1 ? 'picture was' : 'pictures were'} tried more than once (${inStacks.length} frames); ${big.length} got 5 or more tries.`,
  '',
  '## Day by day',
  '',
  '| day | frames | set aside, fixable | shake | soft |',
  '|---|---|---|---|---|',
  ...dayRows,
  '',
  'Measured by the page\'s own measures on the embedded previews (360 px) and lumina-core\'s flags; no record of your own keeps was used, so this is what Pick would do, not what you did.',
].join('\n');

fs.mkdirSync(path.join(OUT, 'rejects'), { recursive: true });
fs.writeFileSync(path.join(OUT, 'rejects', NAME + '.md'), md + '\n');
fs.writeFileSync(path.join(OUT, 'rejects', NAME + '.json'), JSON.stringify({ name: NAME, from: FROM, to: TO, frames }, null, 1));
console.log(md);
log('→ ' + path.join(OUT, 'rejects', NAME + '.md'));
