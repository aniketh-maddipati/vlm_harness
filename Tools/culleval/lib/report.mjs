// The report as Markdown. Numbers only above "## Worst"; file names appear only below it, and the
// report is written outside the repo.
const pct = x => (x == null ? '–' : (100 * x).toFixed(0) + ' %');
const f2 = x => (x == null ? '–' : x.toFixed(2));
const table = (head, rows) => ['| ' + head.join(' | ') + ' |', '|' + head.map(() => '---').join('|') + '|', ...rows.map(r => '| ' + r.join(' | ') + ' |')].join('\n');

const LEVEL = { drive: 'camera bursts (drive mode)', repeat: 'bursts by hand (same framing, seconds apart)', scene: 'tries at one picture (same framing, close in time)' };

export function markdown(rep, local = {}) {
  const S = rep.shoots.filter(s => !s.skipped), K = S.filter(s => s.picks), out = [];
  out.push('# Lumina culling eval', '', rep.when + ' · core ' + rep.core + (rep.readOneDrift ? ' · readOne changed, review lib/measure.mjs' : '') + ' · bursts by hand ≤ ' + rep.gaps.repeatGap + ' s · tries ≤ ' + rep.gaps.sceneGap + ' s', '');
  out.push('## Truth', '', table(['shoot', 'frames', 'of shot', 'days', 'keeps known for', 'kept', 'keep rate', 'truth', 'note'],
    S.map(s => [s.id, s.frames, s.shot ?? '–', s.days, s.truth ? s.truth.frames : '–', s.truth ? s.truth.kept : '–', s.truth ? pct(s.truth.kept / s.truth.frames) : '–', s.truth ? s.truth.source + (s.truth.exports != null ? ' (' + s.truth.exports + ', ' + s.truth.edited + ' edited' + (s.truth.fromKeepsList ? ', ' + s.truth.fromKeepsList + ' from a saved keeps list' : '') + ')' : '') + (s.complete ? '' : ' · partial') : s.truthMissing ? 'grouping only · ' + s.truthMissing : 'grouping only', s.note])), '',
    '"of shot" is the camera\'s shutter count from the first to the last frame: how many frames were taken in that span. Exports that carry no edits at all are a batch export, not a selection; do not use them as keeps.', '');
  for (const s of rep.shoots.filter(s => s.skipped)) out.push('- skipped ' + s.id + ': ' + s.skipped);

  out.push('', '## Grouping: Lumina\'s stacks against what was shot', '', 'A pair counts when two frames share a group. Precision: of the pairs Lumina stacked, how many belong together. Recall: of the pairs that belong together, how many Lumina stacked.', '');
  const gr = (name, g) => [name, g.truthGroups, g.predGroups, pct(g.precision), pct(g.recall), f2(g.f1), g.exact, g.overSplit, g.merged, g.underSplit];
  for (const level of ['repeat', 'drive', 'scene']) {
    out.push('### ' + LEVEL[level], '', table(['shoot', 'truth groups', 'Lumina stacks', 'precision', 'recall', 'F1', 'exact', 'over-split', 'whole but merged', 'stacks mixing groups'],
      [...S.map(s => gr(s.id, s.grouping[level])), gr('**all**', rep.pooled.grouping[level])]), '');
    const sizes = {}; for (const s of S) for (const [b, v] of Object.entries(s.grouping[level].bySize)) { const t = (sizes[b] ||= { groups: 0, exact: 0, overSplit: 0, pairs: 0, pairsKept: 0 }); for (const k of Object.keys(t)) t[k] += v[k]; }
    if (Object.keys(sizes).length) out.push(table(['truth group size', 'groups', 'exact', 'over-split', 'pair recall'], Object.keys(sizes).sort().map(b => [b, sizes[b].groups, sizes[b].exact, sizes[b].overSplit, pct(sizes[b].pairsKept / sizes[b].pairs)])), '');
  }
  const W = rep.pooled.whatIfDriveRead, D = rep.pooled.driveRead;
  out.push('### What if the page read the camera\'s drive data', '', 'The page read drive data (sequence number, release mode) on ' + D.frames + ' frames; exiftool finds ' + D.truthFrames + ' frames shot in a continuous or bracket mode. The same shoots with that data filled in:', '',
    table(['against', 'truth groups', 'Lumina stacks', 'precision', 'recall', 'F1', 'exact', 'over-split', 'whole but merged', 'stacks mixing groups'], [gr(LEVEL.drive, W.drive), gr(LEVEL.repeat, W.repeat)]), '');
  out.push('### Rows', '', 'No row truth exists (nobody has marked scenes). What can be checked: a row boundary should never fall inside a burst or a run of tries.', '',
    table(['shoot', 'rows', 'frames per row', 'camera bursts cut', 'bursts by hand cut', 'tries cut'], S.map(s => [s.id, s.rows, (s.frames / s.rows).toFixed(1), ...['drive', 'repeat', 'scene'].map(l => s.rowsWhole[l].cut + ' of ' + s.rowsWhole[l].groups)])), '');
  out.push(table(['shoot', 'stacks', 'frames in stacks', 'brackets', 'flagged soft', 'blown', 'shake', 'dark', 'no preview'], S.map(s => [s.id, s.stacks.stacks, s.stacks.framesInStacks, s.stacks.brackets, s.flags.soft, s.flags.blown, s.flags.shake, s.flags.dark, s.noPreview])), '');

  if (K.length) {
    out.push('## Keeps: Lumina\'s automatic keeps against the photographer\'s', '',
      '"Suggested" is the core\'s suggested keeps (the sharpest clean frame of a stack, every clean single). "P on every unit" is what pressing P once on every stack and photo keeps. Keeping everything has precision = the keep rate and recall 100 %.', '');
    const pr = (name, p) => [name, p.frames, p.kept, p.auto, pct(p.precision), pct(p.recall), f2(p.f1), pct(p.keepRate)];
    const rows = [], P = rep.pooled;
    for (const s of K) rows.push(pr(s.id + ' · suggested', s.picks.suggested), pr(s.id + ' · P on every unit', s.picks.pagePick));
    if (P.picksComplete) rows.push(pr('**complete shoots · suggested**', P.picksComplete.suggested));
    if (P.picksAll && (!P.picksComplete || P.picksAll.shoots !== P.picksComplete.shoots)) rows.push(pr('**all with keeps · suggested**', P.picksAll.suggested));
    out.push(table(['', 'frames', 'really kept', 'auto keeps', 'precision', 'recall', 'F1', 'keep rate'], rows), '');
    out.push('Flags (soft, blown, shake) read as "reject": precision = flagged frames the photographer did reject.', '',
      table(['shoot', 'flagged', 'of them rejected', 'precision', 'share of all rejects'], K.map(s => { const f = s.picks.flagsAsReject; return [s.id, f.auto, f.tp, pct(f.precision), pct(f.recall)]; })), '');
    out.push('### Best of stack', '', 'Groups where the photographer kept exactly one frame: did Lumina pick the same one? "Lumina\'s stacks" are the stacks it made. The other two rows take the truth groups as if they had been stacked by hand and ask the core which frame it keeps. Chance = picking at random.', '');
    const bo = (name, b) => [name, b.groups, b.oneKeeper, b.agree, pct(b.agreement), pct(b.chance)];
    const br = []; for (const s of K) br.push(bo(s.id + ' · Lumina\'s stacks', s.bestOf.stacks), bo(s.id + ' · bursts by hand', s.bestOf.repeat), bo(s.id + ' · tries at one picture', s.bestOf.scene));
    const PB = P.picksAll.bestOf; br.push(bo('**all · Lumina\'s stacks**', PB.stacks), bo('**all · bursts by hand**', PB.repeat), bo('**all · tries at one picture**', PB.scene));
    out.push(table(['', 'groups', 'with one keeper', 'agree', 'agreement', 'chance'], br), '');
    const sizes = {}; for (const s of K) for (const [b, v] of Object.entries(s.bestOf.scene.bySize)) { const t = (sizes[b] ||= { oneKeeper: 0, agree: 0 }); t.oneKeeper += v.oneKeeper; t.agree += v.agree; }
    if (Object.keys(sizes).length) out.push('By size (tries at one picture):', '', table(['group size', 'with one keeper', 'agree', 'agreement'], Object.keys(sizes).sort().map(b => [b, sizes[b].oneKeeper, sizes[b].agree, pct(sizes[b].agree / sizes[b].oneKeeper)])), '');
    out.push('### Where it goes wrong', '');
    for (const s of K) { const p = s.patterns; out.push('**' + s.id + '**', '',
      '- suggested but rejected: ' + p.falseKeeps + ' (' + p.falseKeeps_sceneHasAKeeper + ' were one of several tries where another try was kept · ' + p.falseKeeps_sceneAllRejected + ' in a run of tries with none kept · ' + p.falseKeeps_loneFrame + ' lone frames)',
      '- kept but not suggested: ' + p.missedKeeps + ' (flagged soft ' + p.missedKeeps_flaggedSoft + ' · blown ' + p.missedKeeps_flaggedBlown + ' · shake ' + p.missedKeeps_flaggedShake + ' · not the sharpest of its stack ' + p.missedKeeps_notSharpestInStack + ')',
      '- runs of tries with a keeper that Lumina did not show as one stack: ' + p.scenesWithKeeper_notOneStack + ' of ' + p.scenesWithKeeper, ''); }
  } else out.push('## Keeps', '', 'No shoot in the config has a keep / reject truth.', '');

  out.push('## Worst disagreements (file names: this report stays on this Mac)', '');
  for (const s of S) { const l = local[s.id] || {}; if (!(l.worst || []).length && !(l.groupingWorst || []).length) continue;
    out.push('### ' + s.id, '');
    if ((l.worst || []).length) out.push(table(['what', 'photographer kept', 'Lumina', 'detail'], l.worst.map(w => [w.kind, w.kept, w.lumina, w.detail])), '');
    if ((l.groupingWorst || []).length) out.push(table(['what', 'frames', 'first', 'last', 'Lumina stacks'], l.groupingWorst.map(w => [w.kind, w.frames, w.first, w.last, w.luminaStacks])), '');
    if ((l.exportsWithoutRaw || []).length) out.push('Exports whose RAW is not in the folder: ' + l.exportsWithoutRaw.join(', '), ''); }
  return out.join('\n') + '\n';
}
