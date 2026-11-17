#!/usr/bin/env python3
"""Link the exact three source examples imported by pdf_widgets_test.dart.

No nested example pubspec, dependency resolution or test execution is added.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess

COMMIT = 'b87f9d6c3a2532c9695024adf48ca9fbd3c0927a'
FILES = ['pdf_widgets_invoice.dart', 'pdf_widgets_proposal.dart', 'pdf_widgets_report.dart']
FONTS = [
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf',
]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = args.workspace.resolve()
    source = root / 'quds-validation'
    harness = root / 'zotero-toolchain/retry-harness/quds_office_engine'
    assert subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip() == COMMIT
    inputs = ['pubspec.yaml', 'pubspec.lock', '.dart_tool/package_config.json', '.dart_tool/package_graph.json']
    before = {path: sha((harness / path).read_bytes()) for path in inputs}
    target_dir = harness / 'example'
    assert not target_dir.is_symlink(), 'Keep the example wrapper narrow; do not expose its workspace pubspec'
    target_dir.mkdir(exist_ok=True)
    assert not (target_dir / 'pubspec.yaml').exists()
    rows = []
    for name in FILES:
        relative = 'packages/quds_office_engine/example/' + name
        data = subprocess.check_output(['git', '--no-replace-objects', '-C', str(source), 'cat-file', 'blob', COMMIT + ':' + relative])
        actual = source / relative
        assert actual.read_bytes() == data, relative
        entry = subprocess.check_output(['git', '--no-replace-objects', '-C', str(source), 'ls-tree', COMMIT, '--', relative], text=True).strip().split('\t')[0].split()
        directives = [uri for _, uri in re.findall(r'^\s*(?:import|export|part)\s+([\'"])([^\'"]+)\1', data.decode(), re.MULTILINE)]
        relatives = [uri for uri in directives if not uri.startswith(('dart:', 'package:'))]
        assert not relatives, (relative, relatives)
        destination = target_dir / name
        if destination.is_symlink():
            assert destination.resolve() == actual
        elif destination.exists():
            raise ValueError(f'Refusing to replace {destination}')
        else:
            destination.symlink_to(actual)
        assert destination.read_bytes() == data
        rows.append({'canonical_path': relative, 'harness_path': str(destination.relative_to(root)),
                     'source_git_mode': entry[0], 'source_git_blob': entry[2], 'sha256': sha(data),
                     'bytes': len(data), 'import_export_part_uris': directives,
                     'relative_import_export_part_closure': relatives})
    after = {path: sha((harness / path).read_bytes()) for path in inputs}
    assert before == after
    fonts = {name: {'exists': Path(name).is_file(),
                    'sha256': sha(Path(name).read_bytes()) if Path(name).is_file() else None} for name in FONTS}
    receipt = {'recorded_utc': datetime.now(timezone.utc).isoformat(), 'source_commit': COMMIT,
               'direct_importer': 'packages/quds_office_engine/test/pdf_widgets_test.dart',
               'required_source_files': rows, 'relative_source_closure_is_exactly_the_three_examples': True,
               'only_required_examples_exposed': sorted(p.name for p in target_dir.iterdir()) == sorted(FILES),
               'nested_pubspec_absent': not (target_dir / 'pubspec.yaml').exists(),
               'harness_manifests_locks_and_graphs_before': before,
               'harness_manifests_locks_and_graphs_after': after,
               'harness_manifests_locks_and_graphs_unchanged': before == after,
               'optional_system_font_presence_and_sha256': fonts,
               'pub_get_or_tests_run': False, 'production_or_sdk_changes': False,
               'helper_sha256': sha(Path(__file__).read_bytes())}
    assert receipt['only_required_examples_exposed']
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n')
    print(json.dumps(receipt, indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
