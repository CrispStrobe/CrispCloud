"""Hash-bind one finalized host acceptance run to the unchanged SDK validator.

The caller supplies the executed app commit, exact host hashes, test paths, and
receipt paths. The manifest at that commit defines the required artifact set.
Each execution receives its own output directory and preserved package bytes.
"""
import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--workspace', type=Path, required=True)
parser.add_argument('--config', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
workspace = args.workspace.resolve()
app = workspace / 'CrispCloud'
tool = workspace / 'toolchain/office-validation'
output = args.output.resolve()
config_bytes = args.config.read_bytes()
config = json.loads(config_bytes)
commit = config['execution_head']
artifact_root_name = config['artifact_root']
root_path = PurePosixPath(artifact_root_name)
assert root_path.parts[:1] == ('build',) and len(root_path.parts) == 2
assert artifact_root_name in (
    'build/office-sheet-state-acceptance',
    'build/office-style-history-acceptance',
    'build/office-fill-host-acceptance',
)


def committed(path):
    return subprocess.check_output(['git', 'show', commit + ':' + path], cwd=app)


manifest_bytes = committed('tool/office_host_evidence.json')
manifest = json.loads(manifest_bytes)
entries = [item for item in manifest['schema_only_artifacts']
           if PurePosixPath(item['path']).parts[:2] == root_path.parts]
roles = {str(PurePosixPath(item['path']).relative_to(root_path)): item['role']
         for item in entries}
assert len(roles) == len(entries) == config['expected_count']
expected = config['artifact_sha256']
assert set(expected) == set(roles)
artifact_root = (app / config.get('artifact_directory', artifact_root_name)).resolve()
assert artifact_root.is_relative_to(app) and artifact_root.is_dir()
office = {'.xlsx', '.pptx', '.docx', '.docm', '.dotx', '.dotm'}
found = {path.relative_to(artifact_root).as_posix()
         for path in artifact_root.rglob('*')
         if path.is_file() and path.suffix.lower() in office}
assert found == set(expected), (found, set(expected))
for name, digest in expected.items():
    assert sha((artifact_root / name).read_bytes()) == digest, name

provenance_path = workspace / 'external-fill-validation/validator-provenance.json'
provenance = json.loads(provenance_path.read_text())
build = provenance['build']
program = 'tool/office-validation/Program.cs'
assert sha(committed(program)) == sha((app / program).read_bytes()) == build['source_sha256']
project = 'tool/office-validation/OfficeValidation.csproj'
assert sha(committed(project)) == sha((app / project).read_bytes()) == provenance['project']['sha256']
assert sha((tool / 'OfficeValidation.dll').read_bytes()) == build['assembly_sha256']
for name, digest in build['dependencies_sha256'].items():
    assert sha((tool / name).read_bytes()) == digest, name

test_sources = []
for name in config['test_sources']:
    digest = sha(committed(name))
    assert sha((app / name).read_bytes()) == digest, name
    test_sources.append({'path': name, 'sha256': digest})

output.mkdir(parents=True, exist_ok=False)
(output / 'run-config.json').write_bytes(config_bytes)
(output / 'host-records').mkdir()
host_records = []
for index, name in enumerate(config['host_records']):
    source = (app / name).resolve()
    assert source.is_relative_to(app) and source.is_file()
    data = source.read_bytes()
    destination = output / 'host-records' / f'{index:02d}-{source.name}'
    compress = source.suffix == '.json' and len(data) > 100000
    if compress:
        destination = destination.with_suffix(destination.suffix + '.gz')
    saved = gzip.compress(data, mtime=0) if compress else data
    destination.write_bytes(saved)
    assert (gzip.decompress(saved) if compress else saved) == data
    host_records.append({'source_path': name, 'sha256': sha(data),
                         'evidence_copy_sha256': sha(saved),
                         'compression': 'gzip' if compress else None,
                         'evidence_copy': destination.relative_to(output).as_posix()})

commands = []
env = dict(os.environ)
env.update(provenance['environment'])
started = datetime.now(timezone.utc).isoformat()
for label, parameters in (
        ('self-test', ['--self-test']),
        ('schema', [str(artifact_root), str(output / 'schema-report.json')])):
    command = [str(workspace / 'toolchain/dotnet/dotnet'),
               str(tool / 'OfficeValidation.dll'), *parameters]
    run = subprocess.run(command, cwd=app, env=env,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (output / (label + '.log')).write_text(run.stdout)
    commands.append({'label': label, 'command': command, 'cwd': str(app),
                     'exit_code': run.returncode, 'log': label + '.log'})
    write_json(output / 'commands.json', commands)
    print(run.stdout, end='', flush=True)
    if label == 'self-test' and run.returncode:
        raise SystemExit(run.returncode)

report = json.loads((output / 'schema-report.json').read_text())
assert report['Files'] == len(expected)
reports = {item['File']: item for item in report['Reports']}
assert len(reports) == len(expected)
(output / 'artifacts').mkdir()
inventory = []
for name in sorted(expected):
    path = artifact_root / name
    data = path.read_bytes()
    assert sha(data) == expected[name] == reports[str(path)]['Sha256'], name
    copy = output / 'artifacts' / name
    copy.parent.mkdir(parents=True, exist_ok=True)
    copy.write_bytes(data)
    assert sha(copy.read_bytes()) == expected[name]
    record = reports[str(path)]
    inventory.append({'file': name, 'source_path': str(path),
                      'role': roles[name], 'sha256': expected[name],
                      'bytes': len(data), 'evidence_copy': copy.relative_to(output).as_posix(),
                      'schema_errors': len(record.get('Errors', [])),
                      'exception': record.get('Exception')})
for item in test_sources:
    assert sha((app / item['path']).read_bytes()) == item['sha256']
write_json(output / 'artifact-inventory.json', inventory)
summary = {
    'schema_version': 1,
    'execution_head': commit,
    'artifact_root': artifact_root_name,
    'validated_directory': str(artifact_root),
    'validation_source': ('frozen_host_capture' if 'artifact_directory' in config
                          else 'live_host_output_root'),
    'validation_scope': 'schema_only',
    'started_utc': started,
    'completed_utc': datetime.now(timezone.utc).isoformat(),
    'test_sources': test_sources,
    'host_records': host_records,
    'manifest_at_execution_sha256': sha(manifest_bytes),
    'validator_source_sha256': build['source_sha256'],
    'validator_assembly_sha256': build['assembly_sha256'],
    'validator_provenance_sha256': sha(provenance_path.read_bytes()),
    'sdk': build['sdk'], 'runtime': build['runtime'], 'openxml': '3.3.0',
    'format_target': 'Office2019',
    'files': report['Files'], 'schema_failures': report['Failures'],
    'schema_exit_code': commands[-1]['exit_code'],
    'self_test_exit_code': commands[0]['exit_code'],
    'authored_inputs': sum(item['role'] == 'authored_input' for item in inventory),
    'actual_uploads': sum(item['role'] == 'host_output' for item in inventory),
    'hashes_match_host_before_during_after_and_copies': True,
    'collector_sha256': sha(Path(__file__).read_bytes()),
    'inventory': inventory,
}
write_json(output / 'validation-summary.json', summary)
print(json.dumps({key: summary[key] for key in (
    'execution_head', 'artifact_root', 'files', 'schema_failures', 'schema_exit_code')}, indent=2))
raise SystemExit(commands[-1]['exit_code'])
