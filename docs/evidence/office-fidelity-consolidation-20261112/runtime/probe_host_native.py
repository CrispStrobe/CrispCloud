"""Render the eleven new actual host uploads with the unchanged native gate."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import os
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('repository', type=Path)
parser.add_argument('input_directory', type=Path)
parser.add_argument('output_directory', type=Path)
args = parser.parse_args()
repo = args.repository.resolve()
root = args.input_directory.resolve()
output = args.output_directory.resolve()
os.chdir(repo)
assert not output.exists(), 'Native probe must start with a fresh output directory'
output.mkdir(parents=True)
manifest = json.loads((repo / 'build/external/input-manifest.json').read_text())
schema_path = repo / 'build/external/schema-report.json'
schema = json.loads(schema_path.read_text())
assert manifest['total'] == schema['Files'] == 300 and schema['Failures'] == 0
expected = {entry['path']: entry['sha256'] for entry in manifest['files']}
receipts = {Path(entry['File']).resolve(): entry for entry in schema['Reports']}
spec = importlib.util.spec_from_file_location('office_render', repo / 'tool/office-validation/render.py')
render = importlib.util.module_from_spec(spec)
spec.loader.exec_module(render)
names = [f'pending-{kind}{close}-{when}-save.{extension}'
         for kind, extension in (('cell', 'xlsx'), ('slide', 'pptx'))
         for close in ('', '-close') for when in ('before', 'after')]
names += ['word-docm-save.docm', 'word-dotx-save.dotx', 'word-dotm-save.dotm']
assert len(names) == len(set(names)) == 11
report = {
    'status': 'running',
    'source_commit': manifest['source_commit'],
    'managed_source_commit': manifest['managed_source_commit'],
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
    source = root / relative
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    receipt = receipts[source]
    assert digest == expected[relative] == receipt['Sha256']
    assert receipt.get('Errors') == [] and 'Exception' not in receipt
    try:
        record = render.render_document(source, root, output, index)
        record['input_sha256'] = digest
        report['reports'].append(record)
        print(f'{name}: rendered {record["pages"]} pages', flush=True)
    except (OSError, subprocess.SubprocessError, render.FidelityError) as error:
        report['failures'].append({'file': relative, 'input_sha256': digest,
                                   **render.failure_details(error)})
        print(f'{name}: {error}', flush=True)
    assert hashlib.sha256(source.read_bytes()).hexdigest() == digest
    (output / 'render-report.json').write_text(json.dumps(report, indent=2) + '\n')
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
