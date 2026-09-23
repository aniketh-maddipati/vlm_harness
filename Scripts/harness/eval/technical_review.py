#!/usr/bin/env python3
"""Private blind review + persistent project queue. No RAW or recipe is overwritten."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import random
import shutil
import statistics
from sony_inventory import atomic_json, digest, private_output

VERSION = 'technical-review-v1'
ARMS = ('neutral', 'auto', 'policy', 'technical')


def key(raw_sha, pipeline, recipe, model):
    return hashlib.sha256(json.dumps([raw_sha, pipeline, recipe, model], sort_keys=True,
                                    allow_nan=False).encode()).hexdigest()


def percentile(values, p):
    if not values:
        return None
    return sorted(values)[min(len(values)-1, int((len(values)-1)*p))]


def prepare(metrics_path, image_dir, inventory_path, out, seed, limit=12):
    out = private_output(out)
    metrics = json.loads(Path(metrics_path).read_text())
    frames = metrics['frames']
    inventory = json.loads(Path(inventory_path).read_text())
    by_name = {}
    for row in inventory['files']:
        by_name.setdefault(Path(row['path']).name, []).append(row)
    run_sha = digest(Path(metrics_path))
    identity = key(run_sha, VERSION, {'seed': seed, 'limit': limit}, 'blinding')
    existing = out / 'project.json'
    if existing.exists():
        if json.loads(existing.read_text())['review_id'] != identity:
            raise ValueError('Review exists for different inputs; use a new output directory')
        return  # preserve owner choices and blinding on resume
    rng = random.Random(seed)
    strata = {}
    for index, frame in enumerate(frames):
        matches = by_name.get(frame['raw'], [])
        if len({r['sha256'] for r in matches}) != 1:
            raise ValueError('Ambiguous or missing RAW inventory match')
        strata.setdefault(matches[0]['session'], []).append(index)
    for indexes in strata.values():
        rng.shuffle(indexes)
    selected = []
    while len(selected) < limit and any(strata.values()):
        for session in sorted(strata):
            if strata[session] and len(selected) < limit:
                selected.append(strata[session].pop())
    queue = []
    pairs = []
    for index, frame in enumerate(frames):
        matches = by_name.get(frame['raw'], [])
        if len({r['sha256'] for r in matches}) != 1:
            raise ValueError('Ambiguous or missing RAW inventory match')
        record = matches[0]
        technical = frame['arms'].get('technical', {})
        recipe = technical.get('recipe', frame['arms']['neutral']['recipe'])
        fingerprint = key(record['sha256'], run_sha, recipe, VERSION)
        queue.append(dict(id=fingerprint, frame=index, raw_sha=record['sha256'],
                          session=record['session'], lighting=record['lighting'],
                          source_recipe=frame['arms']['neutral']['recipe'], proposal=recipe,
                          hypothesis=technical.get('hypothesis', ''), reason=technical.get('reason', 'not run'),
                          action=technical.get('action', 'abstain'), decision='pending',
                          user_reason='', status='abstained' if technical.get('action', 'abstain') == 'abstain' else 'proposed'))
        if index not in selected:
            continue
        for baseline in ('neutral', 'auto', 'policy'):
            arms = [baseline, 'technical']
            if not all(a in frame['arms'] for a in arms):
                continue
            rng.shuffle(arms)
            pair_id = hashlib.sha256(f'{identity}:{index}:{baseline}'.encode()).hexdigest()[:20]
            for side, arm in zip(('A','B'), arms):
                source = Path(image_dir) / f'frame-{index}-{arm}.jpg'
                shutil.copyfile(source, out / f'{pair_id}-{side}.jpg')
            pairs.append(dict(id=pair_id, frame=index, session=record['session'],
                              lighting=record['lighting'], A=arms[0], B=arms[1],
                              choice=None, severe=False, reason=''))
    # Inconsistency is a queue hypothesis, never an automatic correction.
    groups = {}
    for q in queue:
        groups.setdefault(q['session'], []).append(q)
    for group in groups.values():
        exposures = [q['proposal']['exposure'] for q in group]
        center = statistics.median(exposures)
        for q in group:
            q['inconsistency_hypothesis'] = abs(q['proposal']['exposure'] - center) > 0.5
            q['grouping_note'] = 'inferred time group; lighting not confirmed'
    project = dict(version=VERSION, review_id=identity, run_sha=run_sha, queue=queue, pairs=pairs,
                   evidence_scope='development only until frozen untouched shoot split is verified')
    atomic_json(existing, project)
    cards = []
    for pair in pairs:
        pid = pair['id']
        cards.append(f'''<article data-id="{pid}"><h2>Pair {len(cards)+1}</h2><div class="pair"><figure><img loading="lazy" src="{pid}-A.jpg"><figcaption>A</figcaption></figure><figure><img loading="lazy" src="{pid}-B.jpg"><figcaption>B</figcaption></figure></div><select><option value="">Choose technical starting point</option><option>A</option><option>B</option><option>tie</option><option>both bad</option></select><label><input type="checkbox">Severe harmful result</label><input class="reason" placeholder="Reason; identify harmful side A/B"></article>''')
    script = '''const reviewID=REVIEW_ID;const storageKey='lumina-review-'+reviewID;
const cards=[...document.querySelectorAll('article')];
function collect(){return {review_id:reviewID,decisions:cards.map(c=>({id:c.dataset.id,choice:c.querySelector('select').value,severe:c.querySelector('input').checked,reason:c.querySelector('.reason').value}))}}
function save(){localStorage.setItem(storageKey,JSON.stringify(collect()))}
try{let old=JSON.parse(localStorage.getItem(storageKey));for(let d of old?.decisions||[]){let c=cards.find(c=>c.dataset.id===d.id);if(c){c.querySelector('select').value=d.choice;c.querySelector('input').checked=d.severe;c.querySelector('.reason').value=d.reason}}}catch(e){}
document.addEventListener('change',save);document.addEventListener('input',save);
document.querySelector('button').onclick=()=>{save();let a=document.createElement('a');a.href=URL.createObjectURL(new Blob([JSON.stringify(collect(),null,2)],{type:'application/json'}));a.download='review-decisions.json';a.click();URL.revokeObjectURL(a.href)};
'''.replace('REVIEW_ID', json.dumps(identity))
    (out / 'review.html').write_text('<!doctype html><meta charset="utf-8"><title>Technical starting points</title><style>body{font:17px system-ui;background:#222;color:#eee;max-width:1200px;margin:auto}.pair{display:flex}figure{width:48%;margin:1%}img{width:100%}article{padding:24px;border-bottom:1px solid #888}input.reason{width:90%;margin-top:12px}button{position:sticky;top:0;padding:12px}</style><h1>Blind technical starting points</h1><p>Choose a dependable starting edit, not a preferred style. Tie and both bad are valid. Choices stay in this browser until exported. Keep the downloaded file private.</p><button>Export review decisions</button>' + ''.join(cards) + '<script>' + script + '</script>')
    render_queue(project, out)


def render_queue(project, out):
    rows = []
    for q in project['queue']:
        description = html.escape(f"Frame {q['frame']} · {q['status']} · {q['decision']} · {q['reason']} · hypothesis: {q['hypothesis']}")
        rows.append(f'<li>{description}</li>')
    (out / 'queue.html').write_text('<!doctype html><meta charset="utf-8"><title>Shoot review queue</title><h1>Technical review queue</h1><p>Suggestions and abstentions only. No creative selection or original changes.</p><ul>' + ''.join(rows) + '</ul>')


def import_decisions(out, decisions):
    out = private_output(out)
    p = out / 'project.json'
    project = json.loads(p.read_text())
    if decisions['review_id'] != project['review_id']:
        raise ValueError('Stale or foreign review decisions')
    by_id = {x['id']: x for x in project['pairs']}
    seen = set()
    for d in decisions['decisions']:
        if d['id'] in seen or d['id'] not in by_id:
            raise ValueError('Duplicate or unknown pair')
        seen.add(d['id'])
        if not d.get('choice'):
            continue
        if d['choice'] not in ('A','B','tie','both bad'):
            raise ValueError('Unknown choice')
        if not isinstance(d.get('severe'), bool) or not isinstance(d.get('reason'), str):
            raise ValueError('Malformed decision')
        if (d['severe'] or d['choice'] == 'both bad') and not d['reason'].strip():
            raise ValueError('Harmful results require a reason and visual inspection')
        by_id[d['id']].update(choice=d['choice'], severe=d['severe'], reason=d['reason'][:2000])
    atomic_json(p, project)
    return summarize(project)


def choose(out, item_id, choice, expected, reason):
    """Review state only; even acceptance does not write an application recipe."""
    out = private_output(out)
    p = out / 'project.json'
    project = json.loads(p.read_text())
    item = next(q for q in project['queue'] if q['id'] == item_id)
    if expected != item['id']:
        raise ValueError('Stale proposal')
    if choice not in ('accept', 'reject', 'defer'):
        raise ValueError('Invalid review choice')
    item.update(decision=choice, user_reason=reason)
    atomic_json(p, project)
    render_queue(project, out)


def summarize(project):
    result = {}
    for pair in project['pairs']:
        baseline = next(a for a in (pair['A'], pair['B']) if a != 'technical')
        group = (pair['session'], pair['lighting'], baseline)
        bucket = result.setdefault('|'.join(group), dict(wins=0, ties=0, losses=0, both_bad=0, severe=0, pending=0))
        choice = pair['choice']
        field = 'pending' if not choice else 'ties' if choice == 'tie' else 'both_bad' if choice == 'both bad' else 'wins' if pair[choice] == 'technical' else 'losses'
        bucket[field] += 1
        bucket['severe'] += bool(pair['severe'])
    return dict(promotion='NOT PROMOTED: untouched-shoot benefit and interaction gates require evidence',
                abstentions=sum(q['action']=='abstain' for q in project['queue']), comparisons=result)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    s=p.add_subparsers(dest='command',required=True)
    a=s.add_parser('prepare')
    for name in ('metrics','images','inventory','out'): a.add_argument('--'+name,required=True)
    a.add_argument('--seed',type=int,default=230926);a.add_argument('--limit',type=int,default=12)
    a=s.add_parser('import');a.add_argument('--out',required=True);a.add_argument('--decisions',required=True)
    a=s.add_parser('report');a.add_argument('--out',required=True)
    a=s.add_parser('choose')
    for name in ('out','id','expected','choice','reason'): a.add_argument('--'+name,required=True)
    a=p.parse_args()
    if a.command=='prepare': prepare(a.metrics,a.images,a.inventory,a.out,a.seed,a.limit)
    elif a.command=='import': print(json.dumps(import_decisions(a.out,json.loads(Path(a.decisions).read_text())),indent=2))
    elif a.command=='choose': choose(a.out,a.id,a.choice,a.expected,a.reason)
    else: print(json.dumps(summarize(json.loads((Path(a.out)/'project.json').read_text())),indent=2))

if __name__=='__main__': main()
