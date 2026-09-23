#!/usr/bin/env python3
"""Run private RAW parity evidence against a built macOS XCTest bundle."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('raw', 'truth', 'out', 'xctestrun'):
        parser.add_argument('--' + name, required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    out = args.out.resolve()
    if out == root or root in out.parents:
        parser.error('Private evidence must stay outside the repository')
    out.mkdir(parents=True, exist_ok=False)
    names = sorted({row['raw'] for row in json.loads(args.truth.read_text())['frames']})[:8]
    manifest = {'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
                'truthSHA256': digest(args.truth),
                'rawSHA256': {name: digest(args.raw / name) for name in names},
                'sourceSHA256': {str(p.relative_to(root)): digest(p)
                    for folder in ('Lumina', 'LuminaLogicTests') for p in sorted((root / folder).rglob('*.swift'))},
                'comparison': 'interactive vs encoded full-resolution ProPhoto TIFF, both resampled to sRGB; mean CIE76 <= 1.5'}
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2))
    testroot = str(args.xctestrun.resolve().parent)
    def expand(value):
        if isinstance(value, str): return value.replace('__TESTROOT__', testroot)
        if isinstance(value, list): return [expand(v) for v in value]
        if isinstance(value, dict): return {k: expand(v) for k, v in value.items()}
        return value
    data = expand(plistlib.loads(args.xctestrun.read_bytes()))
    for config in data['TestConfigurations']:
        for target in config['TestTargets']:
            if target['BlueprintName'] == 'LuminaLogicTests':
                target.setdefault('EnvironmentVariables', {}).update(
                    LUMINA_EVAL_RAW_DIR=str(args.raw.resolve()), LUMINA_EVAL_EDIT_DIR=str(args.raw.resolve()),
                    LUMINA_EVAL_TRUTH=str(args.truth.resolve()), LUMINA_EVAL_OUT=str(out), LUMINA_LIVE_MODEL='0')
    testfile = out / 'run.xctestrun'
    testfile.write_bytes(plistlib.dumps(data))
    with (out / 'xcode.log').open('w') as log:
        result = subprocess.run(['xcodebuild', '-xctestrun', str(testfile), '-destination', 'platform=macOS,arch=arm64',
            '-only-testing:LuminaLogicTests/DevelopEvalHarnessTests/testSonyPreviewExportContract',
            '-test-timeouts-enabled', 'NO', '-resultBundlePath', str(out / 'result.xcresult'), 'test-without-building'],
            stdout=log, stderr=subprocess.STDOUT)
    if result.returncode or not (out / 'preview-contract.json').exists():
        raise SystemExit(f'Parity failed or incomplete: {out}/xcode.log')
    print(out)


if __name__ == '__main__':
    main()
