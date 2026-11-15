#!/usr/bin/env python3
"""Recheck retained Office evidence without rerunning Flutter, SDK, or LibreOffice.

Requires Python 3.12+ and Pillow. Input archives must already be downloaded and
extracted. The fixed expectations identify the accepted 15 November 2026 run;
the caller supplies locations so the audit can be repeated after relocation.
"""

import argparse
from collections import Counter
from datetime import datetime, timezone
from decimal import Decimal
import hashlib
import json
from pathlib import Path, PurePosixPath
import platform
import posixpath
import stat
import struct
import subprocess
import sys
from urllib.parse import unquote, urlsplit
import xml.etree.ElementTree as ET
from zipfile import ZipFile

from PIL import Image

SOURCE = '7e5af83c4e6d26247ccf91d2b03c47a816f46231'
RUN = 43685477823
ARTIFACTS = {
    14150845009: ('f84e997b3909f3af4a4eda3a1295b9c9f1f1a2e8adf2f708b3cd293112fc257a', RUN, SOURCE),
    14150637045: ('384d52eafd81c8609eaf549115b3d6e56cd5fd352d1537bf4bd31fc0fb8d5114', RUN, SOURCE),
    14150598848: ('38beb8672841707aadaf4671a879a90c15cbf427da37e29f0c21a42f42b85cdd', RUN, SOURCE),
    14150152775: ('a8f2039b6fa96fe4b79090f15ada5b94404e36f93c05818a02b3802225682466', RUN, SOURCE),
    14149236176: ('3fe8fbf3bca0d941fc67270a9cdb7988e927db6b4b5ddf0237e98aa459354477',
                 43681914471, '1a86e790080c174c27a283b7ac49913ca1fa91f0'),
}
OFFICE = {'.docx', '.docm', '.dotx', '.dotm', '.xlsx', '.pptx'}
NAVIGATION = {
    'source.xlsx': ('Budget', '125.5'),
    'switched-draft.xlsx': ('Budget', '250'),
    'rejected-draft-corrected.xlsx': ('Budget', '300'),
    'rename.xlsx': ("O'Brien 2026", '125.5'),
    'rename-undo.xlsx': ('Budget', '125.5'),
    'rename-redo.xlsx': ("O'Brien 2026", '125.5'),
}
NS = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
      'r': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
      'p': 'http://schemas.openxmlformats.org/package/2006/relationships'}


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def digest_bytes(content):
    return hashlib.sha256(content).hexdigest()


def digest(path):
    return digest_bytes(path.read_bytes())


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def save_json(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')


def safe_path(root, relative):
    name = PurePosixPath(relative)
    require(not name.is_absolute() and '..' not in name.parts and '\\' not in relative,
            f'Unsafe relative path: {relative}')
    require(str(name) == relative and relative not in ('', '.'), f'Noncanonical path: {relative}')
    candidate = root / relative
    require(candidate.resolve().is_relative_to(root.resolve()), f'Path escapes root: {relative}')
    require(not candidate.is_symlink(), f'Symlink not accepted: {relative}')
    return candidate


def inspect_zip(archive, extracted=None):
    with ZipFile(archive) as zipped:
        members = zipped.infolist()
        names = [item.filename for item in members]
        require(len(names) == len(set(names)), f'Duplicate ZIP paths: {archive}')
        files = []
        for item in members:
            relative = item.filename.removesuffix('/') if item.is_dir() else item.filename
            safe_path(Path('/virtual-zip-root'), relative)
            require(not stat.S_ISLNK(item.external_attr >> 16), f'ZIP symlink: {relative}')
            if item.is_dir():
                continue
            content = zipped.read(item)  # Also verifies each entry's CRC.
            if extracted is not None:
                actual = safe_path(extracted, relative)
                require(actual.is_file(), f'Missing extracted member: {actual}')
                require(actual.read_bytes() == content, f'Extraction differs: {actual}')
            files.append({'path': relative, 'bytes': len(content), 'sha256': digest_bytes(content)})
        require(zipped.testzip() is None, f'Corrupt ZIP: {archive}')
    if extracted is not None:
        actual = {str(p.relative_to(extracted)) for p in extracted.rglob('*') if p.is_file()}
        require(actual == {p['path'] for p in files}, f'Unexpected or missing extraction files: {extracted}')
    return files


def source_bytes(app, path):
    return subprocess.check_output(['git', 'show', f'{SOURCE}:{path}'], cwd=app)


def verify_source(app, path):
    expected = source_bytes(app, path)
    actual = safe_path(app, path).read_bytes()
    require(actual == expected, f'Current executed input differs from qualified source: {path}')
    return {'path': path, 'bytes': len(actual), 'sha256': digest_bytes(actual), 'source_commit': SOURCE}


def one(items, description):
    require(len(items) == 1, f'Expected exactly one {description}, got {len(items)}')
    return items[0]


def semantic_workbook(path, expected_name, expected_amount):
    """Read OPC and XML directly, without any Dart/Quds parser or serializer."""
    with ZipFile(path) as archive:
        book = ET.fromstring(archive.read('xl/workbook.xml'))
        sheets = book.findall('s:sheets/s:sheet', NS)
        names = [s.get('name') for s in sheets]
        require(names == [expected_name, 'Reference'], f'{path.name}: sheet identity/order')
        relationships = ET.fromstring(archive.read('xl/_rels/workbook.xml.rels'))
        relation_ids = [r.get('Id') for r in relationships]
        require(len(relation_ids) == len(set(relation_ids)), f'{path.name}: duplicate relationship IDs')
        by_id = {r.get('Id'): r for r in relationships}
        parts = []
        for sheet in sheets:
            relation = by_id[sheet.get('{' + NS['r'] + '}id')]
            require(relation.get('Type') == NS['r'] + '/worksheet', 'Wrong worksheet relationship type')
            target = urlsplit(relation.get('Target', ''))
            require(not target.scheme and not target.netloc and not target.query and not target.fragment,
                    'Worksheet target must be local')
            require(relation.get('TargetMode', 'Internal') == 'Internal', 'External worksheet target')
            decoded = unquote(target.path)
            resolved = decoded.lstrip('/') if decoded.startswith('/') else posixpath.normpath('xl/' + decoded)
            safe_path(Path('/virtual-package'), resolved)
            parts.append(ET.fromstring(archive.read(resolved)))
        shared = []
        if 'xl/sharedStrings.xml' in archive.namelist():
            shared = [''.join(t.itertext()) for t in ET.fromstring(archive.read('xl/sharedStrings.xml')).findall('s:si', NS)]

        def cell(sheet, address):
            return one([c for c in sheet.findall('.//s:sheetData/s:row/s:c', NS) if c.get('r') == address], address)

        def value(sheet, address):
            c = cell(sheet, address)
            if c.get('t') == 'inlineStr':
                return ''.join(one(c.findall('s:is', NS), 'inline string').itertext())
            raw = one(c.findall('s:v', NS), 'cell value').text
            return shared[int(raw)] if c.get('t') == 's' else raw

        budget, reference = parts
        require(Decimal(value(budget, 'B2')) == Decimal(expected_amount), f'{path.name}: amount')
        require(Decimal(value(reference, 'B1')) == Decimal('73'), f'{path.name}: reference sentinel')
        require(value(budget, 'A1') == 'Budget header', f'{path.name}: budget heading')
        require(value(budget, 'A2') == 'Travel', f'{path.name}: row label')
        require(value(reference, 'A1') == 'Reference must remain', f'{path.name}: reference heading')
        qualifier = 'Budget' if expected_name == 'Budget' else "'" + expected_name.replace("'", "''") + "'"
        formula = one(cell(reference, 'B2').findall('s:f', NS), 'formula').text
        require(formula == qualifier + '!B2', f'{path.name}: rewritten formula')
        require(Decimal(value(reference, 'B2')) == Decimal(expected_amount), f'{path.name}: formula cache')
        defined = one([n for n in book.findall('s:definedNames/s:definedName', NS)
                       if n.get('name') == 'BudgetAmount'], 'BudgetAmount name').text
        require(defined == qualifier + '!$B$2', f'{path.name}: rewritten defined name')
        validation = one(budget.findall('s:dataValidations/s:dataValidation', NS), 'validation')
        require(validation.attrib == {'type': 'decimal', 'operator': 'between', 'allowBlank': '0',
                                     'showErrorMessage': '1', 'error': 'Enter an amount from 0 to 1000.', 'sqref': 'B2'},
                f'{path.name}: validation settings')
        require(validation.findtext('s:formula1', namespaces=NS) == '0' and
                validation.findtext('s:formula2', namespaces=NS) == '1000', f'{path.name}: validation bounds')
    return {'file': path.name, 'sha256': digest(path), 'sheets': names, 'amount': expected_amount,
            'reference_sentinel': 73, 'reference_formula': formula, 'reference_cache': expected_amount,
            'defined_name': defined, 'labels_preserved': True, 'validation_preserved': True, 'passed': True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifacts', type=Path, required=True)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    artifacts, app, output = (p.resolve() for p in (args.artifacts, args.app, args.output))
    output.mkdir(parents=True, exist_ok=True)
    receipts_path = artifacts / 'download-receipts.json'
    downloads = read_json(receipts_path)
    require(len(downloads) == len(ARTIFACTS) and {r['id'] for r in downloads} == set(ARTIFACTS), 'Unexpected archive set')
    artifact_rows, extracted_manifest = [], []
    for item in downloads:
        artifact_id = item['id']
        expected_digest, run, source = ARTIFACTS[artifact_id]
        archive = safe_path(artifacts, item['file_name'])
        actual_digest = digest(archive)
        require(actual_digest == expected_digest == item['sha256'] == item['digest'].removeprefix('sha256:'),
                f'Archive digest mismatch: {artifact_id}')
        require(archive.stat().st_size == item['bytes'], f'Archive size mismatch: {artifact_id}')
        if item.get('size_in_bytes') is not None:
            require(archive.stat().st_size == item['size_in_bytes'], f'GitHub size mismatch: {artifact_id}')
        require(item['workflow_run']['id'] == run and item['workflow_run']['head_sha'] == source,
                f'Archive workflow binding differs: {artifact_id}')
        extracted = artifacts / str(artifact_id)
        members = inspect_zip(archive, extracted)
        extracted_manifest.extend({'artifact_id': artifact_id, **m} for m in members)
        artifact_rows.append({'artifact_id': artifact_id, 'archive': archive.name, 'sha256': actual_digest,
                              'bytes': archive.stat().st_size, 'run_id': run, 'source_commit': source,
                              'files': len(members), 'duplicate_paths': 0, 'extraction_matches': True})
    save_json(output / 'extracted-files.json', extracted_manifest)

    source_inputs = [verify_source(app, p) for p in [
        'tool/office_host_evidence.py', 'tool/office_host_evidence.json',
        'test/support/office_device_export_web_acceptance.dart',
        'lib/services/office_device_export.dart', 'lib/services/office_device_export_web.dart', 'pubspec.lock',
        'test/fixtures/office_native_workflows/native-word-expected.docx',
        'test/fixtures/office_native_workflows/native-sheet-expected.xlsx',
        'test/fixtures/office_native_workflows/native-slide-expected.pptx']]
    host = artifacts / '14150637045'
    external = artifacts / '14150598848'
    command = [sys.executable, str(app / 'tool/office_host_evidence.py'), 'verify', '--layout', 'artifact',
               '--root', str(host), '--report', str(output / 'host-inventory.json')]
    result = subprocess.run(command, cwd=app, text=True, capture_output=True, timeout=60)
    (output / 'host-inventory.log').write_text(result.stdout + result.stderr, encoding='utf-8')
    require(result.returncode == 0, 'Host inventory tool failed')
    inventory = read_json(output / 'host-inventory.json')
    hosted_inventory = read_json(external / 'host-inventory.json')
    require(inventory == hosted_inventory, 'Recomputed artifact inventory differs from hosted inventory')
    require(inventory['expected'] == inventory['verified'] == len(inventory['files']) == 182 and not inventory['failures'],
            'Incomplete host inventory')
    require(inventory['verified_rendered'] == 149 and inventory['verified_schema_only'] == 33, 'Validation scopes changed')
    require(inventory['manifest_sha256'] == digest(app / 'tool/office_host_evidence.json'), 'Manifest digest differs')
    inv_by_file = {r['file']: r for r in inventory['files']}
    for name, row in inv_by_file.items():
        candidate = safe_path(host, name)
        require(digest(candidate) == row['sha256'] and candidate.stat().st_size == row['bytes'], f'Host digest differs: {name}')

    schema = read_json(external / 'schema-report.json')
    require(schema['Files'] == len(schema['Reports']) == 540 and schema['Failures'] == 0, 'Schema counts differ')
    schema_files = set()
    for row in schema['Reports']:
        require(row['File'].startswith('evidence/'), 'Unexpected schema path prefix')
        name = row['File'].removeprefix('evidence/')
        require(name not in schema_files, f'Duplicate schema report: {name}')
        schema_files.add(name)
        require(not row['Errors'], f'Hosted SDK errors: {name}')
        candidate = safe_path(host, name)
        require(digest(candidate) == row['Sha256'], f'SDK report not bound to host bytes: {name}')
        inspect_zip(candidate)
    actual_office = {str(p.relative_to(host)) for p in host.rglob('*') if p.is_file() and p.suffix.lower() in OFFICE}
    require(schema_files == actual_office, 'SDK report omits or invents Office files')
    require(set(inv_by_file).issubset(schema_files), 'SDK report omits host outputs')

    nav_root = host / 'build/office-sheet-navigation-acceptance'
    require({p.name for p in nav_root.iterdir() if p.is_file()} == set(NAVIGATION), 'Unexpected navigation outputs')
    navigation = [semantic_workbook(nav_root / name, sheet, amount)
                  for name, (sheet, amount) in NAVIGATION.items()]
    save_json(output / 'navigation-semantics.json', navigation)

    rendered_root = external / 'host-render'
    rendered = read_json(rendered_root / 'render-report.json')
    require(rendered['files'] == rendered['rendered_files'] == len(rendered['reports']) == 149 and not rendered['failures'],
            'Renderer report incomplete')
    reports = {r['file']: r for r in rendered['reports']}
    render_names = {name for name, r in inv_by_file.items() if r['validation_scope'] == 'schema_and_render'}
    require(set(reports) == render_names and len(reports) == 149, 'Rendered file set differs from declarations')
    pixel_checks = []
    for name, row in reports.items():
        source_hash = digest(safe_path(host, name))
        require(source_hash == row['input_sha256'], f'Renderer input hash differs: {name}')
        require(digest(safe_path(external / 'host-input', name)) == source_hash, f'Staged renderer bytes differ: {name}')
        for attempt in row['conversion_attempts']:
            require(attempt['input_sha256_before'] == attempt['input_sha256_after'] == source_hash and attempt['input_unchanged'],
                    f'Renderer conversion changed input: {name}')
        require(row['conversion_attempts'][-1]['status'] == 'converted' and row['conversion_attempts'][-1]['returncode'] == 0,
                f'Renderer did not succeed: {name}')
        pdf = safe_path(rendered_root, row['pdf'])
        require(pdf.read_bytes().startswith(b'%PDF-'), f'Rendered PDF missing: {name}')
        require(len(row['page_artifacts']) == len(row['pixel_sha256']) == row['pages'] > 0, 'Rendered page count differs')
        for i, page in enumerate(row['page_artifacts']):
            require(page['page'] == i + 1, f'Page ordering differs: {name}')
            png = safe_path(rendered_root, page['png'])
            with Image.open(png) as decoded:
                rgb = decoded.convert('RGB')
                require(rgb.size == (page['width'], page['height']), f'Page dimensions differ: {name}')
                pixel_hash = digest_bytes(struct.pack('>II', *rgb.size) + rgb.tobytes())
            require(pixel_hash == page['pixel_sha256'] == row['pixel_sha256'][i], f'Page fingerprint differs: {name}')
            pixel_checks.append({'file': name, 'page': i + 1, 'png': page['png'], 'pixel_sha256': pixel_hash})
    require(rendered['cycle_groups'] == len(rendered['cycle_comparisons']) == 36, 'Repeat-save count differs')
    comparisons = []
    baselines = 0
    for group in rendered['cycle_comparisons']:
        require(group['passed'] is True and group['expected_cycles'] == group['actual_cycles'] == [1, 2, 3], 'Cycle group failed')
        require(len(group['files']) == len(set(group['files'])) == 3, 'Unexpected cycle group size')
        fingerprints = [reports[name]['pixel_sha256'] for name in group['files']]
        require(all(p == fingerprints[0] for p in fingerprints), f'Repeat-save pixels differ: {group["case"]}')
        if group['baseline'] is not None:
            baseline = group['baseline']
            require(inv_by_file[baseline]['role'] == 'independent_reference', 'Baseline is not an independently declared reference')
            require(digest_bytes(source_bytes(app, inv_by_file[baseline]['source_fixture'])) == inv_by_file[baseline]['sha256'],
                    'Reference bytes differ from the exact source fixture')
            require(reports[baseline]['pixel_sha256'] == fingerprints[0], f'Reference pixels differ: {group["case"]}')
            baselines += 1
        comparisons.append({'case': group['case'], 'files': group['files'], 'baseline': group['baseline'], 'passed': True})
    require(baselines == rendered['baseline_comparisons'] == 3, 'Independent reference count differs')
    save_json(output / 'render-integrity.json', {'renderer': rendered['renderer'], 'files': 149,
              'decoded_png_pages': len(pixel_checks), 'cycle_groups': 36, 'reference_comparisons': 3,
              'page_checks': pixel_checks, 'comparisons': comparisons})

    browser_root = artifacts / '14150845009'
    browser = read_json(browser_root / 'receipt.json')
    compiled = read_json(browser_root / 'compile-receipt.json')
    for field, path in [('entrypoint_sha256', 'test/support/office_device_export_web_acceptance.dart'),
                        ('wrapper_sha256', 'lib/services/office_device_export.dart'),
                        ('adapter_sha256', 'lib/services/office_device_export_web.dart')]:
        require(browser[field] == compiled[field] == digest_bytes(source_bytes(app, path)), f'Browser source differs: {field}')
    require(browser['compiled_sha256'] == compiled['compiled_sha256'] == digest(browser_root / 'acceptance.js'), 'Compiled JavaScript differs')
    require(browser['dependency_resolution'] == compiled['dependency_resolution'], 'Browser dependency receipts disagree')
    require(browser['dependency_resolution']['application_lock_sha256'] == digest_bytes(source_bytes(app, 'pubspec.lock')), 'Browser lock digest differs')
    require(browser['filename'] == 'Recovery_ budget_.xlsx', 'Browser filename differs')
    payload = safe_path(browser_root, browser['filename']).read_bytes()
    require(payload == bytes(range(256)) and len(payload) == browser['download_bytes'] == 256, 'Browser payload differs')
    require(digest_bytes(payload) == browser['download_sha256'], 'Browser download hash differs')
    require(browser['outcome'] == 'downloadedCopy' and browser['anchor_connected_at_click'] and
            browser['remaining_download_anchors'] == 0 and browser['object_url_revoked'] and
            browser['revocation_delay_ms'] >= 0 and not browser['page_errors'], 'Browser receipt does not pass')

    ui_root = artifacts / '14150152775'
    ui_rows = []
    for name, dimensions in [('rename-validation.png', (1600, 1000)), ('worksheet-arabic-narrow.png', (390, 1000))]:
        ui_receipt = read_json(ui_root / (name + '.json'))
        path = ui_root / name
        require(ui_receipt['file'] == name and digest(path) == ui_receipt['sha256'], f'UI hash differs: {name}')
        with Image.open(path) as decoded:
            decoded.load()
            require(decoded.size == dimensions == (ui_receipt['width'], ui_receipt['height']), f'UI geometry differs: {name}')
        ui_rows.append({'file': name, 'sha256': digest(path), 'width': dimensions[0], 'height': dimensions[1],
                        'geometry_and_integrity_verified': True, 'text_visual_acceptance': False})

    for row in artifact_rows:
        require(digest(artifacts / row['archive']) == row['sha256'], 'Archive changed during verification')
    for row in source_inputs:
        require(digest(app / row['path']) == row['sha256'], 'Executed source changed during verification')
    receipt = {
        'status': 'passed', 'completed_at_utc': datetime.now(timezone.utc).isoformat(),
        'qualified_source_commit': SOURCE, 'qualified_workflow_run': RUN,
        'verification': 'Local archive, report, XML semantic, PNG pixel and byte-integrity verification of retained hosted evidence',
        'hosted_execution': 'Flutter, Chromium, OpenXML SDK and LibreOffice executed on GitHub Actions; none were rerun by this verifier',
        'python': sys.version, 'platform': platform.platform(), 'pillow': Image.__version__,
        'script_sha256': digest(Path(__file__)), 'download_receipts_sha256': digest(receipts_path),
        'archives': artifact_rows, 'source_inputs': source_inputs,
        'host_inventory': {'command': command, 'exit_code': result.returncode, 'verified': 182, 'rendered': 149,
                           'schema_only': 33, 'declarations_sha256': inventory['manifest_sha256'],
                           'matches_hosted_report_exactly': True, 'controls_rerun': False},
        'schema': {'reports': 540, 'failures': 0, 'all_source_hashes_verified': True,
                   'all_office_files_discovered': True, 'duplicate_internal_zip_paths': 0},
        'navigation': {'files': 6, 'passed': 6, 'report': 'navigation-semantics.json',
                       'method': 'Independent Python ZIP/OPC/XML reads with fixed expectations; no Dart/Quds parser'},
        'rendering': {'files': 149, 'decoded_png_pages': len(pixel_checks), 'cycle_groups': 36,
                      'reference_comparisons': 3, 'all_input_hashes_match_host_outputs': True,
                      'all_page_pixel_hashes_recomputed': True, 'report': 'render-integrity.json'},
        'browser': {'download_bytes': 256, 'download_sha256': browser['download_sha256'],
                    'source_and_compiled_hashes_verified': True, 'hosted_browser': browser['browser_version'],
                    'generated_package_config_available': False,
                    'package_config_limit': 'Generated .dart_tool configuration is absent; its matching digest in both hosted receipts is retained, not locally recomputed'},
        'ui': {'captures': ui_rows, 'limit': 'Existing captures have known font deficiencies. Hashes and dimensions verify geometry only; no glyph/Arabic visual acceptance is claimed'},
        'original_run': {'artifact_id': 14149236176, 'run_id': 43681914471, 'archive_integrity_verified': True,
                         'limit': 'Original failed run retained separately. Its package bytes are not relabeled as the fresh accepted run'},
        'inputs_unchanged': True,
    }
    save_json(output / 'receipt.json', receipt)
    manifest = [{'file': str(p.relative_to(output)), 'bytes': p.stat().st_size, 'sha256': digest(p)}
                for p in sorted(output.iterdir()) if p.is_file() and p.name != 'sha256-manifest.json']
    save_json(output / 'sha256-manifest.json', manifest)
    print(json.dumps({'status': receipt['status'], 'source': SOURCE, 'archives': len(artifact_rows),
                      'schema': 540, 'host': 182, 'navigation': 6, 'rendered': 149,
                      'png_pages': len(pixel_checks), 'cycles': 36, 'references': 3,
                      'receipt': str(output / 'receipt.json')}, indent=2))


if __name__ == '__main__':
    main()
