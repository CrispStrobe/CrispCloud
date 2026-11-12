"""Verify exact schema/native receipts for the independently frozen name cohort.

Usage: python compare_sheet_qualified_names_native.py REPOSITORY PROOF_DIRECTORY
The input inventory must enumerate source paths, snapshot paths and SHA-256s.
No text normalization, pixel masking, or tolerance is used.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def compare(repository, proof):
    inventory = json.loads((proof / 'native-input-inventory.json').read_text())
    inputs = {Path(item['snapshot']).resolve(): item for item in inventory}
    assert len(inputs) == len(inventory) == 10
    assert set(inputs) == {path.resolve() for path in (proof / 'native-input').glob('*.xlsx')}
    schema = json.loads((proof / 'schema-report.json').read_text())
    assert schema['Files'] == 10 and schema['Failures'] == 0
    receipts = {Path(item['File']).resolve(): item for item in schema['Reports']}
    assert len(receipts) == len(schema['Reports']) == 10 and set(receipts) == set(inputs)
    for path, item in inputs.items():
        assert sha(path) == sha(item['path']) == item['sha256'] == receipts[path]['Sha256']
        assert receipts[path].get('Errors') == [] and 'Exception' not in receipts[path]
    renderer = repository / 'tool/office-validation/render.py'
    spec = importlib.util.spec_from_file_location('office_render', renderer)
    render = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(render)
    native = json.loads((proof / 'native-render/render-report.json').read_text())
    records = {item['file']: item for item in native['reports']}
    assert native['files'] == native['rendered_files'] == len(records) == 10
    assert not native['failures'] and not native['native_schema_only_files']
    assert set(records) == {path.name for path in inputs}
    comparisons = []
    for phase in ('recalculated', 'renamed'):
        expected = f'qualified-{phase}-expected.xlsx'
        for cycle in (1, 2, 3):
            actual = f'{phase}-{cycle}.xlsx'
            render.compare_records(records[expected], records[actual])
            render.compare_records(records[f'{phase}-1.xlsx'], records[actual])
            comparisons.append({'file': actual, 'expected': expected,
                                'pages': records[actual]['pages'],
                                'page_count_text_pixels_exact': True,
                                'three_save_cycle_stable': True})
    for path, item in inputs.items():
        assert sha(path) == sha(item['path']) == item['sha256']
    report = {
        'status': 'passed', 'schema_files': 10, 'rendered_files': 10,
        'rendered_pages': sum(item['pages'] for item in records.values()),
        'comparisons': comparisons, 'all_original_and_snapshot_hashes_unchanged': True,
        'masking_or_tolerance': False,
        'renderer': native['renderer'], 'renderer_script_sha256': sha(renderer),
        'comparison_script_sha256': sha(Path(__file__)),
        'inventory_sha256': sha(proof / 'native-input-inventory.json'),
        'schema_report_sha256': sha(proof / 'schema-report.json'),
        'render_report_sha256': sha(proof / 'native-render/render-report.json'),
        'scope': 'Seven qualified-name source/export packages plus two independently authored name expectations and one current independent rename expectation. Six new exports match their respective authored references across all pages. The old rename expectation updates only D10 from unsupported cache 42 to supported numeric 2; its three final exports are checked by the aggregate source acceptance.',
        'unsupported_name_boundaries': [
            'Explicit worksheet qualification without a local definition',
            'Computed and relative defined-name expressions',
            'External workbook and 3D references',
            'Whole-row and whole-column references',
            'OFFSET with scoped-name origins',
        ],
    }
    (proof / 'native-comparison.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repository', type=Path)
    parser.add_argument('proof_directory', type=Path)
    args = parser.parse_args()
    result = compare(args.repository.resolve(), args.proof_directory.resolve())
    print(json.dumps({key: result[key] for key in ('status', 'schema_files', 'rendered_files', 'rendered_pages')}))
