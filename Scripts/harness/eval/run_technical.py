#!/usr/bin/env python3
"""Run a named private Sony evaluation with frozen input/code/model provenance."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import plistlib
import subprocess
import time
from sony_inventory import atomic_json, digest, private_output


def fingerprint(root):
    # Includes untracked source changes, excludes git artifacts and all personal data.
    paths = subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard'],cwd=root,text=True).splitlines()
    h=hashlib.sha256()
    for name in sorted(set(paths)):
        if name.startswith(('Lumina/', 'LuminaLogicTests/', 'Scripts/harness/eval/')):
            p=root/name
            if p.is_file(): h.update(name.encode()+b'\0'+p.read_bytes())
    return h.hexdigest()


def bind_manifest(out, manifest):
    path=out/'run-manifest.json'
    if path.exists() and json.loads(path.read_text()) != manifest:
        raise ValueError('Run inputs changed; use a new named run. Resume refused.')
    atomic_json(path,manifest)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('raw','edits','truth','out','xctestrun'): p.add_argument('--'+name,required=True,type=Path)
    p.add_argument('--limit',type=int)
    p.add_argument('--model',default='qwen2.5-vl-3b-instruct')
    p.add_argument('--live',action='store_true')
    p.add_argument('--legacy-model',action='store_true')
    p.add_argument('--contract',action='store_true')
    p.add_argument('--shoot',action='store_true')
    p.add_argument('--offline-probe',action='store_true')
    a=p.parse_args()
    root=Path(__file__).resolve().parents[3]
    out=private_output(a.out)
    truth=json.loads(a.truth.read_text())
    frames=truth['frames'][:a.limit] if a.limit else truth['frames']
    if a.shoot:
        frames=[{'raw':p.name} for p in sorted(a.raw.iterdir()) if p.suffix.lower()=='.arw']
    manifest=dict(schema=1,commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),
        source_sha=fingerprint(root),truth_sha=digest(a.truth),model=a.model,live=a.live,
        legacy_model=a.legacy_model,contract=a.contract,shoot=a.shoot,offline_probe=a.offline_probe,limit=a.limit,
        inputs={str(a.raw/name):digest(a.raw/name) for name in sorted({f['raw'] for f in frames})},
        exports={} if a.shoot else {str(a.edits/name):digest(a.edits/name) for name in sorted({f['edit'] for f in frames})},
        hardware=platform.platform(),machine=platform.machine(),
        scope='development diagnostics; no heldout evidence',stage_two=False,candidate_limit=1)
    bind_manifest(out,manifest)
    data=plistlib.loads(a.xctestrun.read_bytes())
    testroot=str(a.xctestrun.resolve().parent)
    def expand(value):
        if isinstance(value,str): return value.replace('__TESTROOT__',testroot)
        if isinstance(value,list): return [expand(v) for v in value]
        if isinstance(value,dict): return {k:expand(v) for k,v in value.items()}
        return value
    data=expand(data)
    for config in data['TestConfigurations']:
        for target in config['TestTargets']:
            if target['BlueprintName']=='LuminaLogicTests':
                env=target.setdefault('EnvironmentVariables',{})
                env.update(LUMINA_EVAL_RAW_DIR=str(a.raw.resolve()),LUMINA_EVAL_EDIT_DIR=str(a.edits.resolve()),
                    LUMINA_EVAL_TRUTH=str(a.truth.resolve()),LUMINA_EVAL_OUT=str(out),
                    LUMINA_EVAL_CONTACT_DIR=str(out/'images'),LUMINA_RAW_DIR=str(a.raw.resolve()),
                    LUMINA_TECHNICAL_MODEL='1' if a.live else '0',LUMINA_LIVE_MODEL='1' if a.legacy_model else '0',
                    LUMINA_AUTO_MODEL=a.model)
                if a.offline_probe:
                    env['LUMINA_AUTO_BASE_URL']='http://127.0.0.1:1/v1'
                    env['LUMINA_TECHNICAL_MODEL']='1'
                    env['LUMINA_LIVE_MODEL']='0'
                if a.limit: env['LUMINA_EVAL_LIMIT']=str(a.limit)
                else: env.pop('LUMINA_EVAL_LIMIT',None)
    testfile=out/'run.xctestrun';testfile.write_bytes(plistlib.dumps(data))
    test='testTechnicalShoot' if a.shoot else 'testSonyPreviewExportContract' if a.contract else 'testAutoArmsAgainstHandEdits'
    if a.shoot and (out/'shoot-frames.jsonl').exists():
        raise ValueError('Shoot run already started; use a new named run to avoid duplicate journals')
    command=['xcodebuild','-xctestrun',str(testfile),'-destination','platform=macOS,arch=arm64',
        '-only-testing:LuminaLogicTests/DevelopEvalHarnessTests/'+test,'-test-timeouts-enabled','NO',
        '-resultBundlePath',str(out/('result-'+str(time.time_ns())+'.xcresult')),'test-without-building']
    start=time.monotonic()
    with (out/'xcode.log').open('w') as log: result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
    duration=time.monotonic()-start
    if result.returncode: raise SystemExit(f'Xcode failed: {out}/xcode.log')
    if not a.contract:
        metrics=json.loads((out/'metrics.json').read_text())
        if len(metrics['frames'])!=len(frames): raise SystemExit('Incomplete evaluation; no success claim')
    atomic_json(out/'execution.json',dict(elapsed_seconds=duration,xcode_exit=result.returncode))
    print(out)

if __name__=='__main__': main()
