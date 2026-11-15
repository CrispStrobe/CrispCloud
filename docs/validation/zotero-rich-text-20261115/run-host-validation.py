from pathlib import Path
import datetime, hashlib, json, os, re, subprocess, sys
root = Path('/workspace/scratch/be107e83b1bb')
repo = root / 'CrispCloud'
stage = root / 'crisp-host-staging'
evidence = root / 'runtime-validation'
packages = ['quds_office_engine', 'quds_office_editor', 'quds_reports', 'legacy_doc_parser']
def snapshot():
    files = ['test/office_zotero_test.dart', 'test/office_zotero_ribbon_test.dart', 'analysis_options.yaml']
    files += sorted(str(p.relative_to(repo)) for p in (repo / 'lib').rglob('*') if p.is_file())
    for name in packages:
        files += sorted(str(p.relative_to(repo)) for p in (repo / 'packages' / name / 'lib').rglob('*') if p.is_file())
        files.append(f'packages/{name}/pubspec.yaml')
    return {p: hashlib.sha256((repo / p).read_bytes()).hexdigest() for p in sorted(set(files))}
before = snapshot()
vendor_manifest = json.loads((repo / 'tool/office_fidelity_manifest.json').read_text())
manifest = json.dumps(before, sort_keys=True, separators=(',', ':')).encode()
(evidence / 'host-source-hashes.json').write_text(json.dumps(before, indent=2) + '\n')
command = [str(root / 'flutter-sdk/bin/flutter'), 'test', '--no-pub', '--concurrency=1', '--reporter', 'expanded', 'test/office_zotero_test.dart', 'test/office_zotero_ribbon_test.dart']
started = datetime.datetime.now(datetime.timezone.utc).isoformat()
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
with (evidence / 'host-tests.log').open('w') as output:
    run = subprocess.run(command, cwd=stage, stdout=output, stderr=subprocess.STDOUT)
after = snapshot()
log = (evidence / 'host-tests.log').read_text()
passed = re.search(r'\+(\d+): All tests passed!', log)
receipt = {
    'started_at_utc': started,
    'completed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'repo': 'https://github.com/CrispStrobe/CrispCloud',
    'vendored_quds_commit_at_test': vendor_manifest['source_commit'],
    'standalone_sources_at_test': vendor_manifest['standalone_sources'],
    'head_at_start': head,
    'head_at_completion': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
    'source_files': len(before),
    'source_files_unchanged_during_run': before == after,
    'source_changed_paths': [p for p in sorted(set(before) | set(after)) if before.get(p) != after.get(p)],
    'source_inventory': 'host-source-hashes.json',
    'source_inventory_aggregate_sha256': hashlib.sha256(manifest).hexdigest(),
    'log': 'host-tests.log',
    'log_sha256': hashlib.sha256((evidence / 'host-tests.log').read_bytes()).hexdigest(),
    'runtime': json.loads((root / 'flutter-sdk/bin/cache/flutter.version.json').read_text()),
    'command': command,
    'cwd': str(stage),
    'environment': {k: os.environ[k] for k in ['TMPDIR','PUB_CACHE','XDG_CONFIG_HOME','CI','FLUTTER_ROOT','FLUTTER_SUPPRESS_ANALYTICS','DART_SUPPRESS_ANALYTICS']},
    'exit_code': run.returncode,
    'passed': int(passed.group(1)) if passed else None,
    'harness': {
       'manifest_text': (stage / 'pubspec.yaml').read_text(),
       'lockfile_text': (stage / 'pubspec.lock').read_text(),
       'source_links': {'lib': str(repo / 'lib'), **{f'test/{n}': str(repo / 'test' / n) for n in ['office_zotero_test.dart', 'office_zotero_ribbon_test.dart']}},
       'packages': {name: {'manifest_text': (stage / 'packages' / name / 'pubspec.yaml').read_text(), 'source_links': {p.name: str(p.resolve()) for p in (stage / 'packages' / name).iterdir() if p.is_symlink()}} for name in packages},
       'resolution': 'flutter pub get --enforce-lockfile; normal package downloads and SDK tools; copied focused manifest and rebased historical lock; canonical manifests untouched',
    },
    'limitations': ['Focused real host service/transport/ribbon tests, not complete native app build or full production dependency resolution.', 'No live Zotero desktop/private account, OS keychain or Microsoft Word acceptance.', 'No GitHub Actions polled.']
}
(evidence / 'host-validation-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({k: receipt[k] for k in ['exit_code','passed','source_files','source_files_unchanged_during_run','source_changed_paths']}))
sys.exit(run.returncode or (0 if before == after else 2))
