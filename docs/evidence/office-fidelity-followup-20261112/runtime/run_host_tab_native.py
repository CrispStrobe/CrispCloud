#!/usr/bin/env python3
"""Validate six frozen host tab/ribbon uploads with the unchanged native gates.

Run only after SDK acceptance of the full host snapshot, while the shared native
runtime is idle. This supplements the separate eleven-file host native probe.
"""
import argparse
from datetime import datetime, timezone
from pathlib import Path
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
from app_external_acceptance import (VALIDATOR, count_options, read_json, require,
                                     require_file, require_runtime_environment,
                                     runtime_receipt, sha, verify_pins,
                                     verify_schema, write_json)

SELECTED = tuple(sorted(
    [f'build/fidelity-custom-tabs/host-tabs-{cycle}.docx' for cycle in (1, 2, 3)] +
    [f'build/fidelity-host/ribbon-edits-{cycle}.docx' for cycle in (1, 2, 3)]))
CASES = {'build/fidelity-custom-tabs/host-tabs.docx',
         'build/fidelity-host/ribbon-edits.docx'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', type=Path, required=True,
                        help='Accepted full snapshot directory containing input-manifest.json')
    parser.add_argument('--output', type=Path, required=True, help='Fresh focused evidence directory')
    count_options(parser)
    args = parser.parse_args()
    require((args.engine_count, args.host_count) == (296, 62),
            'This focused evidence must originate in the final 296-engine + 62-host snapshot')
    require_runtime_environment()
    snapshot, output = args.snapshot.resolve(), args.output.resolve()
    manifest = verify_schema(snapshot, args)
    accepted = read_json(snapshot / 'external-summary.json')
    require(accepted['status'] in ('schema_passed_native_pending', 'passed') and
            accepted.get('all_schema_receipt_hashes_match') is True and
            accepted['input_manifest_sha256'] == sha(snapshot / 'input-manifest.json') and
            accepted['schema_report_sha256'] == sha(snapshot / 'schema-report.json'),
            'Full snapshot has no unchanged passing SDK acceptance receipt')
    repository = Path(manifest['repository'])
    source_inputs = Path(manifest['input_root'])
    require(not output.is_relative_to(repository) and not output.is_relative_to(source_inputs),
            'Focused evidence must be outside the app checkout and frozen inputs')
    verify_pins(repository, manifest['source_commit'], manifest['managed_source_commit'], args.managed_count)
    runtime = runtime_receipt(repository)
    for name, digest in runtime.items():
        require(digest == manifest[name], f'Frozen runtime or validation script changed: {name}')
    entries = {item['path']: item for item in manifest['files']}
    selected = [entries[name] for name in SELECTED]
    require(len(selected) == 6 and all(item['producer_group'] == 'host' for item in selected),
            'Focused inputs must be exactly six actual host captures')
    require(not output.exists(), 'Focused validation requires a fresh output directory')
    inputs = output / 'inputs'
    inputs.mkdir(parents=True)
    for name in SELECTED:
        target = inputs / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(require_file(source_inputs, name), target)
    focused = {
        'source_commit': manifest['source_commit'], 'managed_source_commit': manifest['managed_source_commit'],
        'parent_input_manifest_sha256': sha(snapshot / 'input-manifest.json'),
        'parent_schema_report_sha256': sha(snapshot / 'schema-report.json'),
        'parent_total': manifest['total'], 'input_root': str(inputs), 'total': 6, 'files': selected,
    }
    write_json(output / 'input-manifest.json', focused)
    summary = {
        'status': 'running', 'started_utc': datetime.now(timezone.utc).isoformat(),
        'source_commit': manifest['source_commit'], 'managed_source_commit': manifest['managed_source_commit'],
        'managed_source_files_verified': args.managed_count, 'parent_snapshot': str(snapshot),
        'parent_input_manifest_sha256': focused['parent_input_manifest_sha256'],
        'parent_schema_report_sha256': focused['parent_schema_report_sha256'],
        'input_manifest_sha256': sha(output / 'input-manifest.json'),
        'helper_sha256': sha(__file__), 'runtime': runtime,
        'scope': 'Six actual host custom-tab/dialog and ribbon-upload saves; two complete native three-save comparisons. Supplementary to the eleven-file host probe.',
        'files': selected,
    }

    def check_inputs():
        require({p.relative_to(inputs).as_posix() for p in inputs.rglob('*') if p.is_file()} == set(SELECTED),
                'Focused physical input set changed')
        for item in selected:
            path = require_file(inputs, item['path'])
            require(sha(path) == item['sha256'] and path.stat().st_size == item['bytes'],
                    f'Focused input bytes changed: {item["path"]}')

    def check_sdk():
        check_inputs()
        report = read_json(output / 'schema-report.json')
        require(report['Files'] == 6 and report['Failures'] == 0 and len(report['Reports']) == 6,
                'Focused SDK validation must pass all six files')
        rows = {item['File']: item for item in report['Reports']}
        require(set(rows) == {str(inputs / name) for name in SELECTED},
                'Focused SDK receipt set differs from exact input paths')
        for item in selected:
            row = rows[str(inputs / item['path'])]
            require(row['Sha256'] == item['sha256'] and row.get('Errors') == [] and 'Exception' not in row,
                    f'Focused SDK bytes or validity mismatch: {item["path"]}')

    def run(name, command):
        summary.setdefault('commands', {})[name] = command
        write_json(output / 'summary.json', summary)
        with (output / f'{name}.log').open('w') as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=False)
        require(result.returncode == 0, f'{name} failed; preserved report and log')

    try:
        check_inputs()
        run('schema', ['dotnet', str(VALIDATOR), str(inputs), str(output / 'schema-report.json')])
        check_sdk()
        run('render', [sys.executable, str(repository / 'tool/office-validation/render.py'),
                       str(inputs), str(output / 'render'), '--schema-report', str(output / 'schema-report.json')])
        render = read_json(output / 'render/render-report.json')
        require(render['files'] == render['rendered_files'] == render['visual_input_files'] == 6 and
                render['native_schema_only_files'] == 0 and not render['failures'] and
                render['cycle_groups'] == 2, 'Focused native validation must render six files and pass two cycles')
        comparisons = render['cycle_comparisons']
        require(len(comparisons) == 2 and {row['case'] for row in comparisons} == CASES and
                all(row['passed'] is True and row['actual_cycles'] == row['expected_cycles'] == [1, 2, 3]
                    for row in comparisons), 'Focused native comparison set is incomplete or changed')
        require(len(render['reports']) == 6 and {row['file'] for row in render['reports']} == set(SELECTED),
                'Focused native report paths differ from selected inputs')
        check_sdk()
        verify_schema(snapshot, args)
        require(sha(snapshot / 'input-manifest.json') == focused['parent_input_manifest_sha256'] and
                sha(snapshot / 'schema-report.json') == focused['parent_schema_report_sha256'],
                'Accepted parent receipts changed during focused validation')
        verify_pins(repository, manifest['source_commit'], manifest['managed_source_commit'], args.managed_count)
        require(runtime_receipt(repository) == runtime, 'Validation runtime changed during focused execution')
        summary.update(status='passed', sdk_files=6, sdk_failures=0, rendered_files=6,
                       cycle_groups=2, native_failures=[], all_input_hashes_unchanged=True,
                       renderer=render['renderer'], cycle_comparisons=comparisons,
                       evidence_sha256={name: sha(output / name) for name in
                                        ('schema-report.json', 'schema.log', 'render/render-report.json', 'render.log')})
    except Exception as error:
        summary.update(status='failed', error=repr(error))
        raise
    finally:
        summary['finished_utc'] = datetime.now(timezone.utc).isoformat()
        write_json(output / 'summary.json', summary)
    print(str(output / 'summary.json'))


if __name__ == '__main__':
    main()
