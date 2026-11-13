#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Package existing measurements without invoking document converters."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile

BASE = Path('/workspace/scratch/c1ca2a1344e9')
BASELINE_PIN = 'c05f187b99e46b6d8d1b6aed6610307f33e1725c'
OLD_RUNTIME = 'c5ff75e76163d9abbdd44a9f2a7c5ad210929289'
FIXED_PIN = '1b8cc9e28aa9f4da2d0f0fa9318758bce0e923f1'
EXCLUDED = {'profile', '__pycache__', 'cache', 'tmp'}
HERE = Path(__file__).resolve().parent


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + '\n').encode()


def git(repo, *args):
    return subprocess.check_output(['git', *args], cwd=repo)


def collect(directory, prefix, files, omitted):
    for path in sorted(directory.rglob('*')):
        if not path.is_file():
            continue
        relative = path.relative_to(directory)
        name = (Path(prefix) / relative).as_posix()
        raw = path.read_bytes()
        if EXCLUDED.intersection(relative.parts):
            omitted.append({'path': name, 'bytes': len(raw), 'sha256': sha(raw),
                            'reason': 'Incidental native profile, cache or temporary state'})
            continue
        if path.is_symlink() or name in files:
            raise ValueError('Unexpected symlink or duplicate: ' + name)
        files[name] = (raw, 0o755 if path.stat().st_mode & 0o111 else 0o644)


def snapshot_source(repo, report, files):
    pin = report['repository']['commit']
    rows = []
    paths = dict(report['sourceBefore']['files'])
    # Include each actual original fixture, even though the runner's compiler
    # receipt deliberately has a narrower source inventory.
    for case in report['cases']:
        relative = Path(case['source']['path']).relative_to(repo).as_posix()
        paths[relative] = case['source']['sha256']
    for path, digest in sorted(paths.items()):
        result = subprocess.run(['git', 'show', pin + ':' + path], cwd=repo, capture_output=True)
        if result.returncode == 0:
            raw = result.stdout
            kind = 'committed Git object'
            blob = git(repo, 'rev-parse', pin + ':' + path).decode().strip()
        else:
            if path not in {'.dart_tool/package_config.json', 'pubspec.lock'}:
                raise ValueError('Uncommitted source is not a declared resolution input: ' + path)
            raw = (repo / path).read_bytes()
            kind, blob = 'retained generated resolution input', None
        if sha(raw) != digest:
            raise ValueError('Measured source mismatch: ' + path)
        files['source/' + path] = (raw, 0o644)
        rows.append({'path': path, 'bytes': len(raw), 'sha256': digest,
                     'origin': kind, 'gitBlob': blob})
    identity = {'schema': 1, 'commit': pin, 'tree': report['repository']['tree'],
                'measuredSourceFiles': len(report['sourceBefore']['files']), 'files': rows}
    if pin == BASELINE_PIN:
        trees = git(repo, 'rev-parse', pin + ':lib', OLD_RUNTIME + ':lib').decode().splitlines()
        if len(set(trees)) != 1:
            raise ValueError('Baseline runtime differs from its original library')
        identity.update(runtimeUnchangedFrom=OLD_RUNTIME, libraryTree=trees[0])
    files['source-identities.json'] = (encoded(identity), 0o644)


def archive(name, files, omitted):
    files['omissions.json'] = (encoded({'schema': 1, 'files': omitted,
                                      'fileCount': len(omitted),
                                      'rawBytes': sum(r['bytes'] for r in omitted)}), 0o644)
    output = HERE / (name + '.tar.xz')
    with tarfile.open(output, 'w:xz', preset=6, format=tarfile.PAX_FORMAT) as tf:
        for path, (raw, mode) in sorted(files.items()):
            info = tarfile.TarInfo(path)
            info.size, info.mode, info.mtime = len(raw), mode, 0
            tf.addfile(info, io.BytesIO(raw))
    raw = output.read_bytes()
    manifest = {'schema': 1, 'archive': output.name, 'archiveBytes': len(raw),
                'archiveSha256': sha(raw), 'fileCount': len(files),
                'rawBytes': sum(len(v[0]) for v in files.values()),
                'files': [{'path': p, 'bytes': len(v[0]), 'sha256': sha(v[0]), 'mode': oct(v[1])}
                          for p, v in sorted(files.items())]}
    (HERE / (name + '-manifest.json')).write_bytes(encoded(manifest))
    print(json.dumps({k: v for k, v in manifest.items() if k != 'files'}), flush=True)


def matrix(name, directory, repo, pin):
    report = json.loads((directory / 'report.json').read_bytes())
    if report['repository']['commit'] != pin or report['repository']['workingTreeStatus'] != '':
        raise ValueError('Wrong or dirty measurement source')
    if report['status'] not in {'completed-discovery', 'completed-with-errors'}:
        raise ValueError('Measurement is still running')
    files, omitted = {}, []
    collect(directory, 'run', files, omitted)
    snapshot_source(repo, report, files)
    if name == 'baseline':
        collect(BASE / 'path-matrix-observer-c05f187b', 'observer', files, omitted)
        historical = BASE / 'path-matrix-baseline-c05f187b-verification.json'
        files['historical-verification.json'] = (historical.read_bytes(), 0o644)
    archive(name, files, omitted)


def auxiliary():
    files, omitted = {}, []
    for prefix, folder in [('note-order', 'note-order-paths-20261113'),
                           ('markdown-metadata', 'markdown-metadata-controls-20261113'),
                           ('independent-review', 'path-matrix-independent-review')]:
        collect(BASE / folder, prefix, files, omitted)
    files['probe_note_order_paths.py'] = ((BASE / 'probe_note_order_paths.py').read_bytes(), 0o644)
    repo = BASE / 'parser-path-evidence'
    replay_sources = {}
    for name in ['verify_path_matrix.py', 'path_matrix.py', 'oracle.py', 'structure.py', 'run.py', 'goldens.py']:
        path = 'tool/fidelity/' + name
        raw = git(repo, 'show', FIXED_PIN + ':' + path)
        files['replay-source/' + path] = (raw, 0o644)
        replay_sources[path] = sha(raw)
    files['replay-source.json'] = (encoded({'schema': 1, 'commit': FIXED_PIN,
        'tree': git(repo, 'rev-parse', FIXED_PIN + '^{tree}').decode().strip(),
        'files': replay_sources}), 0o644)
    archive('auxiliary', files, omitted)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('scope', choices=['baseline', 'auxiliary', 'fixed'])
    args = parser.parse_args()
    if args.scope == 'baseline':
        matrix('baseline', BASE / 'path-matrix-baseline-c05f187b', BASE / 'parser-path-matrix', BASELINE_PIN)
    elif args.scope == 'fixed':
        matrix('fixed', BASE / 'path-matrix-fixed-1b8cc9e2', BASE / 'parser-independent-combined', FIXED_PIN)
    else:
        auxiliary()


if __name__ == '__main__':
    main()
