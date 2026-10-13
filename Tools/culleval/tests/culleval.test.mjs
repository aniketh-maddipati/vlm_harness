// node --test Tools/culleval/tests/culleval.test.mjs      (synthetic data only; runs on Linux)
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { pairwise, splits, cutBy, picks, bestOf, pool, prf } from '../lib/score.mjs';
import { seconds, truthGroups, sameFraming, matchExports } from '../lib/truth.mjs';
import { run, cutsFor, DESIGN } from '../lib/core.mjs';
import { READONE, readOneHash, recordOf, RAW_FILE } from '../lib/measure.mjs';
import { markdown } from '../lib/report.mjs';
import * as app from '../lib/app.mjs';

const groups = (...gs) => { const m = new Map(); gs.forEach((g, i) => g.forEach(id => m.set(id, 'g' + i))); return m; };
const ids = m => [...m.keys()];

test('pairwise: a perfect grouping scores 1', () => {
  const t = groups(['a', 'b', 'c'], ['d'], ['e', 'f']);
  assert.deepEqual(pairwise(t, t, ids(t)), { tp: 4, fp: 0, fn: 0, precision: 1, recall: 1, f1: 1 });
});

test('pairwise: an over-split burst loses recall, a merged stack loses precision', () => {
  const truth = groups(['a', 'b', 'c', 'd'], ['e'], ['f']);
  const over = pairwise(groups(['a', 'b'], ['c', 'd'], ['e'], ['f']), truth, ids(truth));
  assert.deepEqual([over.tp, over.fp, over.fn], [2, 0, 4]);
  assert.equal(over.precision, 1); assert.equal(over.recall, 2 / 6);
  const under = pairwise(groups(['a', 'b', 'c', 'd', 'e', 'f']), truth, ids(truth));
  assert.deepEqual([under.tp, under.fp, under.fn], [6, 9, 0]);
  assert.equal(under.recall, 1); assert.equal(under.precision, 6 / 15);
});

test('pairwise: nothing stacked and nothing to stack has no precision or recall', () => {
  const t = groups(['a'], ['b']), r = pairwise(t, t, ids(t));
  assert.equal(r.precision, null); assert.equal(r.recall, null); assert.equal(r.f1, null);
  assert.equal(prf(0, 0, 3).recall, 0);
});

test('splits: exact, over-split, whole but merged, stacks mixing groups, by size', () => {
  const truth = groups(['a', 'b'], ['c', 'd', 'e'], ['f', 'g'], ['h'], ['i', 'j', 'k', 'l', 'm', 'n']);
  const pred = groups(['a', 'b'], ['c', 'd'], ['e'], ['f', 'g', 'h'], ['i', 'j', 'k'], ['l', 'm', 'n']);
  const s = splits(pred, truth, ids(truth));
  assert.deepEqual([s.truthGroups, s.exact, s.overSplit, s.merged, s.underSplit, s.predGroups], [4, 1, 2, 1, 1, 5]);
  assert.deepEqual(s.bySize['2'], { groups: 2, exact: 1, overSplit: 0, pairs: 2, pairsKept: 2, recall: 1 });
  assert.equal(s.bySize['3-5'].recall, 1 / 3);
  assert.equal(s.bySize['6+'].recall, 6 / 15);
});

test('cutBy: a row boundary inside a burst', () => {
  const truth = groups(['a', 'b'], ['c', 'd'], ['e']);
  assert.deepEqual(cutBy(groups(['a', 'b', 'c'], ['d', 'e']), truth, ids(truth)), { groups: 2, cut: 1, whole: 0.5 });
});

test('picks: precision and recall of auto keeps', () => {
  const p = picks(new Set(['a', 'b', 'c']), new Set(['b', 'c', 'd', 'e']), ['a', 'b', 'c', 'd', 'e', 'f']);
  assert.deepEqual([p.tp, p.fp, p.fn, p.tn], [2, 1, 2, 1]);
  assert.equal(p.precision, 2 / 3); assert.equal(p.recall, 0.5); assert.equal(p.keepRate, 4 / 6); assert.equal(p.autoRate, 0.5);
  // frames outside ids (no truth for them) are not counted
  assert.equal(picks(new Set(['a', 'z']), new Set(['a']), ['a']).fp, 0);
});

test('bestOf: only groups with exactly one keeper count', () => {
  const b = bestOf([
    { ids: ['a', 'b'], pick: 'a' },            // one keeper, same frame
    { ids: ['c', 'd', 'e', 'f'], pick: 'c' },  // one keeper, another frame
    { ids: ['g', 'h'], pick: 'g' },            // both kept
    { ids: ['i', 'j'], pick: 'i' },            // none kept
    { ids: ['k'], pick: 'k' },                 // a single: not a group
  ], new Set(['a', 'd', 'g', 'h', 'k']));
  assert.deepEqual([b.groups, b.oneKeeper, b.agree, b.manyKeepers, b.noKeeper], [4, 2, 1, 1, 1]);
  assert.equal(b.agreement, 0.5); assert.equal(b.chance, (1 / 2 + 1 / 4) / 2);
  assert.deepEqual(b.misses, [{ ids: ['c', 'd', 'e', 'f'], pick: 'c', kept: 'd' }]);
  assert.deepEqual(b.bySize['3-5'], { oneKeeper: 1, agree: 0, agreement: 0 });
});

test('pool: counts add, ratios are recomputed', () => {
  const p = pool([picks(new Set(['a']), new Set(['a']), ['a', 'b']), picks(new Set(['c', 'd']), new Set(['e']), ['c', 'd', 'e'])]);
  assert.deepEqual([p.tp, p.fp, p.fn, p.frames, p.kept, p.auto], [1, 2, 1, 5, 2, 3]);
  assert.equal(p.precision, 1 / 3); assert.equal(p.recall, 0.5);
});

const fr = (id, time, o = {}) => ({ id, name: id + '.ARW', date: '2026:01:01 ' + time, t: seconds('2026:01:01 ' + time), seq: 1, shutter: +id.slice(1), lens: 'FE 35mm', fl: 35, orient: 1, ...o });

test('truthGroups: drive ⊂ repeat ⊂ scene', () => {
  const F = [fr('f1', '10:00:00'), fr('f2', '10:00:00', { seq: 2 }), fr('f3', '10:00:01', { seq: 3 }),   // a camera burst
    fr('f4', '10:00:03'),                                                                             // by hand, 2 s later
    fr('f5', '10:00:11'),                                                                             // another try, 8 s later
    fr('f6', '10:00:13', { orient: 6 }),                                                              // turned: a new group
    fr('f7', '10:00:14', { orient: 6, fl: 85 }),                                                      // zoomed: a new group
    fr('f8', '10:05:00', { orient: 6, fl: 85 })];
  const t = truthGroups(F), label = (m, ...a) => a.map(id => m.get(id));
  assert.equal(new Set(label(t.drive, 'f1', 'f2', 'f3')).size, 1);
  assert.notEqual(t.drive.get('f4'), t.drive.get('f3'));
  assert.equal(new Set(label(t.repeat, 'f1', 'f2', 'f3', 'f4')).size, 1);
  assert.notEqual(t.repeat.get('f5'), t.repeat.get('f4'));
  assert.equal(new Set(label(t.scene, 'f1', 'f2', 'f3', 'f4', 'f5')).size, 1);
  assert.equal(new Set(label(t.scene, 'f5', 'f6', 'f7', 'f8')).size, 4);
  // order comes from time and the shutter count, not from the order given
  assert.deepEqual([...truthGroups(F.slice().reverse()).repeat.entries()].sort(), [...t.repeat.entries()].sort());
});

test('truthGroups: sequence numbers that restart are separate presses', () => {
  const t = truthGroups([fr('f1', '10:00:00', { fl: 35 }), fr('f2', '10:00:00', { seq: 2 }), fr('f3', '10:00:01', { seq: 1, fl: 200, lens: 'FE 70-200mm' }), fr('f4', '10:00:01', { seq: 2, fl: 200, lens: 'FE 70-200mm' })]);
  assert.equal(new Set(t.drive.values()).size, 2);
  assert.equal(sameFraming({ lens: 'a', fl: 50, orient: 1 }, { lens: 'a', fl: 52, orient: 1 }), true);
  assert.equal(sameFraming({ lens: 'a', fl: 50, orient: 1 }, { lens: 'a', fl: 70, orient: 1 }), false);
});

test('matchExports: by name, by capture time for renamed files, virtual copies, ambiguity', () => {
  const raws = [
    { id: 'r1', name: 'DSC00001.ARW', date: '2026:01:01 10:00:00', exp: 0.01, fnum: 4, iso: 100, fl: 35 },
    { id: 'r2', name: 'LUM00002.ARW', date: '2026:01:01 10:00:05', exp: 0.01, fnum: 4, iso: 100, fl: 35 },
    { id: 'r3', name: 'LUM00003.ARW', date: '2026:01:01 10:00:09', exp: 0.01, fnum: 4, iso: 100, fl: 35 },
    { id: 'r4', name: 'LUM00004.ARW', date: '2026:01:01 10:00:09', exp: 0.02, fnum: 4, iso: 100, fl: 35 },
    { id: 'r5', name: 'LUM00005.ARW', date: '2026:01:01 10:00:20', exp: 0.01, fnum: 4, iso: 100, fl: 35 },
    { id: 'r6', name: 'LUM00006.ARW', date: '2026:01:01 10:00:20', exp: 0.01, fnum: 4, iso: 100, fl: 35 },
    { id: 'r7', name: 'LUM00007.ARW', date: '2026:01:01 10:00:30', exp: 0.01, fnum: 4, iso: 100, fl: 35 },
  ];
  const ex = (name, raw, time, o = {}) => ({ name, raw, date: '2026:01:01 ' + time, exp: 0.01, fnum: 4, iso: 100, fl: 35, ...o });
  const m = matchExports(raws, [ex('DSC00001.jpg', 'DSC00001.ARW', '10:00:00'), ex('DSC00001-2.jpg', 'DSC00001.ARW', '10:00:00'),
    ex('DSC09002.jpg', 'DSC09002.ARW', '10:00:05'),                 // renamed on the card copy: found by time
    ex('DSC09004.jpg', 'DSC09004.ARW', '10:00:09', { exp: 0.02 }),  // two in that second: the exposure decides
    ex('DSC09005.jpg', 'DSC09005.ARW', '10:00:20'),                 // two in that second, same exposure: ambiguous
    ex('DSC09999.jpg', 'DSC09999.ARW', '11:00:00')]);               // its RAW is not here
  assert.deepEqual([...m.kept].sort(), ['r1', 'r2', 'r4']);
  assert.deepEqual([...m.ambiguous].sort(), ['r5', 'r6']);
  assert.deepEqual(m.unmatched, ['DSC09999.jpg']);
  assert.deepEqual(m.rule, { name: 2, time: 2 });
});

test('matchExports: file numbers repeat across cards; a derived export goes to the RAW it is named after', () => {
  const raws = [
    { id: 'old', name: 'DSC00001.ARW', date: '2025:01:01 09:00:00' },
    { id: 'new', name: 'DSC00001.ARW', date: '2026:01:01 10:00:00' },
    { id: 'b1', name: 'DSC00002.ARW', date: '2026:01:01 10:00:07' },
    { id: 'b2', name: 'DSC00003.ARW', date: '2026:01:01 10:00:07' },
  ];
  const m = matchExports(raws, [{ name: 'a.jpg', raw: 'DSC00001.ARW', date: '2025:01:01 09:00:00' }, { name: 'b.jpg', raw: 'DSC00001.ARW', date: '2026:01:01 10:00:00' },
    { name: 'c.jpg', raw: 'DSC00003-Enhanced-NR.dng', date: '2026:01:01 10:00:07' }]);
  assert.deepEqual([...m.kept].sort(), ['b2', 'new', 'old']);
  assert.equal(m.ambiguous.size, 0);
  assert.deepEqual(m.rule, { name: 2, time: 1 });
});

test('core: the page\'s own logic gives stacks, keeps and flags, keyed by path', () => {
  const fx = JSON.parse(fs.readFileSync(path.join(DESIGN, 'lumina-core-v4.fixtures.json'), 'utf8'));
  const c = run(fx.stacks.input), big = c.stacks.filter(s => s.ids.length > 1);
  assert.deepEqual(big.map(s => s.kind + ':' + s.ids.length), fx.stacks.expect);
  for (const s of big) {
    if (s.kind === 'bracket') { assert.equal(s.pick, null); s.ids.forEach(id => assert.ok(c.pagePick.has(id) && c.sug.has(id))); }
    else { assert.ok(s.ids.includes(s.pick)); assert.equal(s.ids.filter(id => c.pagePick.has(id)).length, 1); assert.equal(c.flags.get(s.pick).rank, 1); }
  }
  assert.equal(c.stack.size, fx.stacks.input.length); assert.equal(new Set(c.order).size, fx.stacks.input.length);
});

test('core: cutsFor stacks a truth group the page left as singles', () => {
  const p = (i, s, focus) => ({ name: 'DSC0000' + i + '.ARW', path: 'x/' + i, date: '2026:09:26 14:00:' + String(s).padStart(2, '0'), exp: 0.004, fl: 35, ev: 0, iso: 400, lens: 'FE 35mm', lum: 0.5, focus, clip: 0, portrait: false, src: '', lg: '' });
  const list = [p(1, 0, 100), p(2, 4, 300), p(3, 8, 200), p(4, 40, 150)];
  const first = run(list); assert.equal(first.stacks.every(s => s.ids.length === 1), true);
  const truth = groups(['x/1', 'x/2', 'x/3'], ['x/4']), forced = run(list, cutsFor(first, truth, first.order));
  const g = forced.stacks.find(s => s.ids.length === 3);
  assert.deepEqual(g.ids, ['x/1', 'x/2', 'x/3']); assert.equal(g.pick, 'x/2');
});

test('measure: a phone is shown as readOne shows it, a camera is unchanged', () => {
  const phone = recordOf({ make: 'Apple', model: 'iPhone 15 Pro', fl: 6.86, fl35: 24, lens: 'iPhone 15 Pro back triple camera 6.86mm f/1.78', date: '2026:05:19 10:00:00', exp: 0.01, iso: 64 }, '/s/IMG_0001.DNG', 1000);
  assert.deepEqual([phone.make, phone.model, phone.lens, phone.fl, phone.name], ['Apple', 'iPhone 15 Pro', '1× camera', 24, 'IMG_0001.DNG']);
  assert.equal(recordOf({ make: 'Apple', model: 'iPhone 15 Pro', fl: 6.86, lens: 'back camera' }, 'x.DNG', 1).fl, 6.86, 'no 35 mm focal length: the real one stays, and so does the lens');
  assert.equal(recordOf({ make: 'Apple', model: 'iPhone 15 Pro', fl: 6.86, lens: 'back camera' }, 'x.DNG', 1).lens, 'back camera');
  const sony = { make: 'SONY', model: 'ILCE-7M3', fl: 35, fl35: 35, lens: 'FE 35mm F1.8', date: '2026:05:19 10:00:00', exp: 0.004, iso: 100 };
  for (const f of ['/s/DSC00001.ARW', '/s/DSC00001.DNG']) {
    const r = recordOf(sony, f, 1000);
    assert.deepEqual([r.make, r.model, r.lens, r.fl], ['SONY', 'ILCE-7M3', 'FE 35mm F1.8', 35], 'a Sony camera is not a phone, whatever the extension');
  }
  assert.equal(recordOf({ model: 'ILCE-7M3', fl: 35 }, 'x.ARW', 1).make, null);
});

test('measure: the eval reads the files the page reads', () => {
  assert.deepEqual(['a.ARW', 'b.arw', 'c.DNG', 'd.dng', 'e.JPG', 'f.xmp', 'g.HEIC', 'h.ARW.xmp'].filter(n => RAW_FILE.test(n)), ['a.ARW', 'b.arw', 'c.DNG', 'd.dng']);
});

test('measure: the page\'s readOne is the one lib/measure.mjs repeats', () => {
  assert.equal(readOneHash(), READONE, 'the design\'s readOne changed: review IN_PAGE and recordOf in Tools/culleval/lib/measure.mjs, then update READONE');
});

test('report: file names stay below the "Worst" heading', () => {
  const g = { ...pairwise(groups(['a', 'b']), groups(['a', 'b']), ['a', 'b']), ...splits(groups(['a', 'b']), groups(['a', 'b']), ['a', 'b']) };
  const cut = { groups: 1, cut: 0, whole: 1 }, pk = picks(new Set(['a']), new Set(['a']), ['a', 'b']), b = { ...bestOf([{ ids: ['a', 'b'], pick: 'a' }], new Set(['a'])), misses: 0 };
  const shoot = { id: 's', note: '', frames: 2, days: 1, shot: 2, rows: 1, noPreview: 0, complete: true, grouping: { drive: g, repeat: g, scene: g }, rowsWhole: { drive: cut, repeat: cut, scene: cut },
    stacks: { stacks: 1, framesInStacks: 2, brackets: 0 }, flags: { soft: 0, blown: 0, shake: 0, dark: 0 }, truth: { source: 'exports', exports: 1, edited: 1, frames: 2, kept: 1 },
    picks: { suggested: pk, pagePick: pk, flagsAsReject: pk }, bestOf: { stacks: b, repeat: b, scene: b },
    patterns: { falseKeeps: 0, falseKeeps_sceneHasAKeeper: 0, falseKeeps_sceneAllRejected: 0, falseKeeps_loneFrame: 0, missedKeeps: 0, missedKeeps_flaggedSoft: 0, missedKeeps_flaggedBlown: 0, missedKeeps_flaggedShake: 0, missedKeeps_notSharpestInStack: 0, scenesWithKeeper_notOneStack: 0, scenesWithKeeper: 1 } };
  const one = { shoots: 1, suggested: pk, pagePick: pk, flagsAsReject: pk, bestOf: { stacks: b, repeat: b, scene: b } };
  const md = markdown({ when: 'now', core: 'x', readOneDrift: false, gaps: { repeatGap: 2, sceneGap: 10 }, shoots: [shoot],
    pooled: { grouping: { drive: g, repeat: g, scene: g }, whatIfDriveRead: { drive: g, repeat: g }, driveRead: { frames: 0, truthFrames: 0 }, picksComplete: one, picksAll: one } },
    { s: { worst: [{ kind: 'k', kept: 'DSC01234.ARW', lumina: 'DSC01235.ARW', detail: '' }], groupingWorst: [] } });
  const [above, below] = md.split('\n## Worst');
  assert.ok(!/DSC0123/.test(above)); assert.ok(/DSC01234\.ARW/.test(below)); assert.ok(/F1/.test(above));
});

// ——— through the app (lib/app.mjs): a probe dump against picks
const shot = (n, o = {}) => ({ path: 'shoot/DSC' + String(n).padStart(5, '0') + '.ARW', date: '2026-05-19', sec: '10:00:' + String(n % 60).padStart(2, '0'), row: 0, gid: 'g' + n, kind: 'single', rank: 1, peak: false, sug: true, soft: false, slight: false, blown: false, shake: false, dark: false, ...o });

test('app: a pick is an export that names the RAW at its capture second; only days with a pick are scored', () => {
  const ex = app.exportsFromCsv('SourceFile,FileName,RawFileName,DateTimeOriginal\r\na/x.jpg,x.jpg,DSC00001.ARW,2026:05:19 10:00:01\n"a/y, z.jpg",y.jpg,,2026:05:19 10:00:02\na/w.jpg,w.jpg,DSC09999.ARW,2026:05:19 11:00:00\n');
  assert.deepEqual(ex.map(e => [e.name, e.raw, e.date]), [['a/x.jpg', 'DSC00001.ARW', '2026:05:19 10:00:01'], ['a/w.jpg', 'DSC09999.ARW', '2026:05:19 11:00:00']], 'a camera JPEG names no RAW');
  const photos = [shot(1), shot(1, { path: 'old/DSC00001.ARW', date: '2025-01-01' }), shot(2)];      // the same file number on another card
  const l = app.label(photos, ex);
  assert.deepEqual(photos.map(p => p.pick), [true, false, false]);
  assert.equal(l.photos.length, 2);
  assert.deepEqual(l.unmatched, ['a/w.jpg']);
});

test('app: recall of the suggested keeps, a flag\'s false alarms on picks, the pick of a burst against rank 1', () => {
  const burst = [2, 1, 3, 4].map((rank, i) => shot(10 + i, { row: 1, gid: 'b', kind: 'burst', rank, sug: rank === 1, peak: i === 2, pick: rank === 1 }));
  const photos = [shot(1, { pick: true }), shot(2, { soft: true, sug: false, pick: true }), shot(3, { sug: false, pick: false }), ...burst].map(p => ({ ...p, pool: 'a' }));
  const s = app.score(photos);
  assert.deepEqual([s.photos, s.picks, s.days], [7, 3, 1]);
  assert.equal(s.suggested.recall, 2 / 3); assert.equal(s.suggested.precision, 1); assert.equal(s.suggested.keptIfNot, 1 / 5);
  assert.deepEqual([s.flags.soft.auto, s.flags.soft.tp, s.flags.soft.precision, s.flags.soft.recall], [1, 1, 1, 1 / 3]);
  assert.deepEqual([s.bursts.bursts, s.bursts.frames, s.bursts.withAPick, s.bursts.picksInBursts, s.bursts.picksSingle], [1, 4, 1, 1, 2]);
  assert.deepEqual([s.bursts.rank1.oneKeeper, s.bursts.rank1.agree, s.bursts.rank1.chance], [1, 1, 0.25]);
  assert.deepEqual([s.bursts.peak.oneKeeper, s.bursts.peak.agree], [1, 0]);
  assert.deepEqual(s.rows, { rows: 2, withAPick: 2, meanSize: 3.5, meanPicksWhenAny: 1.5 });
  // The same paths in another dump are other photos.
  assert.equal(app.score([...photos, ...photos.map(p => ({ ...p, pool: 'b' }))]).bursts.bursts, 2);
});

test('app: the report names no files', () => {
  const photos = [shot(1), shot(2, { sug: false })].map(p => ({ ...p, pool: 'pool-a' }));
  const l = app.label(photos, [{ name: 'x.jpg', raw: 'DSC00001.ARW', date: '2026:05:19 10:00:01' }]), s = app.score(l.photos);
  const md = app.markdown({ 'pool-a': s, empty: app.score([]) }, s, 1, 0);
  assert.match(md, /\| pool-a \| 1 \| 2 \| 1 \| 50 % \| 1 \(50 %\) \| 100 % \|/);
  assert.match(md, /\| empty \| 0 \| 0 \| 0 \|/);
  assert.match(md, /not found in these folders: 1\./);
  assert.doesNotMatch(md, /DSC0|\.ARW|\.jpg/);
});
