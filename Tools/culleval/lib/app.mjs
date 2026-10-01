// The culling eval through the app: the probe's dump of what lumina-core decided (dump-decisions.json:
// the real page and the native reader open a folder) against the photographer's picks. Pure.
// The picks are matched by truth.mjs and scored by score.mjs, the same as culleval.mjs; only who
// read the photos differs. A dump photo: {path, date, sec, row, gid, kind, rank, peak, sug, soft, …}.
import { matchExports } from './truth.mjs';
import { picks, bestOf } from './score.mjs';
import { pct, table } from './report.mjs';

export const FLAGS = ['soft', 'slight', 'blown', 'shake', 'dark'];
const div = (a, b) => (b ? a / b : null);

// `exiftool -csv -FileName -RawFileName -DateTimeOriginal <exports…>` → what matchExports reads.
// An export that names no RAW (a camera JPEG) is not a pick.
export function exportsFromCsv(text) {
  const rows = []; let row = [], cell = '', quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) { if (c !== '"') cell += c; else if (text[i + 1] === '"') { cell += '"'; i++; } else quoted = false; }
    else if (c === '"') quoted = true;
    else if (c === ',') { row.push(cell); cell = ''; }
    else if (c === '\n') { row.push(cell.replace(/\r$/, '')); rows.push(row); row = []; cell = ''; }
    else cell += c;
  }
  if (cell || row.length) { row.push(cell); rows.push(row); }
  const head = rows.shift() || [], col = k => head.indexOf(k), at = (r, k) => (r[col(k)] || '').trim();
  return rows.map((r, i) => ({ name: at(r, 'SourceFile') || at(r, 'FileName') || String(i), raw: at(r, 'RawFileName'), date: at(r, 'DateTimeOriginal').slice(0, 19) }))
    .filter(e => e.raw && e.date.length === 19);
}

// Adds `pick` to each photo of one dump. Scored: the days with at least one pick (a day never
// exported from is unlabeled, not "all rejected"), without the frames that can't be told apart.
export function label(photos, exports) {
  const m = matchExports(photos.map(p => ({ id: p.path, name: p.path.split('/').pop(), date: String(p.date || '').replace(/-/g, ':') + ' ' + (p.sec || '') })), exports);
  for (const p of photos) p.pick = m.kept.has(p.path);
  const days = new Set(photos.filter(p => p.pick).map(p => p.date));
  return { photos: photos.filter(p => days.has(p.date) && !m.ambiguous.has(p.path)), unmatched: m.unmatched, ambiguous: m.ambiguous.size, rule: m.rule };
}

// Every number the report prints, from labeled photos. `pool` (the dump's name) keeps paths, stacks
// and rows of different dumps apart.
export function score(photos) {
  const key = (p, k) => (p.pool ?? '') + '\u0000' + k, id = p => key(p, p.path), ids = photos.map(id);
  const set = f => new Set(photos.filter(f).map(id)), by = (list, k) => { const m = new Map(); for (const p of list) { const g = k(p); if (!m.has(g)) m.set(g, []); m.get(g).push(p); } return [...m.values()]; };
  const kept = set(p => p.pick), out = { photos: ids.length, picks: kept.size, pickRate: div(kept.size, ids.length), days: new Set(photos.map(p => p.date)).size };
  if (!ids.length) return out;
  // score.mjs's picks: auto = said (suggested, or flagged), tp = picks carrying it, precision = picked
  // if said, recall = the share of picks carrying it. keptIfNot = picked if not said.
  const said = f => { const s = picks(set(f), kept, ids); return { ...s, keptIfNot: div(s.fn, s.fn + s.tn) }; };
  out.suggested = said(p => p.sug);
  out.flags = Object.fromEntries(FLAGS.map(f => [f, said(p => p[f])]));
  // Bursts where exactly one frame was picked: is it the frame ranked first, the one marked as the peak?
  const bursts = by(photos.filter(p => p.kind === 'burst' && p.gid), p => key(p, p.gid));
  const best = which => { const { misses, ...b } = bestOf(bursts.filter(g => g.some(which)).map(g => ({ ids: g.map(id), pick: id(g.find(which)) })), kept); return b; };
  out.bursts = { bursts: bursts.length, frames: bursts.reduce((n, g) => n + g.length, 0), withAPick: bursts.filter(g => g.some(p => p.pick)).length,
    rank1: best(p => p.rank === 1), peak: best(p => p.peak),
    picksInBursts: photos.filter(p => p.pick && p.kind === 'burst').length, picksSingle: photos.filter(p => p.pick && p.kind !== 'burst').length };
  const perRow = by(photos, p => key(p, p.row)).map(r => r.filter(p => p.pick).length), withAPick = perRow.filter(n => n).length;
  out.rows = { rows: perRow.length, withAPick, meanSize: div(ids.length, perRow.length), meanPicksWhenAny: div(kept.size, withAPick) };
  return out;
}

// pools: {name: score}, total: the score of all pools together. Numbers only: no file names.
export function markdown(pools, total, unmatched, ambiguous) {
  const L = ['# Culling eval through the app: lumina-core against the photographer\'s picks', '',
    'A pick = a RAW with a finished Lightroom export, stricter than a culling keep: read recall on picks and each flag\'s false alarms, not precision. Scored on days with at least one pick. Numbers only.', ''];
  L.push(table(['shoot', 'days', 'photos', 'picks', 'pick rate', 'suggested keeps', 'picks among suggested (recall)'], [...Object.entries(pools), ['**all**', total]].map(([name, s]) =>
    s.photos ? [name, s.days, s.photos, s.picks, pct(s.pickRate), s.suggested.auto + ' (' + pct(s.suggested.autoRate) + ')', pct(s.suggested.recall)] : [name, 0, 0, 0, '–', '–', '–'])));
  if (total.photos) {
    const g = total.suggested, b = total.bursts, r = total.rows, f1 = x => (x == null ? '–' : x.toFixed(1));
    const best = x => x.agree + ' of ' + x.oneKeeper + ' (' + pct(x.agreement) + '; chance ' + pct(x.chance) + ')';
    L.push('', '## Suggested keeps', '',
      '- lumina-core suggests keeping ' + pct(g.autoRate) + ' of the photos; ' + pct(g.recall) + ' of the picks are among them.',
      '- A suggested photo was picked ' + pct(g.precision) + ' of the time, a not-suggested one ' + pct(g.keptIfNot) + '.',
      '', '## Flags', '',
      table(['flag', 'photos flagged', 'picks flagged (false alarms)', 'picked if flagged', 'picked if not'], FLAGS.map(f => { const x = total.flags[f];
        return [f, x.auto + ' (' + pct(x.autoRate) + ')', x.tp + ' (' + pct(x.recall) + ' of picks)', pct(x.precision), pct(x.keptIfNot)]; })),
      '', '## Bursts', '',
      '- ' + b.bursts + ' bursts (' + b.frames + ' frames); ' + b.withAPick + ' hold a pick, ' + b.rank1.oneKeeper + ' exactly one (' + b.rank1.manyKeepers + ' more than one).',
      '- With exactly one pick: it is the frame ranked first in ' + best(b.rank1) + '; where a peak is marked, the pick is the peak in ' + best(b.peak) + '.',
      '- ' + b.picksInBursts + ' picks come from bursts, ' + b.picksSingle + ' from single frames.',
      '', '## Rows', '',
      '- ' + r.rows + ' rows (mean ' + f1(r.meanSize) + ' photos); ' + r.withAPick + ' hold a pick, ' + f1(r.meanPicksWhenAny) + ' picks each on average.');
  }
  L.push('', 'Exports that name a RAW not found in these folders: ' + unmatched + '. Frames left out because an export could be one of several: ' + ambiguous + '.');
  return L.join('\n') + '\n';
}
