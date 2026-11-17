#!/usr/bin/env python3
"""Bind the unchanged PDF verifier to the isolated, fully qualified retry source."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import traceback

SOURCE_COMMIT = 'b87f9d6c3a2532c9695024adf48ca9fbd3c0927a'
SOURCE_TREE = 'acb1d1060879dc4a8168df8abf3105dc828af360'
VERIFIER_SHA256 = 'dc089ba747fdbd8acd04d07fbe18986763020f2b3df419a0fef65ee9ce381b3f'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def git(source, *args):
    return subprocess.check_output(['git', '-C', str(source), *args], timeout=60).decode().strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['source-dir', 'verifier', 'input', 'output', 'producer-receipt', 'invocation']:
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    source = args.source_dir.resolve()
    verifier = args.verifier.resolve()
    emitted = args.input.resolve()
    output = args.output.resolve()
    producer = args.producer_receipt.resolve()
    invocation_path = args.invocation.resolve()
    binding_path = output.with_name(output.name + '-binding.json')
    require(not binding_path.exists(), 'Preserve the earlier binding; choose a new output directory for another attempt.')
    require(not output.exists() or (output.is_dir() and not any(output.iterdir())), 'PDF verifier output must be new or empty.')
    require(sha(verifier) == VERIFIER_SHA256, 'Original PDF verifier bytes changed.')
    require(git(source, 'rev-parse', 'HEAD') == SOURCE_COMMIT, 'The isolated source checkout must remain at the qualified commit.')
    require(git(source, 'rev-parse', 'HEAD^{tree}') == SOURCE_TREE, 'The isolated source tree differs from the qualified tree.')
    receipt = json.loads(producer.read_text())
    invocation = json.loads(invocation_path.read_text())
    require(receipt.get('status') == 'passed' and receipt.get('all_passed') is True, 'Wait for the full canonical qualification to pass before PDF verification.')
    require(receipt.get('qualified_published_source_commit') == SOURCE_COMMIT and receipt.get('qualified_source_tree') == SOURCE_TREE, 'Producer source identity does not match.')
    require(Path(receipt['source_checkout']).resolve() == source, 'Producer checkout does not match the selected isolated checkout.')
    gates = ['analysis_config_restored', 'source_inputs_unchanged', 'external_dependency_and_runtime_inputs_unchanged', 'harness_inputs_unchanged', 'published_source_still_matches']
    require(all(receipt.get(key) is True for key in gates), 'Producer integrity gates are incomplete or failed.')
    require(invocation['source_commit'] == SOURCE_COMMIT and invocation['expected_tree'] == SOURCE_TREE, 'Invocation source identity does not match.')
    require(invocation['expected_runner_sha256'] == receipt['reproduction_script_sha256'], 'Invocation and producer runner hashes differ.')
    require(Path(invocation['environment']['QUDS_ALIAS_RENDER_OUTPUT']).resolve() == emitted, 'Selected PDF directory differs from the recorded emitting invocation.')
    cohort = next(row for row in receipt['commands'] if row['name'] == 'engine-recovery-integration')
    require(cohort['status'] == 'passed' and cohort['exit_code'] == 0 and cohort['passed_tests'] is not None, 'The emitting engine cohort did not complete successfully.')
    emitters = ['test/pdf_cid_encoding_test.dart', 'test/pdf_unicode_alias_export_test.dart']
    require(all(name in cohort['command'] for name in emitters), 'Producer command does not contain both PDF emitting tests.')
    require(sha(producer.parent / cohort['log']) == cohort['log_sha256'], 'Producer engine log does not match its final receipt.')
    module = {'__name__': 'quds_original_pdf_verifier', '__file__': str(verifier)}
    exec(compile(verifier.read_bytes(), str(verifier), 'exec'), module)
    original_repo = str(module['REPO'])
    module['REPO'] = source
    source_after = json.loads((producer.parent / 'source-after.json').read_text())['sha256_by_path']
    checked_source = {}
    absent_declared_source = []
    for name in module['SOURCE_PATHS']:
        path = source / name
        if not path.is_file():
            require(not git(source, 'ls-tree', SOURCE_COMMIT, '--', name), 'Tracked verifier source input is missing: ' + name)
            require(name not in source_after, 'Producer input is missing from the verifier checkout: ' + name)
            absent_declared_source.append(name)
            continue
        checked_source[name] = sha(path)
        require(source_after.get(name) == checked_source[name], 'Verifier source differs from the finalized producer input map: ' + name)
    inputs = {}
    for name in module['INPUT_NAMES']:
        path = emitted / name
        require(path.is_file(), 'Expected fresh PDF fixture input is missing: ' + name)
        inputs[name] = {'path': str(path), 'bytes': path.stat().st_size, 'sha256': sha(path), 'modified_utc': datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat()}
    binding = {
        'schema': 'quds-retry-pdf-verifier-binding-v1',
        'started_utc': datetime.now(timezone.utc).isoformat(),
        'source_commit': SOURCE_COMMIT,
        'source_tree': SOURCE_TREE,
        'source_checkout': str(source),
        'original_verifier': {'path': str(verifier), 'sha256': sha(verifier)},
        'wrapper': {'path': str(Path(__file__).resolve()), 'sha256': sha(Path(__file__))},
        'only_verifier_override': {'name': 'REPO', 'original': original_repo, 'selected': str(source)},
        'verifier_checks_changed': False,
        'producer_receipt': {'path': str(producer), 'sha256': sha(producer)},
        'invocation': {'path': str(invocation_path), 'sha256': sha(invocation_path)},
        'completed_emitting_command': cohort,
        'emitted_inputs_before': inputs,
        'source_sha256_matched_to_final_producer_map': checked_source,
        'absent_declared_source_paths_not_tracked_or_in_producer_map': absent_declared_source,
        'dependency_lock_scope': 'The original verifier snapshots its declared paths only when present. This source has no tracked root pubspec.lock; the completed producer receipt independently fingerprints the unchanged locked harness inputs.',
        'counts_added_to_dart_flutter_qualification': 0,
        'provenance_scope': 'Inputs are taken from the directory named by the recorded emitting invocation after its complete successful source-bound producer run. The unmodified verifier separately copies and hashes the producer receipt and fixture inputs.',
        'passed': False,
    }
    old_argv = sys.argv
    try:
        sys.argv = [str(verifier), '--input', str(emitted), '--output', str(output), '--producer-receipt', str(producer)]
        exit_code = module['main']()
        binding['verifier_exit_code'] = exit_code
        verified = json.loads((output / 'receipt.json').read_text())
        binding['verifier_receipt_sha256'] = sha(output / 'receipt.json')
        binding['checked_source_still_matches'] = all(sha(source / name) == value for name, value in checked_source.items())
        binding['passed'] = exit_code == 0 and verified.get('passed') is True and binding['checked_source_still_matches'] and verified['source_before_sha256'] == checked_source
        return 0 if binding['passed'] else 1
    except BaseException as error:
        binding['error'] = type(error).__name__ + ': ' + str(error)
        binding['traceback'] = traceback.format_exc()
        raise
    finally:
        sys.argv = old_argv
        binding['finished_utc'] = datetime.now(timezone.utc).isoformat()
        binding_path.write_text(json.dumps(binding, indent=2, sort_keys=True) + '\n')
        print(json.dumps({'binding': str(binding_path), 'passed': binding['passed']}), flush=True)


if __name__ == '__main__':
    raise SystemExit(main())
