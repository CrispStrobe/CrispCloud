"""Render eleven host uploads from an explicitly counted exact app snapshot.

This supplementary native scope does not certify repeated save cycles or the
complete engine corpus. Every input remains bound to the frozen SDK byte receipt.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import subprocess
import sys
import time

sys.dont_write_bytecode = True
from app_external_acceptance import (count_options, read_json, require, require_file,
                                     require_runtime_environment, runtime_receipt, sha,
                                     verify_pins, verify_schema)

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('repository', type=Path)
parser.add_argument('input_directory', type=Path)
parser.add_argument('output_directory', type=Path)
parser.add_argument('--manifest', required=True, type=Path)
parser.add_argument('--schema-report', required=True, type=Path)
count_options(parser)
args = parser.parse_args()
repo = args.repository.resolve()
root = args.input_directory.resolve()
output = args.output_directory.resolve()
manifest_path = args.manifest.resolve()
schema_path = args.schema_report.resolve()
require(manifest_path.name == 'input-manifest.json' and
        schema_path == manifest_path.parent / 'schema-report.json',
        'Probe requires the frozen manifest and its exact adjacent SDK report')
require_runtime_environment()
manifest = verify_schema(manifest_path.parent, args)
schema = read_json(schema_path)
require(root == Path(manifest['input_root']).resolve() and
        repo == Path(manifest['repository']).resolve(), 'Probe input/repository mismatch')
verify_pins(repo, manifest['source_commit'], manifest['managed_source_commit'], args.managed_count)
for name, digest in runtime_receipt(repo).items():
    require(digest == manifest[name], f'Frozen runtime or validation script changed: {name}')
expected = {entry['path']: entry['sha256'] for entry in manifest['files']}
receipts = {Path(entry['File']): entry for entry in schema['Reports']}
spec = importlib.util.spec_from_file_location('office_render', repo / 'tool/office-validation/render.py')
render = importlib.util.module_from_spec(spec)
spec.loader.exec_module(render)
names = [f'pending-{kind}{close}-{when}-save.{extension}'
         for kind, extension in (('cell', 'xlsx'), ('slide', 'pptx'))
         for close in ('', '-close') for when in ('before', 'after')]
names += ['word-docm-save.docm', 'word-dotx-save.dotx', 'word-dotm-save.dotm']
require(len(names) == len(set(names)) == 11, 'Supplementary native scope changed')
for name in names:
    require('build/fidelity-host/' + name in expected, f'Missing declared native host capture: {name}')
require(not output.exists(), 'Native probe must start with a fresh output directory')
output.mkdir(parents=True)
report = {
    'status': 'running',
    'source_commit': manifest['source_commit'],
    'managed_source_commit': manifest['managed_source_commit'],
    'schema_input_count': args.engine_count + args.host_count,
    'engine_files': args.engine_count, 'host_files': args.host_count,
    'managed_source_files_verified': args.managed_count,
    'input_manifest_sha256': hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
    'probe_script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'renderer': subprocess.check_output(['libreoffice', '--version'], text=True).strip(),
    'scope': 'Supplementary native conversion of eleven actual host uploads: four XLSX, four PPTX, and DOCM/DOTX/DOTM. No repeated-save-cycle certification is implied.',
    'native_conversion_function': 'Unchanged tool/office-validation/render.py render_document',
    'native_conversion_script_sha256': hashlib.sha256((repo / 'tool/office-validation/render.py').read_bytes()).hexdigest(),
    'schema_report_sha256': hashlib.sha256(schema_path.read_bytes()).hexdigest(),
    'files': 11, 'reports': [], 'failures': [],
}
started = time.monotonic()
for index, name in enumerate(sorted(names)):
    relative = 'build/fidelity-host/' + name
    source = require_file(root, relative)
    digest = sha(source)
    receipt = receipts[source]
    require(digest == expected[relative] == receipt['Sha256'], f'SDK input hash mismatch: {relative}')
    require(receipt.get('Errors') == [] and 'Exception' not in receipt, f'SDK failure: {relative}')
    try:
        record = render.render_document(source, root, output, index)
        record['input_sha256'] = digest
        report['reports'].append(record)
        print(f'{name}: rendered {record["pages"]} pages', flush=True)
    except (OSError, subprocess.SubprocessError, render.FidelityError) as error:
        report['failures'].append({'file': relative, 'input_sha256': digest,
                                   **render.failure_details(error)})
        print(f'{name}: {error}', flush=True)
    require(sha(require_file(root, relative)) == digest, f'Native renderer changed input: {relative}')
    (output / 'render-report.json').write_text(json.dumps(report, indent=2) + '\n')
verify_schema(manifest_path.parent, args)
verify_pins(repo, manifest['source_commit'], manifest['managed_source_commit'], args.managed_count)
require(len(report['reports']) + len(report['failures']) == 11, 'Incomplete supplementary native capture')
report.update({
    'status': 'failed' if report['failures'] else 'passed',
    'rendered_files': len(report['reports']),
    'rendered_pages': sum(entry['pages'] for entry in report['reports']),
    'all_input_hashes_unchanged': True,
    'elapsed_seconds': time.monotonic() - started,
})
(output / 'render-report.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({key: report[key] for key in ('status', 'rendered_files', 'rendered_pages', 'elapsed_seconds')}))
raise SystemExit(1 if report['failures'] else 0)
