#!/usr/bin/env python3
"""Adapt and run the incoming ODS regression cohort on the production graph.

Without --run, this script only prepares adapters and provenance. The two
vendored tests remain byte-for-byte unchanged. No dependency resolution runs.
"""

import argparse
import datetime
import difflib
import hashlib
import json
import pathlib
import re
import stat
import subprocess
import time


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[3]
ENGINE = 'packages/quds_office_engine'
ADAPTER_ROOT = ROOT / 'build/office-incoming-tests'
ORIGINALS = [
    f'{ENGINE}/test/ods_sheet_reader_test.dart',
    f'{ENGINE}/test/sheet_formula_test.dart',
]
FIXTURES = [
    f'{ENGINE}/test/fixtures/fidelity/legacy-sheet.ods',
    f'{ENGINE}/test/fixtures/fidelity/legacy-sheet-edge.ods',
]
HOST_TEST = 'test/widget/ods_editor_workflow_test.dart'
IMPORT = (
    "import 'package:test/test.dart';",
    "import 'package:flutter_test/flutter_test.dart';",
)


def stamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def identity(path):
    return {
        'sha256': sha(path),
        'bytes': path.stat().st_size,
        'mode': oct(stat.S_IMODE(path.stat().st_mode)),
    }


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def source_inventory():
    paths = git('ls-files', '--cached', '--others', '--exclude-standard').splitlines()
    extensions = {'.dart', '.rs', '.c', '.cpp', '.h', '.yaml', '.lock', '.toml'}
    selected = sorted(set(
        path for path in paths
        if (path.startswith(('lib/', 'test/', 'packages/'))
            and pathlib.Path(path).suffix in extensions)
        or path in {'.fvmrc', 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'}
    ))
    return {
        path: sha(ROOT / path) for path in selected if (ROOT / path).is_file()
    }


def adapt(path):
    raw = (ROOT / path).read_bytes()
    text = raw.decode('utf-8')
    replacements = [IMPORT]
    if path.endswith('/ods_sheet_reader_test.dart'):
        replacements.extend(
            (f"'{fixture.removeprefix(ENGINE + '/')}'", f"'{fixture}'")
            for fixture in FIXTURES
        )
    adapted = text
    for before, after in replacements:
        count = adapted.count(before)
        if count != 1:
            raise ValueError(f'{path}: expected one occurrence of {before!r}, got {count}')
        adapted = adapted.replace(before, after, 1)
    # Reversing only the declared substitutions must recover every original byte.
    reversed_text = adapted
    for before, after in reversed(replacements):
        if reversed_text.count(after) != 1:
            raise ValueError(f'{path}: replacement is not uniquely reversible')
        reversed_text = reversed_text.replace(after, before, 1)
    if reversed_text.encode('utf-8') != raw:
        raise ValueError(f'{path}: undeclared byte difference in the adapter')
    target = ADAPTER_ROOT / pathlib.Path(path).name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(adapted.encode('utf-8'))
    diff = ''.join(difflib.unified_diff(
        text.splitlines(keepends=True), adapted.splitlines(keepends=True),
        fromfile=path, tofile=str(target.relative_to(ROOT)),
    ))
    return {
        'original_path': path,
        'original': identity(ROOT / path),
        'adapted_path': str(target.relative_to(ROOT)),
        'adapted': identity(target),
        'substitutions': [{'from': before, 'to': after, 'occurrences': 1}
                          for before, after in replacements],
        'reverse_substitutions_recover_original_bytes': True,
    }, diff


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected-head', required=True,
                        help='Required integrated Git commit; must equal current HEAD.')
    parser.add_argument('--label', default=datetime.datetime.now(
        datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ'),
        help='New evidence subdirectory name; existing directories are refused.')
    parser.add_argument('--run', action='store_true',
                        help='Run the SDK after preparation; omitted means prepare only.')
    parser.add_argument('--toolchain-wrapper', type=pathlib.Path,
                        default=ROOT.parent / 'toolchain/run')
    args = parser.parse_args()
    if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_-]*', args.label):
        parser.error('--label must be a simple nonempty directory name')
    expected = git('rev-parse', '--verify', args.expected_head + '^{commit}')
    head = git('rev-parse', 'HEAD')
    if head != expected:
        parser.error(f'HEAD is {head}; expected integrated source {expected}')
    wrapper = args.toolchain_wrapper.resolve()
    if not wrapper.is_file():
        parser.error(f'Toolchain wrapper does not exist: {wrapper}')
    evidence = HERE / args.label
    evidence.mkdir(exist_ok=False)
    prepared_utc = stamp()
    inventory = source_inventory()
    inventory_path = evidence / 'source-before-sha256.json'
    write_json(inventory_path, inventory)
    protected_paths = [
        *ORIGINALS, *FIXTURES, HOST_TEST,
        'pubspec.yaml', 'pubspec.lock', '.dart_tool/package_config.json',
        'tool/office_fidelity_manifest.json',
    ]
    protected = {path: identity(ROOT / path) for path in protected_paths}
    adapters = []
    diffs = []
    for original in ORIGINALS:
        adapter, diff = adapt(original)
        adapters.append(adapter)
        diffs.append(diff)
    patch = evidence / 'adapters.patch'
    patch.write_text(''.join(diffs))
    command = [
        str(wrapper), 'flutter', 'test', '--no-pub', '--concurrency=1',
        '--reporter=expanded',
        *(adapter['adapted_path'] for adapter in adapters), HOST_TEST,
    ]
    receipt = {
        'scope': 'Targeted incoming ODS reader, validation model and XLSX '
                 'serialization regression acceptance; not full Office qualification.',
        'prepared_utc': prepared_utc,
        'cwd': str(ROOT),
        'source_head': head,
        'source_worktree_status': git('status', '--short').splitlines(),
        'command': command,
        'original_test_files': [*ORIGINALS, HOST_TEST],
        'executed_test_files': [*(adapter['adapted_path'] for adapter in adapters),
                                HOST_TEST],
        'adapters': adapters,
        'adapter_patch': {'path': patch.name, **identity(patch)},
        'protected_inputs_before': protected,
        'source_inventory': {
            'path': inventory_path.name,
            'sha256': sha(inventory_path),
            'count': len(inventory),
            'selection': 'Tracked and nonignored lib/, test/ and packages/ files '
                         'with .dart/.rs/.c/.cpp/.h/.yaml/.lock/.toml suffixes, plus '
                         '.fvmrc, pubspec.yaml, pubspec.lock and analysis_options.yaml.',
        },
        'toolchain_wrapper': {'path': str(wrapper), **identity(wrapper)},
        'adapter_script': {'path': str(pathlib.Path(__file__).relative_to(ROOT)),
                           **identity(pathlib.Path(__file__))},
        'normal_production_graph': True,
        'dependency_resolution_invoked': False,
        'native_hooks_disabled': False,
        'github_actions_queried_or_awaited': False,
        'sdk_invoked': bool(args.run),
    }
    write_json(evidence / 'receipt.json', receipt)
    if not args.run:
        print(json.dumps({'prepared': str(evidence), 'sdk_invoked': False,
                          'source_head': head, 'command': command}, indent=2))
        return 0

    receipt['started_utc'] = stamp()
    write_json(evidence / 'receipt.json', receipt)
    log_path = evidence / 'run.log'
    start = time.monotonic()
    error = None
    code = None
    with log_path.open('w') as log:
        try:
            result = subprocess.run(command, cwd=ROOT, stdout=log,
                                    stderr=subprocess.STDOUT, check=False)
            code = result.returncode
        except BaseException as caught:
            error = f'{type(caught).__name__}: {caught}'
            log.write('\nRunner exception: ' + error + '\n')
    after = source_inventory()
    protected_after = {path: identity(ROOT / path) for path in protected_paths}
    changes = [path for path in sorted(inventory.keys() | after.keys())
               if inventory.get(path) != after.get(path)]
    protected_changes = [path for path in protected_paths
                         if protected[path] != protected_after[path]]
    adapter_changes = [adapter['adapted_path'] for adapter in adapters
                       if identity(ROOT / adapter['adapted_path']) != adapter['adapted']]
    lines = log_path.read_text().splitlines()
    final = next((line for line in reversed(lines)
                  if 'All tests passed!' in line or 'Some tests failed.' in line), '')
    counts = re.search(r'\+(\d+)(?: ~(\d+))?(?: -(\d+))?:', final)
    receipt.update({
        'finished_utc': stamp(),
        'seconds': round(time.monotonic() - start, 3),
        'exit_code': code,
        'runner_error': error,
        'head_at_end': git('rev-parse', 'HEAD'),
        'changed_sources': changes,
        'changed_protected_inputs': protected_changes,
        'changed_adapters': adapter_changes,
        'protected_inputs_after': protected_after,
        'final_test_line': final,
        'log': {'path': log_path.name, **identity(log_path)},
    })
    if counts:
        receipt['counts'] = dict(zip(
            ['passed', 'skipped', 'failed'],
            (int(value or 0) for value in counts.groups()),
        ))
    if changes:
        write_json(evidence / 'source-after-sha256.json', after)
    receipt['accepted'] = (
        code == 0 and error is None and 'All tests passed!' in final
        and not changes and not protected_changes and not adapter_changes
    )
    write_json(evidence / 'receipt.json', receipt)
    print(json.dumps({key: receipt[key] for key in [
        'source_head', 'seconds', 'exit_code', 'runner_error', 'final_test_line',
        'changed_sources', 'changed_protected_inputs', 'changed_adapters', 'accepted',
    ]}, indent=2), flush=True)
    return 0 if receipt['accepted'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
