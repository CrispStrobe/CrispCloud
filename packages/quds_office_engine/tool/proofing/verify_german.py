#!/usr/bin/env python3
"""Locally verify German proofing and write a source-bound receipt.

No GitHub Actions are used. Requires the workspace's resolved dependencies,
Dart 3.12+ (normally the pinned Flutter SDK), Node and the pinned word-list file.
Use --download-wordlist only when a pinned upstream download is desired.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

PACKAGE = Path(__file__).resolve().parents[2]
REPO = PACKAGE.parents[1]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sources() -> dict[str, str]:
    paths: list[Path] = []
    for folder in ['lib/src/proofing', 'test/proofing', 'tool/proofing', 'third_party/proofing']:
        paths.extend(path for path in (PACKAGE / folder).rglob('*') if path.is_file() and '__pycache__' not in path.parts)
    paths.extend([PACKAGE / 'lib/src/opc/zip/deflate_codec.dart', PACKAGE / 'pubspec.yaml', REPO / 'pubspec.lock'])
    return {str(path.relative_to(REPO)): sha256(path) for path in sorted(paths) if path.exists()}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dart', default=shutil.which('dart'))
    parser.add_argument('--node', default=shutil.which('node'))
    wordlist = parser.add_mutually_exclusive_group(required=True)
    wordlist.add_argument('--wordlist', type=Path)
    wordlist.add_argument('--download-wordlist', action='store_true')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not args.dart or not args.node:
        parser.error('Dart and Node executable paths are required')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    before = sources()
    record: dict[str, object] = {
        'schema_version': 1,
        'started_at_utc': datetime.now(timezone.utc).isoformat(),
        'scope': 'Shared proofing contract, shipped German data, rules and terminology; no editor/native Harper/browser claims.',
        'javascript_execution': 'Compiled Dart JavaScript executed in Node; not browser or Worker integration.',
        'source_sha256': before,
        'commands': [],
    }
    commands: list[dict[str, object]] = []
    record['commands'] = commands

    def run(label: str, command: list[str]) -> None:
        started = time.monotonic()
        completed = subprocess.run(command, cwd=PACKAGE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        log = output / f'{label}.log'
        log.write_text(completed.stdout)
        commands.append({'label': label, 'command': command, 'working_directory': str(PACKAGE.relative_to(REPO)),
                         'exit_code': completed.returncode, 'duration_seconds': round(time.monotonic() - started, 3),
                         'log': log.name, 'log_sha256': sha256(log)})
        print(f'{label}: exit {completed.returncode}', flush=True)
        if completed.returncode:
            print(completed.stdout[-6000:], flush=True)
            raise RuntimeError(f'{label} failed')

    success = False
    try:
        run('dart-version', [args.dart, '--version'])
        run('node-version', [args.node, '--version'])
        run('analyze', [args.dart, 'analyze', '--fatal-infos', 'lib/src/proofing', 'test/proofing', 'tool/proofing/german_js_smoke.dart'])
        run('tests', [args.dart, 'test', 'test/proofing', '--reporter', 'expanded'])
        run('javascript-tests', [args.dart, 'test', '--platform', 'node', 'test/proofing', '--reporter', 'expanded'])
        generation = [sys.executable, 'tool/proofing/generate_german_lexicon.py', '--check']
        generation += ['--source', str(args.wordlist.resolve())] if args.wordlist else ['--download']
        run('dictionary-reproducibility', generation)
        with tempfile.TemporaryDirectory(prefix='quds-german-proofing-') as temporary:
            javascript = str(Path(temporary) / 'german-proofing.js')
            run('compile-javascript', [args.dart, 'compile', 'js', '-O2', 'tool/proofing/german_js_smoke.dart', '-o', javascript])
            record['compiled_javascript_sha256'] = sha256(Path(javascript))
            run('javascript-smoke', [args.node, '-e', 'globalThis.self=globalThis; require(process.argv[1]);', javascript])
        success = True
    finally:
        after = sources()
        record['inputs_unchanged_during_validation'] = before == after
        record['passed'] = success and before == after
        record['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
        if before != after:
            record['changed_inputs'] = sorted(path for path in before.keys() | after.keys() if before.get(path) != after.get(path))
        (output / 'receipt.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')
    if not record['passed']:
        raise SystemExit('Source changed during validation; rerun against a stable revision.')
    print(f'Passed; receipt: {output / "receipt.json"}', flush=True)


if __name__ == '__main__':
    main()
