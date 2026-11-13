#!/usr/bin/env python3
"""Verify retained hosted Office results without rerunning Flutter or renderers."""
import argparse
from collections import Counter
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import posixpath
import re
import struct
import subprocess
import tarfile
from urllib.parse import unquote, urlsplit
from xml.etree import ElementTree as ET
import zipfile
import zlib

APP = 'fb81b2ace557964459189afd7c0c7d76b2c9557d'
TREE = 'a14d066f1179ea00e20eaa3431aec0dd4fe05a5f'
RUNTIME = '86d5a218853d8441afe8bc28f19cfe0adf4cd71e'
RUNTIME_TREE = '765bf752b0095233192d38e678941e7ca92a76b8'
PARSER = 'c5ff75e76163d9abbdd44a9f2a7c5ad210929289'
RUN, HOST_JOB, EXTERNAL_JOB = 43390627156, 131769379446, 131783096763
HOST_ARTIFACT = 14022440972
HOST_ZIP_SHA = '36e2cd7585656cc2e33c038bd499c2d19e0c39427b453ad7d1dcb282a65d7805'
HOST_ZIP_BYTES = 3787466
EXTERNAL_ARTIFACT = 14022222719
EXTERNAL_ZIP_SHA = 'c04ab98780403ab553489528875e29ab0b7f66b81e70ba4d6cb63281a03da69c'
EXTERNAL_ZIP_BYTES = 3026036
RENDER_SOURCE_SHA = '93fb7bef445b0da340e9355b319bb92ce26ebc7fae11b8cc69fb75b27aae29e6'
MANIFEST_SHA = '893738241f73d9cbf2e2e1f0dc11231d1a6faa3f788ba7d6fdda815ed98b4c1d'
HOST_ROOT = '/home/runner/work/CrispCloud/CrispCloud'
COVERAGE = 'build/fidelity-host/coverage/run-20261113T083440Z-3216'
FLUTTER = '/opt/hostedtoolcache/flutter/stable-3.47.8-x64/flutter/bin/flutter'
HOOK = b'\nhooks:\n  user_defines:\n    sqlite3:\n      source: system\n      name_windows: winsqlite3\n'
GENERATED = {
    '.dart_tool/package_config.json', '.dart_tool/package_graph.json',
    'packages/quds_office_engine/.dart_tool/package_config.json',
    'packages/quds_office_engine/.dart_tool/package_graph.json',
    'packages/quds_office_engine/pubspec.lock',
}
HOST_STEPS = [
    'Set up job', 'Run actions/checkout@v4', 'Verify committed Office sources before test hooks',
    'Set up bundled ebook converter', 'Run subosito/flutter-action@v2', 'Native test dependencies',
    'Run flutter pub get', 'Shared corpus and host save workflow', 'Run actions/upload-artifact@v4',
    'Post Run subosito/flutter-action@v2', 'Post Set up bundled ebook converter',
    'Post Run actions/checkout@v4', 'Complete job',
]
EXTERNAL_STEPS = [
    'Set up job', 'Run actions/checkout@v4', 'Run actions/setup-dotnet@v4',
    'Run actions/download-artifact@v4', 'Require every actual host export',
    'Prove validator detects invalid XML', 'Validate host uploads and engine exports',
    'Stage exact actual-host bytes for native rendering', 'Install independent host renderer',
    'Check actual-host rendering and repeated saves', 'Run actions/upload-artifact@v4',
    'Post Run actions/setup-dotnet@v4', 'Post Run actions/checkout@v4', 'Complete job',
]
TESTS = [
    'test/office_fidelity_workflow_test.dart', 'test/office_formatting_preservation_test.dart',
    'test/office_roundtrip_preservation_test.dart', 'test/office_section_break_fidelity_test.dart',
    'test/office_editor_fixes_test.dart', 'test/office_footnote_test.dart',
    'test/office_ribbon_footnotes_test.dart', 'test/office_ribbon_common_i18n_test.dart',
    'test/office_document_service_test.dart', 'test/legacy_word_document_test.dart',
    'test/legacy_word_conversion_strings_test.dart', 'test/legacy_word_copy_target_test.dart',
    'test/word_template_preservation_test.dart', 'test/word_format_strings_test.dart',
    'test/office_preview_fidelity_test.dart', 'test/office_preview_strings_test.dart',
    'test/preview_media_localization_test.dart', 'test/recursive_search_service_test.dart',
    'test/office_pdf_service_test.dart', 'test/widget/office_editor_dialog_test.dart',
    'test/widget/office_editor_ribbon_test.dart', 'test/widget/office_paragraph_dialog_test.dart',
    'test/widget/office_paragraph_fidelity_test.dart', 'test/widget/office_font_fidelity_test.dart',
    'test/widget/office_picture_fidelity_test.dart', 'test/widget/office_html_widget_factory_test.dart',
    'test/widget/office_metafile_preview_test.dart', 'test/widget/office_save_fidelity_test.dart',
    'test/widget/legacy_word_conversion_dialog_test.dart', 'test/widget/legacy_word_routing_test.dart',
]
MAIN_TYPES = {
    '.docx': ('application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml', 'wordprocessingml', 'document'),
    '.docm': ('application/vnd.ms-word.document.macroEnabled.main+xml', 'wordprocessingml', 'document'),
    '.dotx': ('application/vnd.openxmlformats-officedocument.wordprocessingml.template.main+xml', 'wordprocessingml', 'document'),
    '.dotm': ('application/vnd.ms-word.template.macroEnabledTemplate.main+xml', 'wordprocessingml', 'document'),
    '.xlsx': ('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml', 'spreadsheetml', 'workbook'),
    '.pptx': ('application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml', 'presentationml', 'presentation'),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def blob(data):
    return hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()


def load(records, name):
    return json.loads(records[name])


def safe(name):
    path = PurePosixPath(name)
    return not path.is_absolute() and '..' not in path.parts and '\\' not in name and str(path) == name


def unpack(raw):
    records = {}
    with tarfile.open(fileobj=io.BytesIO(raw), mode='r:xz') as archive:
        for member in archive:
            require(member.isfile() and safe(member.name), 'Unsafe metadata member')
            require(member.name not in records and member.size <= 64 * 1024 * 1024, 'Metadata member limit')
            records[member.name] = archive.extractfile(member).read()
            require(len(records) <= 1000 and sum(map(len, records.values())) <= 128 * 1024 * 1024, 'Metadata archive limit')
    return records


def unzip(raw, inventory):
    files = {}
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        require(len(archive.infolist()) <= 25000, 'ZIP member limit')
        for member in archive.infolist():
            require(not member.is_dir() and safe(member.filename), 'Unsafe ZIP member')
            require(member.filename not in files and member.file_size <= 256 * 1024 * 1024, 'Duplicate/oversized ZIP member')
            data = archive.read(member)
            files[member.filename] = data
            expected = {'bytes': len(data), 'sha256': sha(data),
                        'zipCompressedBytes': member.compress_size, 'zipCompression': member.compress_type,
                        'zipCrc32': member.CRC, 'zipExternalAttributes': member.external_attr}
            require(inventory['files'][member.filename] == expected, 'ZIP member bytes: ' + member.filename)
            require(sum(map(len, files.values())) <= 1024 * 1024 * 1024, 'ZIP expansion limit')
    require(set(files) == set(inventory['files']) and inventory['directories'] == [], 'Complete ZIP inventory')
    require(inventory['fileCount'] == len(files) and inventory['uncompressedBytes'] == sum(map(len, files.values())), 'ZIP totals')
    return files


def inspect_package(name, data):
    kind, namespace, local = MAIN_TYPES[PurePosixPath(name).suffix.lower()]
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), 'Duplicate OPC part')
        require(archive.testzip() is None, 'Damaged OPC part')
        rels = ET.fromstring(archive.read('_rels/.rels'))
        require(rels.tag == '{http://schemas.openxmlformats.org/package/2006/relationships}Relationships', 'OPC relationships namespace')
        owning = [r for r in rels if r.get('Type') in {
            'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument',
            'http://purl.oclc.org/ooxml/officeDocument/relationships/officeDocument'}]
        require(len(owning) == 1, 'OPC main relationship count')
        relation = owning[0]
        uri = urlsplit(relation.get('Target', ''))
        require(relation.get('TargetMode', 'Internal') == 'Internal' and not any((uri.scheme, uri.netloc, uri.query, uri.fragment)), 'OPC main relationship target')
        target = unquote(uri.path)
        require(target and '\\' not in target, 'OPC main target')
        main = posixpath.normpath(target.lstrip('/'))
        require(safe(main) and main in names, 'OPC main target escape/missing')
        types = ET.fromstring(archive.read('[Content_Types].xml'))
        type_ns = 'http://schemas.openxmlformats.org/package/2006/content-types'
        require(types.tag == '{' + type_ns + '}Types', 'OPC content types namespace')
        actual = [r.get('ContentType') for r in types.findall('{' + type_ns + '}Override')
                  if unquote(r.get('PartName', '')).lstrip('/') == main]
        require(actual == [kind], 'OPC main content type')
        root = ET.fromstring(archive.read(main))
        require(root.tag in {'{http://schemas.openxmlformats.org/' + namespace + '/2006/main}' + local,
                             '{http://purl.oclc.org/ooxml/' + namespace + '/main}' + local}, 'OPC main root')
    return main


def verify_sources(records, repository=None):
    source = load(records, 'source.json')
    require(source['commit'] == APP and source['tree'] == TREE and source['status'] == '' and len(source['files']) == 7579, 'Committed source identity')
    for name, data in records.items():
        if name.startswith('source/'):
            expected = source['files'][name.removeprefix('source/')]
            require(expected['bytes'] == len(data) and expected['sha256'] == sha(data) and expected['gitBlob'] == blob(data), 'Captured source bytes: ' + name)
    source_review = records['independent-source-review.json']
    require(sha(source_review) == '167ce4f3570839f1b94b09685bf018670e21b611e346fafefa4a48af65651c95', 'Independent source review')
    vendor = load(records, 'source/tool/office_fidelity_manifest.json')
    require(len(vendor['files']) == 1679, 'Pinned Office inventory size')
    require(all(source['files'][name]['sha256'] == digest for name, digest in vendor['files'].items()), 'Pinned Office source hashes')
    require(PARSER in records['source/pubspec.yaml'].decode(), 'Parser integration pin')
    workflow = records['source/.github/workflows/office-fidelity.yml'].decode()
    require(workflow.index('python3 tool/verify_office_fidelity.py --require-tracked') < workflow.index('python3 tool/with_ci_system_sqlite.py bash tool/check_office_fidelity.sh'), 'Pre-hook tracked gate ordering')
    require('    needs: host-roundtrip' in workflow and "flutter-version: '3.47.8'" in workflow, 'Hosted workflow dependencies/runtime')
    if repository is not None:
        git = lambda *args: subprocess.check_output(['git', '-C', str(repository), *args])
        require(git('rev-parse', APP + '^{tree}').decode().strip() == TREE, 'Git source tree')
        require(git('rev-parse', RUNTIME + '^{tree}').decode().strip() == RUNTIME_TREE, 'Git measured runtime tree')
        git('merge-base', '--is-ancestor', RUNTIME, APP)
        changes = git('diff', '--name-only', RUNTIME, APP).decode().splitlines()
        require(len(changes) == 9 and all(name.startswith('docs/') for name in changes), 'Measured runtime to hosted source documentation-only delta')
        expected = {}
        for entry in git('ls-tree', '-rlz', APP).split(b'\0'):
            if entry:
                metadata, name = entry.decode().split('\t')
                mode, kind, oid, size = metadata.split()
                require(kind == 'blob', 'Unexpected Git entry')
                expected[name] = (mode, oid, int(size))
        require(expected == {name: (item['gitMode'], item['gitBlob'], item['bytes']) for name, item in source['files'].items()}, 'Complete Git source inventory')
    return source['files']


def verify_host_inventory(records, host):
    raw = records['source/tool/office_host_evidence.json']
    require(sha(raw) == MANIFEST_SHA, 'Pinned host output manifest')
    paths = json.loads(raw)['outputs']
    require(len(paths) == len(set(paths)) == 122, 'Required host path count')
    report = load(host, 'build/fidelity-host/inventory.json')
    require(report['expected'] == report['verified'] == 122 and report['failures'] == [], 'Host inventory result')
    require(report['manifest_sha256'] == MANIFEST_SHA, 'Host inventory source')
    actual = {item['path']: item for item in report['files']}
    require(len(actual) == len(report['files']) == 122 and set(actual) == set(paths), 'Exact host path set')
    require({n for n in host if n.startswith('build/') and PurePosixPath(n).suffix.lower() in MAIN_TYPES} == set(paths), 'Actual host package inventory')
    require(Counter(PurePosixPath(p).suffix for p in paths) == {'.docx': 99, '.xlsx': 4, '.pptx': 16, '.docm': 1, '.dotm': 1, '.dotx': 1}, 'Host package format counts')
    for name, item in actual.items():
        data = host[name]
        require(item['file'] == name and item['bytes'] == len(data) and item['sha256'] == sha(data), 'Host package byte identity: ' + name)
        require(item['format'] == PurePosixPath(name).suffix[1:] and item['main_part'] == inspect_package(name, data), 'Host package owning part')
    packages = {name for name in host if PurePosixPath(name).suffix.lower() in MAIN_TYPES}
    require(len(packages) == 468 and len(packages - set(paths)) == 346, 'Separate engine/host package totals')
    return paths


def verify_coverage(records, host, source):
    receipt_bytes = host[COVERAGE + '/collection-receipt.json']
    receipt = json.loads(receipt_bytes)
    require(receipt['schema_version'] == 1 and receipt['status'] == 'complete' and receipt['returncode'] == 0, 'Coverage collection result')
    require(receipt['host_root'] == HOST_ROOT and receipt['coverage_directory'] == HOST_ROOT + '/' + COVERAGE, 'Coverage collection cwd/destination')
    expected_command = [FLUTTER, 'test', '--no-pub', '--coverage', '--coverage-path=' + HOST_ROOT + '/' + COVERAGE + '/lcov.info', *TESTS]
    require(receipt['command'] == expected_command, 'Exact 30-suite Flutter command')
    script = records['source/tool/check_office_fidelity.sh'].decode()
    require(re.findall(r'^  (test/[^ ]+\.dart)', script, re.M) == TESTS, 'Pinned host suite order')
    runtime = receipt['runtime']
    require(runtime['executable'] == FLUTTER and runtime['sha256'] == '7d486c33b30a0cf1ea5146231c68bb8f966cdb4e087c5cd8b37e14513f536e7d', 'Hosted Flutter executable identity')
    version = json.loads(runtime['version'])
    require(version['frameworkVersion'] == '3.47.8' and version['dartSdkVersion'] == '3.13.7'
            and version['frameworkRevision'] == '737ba8f885dc774b53b442759999a312c9461e4e', 'Hosted Flutter/Dart version')
    inputs = receipt['input_sha256']
    require(len(inputs) == 3971 and set(inputs) - set(source) == GENERATED, 'Coverage generated/committed input inventory')
    original = records['source/pubspec.yaml']
    hooked = original.rstrip(b'\r\n') + b'\n' + HOOK
    require(len(original) == 10756 and len(hooked) == 10845, 'SQLite hook size boundary')
    require(sha(original) == 'c3a86f613b810ee66f7b12dbcaa0161e2d616846512ef0073bc3effc80a665aa'
            and sha(hooked) == '66e6c8810da5200bc377ea187673cdafbf5386abe150be499d9654ff5b64a2de', 'SQLite hook exact bytes')
    for name, digest in inputs.items():
        if name in source:
            require(digest == (sha(hooked) if name == 'pubspec.yaml' else source[name]['sha256']), 'Tested source input: ' + name)
    require(set(load(records, 'source/tool/office_fidelity_manifest.json')['files']) <= set(inputs), 'Complete vendor coverage inputs')
    input_sha = sha(json.dumps(inputs, sort_keys=True).encode())
    require(receipt['input_tree_sha256'] == input_sha == 'ab6705844c3ece61987d80a24440efb3f039c8b5a9e06cb36607442fbdd4e126', 'Coverage complete input digest')
    lcov = host[COVERAGE + '/lcov.info']
    require(receipt['coverage_sha256'] == {'lcov.info': sha(lcov)}, 'Coverage raw LCOV binding')
    gaps_bytes = host[COVERAGE + '/gaps.json']
    require(gaps_bytes == host['build/fidelity-host/coverage/gaps.json'], 'Coverage summary copies')
    gaps = json.loads(gaps_bytes)
    require(gaps['status'] == 'complete' and gaps['source_git_commit'] == APP and gaps['source_git_dirty'] is False, 'Scoped coverage source status')
    collection = gaps['collection']
    require(collection['verified'] is True and collection['receipt_sha256'] == sha(receipt_bytes), 'Coverage receipt binding')
    require(collection['input_tree_sha256'] == input_sha and collection['input_files'] == 3971, 'Coverage summary input binding')
    for key in ['command', 'runtime', 'started_at', 'completed_at', 'coverage_sha256']:
        require(collection[key] == receipt[key], 'Coverage summary collection field: ' + key)
    scoped = gaps['source_sha256']
    scope_patterns = ['lib/services/office_*.dart', 'lib/widgets/office_*.dart',
                      'lib/services/legacy_word_copy_target.dart',
                      'lib/widgets/legacy_word_conversion_action.dart',
                      'lib/widgets/legacy_word_conversion_dialog.dart']
    expected_scope = {name for name in source if any(PurePosixPath(name).match(pattern) for pattern in scope_patterns)}
    require(gaps['scope'] == scope_patterns and set(scoped) == expected_scope and len(scoped) == 12, 'Exact committed coverage scope')
    require(all(source[name]['sha256'] == digest and sha(records['source/' + name]) == digest for name, digest in scoped.items()), 'Scoped coverage source bytes')
    require(gaps['source_tree_sha256'] == sha(json.dumps(scoped, sort_keys=True).encode()), 'Scoped source digest')
    merged, current, hits, totals = {}, None, {}, {}
    for entry in lcov.decode().splitlines():
        if entry.startswith('SF:'):
            require(current is None, 'LCOV record boundary')
            name = entry[3:].removeprefix(HOST_ROOT + '/')
            current = name if name in scoped else None
            hits, totals = {}, {}
        elif entry == 'end_of_record':
            if current is not None:
                require(totals == {'LF': len(hits), 'LH': sum(value > 0 for value in hits.values())}, 'LCOV record totals')
                target = merged.setdefault(current, {})
                for line, count in hits.items():
                    target[line] = target.get(line, 0) + count
            current = None
        elif current is not None and entry.startswith('DA:'):
            fields = entry[3:].split(',')
            require(len(fields) in (2, 3), 'LCOV DA fields')
            line, count = int(fields[0]), int(fields[1])
            require(line > 0 and count >= 0 and line not in hits, 'LCOV DA value')
            hits[line] = count
        elif current is not None and entry.startswith(('LF:', 'LH:')):
            key, value = entry.split(':', 1)
            require(key not in totals, 'LCOV duplicate summary')
            totals[key] = int(value)
    require(current is None and set(merged) == set(scoped), 'LCOV complete scoped inventory')
    actual = []
    for name, lines in sorted(merged.items()):
        require(max(lines) <= len(records['source/' + name].decode().splitlines()), 'LCOV source line bounds')
        actual.append({'path': name, 'hit': sum(c > 0 for c in lines.values()), 'total': len(lines),
                       'uncovered_lines': sorted(line for line, count in lines.items() if count == 0)})
    require(gaps['files'] == actual and gaps['uninstrumented_files'] == [], 'LCOV per-source results')
    require(gaps['covered_lines'] == sum(f['hit'] for f in actual) == 2624 and gaps['instrumented_lines'] == sum(f['total'] for f in actual) == 4138, 'LCOV aggregate results')
    return receipt


def verify_host(records, host, repository=None):
    source = verify_sources(records, repository)
    jobs = load(records, 'office-host-jobs.json')['jobs']
    require(len(jobs) == 2 and {job['id'] for job in jobs} == {HOST_JOB, EXTERNAL_JOB}, 'Hosted job inventory')
    job = next(job for job in jobs if job['id'] == HOST_JOB)
    require(job['run_id'] == RUN and job['head_sha'] == APP and job['name'] == 'host-roundtrip', 'Hosted host job identity')
    require(job['status'] == 'completed' and job['conclusion'] == 'success', 'Hosted host result')
    require(len(job['steps']) == 13 and all(s['status'] == 'completed' and s['conclusion'] == 'success' for s in job['steps']), 'Hosted host steps')
    names = [s['name'] for s in job['steps']]
    require(names == HOST_STEPS, 'Exact required host steps')
    require(names.index('Verify committed Office sources before test hooks') < names.index('Shared corpus and host save workflow'), 'Actual pre-hook gate ordering')
    log = records['host-job.log'].decode('utf-8-sig')
    gate = 'python3 tool/verify_office_fidelity.py --require-tracked'
    hook = 'python3 tool/with_ci_system_sqlite.py bash tool/check_office_fidelity.sh'
    require(log.index(gate) < log.index(hook), 'Actual log source/hook ordering')
    for text in [APP, 'Verified 1679 Office files', 'CI SQLite: libsqlite3.so, version 3.45.1, foreign keys/transactions verified; optional FTS5=True',
                 'Host inventory: 122/122 verified; 0 failures', 'Office host coverage: 2624/4138 instrumented lines (63.4%); 0 files absent',
                 'Ran 440 tests', 'Ran 14 tests', 'Ran 34 tests']:
        require(text in log, 'Actual host log marker: ' + text)
    require(sum('✅ test/' in line for line in log.splitlines()) == 1165, 'Engine success event count')
    require(sum('✅ ' + HOST_ROOT + '/test/' in line for line in log.splitlines()) == 202, 'Host success event count')
    artifacts = load(records, 'office-artifacts-host.json')
    require(artifacts['total_count'] == 1 and len(artifacts['artifacts']) == 1, 'Host artifact inventory')
    artifact = artifacts['artifacts'][0]
    require(artifact['id'] == HOST_ARTIFACT and artifact['name'] == 'office-host-fidelity-evidence', 'Host artifact identity')
    require(artifact['workflow_run']['id'] == RUN and artifact['workflow_run']['head_sha'] == APP, 'Host artifact source')
    require(artifact['size_in_bytes'] == HOST_ZIP_BYTES and artifact['digest'] == 'sha256:' + HOST_ZIP_SHA, 'Host artifact API digest')
    inventory = load(records, 'host-artifact-inventory.json')
    require(inventory['artifact'] == artifact and inventory['archiveSha256'] == HOST_ZIP_SHA and inventory['archiveBytes'] == HOST_ZIP_BYTES, 'Host artifact downloaded identity')
    require(inventory['fileCount'] == len(host) == 519 and inventory['uncompressedBytes'] == sum(map(len, host.values())) == 7504304, 'Host artifact totals')
    require(set(host) == set(inventory['files']), 'Retained host archive inventory')
    for name, data in host.items():
        require(inventory['files'][name]['bytes'] == len(data) and inventory['files'][name]['sha256'] == sha(data), 'Retained host member: ' + name)
    paths = verify_host_inventory(records, host)
    verify_coverage(records, host, source)
    return {'hostFiles': len(paths), 'hostArtifactMembers': len(host)}


def png_rgb(raw):
    """Decode the captured renderer's deterministic RGB/filter-0 PNGs."""
    require(raw.startswith(b'\x89PNG\r\n\x1a\n'), 'PNG signature')
    position, chunks, compressed, width, height = 8, [], [], None, None
    while position < len(raw):
        require(position + 12 <= len(raw), 'PNG truncated chunk')
        size = struct.unpack('>I', raw[position:position + 4])[0]
        kind = raw[position + 4:position + 8]
        require(position + size + 12 <= len(raw), 'PNG chunk size')
        data = raw[position + 8:position + 8 + size]
        checksum = struct.unpack('>I', raw[position + 8 + size:position + 12 + size])[0]
        require(zlib.crc32(kind + data) & 0xffffffff == checksum, 'PNG chunk CRC')
        chunks.append(kind)
        if kind == b'IHDR':
            require(size == 13 and chunks == [b'IHDR'], 'PNG header position')
            width, height, depth, color, compression, filtering, interlace = struct.unpack('>IIBBBBB', data)
            require(0 < width <= 10000 and 0 < height <= 10000 and width * height <= 16000000, 'PNG dimensions limit')
            require((depth, color, compression, filtering, interlace) == (8, 2, 0, 0, 0), 'PNG captured RGB encoding')
        elif kind == b'IDAT':
            compressed.append(data)
        elif kind == b'IEND':
            require(size == 0, 'PNG end chunk')
        else:
            raise ValueError('Unexpected captured PNG chunk')
        position += size + 12
    require(chunks == [b'IHDR', b'IDAT', b'IEND'] and width is not None, 'PNG exact chunk inventory')
    decoder = zlib.decompressobj()
    stride = width * 3
    pixels = decoder.decompress(b''.join(compressed), height * (stride + 1) + 1)
    require(decoder.eof and not decoder.unused_data and len(pixels) == height * (stride + 1), 'PNG exact decompressed size')
    require(all(pixels[row * (stride + 1)] == 0 for row in range(height)), 'PNG unfiltered rows')
    rgb = b''.join(pixels[row * (stride + 1) + 1:(row + 1) * (stride + 1)] for row in range(height))
    return width, height, rgb


def verify_native(records, host, external):
    report = load(external, 'host-render/render-report.json')
    require(report['renderer'] == 'LibreOffice 24.2.7.2 420(Build:2)', 'Observed native renderer')
    require(report['files'] == report['rendered_files'] == report['visual_input_files'] == 122, 'Native render totals')
    require(report['native_schema_only_files'] == 0 and report['native_schema_only'] == [] and report['schema_report'] is None, 'Actual native exclusions')
    require(report['failures'] == [] and report['picture_pixel_oracle_files'] == 18, 'Native result/picture oracle count')
    require(report['pixel_fingerprint'] == 'SHA-256 of big-endian uint32 width/height followed by RGB bytes', 'Native fingerprint definition')
    require(report['soffice_retry_policy'] == {'maximum_attempts': 3, 'retry_returncode': -9,
            'scope': 'SOFFICE conversion only; unchanged input and fresh profile/output per attempt'}, 'Native bounded retry policy')
    paths = load(records, 'source/tool/office_host_evidence.json')['outputs']
    rendered = {item['file']: item for item in report['reports']}
    require(len(rendered) == len(report['reports']) == 122 and set(rendered) == set(paths), 'Exact native input coverage')
    renderer_source = records['source/tool/office-validation/render.py']
    require(sha(renderer_source) == RENDER_SOURCE_SHA, 'Pinned pure geometry/comparison helper')
    # Reuse only known, hash-pinned pure validation functions. No renderer/main
    # is invoked. ZIP access is redirected to the retained in-memory packages.
    namespace = {'__name__': 'retained_renderer_checks', '__file__': 'retained-render.py'}
    exec(compile(renderer_source, 'retained-render.py', 'exec'), namespace)
    namespace['ZipFile'] = lambda path: zipfile.ZipFile(io.BytesIO(host[PurePosixPath(path).as_posix()]))
    expected_members = {'host-inventory.json', 'schema-report.json', 'host-render/render-report.json'}
    expected_members.update('host-input/' + name for name in paths)
    profiles, page_count, picture_count = set(), 0, 0
    for index, item in enumerate(report['reports']):
        name, digest = item['file'], sha(host[item['file']])
        require(item['input_sha256'] == digest, 'Native source hash: ' + name)
        require(external['host-input/' + name] == host[name], 'Exact staged host input: ' + name)
        require(item['pdf'] == f'{index:03d}/document.pdf', 'Native PDF mapping')
        pdf = external['host-render/' + item['pdf']]
        require(pdf.startswith(b'%PDF-') and len(pdf) > 100, 'Retained native PDF')
        require(len(re.findall(rb'/Type\s*/Page\b', pdf)) == item['pages'], 'Retained PDF page objects')
        text_name = f'host-render/{index:03d}/text.txt'
        require(external[text_name].decode() == item['text'], 'Native extracted text bytes')
        expected_members.update({'host-render/' + item['pdf'], text_name})
        pages = item['page_artifacts']
        require(item['pages'] == len(pages) == len(item['pixel_sha256']) and item['pages'] > 0, 'Native page inventory')
        case = namespace['host_picture_case'](name)
        require(('picture_pixel_evidence' in item) == (case is not None), 'Native picture oracle membership')
        for page_index, page in enumerate(pages, 1):
            require(page['page'] == page_index and page['png'] == f'{index:03d}/page-{page_index:04d}.png', 'Native page path/order')
            png_name = 'host-render/' + page['png']
            width, height, rgb = png_rgb(external[png_name])
            fingerprint = sha(struct.pack('>II', width, height) + rgb)
            require(page['width'] == width and page['height'] == height, 'Native page dimensions')
            require(page['pixel_sha256'] == item['pixel_sha256'][page_index - 1] == fingerprint, 'Decoded native RGB fingerprint')
            expected_members.add(png_name)
            page_count += 1
            if case is not None:
                require(item['pages'] == 1, 'Picture oracle single page')
                geometry = namespace['picture_package_geometry'](PurePosixPath(name), case)
                measured = namespace['picture_pixel_evidence'](case, width, height, rgb, geometry,
                           item['picture_pixel_evidence']['page_size_points'])
                require(measured == item['picture_pixel_evidence'], 'Measured picture pixels/package geometry')
                picture_count += 1
        attempts = item['conversion_attempts']
        require(len(attempts) == 1, 'Observed conversion attempt inventory')
        attempt = attempts[0]
        require(attempt['attempt'] == 1 and attempt['status'] == 'converted' and attempt['returncode'] == 0, 'Native conversion result')
        require(attempt['input_sha256_before'] == attempt['input_sha256_after'] == digest and attempt['input_unchanged'] is True, 'Native conversion source stability')
        command = attempt['command']
        require(len(command) == 8 and command[0] == '/usr/bin/libreoffice' and command[2:6] == ['--headless', '--convert-to', 'pdf', '--outdir'], 'Exact native conversion argv')
        output = command[6]
        require(re.fullmatch(re.escape(HOST_ROOT) + r'/build/external/host-render/render-' + f'{index:03d}' + r'-attempt-1-[a-z0-9_]+', output) is not None, 'Native unique attempt directory')
        require(command[1] == '-env:UserInstallation=file://' + output + '/profile' and command[7] == HOST_ROOT + '/build/external/host-input/' + name, 'Native profile/input argv')
        require(output not in profiles, 'Native fresh profile per input')
        profiles.add(output)
    require(page_count == 158 and picture_count == 18 and set(external) == expected_members, 'Complete retained native artifact inventory')
    coverage = namespace['cycle_coverage'](paths, rendered)
    require(coverage['cycle_groups'] == 33 and coverage['baseline_comparisons'] == coverage['page_order_comparisons'] == 0
            and len(coverage['render_only_files']) == 23 and coverage['failures'] == [], 'Native comparison scope')
    for key, value in coverage.items():
        require(report[key] == value, 'Recomputed native comparison: ' + key)
    require(all(group['expected_cycles'] == group['actual_cycles'] == [1, 2, 3] for group in coverage['cycle_comparisons']), 'Three-save series inventory')
    return {'nativeFiles': 122, 'nativePages': page_count, 'nativeCycleGroups': 33,
            'nativeBaselineComparisons': 0, 'nativeRenderOnlyFiles': 23, 'nativePictureOracles': 18,
            'nativeSchemaOnlyFiles': 0, 'nativeRetryAttempts': 0}


def verify_schema(host, external):
    schema = load(external, 'schema-report.json')
    packages = {name: data for name, data in host.items() if PurePosixPath(name).suffix.lower() in MAIN_TYPES}
    reports = {item['File']: item for item in schema['Reports']}
    require(schema['Files'] == len(reports) == len(schema['Reports']) == len(packages) == 468 and schema['Failures'] == 0, 'SDK result count')
    require(set(reports) == {'evidence/' + name for name in packages}, 'SDK exact package inventory')
    for name, data in packages.items():
        require(set(reports['evidence/' + name]) == {'File', 'Sha256', 'Errors'}, 'Successful SDK row shape')
        require(reports['evidence/' + name]['Sha256'] == sha(data) and reports['evidence/' + name]['Errors'] == [], 'SDK package bytes/errors: ' + name)


def verify_external(records, host, external):
    run, jobs = load(records, 'office-final-run.json'), load(records, 'office-final-jobs.json')['jobs']
    require(run['id'] == RUN and run['head_sha'] == APP and run['head_commit']['tree_id'] == TREE, 'Final hosted run identity')
    require(run['head_branch'] == 'feature/office-fidelity-gaps-20261113' and run['run_attempt'] == 1
            and run['path'] == '.github/workflows/office-fidelity.yml', 'Final hosted workflow/attempt')
    require(run['status'] == 'completed' and run['conclusion'] == 'success', 'Final hosted run result')
    require(len(jobs) == 2 and {job['id'] for job in jobs} == {HOST_JOB, EXTERNAL_JOB}, 'Final hosted job inventory')
    for job in jobs:
        require(job['run_id'] == RUN and job['head_sha'] == APP and job['status'] == 'completed' and job['conclusion'] == 'success', 'Final hosted job result')
        require(job['name'] == ('host-roundtrip' if job['id'] == HOST_JOB else 'external-schema'), 'Final hosted job name')
        require([step['name'] for step in job['steps']] == (HOST_STEPS if job['id'] == HOST_JOB else EXTERNAL_STEPS), 'Exact final required steps')
        require(len(job['steps']) == (13 if job['id'] == HOST_JOB else 14) and all(step['status'] == 'completed' and step['conclusion'] == 'success' for step in job['steps']), 'Final hosted step results')
    artifacts = load(records, 'office-final-artifacts.json')
    require(artifacts['total_count'] == len(artifacts['artifacts']) == 2 and {item['id'] for item in artifacts['artifacts']} == {HOST_ARTIFACT, EXTERNAL_ARTIFACT}, 'Final artifact inventory')
    artifact = next(item for item in artifacts['artifacts'] if item['id'] == EXTERNAL_ARTIFACT)
    require(artifact['name'] == 'office-host-schema-evidence' and artifact['workflow_run']['id'] == RUN and artifact['workflow_run']['head_sha'] == APP, 'External artifact identity')
    require(artifact['size_in_bytes'] == EXTERNAL_ZIP_BYTES and artifact['digest'] == 'sha256:' + EXTERNAL_ZIP_SHA, 'External API digest')
    host_artifact = next(item for item in artifacts['artifacts'] if item['id'] == HOST_ARTIFACT)
    require(host_artifact == load(records, 'office-artifacts-host.json')['artifacts'][0], 'Stable host artifact metadata')
    inventory = load(records, 'external-artifact-inventory.json')
    require(inventory['artifact'] == artifact and inventory['archiveBytes'] == EXTERNAL_ZIP_BYTES and inventory['archiveSha256'] == EXTERNAL_ZIP_SHA, 'Downloaded external artifact identity')
    require(inventory['fileCount'] == len(external) == 527 and inventory['uncompressedBytes'] == sum(map(len, external.values())) == 4533364, 'External artifact totals')
    for name, data in external.items():
        require(inventory['files'][name]['bytes'] == len(data) and inventory['files'][name]['sha256'] == sha(data), 'External member: ' + name)
    require(set(external) == set(inventory['files']), 'External retained inventory')
    require(load(external, 'host-inventory.json') == load(host, 'build/fidelity-host/inventory.json'), 'Host inventory transfer')
    verify_schema(host, external)
    log = records['external-job.log'].decode('utf-8-sig')
    for text in [APP, "dotnet-install: .NET Core SDK with version '8.0.428' is already installed.",
                 'dotnet run --project tool/office-validation -- --self-test',
                 'dotnet run --no-build --project tool/office-validation -- evidence build/external/schema-report.json',
                 'python3 tool/office-validation/render.py build/external/host-input build/external/host-render',
                 'Open XML SDK controls passed: 8 valid Word packages, 4 invalid XML, 12 mismatched types, and exact discovery.',
                 'Host inventory: 122/122 verified; 0 failures', 'Ran 77 tests']:
        require(text in log, 'Actual external log marker: ' + text)
    require(b'Include="DocumentFormat.OpenXml" Version="3.3.0"' in records['source/tool/office-validation/OfficeValidation.csproj'], 'Pinned Open XML SDK version')
    rendered_lines = re.findall(r'Z (build/[^\r\n]+): rendered (\d+) pages', log)
    native_report = load(external, 'host-render/render-report.json')
    require(len(rendered_lines) == 122 and dict(rendered_lines) == {item['file']: str(item['pages']) for item in native_report['reports']}, 'Actual native render log coverage')
    return {'schemaPackages': 468, 'schemaFailures': 0, **verify_native(records, host, external)}


def verify(directory, repository=None):
    receipt = json.loads((directory / 'receipt.json').read_bytes())
    require(receipt['schemaVersion'] == 1 and receipt['measuredAppCommit'] == APP and receipt['measuredAppTree'] == TREE and receipt['parserCommit'] == PARSER, 'Receipt source')
    require(receipt['measuredRuntimeCommit'] == RUNTIME and receipt['measuredRuntimeTree'] == RUNTIME_TREE, 'Receipt measured runtime')
    require(receipt['officeRunId'] == RUN and receipt['phase'] == 'host-and-external-complete', 'Receipt phase')
    for name, item in receipt['files'].items():
        require(safe(name), 'Unsafe sealed path')
        data = (directory / name).read_bytes()
        require(len(data) == item['bytes'] and sha(data) == item['sha256'], 'Sealed file: ' + name)
    require(set(receipt['files']) == {'README.md', 'verify.py', 'test_verifier.py', 'manifest.json', 'records.tar.xz'}, 'Sealed helper inventory')
    records = unpack((directory / 'records.tar.xz').read_bytes())
    manifest = json.loads((directory / 'manifest.json').read_bytes())['files']
    require(set(records) == set(manifest) and len(records) == receipt['metadataRecordCount'], 'Metadata inventory')
    require(sum(map(len, records.values())) == receipt['metadataUncompressedBytes'], 'Metadata byte total')
    for name, data in records.items():
        require(manifest[name] == {'bytes': len(data), 'sha256': sha(data)}, 'Metadata member: ' + name)
    pieces = []
    for index, item in enumerate(receipt['hostParts'], 1):
        require(item['path'] == f'host-artifact.part{index:02d}', 'Host part order')
        data = (directory / item['path']).read_bytes()
        require(len(data) == item['bytes'] and sha(data) == item['sha256'], 'Host part bytes')
        pieces.append(data)
    raw = b''.join(pieces)
    require(len(raw) == HOST_ZIP_BYTES and sha(raw) == HOST_ZIP_SHA, 'Original host ZIP digest')
    host = unzip(raw, load(records, 'host-artifact-inventory.json'))
    result = verify_host(records, host, repository)
    pieces = []
    for index, item in enumerate(receipt['externalParts'], 1):
        require(item['path'] == f'external-artifact.part{index:02d}', 'External part order')
        data = (directory / item['path']).read_bytes()
        require(len(data) == item['bytes'] and sha(data) == item['sha256'], 'External part bytes')
        pieces.append(data)
    raw = b''.join(pieces)
    require(len(raw) == EXTERNAL_ZIP_BYTES and sha(raw) == EXTERNAL_ZIP_SHA, 'Original external ZIP digest')
    external = unzip(raw, load(records, 'external-artifact-inventory.json'))
    result.update(verify_external(records, host, external))
    print(json.dumps({'verified': True, 'metadataRecords': len(records), **result, 'app': APP}, indent=2))
    return records, host, external


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', nargs='?', type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument('--repository', type=Path)
    arguments = parser.parse_args()
    verify(arguments.directory, arguments.repository)
