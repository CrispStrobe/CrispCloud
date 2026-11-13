#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Verify the sealed source/observation bundle without running native tools.

All guards use exceptions, including under Python -O. Recorded schema-5
snapshots replay against their retained, Git-bound schema-5 source; schema 6
is used only for its separately recorded font counterexample.
"""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import struct
import subprocess
import sys
import types
import xml.etree.ElementTree as ET
import zipfile

BASELINE = '43027f9ddb626a4f8fccbef1c41c7f2ea9fccf47'
SYMBOLS = '9aa9da7c1e378d369c03ed1abcebfd70eb496b0d'
FONTS = 'd5fa58409ce4be3859b05a40132edbef3c4d54cf'
ORACLE6 = '901f85854592cdf5f27d475da27ea5431d6024d5'
FINAL = '927c2cb089cf2d037dc009cdcb9c11b9fe125bf9'
COMBINED = '1b8cc9e28aa9f4da2d0f0fa9318758bce0e923f1'
DART = '/workspace/scratch/c1ca2a1344e9/toolchains/dart-3.13.7/dart-sdk/bin/dart'
WORKTREE = '/workspace/scratch/c1ca2a1344e9/parser-oracle-bug-probes'
PROBES = '/workspace/scratch/c1ca2a1344e9/oracle-probes-20261113'
CONTROL_SHA = '765f8c5f7a3d4eaf6366419c70a0d0b48b2848009ec9549b34c28b0de0dc549f'
PARENT_SHA = 'c16d1e2f9ac6c7d53a762526553a36feea466231068709f9bb00ea0c129fcdc1'
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
NS = {'w': W}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(value):
    return hashlib.sha256(value).hexdigest()


def valid_path(path):
    return (isinstance(path, str) and path and not path.startswith('/') and
            '\\' not in path and '\n' not in path and '\r' not in path and
            all(part not in ('', '.', '..') for part in PurePosixPath(path).parts))


def read_bundle(directory):
    checksums = json.loads((directory / 'checksums.json').read_bytes())
    actual = {path.name for path in directory.iterdir() if path.is_file() and path.name != 'checksums.json'}
    require(actual == set(checksums), 'Top-level evidence inventory differs')
    for name, record in checksums.items():
        require(valid_path(name) and '/' not in name, 'Invalid top-level path')
        value = (directory / name).read_bytes()
        require(len(value) == record['bytes'] and sha(value) == record['sha256'], 'Top-level checksum differs: ' + name)
    manifest = json.loads((directory / 'manifest.json').read_bytes())
    require(manifest['schema'] == 'legacy-doc-parser/independent-symbol-font-evidence' and manifest['version'] == 1, 'Unknown bundle schema')
    require(manifest['sourceCheckpoints'] == {'baseline': BASELINE, 'inlineOracle': 'c73749df59d0978c8bcd20710a2ae92184fab11a',
            'symbols': SYMBOLS, 'fontCharsets': FONTS, 'fontOracle': ORACLE6, 'emptyFontGuard': FINAL, 'combinedRuntime': COMBINED}, 'Manifest source identity differs')
    require(manifest['archive']['path'] == 'observations.zip', 'Unexpected archive path')
    raw = (directory / 'observations.zip').read_bytes()
    require(sha(raw) == manifest['archive']['sha256'] and len(raw) == manifest['archive']['bytes'], 'Archive binding differs')
    records = {record['path']: record for record in manifest['records']}
    require(len(records) == len(manifest['records']), 'Duplicate manifest paths')
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)) and set(names) == set(records), 'Archive inventory differs')
        require(sum(item.file_size for item in archive.infolist()) <= 80 * 1024 * 1024, 'Evidence expansion exceeds limit')
        data = {}
        for name in names:
            require(valid_path(name), 'Invalid archive path')
            value = archive.read(name)
            require(len(value) == records[name]['bytes'] and sha(value) == records[name]['sha256'], 'Archived bytes differ: ' + name)
            data[name] = value
    return data, manifest


def git_bytes(repository, commit, path):
    require(valid_path(path), 'Invalid Git source path')
    result = subprocess.run(['git', 'show', commit + ':' + path], cwd=repository, capture_output=True)
    require(result.returncode == 0, 'Required retained Git source is missing: ' + commit + ':' + path)
    return result.stdout


def verify_git_files(repository, commit, files):
    process = subprocess.Popen(['git', 'cat-file', '--batch'], cwd=repository, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    try:
        for path, expected in files.items():
            require(valid_path(path), 'Invalid tracked source path')
            process.stdin.write((commit + ':' + path + '\n').encode())
            process.stdin.flush()
            header = process.stdout.readline().decode().strip().split()
            require(len(header) == 3 and header[1] == 'blob', 'Missing tracked source: ' + path)
            value = process.stdout.read(int(header[2]))
            require(process.stdout.read(1) == b'\n' and sha(value) == expected, 'Tracked source hash differs: ' + path)
    finally:
        process.stdin.close()
        process.stdout.close()
        process.wait(timeout=10)


def cfb_streams(raw):
    """Bounded v3 reader only for these retained direct-root source controls."""
    require(raw[:8] == bytes.fromhex('d0cf11e0a1b11ae1') and len(raw) % 512 == 0, 'Invalid retained CFB')
    u16 = lambda offset: struct.unpack_from('<H', raw, offset)[0]
    u32 = lambda offset: struct.unpack_from('<I', raw, offset)[0]
    require(u16(30) == 9 and u16(32) == 6 and u16(28) == 0xfffe, 'Unexpected retained CFB geometry')
    sectors = len(raw) // 512 - 1

    def sector(index):
        require(0 <= index < sectors, 'CFB sector out of bounds')
        return raw[(index + 1) * 512:(index + 2) * 512]

    count = u32(44)
    require(count <= 109 and u32(72) == 0, 'Unexpected retained DIFAT extension')
    fat_ids = struct.unpack_from('<109I', raw, 76)[:count]
    fat = [value for index in fat_ids for value in struct.unpack('<128I', sector(index))]

    def chain(start, table):
        result, seen = [], set()
        while start != 0xfffffffe:
            require(0 <= start < len(table) and start not in seen and len(result) <= sectors * 8, 'Invalid retained CFB chain')
            seen.add(start)
            result.append(start)
            start = table[start]
        return result

    directory = b''.join(sector(i) for i in chain(u32(48), fat))
    entries = []
    for offset in range(0, len(directory), 128):
        entry = directory[offset:offset + 128]
        if entry[66] == 0:
            continue
        length = struct.unpack_from('<H', entry, 64)[0]
        require(2 <= length <= 64 and length % 2 == 0, 'Invalid retained CFB name')
        entries.append((entry[:length - 2].decode('utf-16le'), entry[66],
                        struct.unpack_from('<I', entry, 116)[0], struct.unpack_from('<Q', entry, 120)[0]))
    roots = [entry for entry in entries if entry[1] == 5]
    require(len(roots) == 1, 'Missing retained CFB root')
    root = roots[0]
    mini_stream = b''.join(sector(i) for i in chain(root[2], fat))[:root[3]]
    mini_bytes = b''.join(sector(i) for i in chain(u32(60), fat)) if u32(64) else b''
    mini_fat = struct.unpack('<' + 'I' * (len(mini_bytes) // 4), mini_bytes)
    streams = {}
    for name, kind, start, size in entries:
        if kind != 2:
            continue
        require(name not in streams and size <= 32 * 1024 * 1024, 'Invalid retained stream')
        if size < u32(56):
            value = b''.join(mini_stream[i * 64:(i + 1) * 64] for i in chain(start, mini_fat))
        else:
            value = b''.join(sector(i) for i in chain(start, fat))
        require(len(value) >= size, 'Truncated retained stream')
        streams[name] = value[:size]
    return streams


def font_source(raw):
    streams = cfb_streams(raw)
    word = streams['WordDocument']
    u16 = lambda offset: struct.unpack_from('<H', word, offset)[0]
    table_name = '1Table' if u16(10) & 0x200 else '0Table'
    table = streams[table_name]
    cslw = 34 + u16(32) * 2
    pairs = cslw + 2 + u16(cslw) * 4 + 2
    start, length = struct.unpack_from('<II', word, pairs + 15 * 8)
    position = start + (2 if table[start:start + 2] == b'\xff\xff' else 0)
    count, extra = struct.unpack_from('<HH', table, position)
    position += 4
    fonts = []
    for index in range(count):
        size = table[position] + 1
        require(size >= 42 and size % 2 == 0 and position + size + extra <= start + length, 'Invalid retained FFN extent')
        names = table[position + 40:position + size].decode('utf-16le').split('\0')
        require(names[-1] == '', 'Unterminated retained FFN name')
        fonts.append({'index': index, 'tableOffset': position, 'recordSize': size,
                      'flags': table[position + 1], 'weight': struct.unpack_from('<H', table, position + 2)[0],
                      'charset': table[position + 4], 'alternateNameOffset': table[position + 5],
                      'names': names[:-1], 'panose': list(table[position + 6:position + 16]),
                      'signature': list(table[position + 16:position + 40])})
        position += size + extra
    require(position == start + length, 'FFN table boundary differs')
    return {'sourceSha256': sha(raw), 'table': table_name, 'offset': start, 'length': length, 'fonts': fonts}


def package_parts(raw):
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        require(len(archive.namelist()) == len(set(archive.namelist())), 'Duplicate package parts')
        return {name: archive.read(name) for name in archive.namelist()}


def bbox(raw):
    pages = []
    for page in ET.fromstring(raw).iter():
        if page.tag.rsplit('}', 1)[-1] != 'page':
            continue
        words = [{'text': word.text or '', 'box': [float(word.get(k)) for k in ('xMin', 'yMin', 'xMax', 'yMax')]}
                 for word in page.iter() if word.tag.rsplit('}', 1)[-1] == 'word']
        pages.append({'size': [float(page.get('width')), float(page.get('height'))], 'words': words})
    require(pages, 'No retained page boxes')
    return pages


def ppm(raw):
    header = re.match(rb'P6\s+(\d+)\s+(\d+)\s+255\n', raw)
    require(header is not None, 'Invalid retained PPM header')
    width, height = int(header[1]), int(header[2])
    pixels = raw[header.end():]
    require(width > 0 and height > 0 and len(pixels) == width * height * 3, 'Invalid retained RGB extent')
    return width, height, pixels


def compare(reference, actual):
    rp, ap = reference['pages'], actual['pages']
    same_text = len(rp) == len(ap) and all([w['text'] for w in a['words']] == [w['text'] for w in b['words']] for a, b in zip(rp, ap))
    drift = max([0.0] + [abs(x - y) for a, b in zip(rp, ap) for wa, wb in zip(a['words'], b['words']) for x, y in zip(wa['box'], wb['box'])]) if same_text else None
    dimensions = len(rp) == len(ap) and all(a['size'] == b['size'] for a, b in zip(rp, ap))
    settings = reference['rasterColorSpace'] == 'RGB' and reference['rasterDpi'] > 0 and all(reference[k] == actual[k] for k in ('rasterDpi', 'rasterColorSpace'))
    raster = settings and reference['rasterSha256'] == actual['rasterSha256']
    text = reference['text'] == actual['text']
    return {'referencePages': len(rp), 'actualPages': len(ap), 'pageDimensionsMatch': dimensions,
            'pageTextMatches': same_text, 'maximumWordDriftPoints': drift, 'tolerancePoints': 0.25,
            'matchesWithinTolerance': dimensions and same_text and drift is not None and drift <= 0.25,
            'rasterSettingsMatch': settings, 'rasterExactlyMatches': raster, 'layoutTextExactlyMatches': text,
            'exactOnThisRenderer': raster and text and drift == 0 and dimensions}


def pixel_difference(a, b):
    require(len(a) == len(b) and len(a) % 3 == 0, 'Pixel comparison dimensions differ')
    return {'changedPixels': sum(a[i:i + 3] != b[i:i + 3] for i in range(0, len(a), 3)),
            'absoluteRgbError': sum(abs(x - y) for x, y in zip(a, b))}


def load_oracle(data, repository, commit, sources):
    # Execute only exact retained repository code, never an arbitrary ZIP module.
    definitions = {}
    for name in ('structure', 'oracle'):
        path = 'tool/fidelity/' + name + '.py'
        value = git_bytes(repository, commit, path)
        require(sha(value) == sources['files'][path], 'Versioned oracle source binding differs')
        definitions[name] = value
    previous = sys.modules.get('structure')
    try:
        module = types.ModuleType('structure')
        module.__file__ = str(repository / 'tool/fidelity/structure.py')
        exec(compile(definitions['structure'], module.__file__, 'exec'), module.__dict__)
        sys.modules['structure'] = module
        oracle = types.ModuleType('retained_oracle')
        oracle.__file__ = str(repository / 'tool/fidelity/oracle.py')
        exec(compile(definitions['oracle'], oracle.__file__, 'exec'), oracle.__dict__)
        return oracle
    finally:
        if previous is None:
            sys.modules.pop('structure', None)
        else:
            sys.modules['structure'] = previous


def verify_data(data, repository):
    read = lambda path: json.loads(data[path])
    initial = read('before-source.json')
    symbol_build = read('symbol-after-convert.build.json')
    font_build = read('font-portable-validation.json')
    final = read('font-final-output-equivalence/report.json')
    for receipt, directory in [(initial['buildSource'], 'baseline-build-sources'),
                               (symbol_build['sources'], 'build-sources'),
                               (font_build['source'], 'font-build-sources'),
                               (final['sources'], 'font-final-output-equivalence/sources')]:
        require(sha(json.dumps(receipt['files'], sort_keys=True, separators=(',', ':')).encode()) == receipt['sha256'], 'Build source inventory digest differs')
        for path, digest in receipt['files'].items():
            require(sha(data[directory + '/' + digest]) == digest, 'Retained build source bytes differ: ' + path)
    require(final['sourceCommit'] == FINAL and final['sourcesUnchanged'] is True, 'Final source identity differs')
    require(final['sourceTree'] == '4c39f4c912ec542792aa878e014c6040f6ce00fc', 'Final source tree differs')
    final_run = read('font-followup-validation-v2.json')
    require(final_run['sourcesUnchanged'] is True, 'Final test inputs changed')
    verify_git_files(repository, FINAL, final_run['sourceFiles'])
    for build, commit in [(initial['buildSource'], BASELINE), (symbol_build['sources'], SYMBOLS),
                          (font_build['source'], FONTS), (final['sources'], FINAL)]:
        verify_git_files(repository, commit, {p: h for p, h in build['files'].items() if p.startswith('lib/')})
    oracle4 = load_oracle(data, repository, BASELINE, initial['buildSource'])
    oracle5 = load_oracle(data, repository, FONTS, font_build['source'])
    oracle6 = load_oracle(data, repository, FINAL, final['sources'])

    require(sha(data['csymbol.doc']) == CONTROL_SHA and sha(data['symbol-doc/symbol-glyphs.doc']) == PARENT_SHA, 'Pinned binary control identity differs')
    require(data['csymbol.doc'] == git_bytes(repository, SYMBOLS, 'test/fixtures/word_native/symbol-source-control.doc'), 'Committed binary control differs')
    parent = cfb_streams(data['symbol-doc/symbol-glyphs.doc'])
    control = cfb_streams(data['csymbol.doc'])
    patch = read('csymbol-control.json')
    require(set(parent) == set(control) == {entry['path'] for entry in patch['streams']}, 'Control stream inventory differs')
    for entry in patch['streams']:
        name = entry['path']
        require(sha(parent[name]) == entry['beforeSha256'] and sha(control[name]) == entry['afterSha256'] and len(control[name]) == entry['bytes'], 'Control stream binding differs')
        if name != 'WordDocument':
            require(parent[name] == control[name], 'Authored control altered another stream')
    old, new = parent['WordDocument'], control['WordDocument']
    fc, page = patch['literalFc'], patch['chpxPageOffset']
    require(struct.unpack_from('<H', old, fc)[0] == 0xf061 and struct.unpack_from('<H', new, fc)[0] == 0x28, 'Control character operands differ')
    require(len(old) == len(new) and all(a == b or fc <= i < fc + 2 or page <= i < page + 512 for i, (a, b) in enumerate(zip(old, new))), 'Control patch exceeded its declared scope')
    for value, expected in [(old, patch['beforeProperties']), (new, patch['afterProperties'])]:
        block = value[page:page + 512]
        count = block[511]
        boundaries = list(struct.unpack_from('<' + 'I' * (count + 1), block))
        require(boundaries == patch['sourceFcBoundaries'], 'Control CHPX source boundaries differ')
        index = boundaries.index(fc)
        offset = block[4 * (count + 1) + index] * 2
        require(list(block[offset + 1:offset + 1 + block[offset]]) == expected, 'Control CHPX operand differs')
    require(font_source(data['csymbol.doc']) == read('symbol-font-source.json'), 'Raw symbol FFN interpretation differs')
    require(font_source(data['font-guard-failure/formatting.doc']) == read('font-final-output-equivalence/formatting-font-source.json'), 'Raw formatting FFN interpretation differs')

    snapshots = 0
    for case in ('character-controls', 'locked-fields', 'note-joins'):
        for kind, path in [('source', 'inputs/' + case + '.docx'),
                           ('native', case + '-native-docx/' + case + '.docx'),
                           ('parser', case + '-parser-before.docx')]:
            expected = read(case + '-' + kind + '-snapshot.json')
            require(expected['oracleSchemaVersion'] == 5 and oracle5.snapshot(io.BytesIO(data[path])) == expected, 'Historical schema-5 snapshot differs: ' + case + '-' + kind)
            snapshots += 1
        observation = read(case + '-observation.json')
        require(observation['sourceSha256'] == sha(data['inputs/' + case + '.docx']) and observation['nativeDocSha256'] == sha(data[case + '-doc/' + case + '.doc']) and observation['nativeDocxSha256'] == sha(data[case + '-native-docx/' + case + '.docx']), 'Initial native path binding differs')
    for case in ('character-controls', 'symbol-glyphs', 'locked-fields', 'note-joins'):
        source, mutation = data['inputs/' + case + '.docx'], data[case + '-mutated.docx']
        require(not oracle4.compare_semantics(oracle4.snapshot(io.BytesIO(source)), oracle4.snapshot(io.BytesIO(mutation))), 'Old false-green control no longer reproduces')
        require(oracle5.compare_semantics(oracle5.snapshot(io.BytesIO(source)), oracle5.snapshot(io.BytesIO(mutation))), 'Schema-5 discrimination is missing')
    for label in ('csymbol', 'implicit', 'nonspecial', 'cleared', 'ordinary'):
        package = package_parts(data[label + '-native/' + label + '.docx'])
        tree = ET.fromstring(package['word/document.xml'])
        glyphs = [(node.get('{' + W + '}font'), (node.get('{' + W + '}char') or '').upper()) for node in tree.iter('{' + W + '}sym')]
        expected = [('Symbol', 'F057'), ('Wingdings', 'F0FC')]
        if label != 'ordinary':
            expected.insert(0, ('Symbol', 'F061'))
        require(glyphs == expected, 'Native symbol/ordinary control differs: ' + label)

    raster_count = 0
    decoded = {}
    def verify_render(directory, facts):
        nonlocal raster_count
        prefix = directory + '/'
        pdfs = [name for name in data if name.startswith(prefix) and '/' not in name[len(prefix):] and name.endswith('.pdf')]
        require(len(pdfs) == 1 and sha(data[pdfs[0]]) == facts['pdfSha256'], 'Rendered PDF binding differs: ' + directory)
        require(data[prefix + 'pages.txt'].decode() == facts['text'] and bbox(data[prefix + 'pages.xhtml']) == facts['pages'], 'Text/word-box render evidence differs: ' + directory)
        manifest_path = prefix + 'raster-manifest.json'
        receipt = read(manifest_path)
        require(facts['rasterManifest']['path'] == 'raster-manifest.json' and facts['rasterManifest']['sha256'] == sha(data[manifest_path]), 'Raster receipt binding differs')
        require(receipt['status'] == 'complete' and receipt['pdfSha256'] == facts['pdfSha256'] and receipt['pages'] == facts['rasterArtifacts'], 'Raster receipt facts differ')
        require(receipt['rasterDpi'] == facts['rasterDpi'] == 72 and receipt['rasterColorSpace'] == facts['rasterColorSpace'] == 'RGB', 'Raster settings differ')
        require(len(receipt['pages']) == receipt['pdfPageCount'] == receipt['expectedPages'] == len(facts['pages']), 'Raster/page count differs')
        require(sha(data[prefix + receipt['pdfInfo']['path']]) == receipt['pdfInfo']['sha256'], 'PDF info binding differs')
        hashes, pages = [], []
        for item in receipt['pages']:
            compressed = data[prefix + item['path']]
            require(sha(compressed) == item['sha256'] and len(compressed) == item['sizeBytes'], 'Compressed raster differs')
            raw = gzip.decompress(compressed)
            require(sha(raw) == item['uncompressedSha256'] and len(raw) == item['uncompressedSizeBytes'], 'Decoded raster differs')
            pages.append(ppm(raw))
            hashes.append(sha(raw))
            raster_count += 1
        require(hashes == facts['rasterSha256'], 'Reported raster fingerprint differs')
        decoded[directory] = pages

    reports = {}
    for group in ('symbol-native-measurements', 'font-native-measurements'):
        report = read(group + '/report.json')
        reports[group] = report
        require(report['status'] == 'complete' and report['sourceSha256'] == CONTROL_SHA, 'Incomplete native report')
        expected_before = initial['converterSha256'] if group.startswith('symbol') else symbol_build['executableSha256']
        expected_after = symbol_build['executableSha256'] if group.startswith('symbol') else font_build['executableSha256']
        require(report['beforeConverterSha256'] == expected_before and report['afterConverterSha256'] == expected_after, 'Native converter identity differs')
        require(sha(data[group + '/fonts.txt']) == report['fontInventorySha256'] and sha(data[group + '/font-files.json']) == report['fontFilesSha256'], 'Recorded font environment differs')
        require('26.8.0.0.alpha0' in report['tools']['office']['version'] and '2c87e51eeaa2b413ff4ae097b2705eea1995d8e5' in report['tools']['office']['version'], 'Native renderer identity differs')
        require('26.05.0' in report['tools']['pdftoppm']['version'] and '26.05.0' in report['tools']['pdfinfo']['version'] and '25.03.0' in report['tools']['pdftotext']['version'], 'PDF tool identity differs')
        imports = {item['label']: item for item in report['imports']}
        require(set(imports) == {'before', 'after', 'cycle-1-converted', 'cycle-2-converted'}, 'Native import cohort differs')
        inputs = {'before': 'csymbol.doc', 'after': 'csymbol.doc',
                  'cycle-1-converted': group + '/cycle-1-binary/after.doc',
                  'cycle-2-converted': group + '/cycle-2-binary/cycle-1-converted.doc'}
        for label, path in inputs.items():
            command = imports[label]
            require(command['exitCode'] == 0 and command['sourceSha256'] == sha(data[path]) and command['argv'][1].endswith('/' + path) and command['argv'][2].endswith('/' + group + '/' + label + '.docx'), 'Native parser invocation binding differs')
        render_inputs = {'source': 'csymbol.doc', 'before-render': group + '/before.docx', 'after-render': group + '/after.docx'}
        for number in (1, 2):
            render_inputs[f'cycle-{number}-binary-render'] = inputs[f'cycle-{number}-converted']
            render_inputs[f'cycle-{number}-converted-render'] = group + f'/cycle-{number}-converted.docx'
        require(set(report['renders']) == set(render_inputs), 'Native render cohort differs')
        for label, facts in report['renders'].items():
            require(facts['inputSha256'] == sha(data[render_inputs[label]]), 'Native render input identity differs')
            verify_render(group + '/' + label, facts)
        require(report['beforeAgainstSource'] == compare(report['renders']['source'], report['renders']['before-render']) and report['afterAgainstSource'] == compare(report['renders']['source'], report['renders']['after-render']), 'Native initial comparison differs')
        require([item['cycle'] for item in report['cycles']] == [1, 2], 'Native cycle inventory differs')
        for cycle in report['cycles']:
            number = cycle['cycle']
            binary_path = group + f'/cycle-{number}-binary/' + ('after.doc' if number == 1 else 'cycle-1-converted.doc')
            converted_path = group + f'/cycle-{number}-converted.docx'
            native_path = group + f'/cycle-{number}-native/' + ('after.docx' if number == 1 else 'cycle-1-converted.docx')
            require(cycle['binarySha256'] == sha(data[binary_path]) and cycle['convertedSha256'] == sha(data[converted_path]) and cycle['nativeDocxSha256'] == sha(data[native_path]), 'Native cycle source/output binding differs')
            current = report['renders'][f'cycle-{number}-converted-render']
            require(cycle['againstOwnBinary'] == compare(report['renders'][f'cycle-{number}-binary-render'], current) and cycle['againstInitialSource'] == compare(report['renders']['source'], current), 'Native cycle comparison differs')
        for label, path in [('before', group + '/before.docx'), ('after', group + '/after.docx'),
                            ('cycle-1-converted', group + '/cycle-1-converted.docx'), ('cycle-2-converted', group + '/cycle-2-converted.docx'),
                            ('cycle-1-native', group + '/cycle-1-native/after.docx'), ('cycle-2-native', group + '/cycle-2-native/cycle-1-converted.docx')]:
            require(oracle5.snapshot(io.BytesIO(data[path])) == read(group + '/' + label + '-snapshot.json'), 'Native historical snapshot differs')
            snapshots += 1
    symbol, font = reports.values()
    require(symbol['afterAgainstSource']['rasterExactlyMatches'] is False and abs(symbol['afterAgainstSource']['maximumWordDriftPoints'] - 2.7) < 1e-10, 'Original residual was erased')
    require(font['afterAgainstSource']['exactOnThisRenderer'] is True and all(c['againstInitialSource']['exactOnThisRenderer'] and c['againstOwnBinary']['exactOnThisRenderer'] for c in font['cycles']), 'Final bounded native equality differs')
    pixels = read('symbol-native-measurements/target-pixels.json')
    source, before, after = [decoded['symbol-native-measurements/' + name][0] for name in ('source', 'before-render', 'after-render')]
    require(source[:2] == before[:2] == after[:2] == (612, 792), 'Pixel geometry differs')
    cutoff = 86 * 612 * 3
    for key, a, b in [('beforeFirstLine', source[2][:cutoff], before[2][:cutoff]), ('afterFirstLine', source[2][:cutoff], after[2][:cutoff]),
                      ('beforeFullPage', source[2], before[2]), ('afterFullPage', source[2], after[2]),
                      ('beforeAfterBelowFirstLine', before[2][cutoff:], after[2][cutoff:])]:
        require(pixels[key] == pixel_difference(a, b), 'Pixel attribution differs: ' + key)

    counter = read('font-metadata-counterfactuals-v2/report.json')
    original_parts = package_parts(data['symbol-native-measurements/after.docx'])
    require(counter['sourceParserDocxSha256'] == sha(data['symbol-native-measurements/after.docx']), 'Counterfactual source differs')
    require([case['charset'] for case in counter['cases']] == ['02', '01'], 'Paired charset controls differ')
    for case in counter['cases']:
        value = case['charset']
        path = 'font-metadata-counterfactuals-v2/wingdings-charset-' + value + '.docx'
        parts = package_parts(data[path])
        require(sha(data[path]) == case['packageSha256'] and case['documentXmlUnchanged'] is True, 'Counterfactual package binding differs')
        require(set(parts) == set(original_parts) | {'word/fontTable.xml'}, 'Counterfactual part inventory differs')
        for name in original_parts:
            if name not in ('[Content_Types].xml', 'word/_rels/document.xml.rels'):
                require(parts[name] == original_parts[name], 'Counterfactual changed original content: ' + name)
        table = ET.fromstring(parts['word/fontTable.xml'])
        definitions = table.findall('w:font', NS)
        require(len(definitions) == 1 and definitions[0].get('{' + W + '}name') == 'Wingdings' and definitions[0].find('w:charset', NS).get('{' + W + '}val') == value, 'Counterfactual charset operand differs')
        verify_render('font-metadata-counterfactuals-v2/render-' + value, case['render'])
        require(case['againstOriginalSource'] == compare(symbol['renders']['source'], case['render']) and case['againstCurrentParser'] == compare(symbol['renders']['after-render'], case['render']), 'Counterfactual comparison differs')
    control = read('font-charset-counterexample.json')
    inputs = []
    for item in control['inputs']:
        require(sha(data[item['path']]) == item['sha256'], 'Font oracle input binding differs')
        inputs.append(data[item['path']])
    require(control['baselineOracleSchema'] == 5 and control['currentOracleSchema'] == 6, 'Font oracle version differs')
    old_differences = oracle5.compare_semantics(*(oracle5.snapshot(io.BytesIO(value)) for value in inputs))
    new_differences = oracle6.compare_semantics(*(oracle6.snapshot(io.BytesIO(value)) for value in inputs))
    require(old_differences == control['baselineDifferences'] == [] and new_differences == control['currentDifferences'] and [item['property'] for item in new_differences] == ['fontCharsets'], 'Font false-green discrimination differs')

    require(len(final['cases']) == 3, 'Final output-equivalence cohort differs')
    for case in final['cases']:
        require(sha(data[case['source']]) == case['sourceSha256'] and sha(data[case['output']]) == case['sha256'], 'Final output binding differs')
        require(case['bytesIdentical'] is True and data[case['output']] == data[case['alreadyRendered']] and sha(data[case['alreadyRendered']]) == case['alreadyRenderedSha256'], 'Final output is not the already-rendered package')
    combined = read('combined-source-equivalence/equivalence.json')
    projection = read('combined-source-equivalence/matrix-source-projection.json')
    require(combined['combinedSourceCommit'] == projection['repository']['commit'] == COMBINED and combined['previousSourceCommit'] == FINAL, 'Combined source identity differs')
    require(combined['combinedSourceTree'] == projection['repository']['tree'] == '8b826eb2239438565faefa718bd42da61107d95e' and projection['repository']['workingTreeStatus'] == '', 'Combined source tree differs')
    require(sha(data['combined-source-equivalence/matrix-source-projection.json']) == combined['sourceProjectionSha256'], 'Combined source projection binding differs')
    require(projection['sourceBefore'] == projection['sourceAfterBuild'], 'Combined build sources changed')
    files = projection['sourceBefore']['files']
    require(sha(json.dumps(files, sort_keys=True, separators=(',', ':')).encode()) == projection['sourceBefore']['sha256'], 'Combined source inventory digest differs')
    for path, digest in files.items():
        require(sha(data['combined-source-equivalence/sources/' + digest]) == digest, 'Combined retained source differs: ' + path)
    # These two generated dependency inputs are retained byte-for-byte but are
    # not tracked Git files. Every other recorded source must match the commit.
    verify_git_files(repository, COMBINED, {p: h for p, h in files.items()
                                          if p not in ('.dart_tool/package_config.json', 'pubspec.lock')})
    require(combined['combinedParserSha256'] == projection['parserIdentity']['sha256'], 'Combined executable binding differs')
    require(sha(data['combined-source-equivalence/source.doc']) == combined['sourceSha256'] == CONTROL_SHA == projection['case']['source']['sha256'], 'Combined original source differs')
    value = data['combined-source-equivalence/parser.docx']
    require(sha(value) == combined['combinedOutputSha256'] == projection['parserNode']['sha256'] and len(value) == combined['combinedOutputBytes'] == projection['parserNode']['bytes'] == 5687, 'Combined output binding differs')
    require(combined['bytesIdentical'] is True and value == data[combined['alreadyRendered']] and sha(value) == combined['alreadyRenderedSha256'], 'Combined output is not the already-rendered package')
    require(projection['parserNode']['id'] == 'parser-docx' and projection['parserNode']['from'] == 'source' and projection['parserNode']['status'] == 'success' and projection['parserNode']['format'] == 'docx', 'Combined parser path differs')
    for prefix in ('compile', 'parser'):
        command = read('combined-source-equivalence/' + prefix + '-command.json')
        require(command['status'] == 'success' and command['returncode'] == 0 and command['timedOut'] is False, 'Combined command did not complete')
        for stream in ('stdout', 'stderr'):
            value = data['combined-source-equivalence/' + prefix + '-' + stream]
            require(len(value) == command[stream]['bytes'] and sha(value) == command[stream]['sha256'], 'Combined command stream binding differs')
        if prefix == 'compile':
            require(command == projection['compileCommand'] and command['argv'][0:5] == [DART, 'compile', 'exe', 'tool/fidelity/convert.dart', '-o'], 'Combined compiler command differs')
        else:
            require(len(command['argv']) == 3 and command['argv'][1].endswith('/06-symbol-source-control/source/symbol-source-control.doc') and command['argv'][2] == projection['parserNode']['path'], 'Combined parser command differs')
    failure = read('font-guard-failure/report.json')
    require(failure['exitCode'] == 255 and failure['outputExists'] is False and failure['executableSha256'] == font_build['executableSha256'], 'Original font guard failure differs')
    require(sha(data['font-guard-failure/formatting.doc']) == failure['sourceSha256'] and b'Invalid Word font definition' in data['font-guard-failure/stderr.txt'], 'Font guard counterexample differs')
    require(sha(data['font-guard-failure/stdout.txt']) == failure['stdoutSha256'] and sha(data['font-guard-failure/stderr.txt']) == failure['stderrSha256'], 'Original guard streams differ')
    commands = {command['label']: command for command in final_run['commands']}
    require(set(commands) == {'targeted-tests', 'analyze', 'vm', 'full-web', 'schema-generate', 'schema-validate'} and all(c['exitCode'] == 0 for c in commands.values()), 'Final command acceptance differs')
    require(all(command['cwd'] == WORKTREE for command in commands.values()), 'Final command cwd differs')
    require(commands['targeted-tests']['argv'] == [DART, 'test', 'test/legacy_word_font_charset_test.dart', 'test/legacy_word_symbol_test.dart', 'test/legacy_word_script_fonts_test.dart', '--reporter', 'expanded'] and '+28: All tests passed!' in commands['targeted-tests']['stdout'], 'Targeted test identity differs')
    require(commands['full-web']['argv'] == ['python3', 'tool/verify_web.py', '--dart', DART], 'Full web command identity differs')
    require(commands['analyze']['argv'] == [DART, 'analyze'] and commands['vm']['argv'] == [DART, 'run', 'tool/font_charset_web_acceptance.dart'], 'Dart check command identity differs')
    require(commands['schema-generate']['argv'] == [DART, 'run', 'tool/fidelity/font_charset_schema_fixture.dart', PROBES + '/font-schema-followup'], 'Schema generator command differs')
    for cohort in ('Legacy DOC', 'Media', 'Ink', 'Ink header', 'Symbol', 'Font charset'):
        require(cohort + ' JavaScript acceptance passed:' in commands['full-web']['stdout'], 'Missing actual full-web cohort: ' + cohort)
    require('"cases":8,"checks":40,"puaRemapped":false' in commands['full-web']['stdout'], 'Final font JavaScript result differs')
    schema_cases = {
        'symbol-schema': ['deleted', 'plain'],
        'font-schema': ['conflict', 'default-symbol-alias', 'default', 'symbol', 'unknown'],
        'font-schema-followup': ['conflict', 'default-symbol-alias', 'default', 'empty-name', 'symbol', 'unknown'],
    }
    schema_outputs = 0
    for directory, cases in schema_cases.items():
        result = read(directory + '-validation.json')
        require(result['Files'] == len(cases) and result['Failures'] == 0 and len(result['Reports']) == len(cases), 'Schema validation totals differ')
        rows = {Path(item['File']).stem: item for item in result['Reports']}
        require(set(rows) == set(cases), 'Schema validation cohort differs')
        for name in cases:
            path = directory + '/' + name + '.docx'
            require(rows[name]['Errors'] == [] and rows[name]['Sha256'] == sha(data[path]) and rows[name]['File'].endswith('/' + path), 'Actual schema output binding differs')
            schema_outputs += 1
            if directory.startswith('font-schema'):
                parts = package_parts(data[path])
                if name in ('conflict', 'unknown', 'empty-name'):
                    require('word/fontTable.xml' not in parts, 'Guarded schema source emitted active font metadata')
                else:
                    tree = ET.fromstring(parts['word/fontTable.xml'])
                    charsets = [node.get('{' + W + '}val') for node in tree.iter('{' + W + '}charset')]
                    require(charsets == ['01' if name == 'default' else '02'], 'Schema font charset operand differs')
    return {'archivedFiles': len(data), 'rawRasters': raster_count, 'historicalSchema5Snapshots': snapshots,
            'originalFalseGreenControls': 4, 'fontFalseGreenControls': 1,
            'nativeSymbolCycles': 2, 'nativeFontCycles': 2, 'finalEquivalentPackages': 3,
            'schemaOutputsAcrossRetainedStages': schema_outputs,
            'combinedEquivalentPackages': 1, 'combinedRetainedSourceInputs': len(files),
            'finalTrackedTestInputs': len(final_run['sourceFiles'])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', type=Path, default=Path(__file__).resolve().parents[3])
    args = parser.parse_args()
    directory = Path(__file__).resolve().parent
    data, manifest = read_bundle(directory)
    result = verify_data(data, args.repository.resolve())
    print(json.dumps({'verified': True, **result}, sort_keys=True))


if __name__ == '__main__':
    main()
