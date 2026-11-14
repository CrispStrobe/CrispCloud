"""Exercise the exact inventory CLI and workflow staging with synthetic packages.

The existing unit fixture builder supplies OPC integrity controls. These are
not host exports, SDK schema acceptance, or rendered/visual acceptance.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys

import yaml


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
app, output = args.app.resolve(), args.output.resolve()
output.mkdir(parents=True, exist_ok=False)
sys.path.insert(0, str(app / 'tool'))
import office_host_evidence as evidence
from test_office_host_evidence import package

manifest = json.loads(evidence.MANIFEST.read_text())
workflow_path = app / '.github/workflows/office-fidelity.yml'
workflow = yaml.safe_load(workflow_path.read_text())
source_hashes = {name: digest(app / name) for name in (
    '.github/workflows/office-fidelity.yml', 'tool/office_host_evidence.py',
    'tool/office_host_evidence.json', 'tool/test_office_host_evidence.py')}
upload = next(step for step in workflow['jobs']['host-roundtrip']['steps']
              if step.get('with', {}).get('name') == 'office-host-fidelity-evidence')
uploaded_paths = {line.strip().rstrip('/') for line in upload['with']['path'].splitlines()}
scoped_roots = {'/'.join(PurePosixPath(item['path']).parts[:2])
               for item in manifest['schema_only_artifacts']}
assert scoped_roots <= uploaded_paths

artifact = output / 'evidence/downloaded-artifact'
references = {entry['path']: entry for entry in evidence.reference_entries()}
for name in evidence.expected_paths():
    path = artifact / name
    if name in references:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes((app / references[name]['fixture']).read_bytes())
    else:
        package(path)

commands = []
environment = dict(os.environ)
environment['PYTHONDONTWRITEBYTECODE'] = '1'


def run(label, command, expected_exit):
    result = subprocess.run(command, cwd=output, env=environment,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (output / (label + '.log')).write_text(result.stdout)
    commands.append({'label': label, 'command': command, 'cwd': str(output),
                     'exit_code': result.returncode, 'expected_exit_code': expected_exit})
    print(result.stdout, end='', flush=True)
    if result.returncode != expected_exit:
        raise AssertionError(f'{label}: expected exit {expected_exit}, got {result.returncode}')


def inventory(label, report, expected_exit):
    run(label, [sys.executable, str(app / 'tool/office_host_evidence.py'), 'verify',
                '--root', str(output / 'evidence'), '--report', str(report)], expected_exit)
    return json.loads(report.read_text())


report = inventory('complete-inventory', output / 'build/external/host-inventory.json', 0)
assert report['expected'] == report['verified'] == 170
assert report['expected_rendered'] == report['verified_rendered'] == 149
assert report['expected_schema_only'] == report['verified_schema_only'] == 21
stage = next(step for step in workflow['jobs']['external-schema']['steps']
             if step.get('name') == 'Stage required rendered host artifacts')
stage_script = output / 'workflow-render-stage.sh'
stage_script.write_text(stage['run'])
run('workflow-render-stage', ['bash', str(stage_script)], 0)
staging = output / 'build/external/host-input'
expected_rendered = set(manifest['outputs']) | set(references)
actual_rendered = {file.relative_to(staging).as_posix()
                   for file in staging.rglob('*') if file.is_file()}
assert actual_rendered == expected_rendered
for name in expected_rendered:
    assert digest(staging / name) == digest(artifact / name)

missing_controls = []
for root in sorted(scoped_roots):
    names = [entry['path'] for entry in manifest['schema_only_artifacts']
             if entry['path'].startswith(root + '/')]
    saved = {name: (artifact / name).read_bytes() for name in names}
    for name in names:
        (artifact / name).unlink()
    label = 'missing-' + PurePosixPath(root).name
    rejected = inventory(label, output / (label + '.json'), 1)
    assert set(rejected['failures']) == {f'{name}: expected one file, found 0' for name in names}
    assert rejected['verified_rendered'] == 149
    missing_controls.append({'root': root, 'missing_files': len(names),
                             'exit_code': 1, 'failures': len(rejected['failures'])})
    for name, data in saved.items():
        (artifact / name).write_bytes(data)

assert source_hashes == {name: digest(app / name) for name in source_hashes}
receipt = {
    'scope': 'Synthetic OPC integrity/CLI/staging controls only. No SDK, host-run, or rendering result is claimed.',
    'app_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=app, text=True).strip(),
    'source_sha256': source_hashes,
    'source_inputs_unchanged': True,
    'pyyaml_version': yaml.__version__,
    'positive_inventory_expected': report['expected'],
    'positive_inventory_verified': report['verified'],
    'render_staging_files': len(actual_rendered),
    'render_staging_exactly_matches_legacy_manifest': True,
    'all_staged_bytes_match_inventory': True,
    'schema_only_files_validated_by_inventory': report['verified_schema_only'],
    'schema_only_roots_in_upload': sorted(scoped_roots),
    'missing_controls': missing_controls,
    'workflow_stage_script_sha256': digest(stage_script),
    'collector_sha256': digest(Path(__file__)),
    'commands': commands,
}
(output / 'artifact-flow-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({key: receipt[key] for key in (
    'positive_inventory_verified', 'render_staging_files',
    'schema_only_files_validated_by_inventory', 'missing_controls')}, indent=2))
