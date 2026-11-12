#!/usr/bin/env python3
"""Run existing app Word assertions with only the flutter_test import adapted."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote, urljoin, urlparse

# Set by the command-line arguments before preparation or execution.
ROOT = Path()
APP = Path()
CACHE = Path()
DART = Path()
FROM = b'package:flutter_test/flutter_test.dart'
TO = b'package:test/test.dart'
SUITES = [
    'word_conversion_inspection_test.dart',
    'legacy_word_structured_conversion_test.dart',
    'legacy_word_structured_document_test.dart',
    'legacy_word_structured_render_test.dart',
    'legacy_word_structured_bounds_test.dart',
    'legacy_word_sprm_regression_test.dart',
    'legacy_word_document_test.dart',
    'installed_office_converter_test.dart',
]
EXCLUDED = {
    'test/legacy_word_previous_regressions_test.dart':
        'Imports preview_media.dart, Flutter material/services and video_player; '
        'cannot run unchanged using a data-only test import adapter.',
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def git(*args):
    return subprocess.check_output(['git', '-C', str(APP), *args], text=True).strip()


def environment():
    return dict(os.environ, PUB_CACHE=str(CACHE), DART_SUPPRESS_ANALYTICS='true',
                TMPDIR=str(ROOT / 'tmp'))


def link(path, target):
    if path.is_symlink() and path.resolve() == target.resolve():
        return
    if path.exists() or path.is_symlink():
        raise ValueError(f'Unexpected existing adapter path: {path}')
    path.symlink_to(target, target_is_directory=True)


def prepare():
    (ROOT / 'test').mkdir(exist_ok=True)
    link(ROOT / 'lib', APP / 'lib')
    link(ROOT / 'packages', APP / 'packages')
    link(ROOT / 'test/support', APP / 'test/support')
    link(ROOT / 'test/fixtures', APP / 'test/fixtures')
    records = []
    for name in SUITES:
        source = APP / 'test' / name
        original = source.read_bytes()
        if original.count(FROM) != 1:
            raise ValueError(f'Expected exactly one test-framework import: {name}')
        adapted = original.replace(FROM, TO)
        (ROOT / 'test' / name).write_bytes(adapted)
        records.append({'source': 'test/' + name,
                        'sourceSha256': sha(original),
                        'adaptedSha256': sha(adapted),
                        'importReplacementCount': 1})
    manifest = {'version': 1, 'onlyTransformation': {
        'from': FROM.decode(), 'to': TO.decode()},
        'adapters': records, 'excludedSuites': EXCLUDED,
        'unchangedSymlinks': {'lib': str(APP / 'lib'),
                             'packages': str(APP / 'packages'),
                             'test/support': str(APP / 'test/support'),
                             'test/fixtures': str(APP / 'test/fixtures')}}
    write_json(ROOT / 'prepared-adapters.json', manifest)
    return manifest


def label(path):
    path = path.resolve()
    for root, prefix in [(APP, 'app'), (ROOT, 'adapter'), (CACHE, 'pub-cache')]:
        if path.is_relative_to(root):
            return prefix + '/' + path.relative_to(root).as_posix()
    return str(path)


def snapshot():
    config_path = ROOT / '.dart_tool/package_config.json'
    config = json.loads(config_path.read_text())
    packages = {}
    for item in config['packages']:
        package_root = urljoin(config_path.as_uri(), item['rootUri'])
        uri = urlparse(urljoin(package_root.rstrip('/') + '/',
                               item.get('packageUri', '')))
        if uri.scheme != 'file':
            raise ValueError(f'Unsupported package source: {uri.scheme}')
        packages[item['name']] = Path(unquote(uri.path))
    pending = [ROOT / 'test' / name for name in SUITES]
    visited = set()
    inputs = {}
    unresolved = []
    while pending:
        path = pending.pop().resolve()
        if path in visited:
            continue
        visited.add(path)
        data = path.read_bytes()
        inputs[label(path)] = {'sha256': sha(data), 'bytes': len(data)}
        text = data.decode('utf-8')
        for directive in re.finditer(
                r'''(?ms)^\s*(?:import|export|part(?:\s+of)?)\s+(['"][^;]+);''', text):
            for uri in re.findall(r'''['"]([^'"\n]+)['"]''', directive.group(1)):
                if uri.startswith('dart:'):
                    continue
                if uri.startswith('package:'):
                    package, relative = uri[8:].split('/', 1)
                    if package not in packages:
                        unresolved.append({'owner': label(path), 'uri': uri})
                        continue
                    dependency = packages[package] / relative
                else:
                    dependency = path.parent / uri
                pending.append(dependency)
    if unresolved:
        raise ValueError(f'Unresolved package imports: {unresolved}')
    for path in [ROOT / 'pubspec.yaml', ROOT / 'pubspec.lock', config_path,
                 ROOT / 'word_cohort.py', ROOT / 'prepared-adapters.json',
                 APP / 'packages/legacy_doc_parser/UPSTREAM.json',
                 APP / 'tool/office_fidelity_manifest.json',
                 APP / 'test/fixtures/word_native/formatting.doc',
                 *[APP / 'test' / name for name in SUITES]]:
        data = path.read_bytes()
        inputs[label(path)] = {'sha256': sha(data), 'bytes': len(data)}
    return {'files': inputs, 'fileCount': len(inputs),
            'dartVersion': subprocess.check_output([str(DART), '--version'],
                                                   text=True, env=environment()).strip(),
            'dartExecutable': str(DART),
            'dartExecutableSha256': sha(DART.read_bytes()),
            'appCommit': git('rev-parse', 'HEAD'),
            'appWorktreeStatus': git('status', '--porcelain'),
            'parserUpstream': json.loads((APP / 'packages/legacy_doc_parser/UPSTREAM.json').read_text())}


def run(output):
    output.mkdir(parents=True, exist_ok=False)
    adapters = prepare()
    before = snapshot()
    write_json(output / 'adapters.json', adapters)
    write_json(output / 'inputs-before.json', before)
    command = [str(DART), 'test', *['test/' + name for name in SUITES],
               '--concurrency=2', '--reporter=expanded',
               '--file-reporter=json:' + str(output / 'events.jsonl')]
    started = datetime.now(timezone.utc).isoformat()
    with (output / 'tests.log').open('wb') as log:
        result = subprocess.run(command, cwd=ROOT, env=environment(),
                                stdout=log, stderr=subprocess.STDOUT, timeout=300)
    after = snapshot()
    write_json(output / 'inputs-after.json', after)
    definitions = {}
    completions = {}
    suite_paths = {}
    done = None
    for line in (output / 'events.jsonl').read_text().splitlines():
        event = json.loads(line)
        if event.get('type') == 'suite':
            suite_paths[event['suite']['id']] = event['suite']['path']
        elif event.get('type') == 'testStart':
            definitions[event['test']['id']] = event['test']
        elif event.get('type') == 'testDone' and not event.get('hidden', False):
            completions[event['testID']] = event
        elif event.get('type') == 'done':
            done = event
    summaries = {}
    for test_id, event in completions.items():
        test = definitions[test_id]
        name = Path(suite_paths[test['suiteID']]).name
        summary = summaries.setdefault(name, {'passed': 0, 'failed': 0, 'skipped': 0})
        key = 'skipped' if event.get('skipped') else (
            'passed' if event.get('result') == 'success' else 'failed')
        summary[key] += 1
    unchanged = before['files'] == after['files']
    complete = set(summaries) == set(SUITES) and all(
        value['passed'] > 0 and value['failed'] == 0 and value['skipped'] == 0
        for value in summaries.values())
    success = (result.returncode == 0 and bool(done and done['success'])
               and unchanged and complete)
    summary = {'version': 1, 'startedUtc': started,
               'finishedUtc': datetime.now(timezone.utc).isoformat(),
               'command': command, 'cwd': str(ROOT), 'exitCode': result.returncode,
               'sourceAndDependenciesUnchanged': unchanged,
               'expectedSuiteCount': len(SUITES),
               'executedSuiteCount': len(summaries),
               'cohortCompleteWithoutSkips': complete,
               'success': success, 'testCount': len(completions),
               'suites': summaries, 'excludedSuites': EXCLUDED,
               'scope': 'Data-only test adapter; unchanged assertions except test-framework import. '
                        'Installed-Office tests use fake local processes, not real Office rendering. '
                        'This does not execute Flutter widgets or native build hooks.',
               'files': {path.name: {'sha256': sha(path.read_bytes()),
                                    'bytes': path.stat().st_size}
                         for path in output.iterdir() if path.is_file()}}
    write_json(output / 'summary.json', summary)
    print(json.dumps({key: summary[key] for key in
                      ('success', 'testCount', 'suites', 'sourceAndDependenciesUnchanged')}, indent=2))
    return 0 if success else 1


if __name__ == '__main__':
    import gzip
    import shutil

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True,
                        help='CrispCloud checkout to inspect and test')
    parser.add_argument('--workspace', type=Path, required=True,
                        help='New, nonexistent directory for the adapter and results')
    parser.add_argument('--dart', type=Path, required=True,
                        help='Existing Dart executable, 3.13.7 for the recorded environment')
    parser.add_argument('--pub-cache', type=Path, required=True,
                        help='Existing pub cache; resolution is offline')
    args = parser.parse_args()
    APP = args.app.resolve()
    ROOT = args.workspace.resolve()
    CACHE = args.pub_cache.resolve()
    DART = args.dart.resolve()
    if not (APP / 'pubspec.yaml').is_file() or not DART.is_file() or not CACHE.is_dir():
        parser.error('Supply an existing app checkout, Dart executable, and pub cache')
    ROOT.mkdir(parents=True, exist_ok=False)
    (ROOT / 'tmp').mkdir()
    evidence = Path(__file__).resolve().parent
    pubspec = gzip.decompress((evidence / 'cohort-pubspec.yaml.gz').read_bytes()).decode()
    for name in ('legacy_doc_parser', 'quds_office_engine'):
        old = 'path: ../crispcloud/packages/' + name
        if pubspec.count(old) != 1:
            raise ValueError('Unexpected captured dependency declaration: ' + name)
        pubspec = pubspec.replace(old, 'path: ' + json.dumps(str(APP / 'packages' / name)))
    (ROOT / 'pubspec.yaml').write_text(pubspec)
    (ROOT / 'pubspec.lock').write_bytes(
        gzip.decompress((evidence / 'cohort-pubspec.lock.gz').read_bytes()))
    shutil.copyfile(__file__, ROOT / 'word_cohort.py')
    prepare()
    with (ROOT / 'pub-get.log').open('wb') as log:
        resolution = subprocess.run([str(DART), 'pub', 'get', '--offline'],
                                    cwd=ROOT, env=environment(),
                                    stdout=log, stderr=subprocess.STDOUT)
    if resolution.returncode:
        raise SystemExit('Offline dependency resolution failed; see ' + str(ROOT / 'pub-get.log'))
    sys.exit(run(ROOT / 'results'))
