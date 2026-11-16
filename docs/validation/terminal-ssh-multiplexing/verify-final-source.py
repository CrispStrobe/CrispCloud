#!/usr/bin/env python3
"""Tie local acceptance, Git source, Office adapters and build outputs together."""

import argparse
import datetime
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[2]
ACCEPTED = '2ca566a3a386b5876274d36ff7d93ea21c93fa80'
RUNTIME_SCOPES = ['lib', 'test', 'packages', 'assets', 'android', 'ios',
                  'macos', 'windows', 'linux', 'web', '.fvmrc', 'pubspec.yaml',
                  'pubspec.lock', 'analysis_options.yaml', 'dart_test.yaml']


def sha(data):
    return hashlib.sha256(data).hexdigest()


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def read_saved(path):
    return path.read_bytes() if path.exists() else gzip.decompress(
        path.with_name(path.name + '.gz').read_bytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pre-web', action='store_true')
    args = parser.parse_args()
    phase_names = ['native', 'analysis', 'format', 'live']
    if not args.pre_web:
        phase_names.append('web')
    base = json.loads(read_saved(OUT / 'native-source-sha256.json'))
    phases = {}
    for phase in phase_names:
        record_bytes = (OUT / f'{phase}.json').read_bytes()
        record = json.loads(record_bytes)
        assert record['exit_code'] == 0 and record['changed_sources'] == [], phase
        raw = read_saved(OUT / f'{phase}-source-sha256.json')
        assert json.loads(raw) == base, phase
        phases[phase] = {
            'head_at_start': record['head_at_start'],
            'exit_code': 0,
            'source_count': record['watched_source_count'],
            'source_inventory_uncompressed_sha256': sha(raw),
            'record_sha256': sha(record_bytes),
            'log_uncompressed_sha256': sha(read_saved(OUT / f'{phase}.log')),
        }

    spec = importlib.util.spec_from_file_location(
        'terminal_validation', ROOT / 'tool/run_terminal_validation.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert module.source_hashes() == base, 'Working source differs from acceptance'
    tree = {}
    for row in git('ls-tree', '-rz', ACCEPTED).split(b'\0'):
        if row:
            metadata, path = row.split(b'\t', 1)
            mode, kind, blob = metadata.decode().split()
            tree[path.decode()] = (mode, kind, blob)
    for name, digest in base.items():
        path = ROOT / name
        assert path.is_file() and not path.is_symlink(), name
        data = path.read_bytes()
        assert sha(data) == digest, name
        blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        mode = '100755' if path.stat().st_mode & 0o111 else '100644'
        assert tree.get(name) == (mode, 'blob', blob), name
    changed = git('diff', '--name-only', ACCEPTED, 'HEAD', '--',
                  *RUNTIME_SCOPES).decode().splitlines()
    assert not changed, changed
    dirty = git('diff', '--name-only', 'HEAD', '--',
                *RUNTIME_SCOPES).decode().splitlines()
    assert not dirty, dirty

    office_dir = OUT / 'incoming-office-tests/post-merge'
    office = json.loads((office_dir / 'receipt.json').read_text())
    assert office['exit_code'] == 0
    assert json.loads(read_saved(office_dir / 'source-before-sha256.json')) == base
    for name, identity in office['protected_inputs_before'].items():
        assert sha((ROOT / name).read_bytes()) == identity['sha256'], name
    for adapter in office['adapters']:
        data = (ROOT / adapter['original_path']).read_bytes()
        for replacement in adapter['substitutions']:
            before = replacement['from'].encode()
            assert data.count(before) == replacement['occurrences']
            data = data.replace(before, replacement['to'].encode())
        assert sha(data) == adapter['adapted']['sha256'], adapter['adapted_path']

    visual_dir = OUT / 'screenshots'
    visual = json.loads((visual_dir / 'review.json').read_text())
    for shot in visual['screenshots']:
        assert sha((visual_dir / shot['file']).read_bytes()) == shot['sha256']
    snapshot = json.loads((visual_dir / visual['source_snapshot']).read_text())
    visual_differences = [name for name, identity in snapshot['files'].items()
                          if sha((ROOT / name).read_bytes()) != identity['sha256']]
    record = {
        'recorded_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'accepted_application_source': ACCEPTED,
        'verified_head': git('rev-parse', 'HEAD').decode().strip(),
        'watched_source_count': len(base),
        'all_phase_inventories_identical': True,
        'current_worktree_source_matches': True,
        'all_watched_bytes_and_modes_match_accepted_git_source': True,
        'runtime_paths_changed_since_accepted_source': changed,
        'phases': phases,
        'targeted_office_source_and_adapters_verified': True,
        'visual_image_hashes_verified': True,
        'visual_packaging_source_differences': visual_differences,
        'visual_identity_limit': visual['source_identity_limit'],
        'github_actions_queried_or_awaited': False,
    }
    if not args.pre_web:
        resource = json.loads((OUT / 'web-resource-run.json').read_text())
        assert resource['exit_code'] == 0 and resource['sdk_restored_exactly']
        sdk = Path(resource['sdk'])
        identities = {name: sha((sdk / name).read_bytes())
                      for name in resource['sdk_before']}
        modes = {name: (sdk / name).stat().st_mode
                 for name in resource['sdk_modes_before']}
        assert identities == resource['sdk_before'] == resource['sdk_after']
        assert modes == resource['sdk_modes_before'] == resource['sdk_modes_after']
        web = json.loads((OUT / 'web.json').read_text())
        assert sha((ROOT / 'build/web/main.dart.js').read_bytes()) == web['main_dart_js']['sha256']
        record.update(sdk_sha256=identities, sdk_modes=modes,
                      sdk_restored_exactly=True, web_bundle=web['main_dart_js'])
    target = 'pre-web-source-verification.json' if args.pre_web else 'final-source-verification.json'
    (OUT / target).write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps(record, indent=2))


if __name__ == '__main__':
    main()
