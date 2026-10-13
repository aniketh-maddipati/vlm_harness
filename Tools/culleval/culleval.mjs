#!/usr/bin/env node
// The culling eval: how well Lumina's grouping (rows, stacks) and automatic keeps match what was
// really shot and what the photographer really kept. Measures only; the logic under test is the
// design's own lumina-core, loaded unchanged. See README.md.
//
//   node Tools/culleval/culleval.mjs [--config ~/LuminaEvidence/culleval/shoots.json] [--out ~/LuminaEvidence/culleval]
//                                    [--repeat-gap 2] [--scene-gap 10] [--jobs 4] [--exiftool /usr/local/bin/exiftool] [--allow-missing]
//
// Everything it reads about photos and everything it writes stays under --out (never in the repo).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { run, cutsFor, coreHash } from './lib/core.mjs';
import { measureAll, keyOf, READONE, readOneHash, RAW_FILE } from './lib/measure.mjs';
import { seconds, truthGroups, matchExports, inOrder } from './lib/truth.mjs';
import { pairwise, splits, cutBy, picks, bestOf, pool, prf, members } from './lib/score.mjs';
import { markdown } from './lib/report.mjs';

const t0 = Date.now();
const arg = (n, d) => { const i = process.argv.indexOf('--' + n); return i > 0 ? process.argv[i + 1] : d; };
const home = p => (p.startsWith('~') ? path.join(os.homedir(), p.slice(1)) : p);
const OUT = home(arg('out', '~/LuminaEvidence/culleval')), CONFIG = home(arg('config', path.join(OUT, 'shoots.json')));
const EXIFTOOL = arg('exiftool', fs.existsSync('/usr/local/bin/exiftool') ? '/usr/local/bin/exiftool' : 'exiftool');
const GAPS = { repeatGap: +arg('repeat-gap', 2), sceneGap: +arg('scene-gap', 10) };
const log = s => console.error(s);

if (!fs.existsSync(CONFIG)) { log('no config at ' + CONFIG + '\ncopy Tools/culleval/shoots.example.json there and point it at your shoots'); process.exit(2); }
const config = JSON.parse(fs.readFileSync(CONFIG, 'utf8'));
fs.mkdirSync(path.join(OUT, 'cache'), { recursive: true });

// ——— files and metadata (exiftool once per file, cached by path, size and mtime)
const walk = (dir, re) => fs.readdirSync(dir, { withFileTypes: true }).flatMap(e => e.name.startsWith('.') ? [] : e.isDirectory() ? walk(path.join(dir, e.name), re) : re.test(e.name) ? [path.join(dir, e.name)] : []).sort();
const TAGS = ['DateTimeOriginal', 'ReleaseMode2', 'SequenceImageNumber', 'SequenceLength', 'ShutterCount', 'ExposureTime', 'FNumber', 'ISO', 'FocalLength', 'Orientation', 'LensModel', 'XMP-crs:RawFileName', 'XMP-crs:Exposure2012', 'XMP-crs:Contrast2012', 'XMP-crs:Highlights2012', 'XMP-crs:Shadows2012', 'XMP-crs:Whites2012', 'XMP-crs:Blacks2012', 'XMP-crs:HasCrop'];
const EDITS = ['Exposure2012', 'Contrast2012', 'Highlights2012', 'Shadows2012', 'Whites2012', 'Blacks2012'];
function exif(files) {
  const file = path.join(OUT, 'cache/exif.json'); let cache = {};
  try { cache = JSON.parse(fs.readFileSync(file, 'utf8')); } catch (_) {}
  const keys = new Map(files.map(f => [f, keyOf(f)])), todo = files.filter(f => !cache[keys.get(f)]);
  if (todo.length) {
    log('exiftool: ' + todo.length + ' files (cached afterwards)');
    const args = path.join(OUT, 'cache/exiftool-args.txt'); fs.writeFileSync(args, todo.join('\n') + '\n');
    let out; try { out = execFileSync(EXIFTOOL, ['-fast', '-q', '-json', '-n', ...TAGS.map(t => '-' + t), '-@', args], { maxBuffer: 1 << 30 }); } catch (e) { out = e.stdout; if (!out || !out.length) throw e; }
    for (const r of JSON.parse(out.toString())) cache[keys.get(r.SourceFile)] = r;
    fs.rmSync(args); fs.writeFileSync(file, JSON.stringify(cache));
  }
  return new Map(files.map(f => [f, cache[keys.get(f)] || {}]));
}

// ——— one shoot
const day = d => (d || '').slice(0, 10).replace(/:/g, '-');
async function shoot(sh) {
  const dir = home(sh.raws);
  if (!fs.existsSync(dir)) return { id: sh.id, skipped: 'folder not found' };
  const all = walk(dir, RAW_FILE), ex = exif(all), seen = new Set();
  // dates / datesExclude pick days; from / to ("2026-02-08 14:00:00") pick a stretch of capture time.
  const stamp = d => (d || '').replace(/^(\d{4}):(\d{2}):/, '$1-$2-');
  const inShoot = d => !(sh.dates && !sh.dates.includes(day(d))) && !(sh.datesExclude && sh.datesExclude.includes(day(d))) && !(sh.from && stamp(d) < sh.from) && !(sh.to && stamp(d) > sh.to);
  // The frames of this shoot: its dates, each real frame once (a card copy can hold a frame twice).
  const files = all.filter(f => {
    const e = ex.get(f);
    if (!inShoot(e.DateTimeOriginal)) return false;
    const k = e.ShutterCount != null ? 's' + e.ShutterCount : f; if (seen.has(k)) return false; seen.add(k); return true;
  });
  if (!files.length) return { id: sh.id, skipped: 'no frames' };
  const measured = await measureAll(files, path.join(OUT, 'cache/measure.json'), { jobs: +arg('jobs', 4), log });
  const list = files.map(f => measured.get(f)).filter(p => !p.err), ids = list.map(p => p.path), name = p => path.basename(p);

  // Truth groups from the camera's metadata.
  const frames = ids.map(f => { const e = ex.get(f); return { id: f, name: name(f), date: e.DateTimeOriginal, t: seconds(e.DateTimeOriginal), seq: e.SequenceImageNumber ?? null, shutter: e.ShutterCount ?? null, lens: e.LensModel || '', fl: e.FocalLength || 0, orient: e.Orientation || 1, exp: e.ExposureTime, fnum: e.FNumber, iso: e.ISO }; });
  const truth = truthGroups(frames, GAPS), core = run(list);
  const counted = inOrder(frames).map(f => f.shutter).filter(x => x != null);
  const r = { id: sh.id, note: sh.note || '', frames: ids.length, files: all.length, unreadable: files.length - list.length, noPreview: list.filter(p => p.nopv).length, days: new Set(frames.map(f => day(f.date))).size,
    shot: counted.length ? counted[counted.length - 1] - counted[0] + 1 : null, rows: core.rows, grouping: {}, rowsWhole: {}, local: { worst: [] } };

  // Grouping: Lumina's stacks against each truth level; rows must not cut a truth group.
  for (const level of ['drive', 'repeat', 'scene']) {
    r.grouping[level] = { ...pairwise(core.stack, truth[level], ids), ...splits(core.stack, truth[level], ids) };
    r.rowsWhole[level] = cutBy(core.row, truth[level], ids);
  }
  // What if the page read the camera's drive data (it reads none on these files, see README): the
  // same list with the sequence number exiftool reads, as the page's own fallback tag would give it.
  const whatIf = run(list.map(p => { const e = ex.get(p.path); return { ...p, seqImage: e.ReleaseMode2 && e.SequenceImageNumber ? e.SequenceImageNumber : null, releaseMode2: e.ReleaseMode2 ?? null, seqLength: e.SequenceLength || null }; }));
  r.driveRead = { frames: list.filter(p => p.seqImage != null || p.releaseMode2 != null).length, truthFrames: frames.filter(f => (ex.get(f.id).ReleaseMode2 || 0) !== 0).length };
  r.whatIfDriveRead = { drive: { ...pairwise(whatIf.stack, truth.drive, ids), ...splits(whatIf.stack, truth.drive, ids) }, repeat: { ...pairwise(whatIf.stack, truth.repeat, ids), ...splits(whatIf.stack, truth.repeat, ids) } };
  r.stacks = { stacks: core.stacks.filter(s => s.ids.length > 1).length, framesInStacks: core.stacks.filter(s => s.ids.length > 1).reduce((n, s) => n + s.ids.length, 0), brackets: core.stacks.filter(s => s.kind === 'bracket').length };
  r.flags = { soft: 0, blown: 0, shake: 0, dark: 0 }; for (const f of core.flags.values()) for (const k of Object.keys(r.flags)) if (f[k]) r.flags[k]++;

  // Keeps: exports, sidecars, or a saved Lumina session.
  let kept = null, scope = ids, source = null;
  // A truth source that is not there is no truth: never read a missing folder as "nothing kept".
  const gone = [...(sh.exports || []), ...(sh.keeps || []), ...(sh.session ? [sh.session] : [])].map(home).filter(d => !fs.existsSync(d));
  if (gone.length) r.truthMissing = (sh.session ? 'session' : (sh.exports || []).some(d => gone.includes(home(d))) ? 'exports folder' : 'keeps list') + ' not found';
  if ((sh.exports || sh.keeps) && !gone.length) {
    const jpgs = (sh.exports || []).map(home).flatMap(d => walk(d, /\.jpe?g$/i)), je = exif(jpgs);
    const found = jpgs.map(f => { const e = je.get(f); return { name: name(f), raw: e.RawFileName, date: e.DateTimeOriginal, exp: e.ExposureTime, fnum: e.FNumber, iso: e.ISO, fl: e.FocalLength, edited: EDITS.some(k => +e[k]) || e.HasCrop === true || e.HasCrop === 'True' }; });
    // The keep list of the exports that are here is saved on every run (names and settings, no pixels), so
    // the truth outlives the JPEGs: name the saved file under "keeps" once an exports folder is gone.
    if (found.length) { fs.mkdirSync(path.join(OUT, 'keeps'), { recursive: true }); fs.writeFileSync(path.join(OUT, 'keeps', sh.id + '.json'), JSON.stringify({ shoot: sh.id, saved: new Date().toISOString(), from: sh.exports, exports: found }, null, 1)); }
    const listed = (sh.keeps || []).flatMap(f => JSON.parse(fs.readFileSync(home(f), 'utf8')).exports);
    const exps = [...found, ...listed].filter(e => inShoot(e.date));
    const m = matchExports(frames, exps);
    kept = m.kept; scope = ids.filter(id => !m.ambiguous.has(id)); source = 'exports';
    r.truth = { source, exports: exps.length, fromKeepsList: listed.filter(e => inShoot(e.date)).length, edited: exps.filter(e => e.edited).length, matchedByName: m.rule.name, matchedByTime: m.rule.time, exportsWithoutRaw: m.unmatched.length, ambiguous: m.ambiguous.size };
    r.local.exportsWithoutRaw = m.unmatched;
  } else if (sh.sidecars) {
    kept = new Set(ids.filter(f => { try { const m = /xmp:Rating\s*=\s*"(\d+)"|<xmp:Rating>(\d+)</.exec(fs.readFileSync(f.replace(/\.[^.]+$/, '.xmp'), 'utf8')); return m && +(m[1] ?? m[2]) >= 1; } catch (_) { return false; } }));
    source = 'sidecars'; r.truth = { source };
  } else if (sh.session && !gone.length) {
    // A saved session: keeps are its marks, and only rows the photographer has seen count as decided.
    const s = JSON.parse(fs.readFileSync(home(sh.session), 'utf8')), rel = f => path.relative(dir, f);
    kept = new Set(ids.filter(f => s.marks && s.marks[rel(f)] === 'keep'));
    scope = ids.filter(f => s.seen && s.seen[core.row.get(f)]); source = 'session'; r.truth = { source, rowsSeen: Object.keys(s.seen || {}).length };
  }
  if (kept) {
    const inScope = new Set(scope), flagged = new Set(scope.filter(id => { const f = core.flags.get(id); return f.soft || f.blown || f.shake; }));
    r.truth.frames = scope.length; r.truth.kept = scope.filter(id => kept.has(id)).length; r.complete = sh.complete !== false;
    r.picks = { suggested: picks(core.sug, kept, scope), pagePick: picks(core.pagePick, kept, scope) };
    // Flags as a reject signal: of the flagged frames, how many did the photographer reject.
    const rej = new Set(scope.filter(id => !kept.has(id)));
    r.picks.flagsAsReject = picks(flagged, rej, scope);
    // Best of stack: Lumina's own stacks, then the truth groups as if the photographer had stacked them.
    const group = s => ({ ids: s.ids, pick: s.pick }), within = s => s.ids.every(id => inScope.has(id)) && s.kind !== 'bracket';
    r.bestOf = { stacks: bestOf(core.stacks.filter(within).map(group), kept) };
    for (const level of ['repeat', 'scene']) {
      const forced = run(list, cutsFor(core, truth[level], core.order)), T = members(truth[level], ids);
      const whole = forced.stacks.filter(s => s.ids.length > 1 && within(s) && T.get(truth[level].get(s.ids[0])).length === s.ids.length && new Set(s.ids.map(id => truth[level].get(id))).size === 1);
      r.bestOf[level] = bestOf(whole.map(group), kept);
      r.bestOf[level].stackedByLumina = whole.filter(s => new Set(s.ids.map(id => core.stack.get(id))).size === 1).length;
      r.bestOf[level].forced = forced;
    }
    // Where it goes wrong (file names: local report only).
    const fl = id => core.flags.get(id), why = id => ['soft', 'blown', 'shake'].filter(k => fl(id)[k]).join('+');
    const sceneOf = truth.scene, S = members(sceneOf, ids), sceneKeeps = id => S.get(sceneOf.get(id)).filter(x => kept.has(x)).length;
    const fp = scope.filter(id => core.sug.has(id) && !kept.has(id)), fn = scope.filter(id => !core.sug.has(id) && kept.has(id));
    r.patterns = {
      falseKeeps: fp.length,
      falseKeeps_sceneHasAKeeper: fp.filter(id => S.get(sceneOf.get(id)).length > 1 && sceneKeeps(id) > 0).length,
      falseKeeps_sceneAllRejected: fp.filter(id => S.get(sceneOf.get(id)).length > 1 && sceneKeeps(id) === 0).length,
      falseKeeps_loneFrame: fp.filter(id => S.get(sceneOf.get(id)).length === 1).length,
      missedKeeps: fn.length,
      missedKeeps_flaggedSoft: fn.filter(id => fl(id).soft).length,
      missedKeeps_flaggedBlown: fn.filter(id => fl(id).blown).length,
      missedKeeps_flaggedShake: fn.filter(id => fl(id).shake).length,
      missedKeeps_notSharpestInStack: fn.filter(id => fl(id).bn > 1 && !why(id)).length,
      scenesWithKeeper_notOneStack: [...S.values()].filter(g => g.length > 1 && g.some(id => kept.has(id)) && new Set(g.map(id => core.stack.get(id))).size > 1).length,
      scenesWithKeeper: [...S.values()].filter(g => g.length > 1 && g.some(id => kept.has(id))).length,
    };
    const sc = r.bestOf.scene, F = sc.forced.flags, worst = [];
    for (const m of sc.misses) worst.push({ score: 100 + F.get(m.pick).focus / Math.max(1e-9, F.get(m.kept).focus), kind: 'best of scene: Lumina would keep another frame', kept: name(m.kept), lumina: name(m.pick), detail: m.ids.length + ' frames · the kept frame ranks ' + F.get(m.kept).rank + ' of ' + m.ids.length + ' by sharpness' + (['soft', 'blown', 'shake'].filter(k => F.get(m.kept)[k]).map(k => ' · flagged ' + k).join('')) });
    for (const id of fn) worst.push({ score: 50 + (100 - fl(id).sharp) / 100, kind: 'kept by the photographer, not suggested', kept: name(id), lumina: '', detail: (why(id) ? 'flagged ' + why(id) : 'not the sharpest of its stack') + ' · sharper than ' + fl(id).sharp + ' % of the shoot' });
    for (const id of fp) worst.push({ score: fl(id).sharp / 100, kind: 'suggested, rejected by the photographer', kept: '', lumina: name(id), detail: 'sharper than ' + fl(id).sharp + ' % of the shoot · ' + (S.get(sceneOf.get(id)).length > 1 ? 'one of ' + S.get(sceneOf.get(id)).length + ' tries, ' + sceneKeeps(id) + ' kept' : 'a lone frame') });
    r.local.worst = worst.sort((a, b) => b.score - a.score).slice(0, 10).map(({ score, ...w }) => w);
    for (const k of ['stacks', 'repeat', 'scene']) { r.bestOf[k].misses = r.bestOf[k].misses.length; delete r.bestOf[k].forced; }
  }
  // Worst grouping disagreements: the largest truth bursts Lumina split, the stacks that mix bursts.
  const R = members(truth.repeat, ids);
  r.local.groupingWorst = [...R.values()].filter(g => g.length > 1 && new Set(g.map(id => core.stack.get(id))).size > 1).sort((a, b) => b.length - a.length).slice(0, 10)
    .map(g => ({ kind: 'burst by hand, not stacked', frames: g.length, first: name(g[0]), last: name(g[g.length - 1]), luminaStacks: new Set(g.map(id => core.stack.get(id))).size }));
  return r;
}

// ——— all shoots, pooled numbers, the report
// Everything the config names must be there. A drive that is not mounted would otherwise give a
// report over fewer shoots that looks complete. --allow-missing scores what is there and says what is not.
const missing = config.shoots.flatMap(sh => [sh.raws, ...(sh.exports || []), ...(sh.keeps || []), ...(sh.session ? [sh.session] : [])].map(home).filter(d => !fs.existsSync(d)).map(d => ({ id: sh.id, path: d })));
if (missing.length) {
  const vols = [...new Set(missing.map(m => /^\/Volumes\/[^/]+/.exec(m.path)?.[0]).filter(v => v && !fs.existsSync(v)))];
  log('culleval: ' + missing.length + ' path' + (missing.length > 1 ? 's' : '') + ' named in ' + CONFIG + ' not found:');
  for (const m of missing) log('  ' + m.id + ': ' + m.path);
  if (vols.length) log('not mounted: ' + vols.join(', ') + ' — mount ' + (vols.length > 1 ? 'them' : 'it') + ' and run again.');
  if (!process.argv.includes('--allow-missing')) { log('Nothing was scored. To score only the shoots that are there: --allow-missing (make culleval ALLOW_MISSING=1).'); process.exit(3); }
  log('--allow-missing: scoring the rest; the report lists what was left out.');
}
const shoots = []; for (const sh of config.shoots) { const r = await shoot(sh); shoots.push(r); if (r.skipped) log('skipped ' + sh.id + ': ' + r.skipped); }
const done = shoots.filter(s => !s.skipped), withKeeps = done.filter(s => s.picks), full = withKeeps.filter(s => s.complete);
const sumBest = (list, k) => { const s = { oneKeeper: 0, agree: 0, chanceSum: 0, groups: 0 }; for (const x of list) { const b = x.bestOf[k]; s.groups += b.groups; s.oneKeeper += b.oneKeeper; s.agree += b.agree; s.chanceSum += (b.chance || 0) * b.oneKeeper; } return { groups: s.groups, oneKeeper: s.oneKeeper, agree: s.agree, agreement: s.oneKeeper ? s.agree / s.oneKeeper : null, chance: s.oneKeeper ? s.chanceSum / s.oneKeeper : null }; };
const poolOf = list => list.length ? { shoots: list.length, suggested: pool(list.map(s => s.picks.suggested)), pagePick: pool(list.map(s => s.picks.pagePick)), flagsAsReject: pool(list.map(s => s.picks.flagsAsReject)), bestOf: { stacks: sumBest(list, 'stacks'), repeat: sumBest(list, 'repeat'), scene: sumBest(list, 'scene') } } : null;
const pooled = { frames: done.reduce((n, s) => n + s.frames, 0), grouping: {}, whatIfDriveRead: {}, picksComplete: poolOf(full), picksAll: poolOf(withKeeps) };
for (const level of ['drive', 'repeat', 'scene']) {
  const g = done.map(s => s.grouping[level]), sum = k => g.reduce((n, x) => n + x[k], 0);
  pooled.grouping[level] = { ...prf(sum('tp'), sum('fp'), sum('fn')), truthGroups: sum('truthGroups'), exact: sum('exact'), overSplit: sum('overSplit'), merged: sum('merged'), underSplit: sum('underSplit'), predGroups: sum('predGroups') };
  if (level === 'scene') continue;
  const w = done.map(s => s.whatIfDriveRead[level]), ws = k => w.reduce((n, x) => n + x[k], 0);
  pooled.whatIfDriveRead[level] = { ...prf(ws('tp'), ws('fp'), ws('fn')), truthGroups: ws('truthGroups'), exact: ws('exact'), overSplit: ws('overSplit'), merged: ws('merged'), underSplit: ws('underSplit'), predGroups: ws('predGroups') };
}
pooled.driveRead = { frames: done.reduce((n, s) => n + s.driveRead.frames, 0), truthFrames: done.reduce((n, s) => n + s.driveRead.truthFrames, 0) };
const drift = readOneHash() !== READONE;
const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\..*/, '').replace('T', '-');
const report = { when: new Date().toISOString(), core: coreHash(), readOneDrift: drift, gaps: GAPS, pooled, shoots: shoots.map(({ local, ...s }) => s) };
const local = Object.fromEntries(done.map(s => [s.id, s.local]));
const dir = path.join(OUT, 'report', stamp); fs.mkdirSync(dir, { recursive: true });
fs.writeFileSync(path.join(dir, 'report.json'), JSON.stringify(report, null, 1));
fs.writeFileSync(path.join(dir, 'local-worst.json'), JSON.stringify(local, null, 1));
const md = markdown(report, local); fs.writeFileSync(path.join(dir, 'report.md'), md);
fs.rmSync(path.join(OUT, 'report/latest'), { force: true }); fs.symlinkSync(stamp, path.join(OUT, 'report/latest'));
if (drift) log('NOTE: the page\'s readOne changed since lib/measure.mjs was written (' + readOneHash() + ' ≠ ' + READONE + '): review IN_PAGE there, then update READONE');
console.log(md.split('\n## Worst')[0]);
log('report: ' + path.join(dir, 'report.md') + ' · ' + ((Date.now() - t0) / 1000).toFixed(1) + ' s');
