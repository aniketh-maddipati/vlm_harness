#!/usr/bin/env node
// The culling eval through the app: what lumina-core decided when the real page and the native
// reader opened a folder (the probe's dump, dump-decisions.json), against the photographer's picks.
// Picks are matched and scored by the same code as culleval.mjs (lib/truth.mjs, lib/score.mjs). See README.md.
//
//   node Tools/culleval/culleval-app.mjs --exports exports.csv [--out report.md] <run>/dump-decisions/decisions.json …
//
// exports.csv: exiftool -csv -FileName -RawFileName -DateTimeOriginal <the finished exports…>
// --out also writes <report>.json and labeled.json (every scored photo with `pool` and `pick`, read by
// signals/rank_signals.py) next to it. Keep them out of the repo: labeled.json names files.
import fs from 'node:fs';
import path from 'node:path';
import { exportsFromCsv, label, score, markdown } from './lib/app.mjs';

const args = process.argv.slice(2), opt = n => { const i = args.indexOf('--' + n); return i < 0 ? null : args.splice(i, 2)[1]; };
const csv = opt('exports'), out = opt('out');
if (!csv || !args.length) { console.error('usage: culleval-app.mjs --exports exports.csv [--out report.md] <run>/dump-decisions/decisions.json …'); process.exit(2); }

const exports = exportsFromCsv(fs.readFileSync(csv, 'utf8'));
const pools = {}, all = []; let ambiguous = 0, unmatched = null;
for (const file of args) {
  const pool = path.basename(path.dirname(path.dirname(path.resolve(file))));     // <pool>/dump-decisions/decisions.json
  const photos = JSON.parse(fs.readFileSync(file, 'utf8')).photos.map(p => ({ ...p, pool }));
  const l = label(photos, exports), miss = new Set(l.unmatched);
  pools[pool] = score(l.photos); all.push(...l.photos); ambiguous += l.ambiguous;
  unmatched = unmatched ? new Set([...unmatched].filter(n => miss.has(n))) : miss;  // not found in any dump
}
const total = score(all), md = markdown(pools, total, unmatched.size, ambiguous);
if (out) {
  const beside = name => path.join(path.dirname(out), name);
  fs.writeFileSync(out, md);
  fs.writeFileSync(out.replace(/\.[^./]+$/, '') + '.json', JSON.stringify({ pools, all: total, unmatchedExports: unmatched.size, ambiguous }, null, 1));
  fs.writeFileSync(beside('labeled.json'), JSON.stringify({ photos: all }));
}
console.log(md);
