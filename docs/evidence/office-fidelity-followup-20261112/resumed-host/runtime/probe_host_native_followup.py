"""Render eleven uploads plus three custom-tab paragraph-dialog captures."""
from pathlib import Path
from xml.etree import ElementTree as E
from zipfile import ZipFile
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
parser.add_argument('--manifest', required=True, type=Path)
parser.add_argument('--schema-report', required=True, type=Path)
args = parser.parse_args()
repo = args.repository.resolve()
root = args.input_directory.resolve()
output = args.output_directory.resolve()
os.chdir(repo)
assert not output.exists(), 'Native probe must start with a fresh output directory'
output.mkdir(parents=True)
manifest_path = args.manifest.resolve()
manifest = json.loads(manifest_path.read_text())
schema_path = args.schema_report.resolve()
schema = json.loads(schema_path.read_text())
assert manifest['total'] == schema['Files'] == 358 and schema['Failures'] == 0
assert manifest['engine_files'] == 296 and manifest['host_files'] == 62
assert root == Path(manifest['input_root']).resolve()
expected = {entry['path']: entry['sha256'] for entry in manifest['files']}
receipts = {Path(entry['File']).resolve(): entry for entry in schema['Reports']}
assert len(expected) == len(manifest['files']) == len(receipts) == len(schema['Reports']) == 358
assert {p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()} == set(expected)
assert set(receipts) == {root / name for name in expected}
for relative, digest in expected.items():
    path = root / relative
    assert path.resolve().is_relative_to(root) and not path.is_symlink()
    assert hashlib.sha256(path.read_bytes()).hexdigest() == digest == receipts[path]['Sha256']
    assert receipts[path].get('Errors') == [] and 'Exception' not in receipts[path]
assert hashlib.sha256((repo / 'tool/office-validation/render.py').read_bytes()).hexdigest() == manifest['native_conversion_script_sha256']
spec = importlib.util.spec_from_file_location('office_render', repo / 'tool/office-validation/render.py')
render = importlib.util.module_from_spec(spec)
spec.loader.exec_module(render)
names = [f'pending-{kind}{close}-{when}-save.{extension}'
         for kind, extension in (('cell', 'xlsx'), ('slide', 'pptx'))
         for close in ('', '-close') for when in ('before', 'after')]
names += ['word-docm-save.docm', 'word-dotx-save.dotx', 'word-dotm-save.dotm']
names = ['build/fidelity-host/' + name for name in names]
names += [f'build/fidelity-custom-tabs/host-tabs-{cycle}.docx' for cycle in range(1, 4)]
assert len(names) == len(set(names)) == 14
report = {
    'status': 'running',
    'source_commit': manifest['source_commit'],
    'managed_source_commit': manifest['managed_source_commit'],
    'schema_input_count': 358,
    'input_manifest_sha256': hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
    'probe_script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'renderer': subprocess.check_output(['libreoffice', '--version'], text=True).strip(),
    'scope': 'Supplementary native conversion of eleven uploaded files (four XLSX, four PPTX, DOCM/DOTX/DOTM) plus three custom-tab paragraph-dialog DOCX captures. Repeated-save equivalence is required only for the three custom-tab captures.',
    'native_conversion_function': 'Unchanged tool/office-validation/render.py render_document',
    'native_conversion_script_sha256': hashlib.sha256((repo / 'tool/office-validation/render.py').read_bytes()).hexdigest(),
    'schema_report_sha256': hashlib.sha256(schema_path.read_bytes()).hexdigest(),
    'files': 14, 'reports': [], 'failures': [], 'custom_tab_xml': [],
}
started = time.monotonic()
for index, name in enumerate(sorted(names)):
    relative = name
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
tab_names = [f'build/fidelity-custom-tabs/host-tabs-{cycle}.docx' for cycle in range(1, 4)]
by_name = {entry['file']: entry for entry in report['reports']}
word = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
for name in tab_names:
    with ZipFile(root / name) as archive:
        doc = E.fromstring(archive.read('word/document.xml'))
    paragraphs = doc.find(word + 'body').findall(word + 'p')
    def tabs(paragraph):
        return [(tab.get(word + 'pos'), tab.get(word + 'val'), tab.get(word + 'leader', 'none'))
                for tab in paragraph.findall(word + 'pPr/' + word + 'tabs/' + word + 'tab')]
    first, last = tabs(paragraphs[0]), tabs(paragraphs[-1])
    assert first == [('1447', 'center', 'underscore'), ('2893', 'decimal', 'dot'), ('4325', 'right', 'hyphen')]
    assert last == [('1447', 'right', 'underscore')]
    props = paragraphs[0].find(word + 'pPr')
    assert props.find(word + 'ind').get(word + 'left') == '247'
    assert props.find(word + 'spacing').get(word + 'after') == '145'
    report['custom_tab_xml'].append({'file': name, 'first_paragraph_tabs': first,
                                   'last_paragraph_tabs': last,
                                   'unchanged_indent_twips': 247, 'unchanged_after_twips': 145})
cycle = render.cycle_coverage(tab_names, by_name, root=root)
report['custom_tab_cycle_comparisons'] = cycle
report['failures'].extend(cycle['failures'])
for relative, digest in expected.items():
    assert hashlib.sha256((root / relative).read_bytes()).hexdigest() == digest
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
