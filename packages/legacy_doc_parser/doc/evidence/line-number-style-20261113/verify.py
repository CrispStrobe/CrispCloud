#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Verify exact retained bytes and the bounded Line Number style claims."""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import subprocess
import tarfile
import xml.etree.ElementTree as ET
import zipfile

from audit import audit_control, raw_styles, require


HERE = Path(__file__).resolve().parent
COMMIT = 'a1784cde69397e70fa6e8d6dd4dfe9c96e03f08a'
TREE = 'f19662675e270f377d6356138ca064a71ab91283'
ARCHIVE = 'artifacts.tar.xz'
MANIFEST = 'artifacts.manifest.json'
W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
SCHEMA_STAGES = ('git-head', 'git-status', 'dart-version', 'dotnet-sdks', 'compiler-version',
                 'dotnet-runtimes', 'validator-build', 'validator-self-test', 'positive-control',
                 'negative-controls', 'generate-corpus', 'repeat-corpus', 'schema-validation')
SDK_BINARIES = {'DocumentFormat.OpenXml.Framework.dll', 'DocumentFormat.OpenXml.dll',
                'OfficeValidation.dll', 'System.IO.Packaging.dll'}
RECORDED_ROOT = '/workspace/scratch/c1ca2a1344e9'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def subtree(files, prefix):
    return {name[len(prefix):]: sha(data) for name, data in files.items() if name.startswith(prefix)}


def get_json(files, name):
    return json.loads(files[name])


def safe_path(name):
    path = PurePosixPath(name)
    require(not path.is_absolute() and '..' not in path.parts and str(path) == name and
            name not in ('', '.'), 'Unsafe artifact path: ' + name)


def package(data):
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        require(len(set(z.namelist())) == len(z.namelist()), 'Duplicate package part')
        return {name: z.read(name) for name in z.namelist()}


def line_style(data, expected=True):
    styles = ET.fromstring(package(data)['word/styles.xml'])
    matches = [e for e in styles.findall(W + 'style') if e.get(W + 'styleId') == 'LineNumber']
    require(len(matches) == int(expected), 'Line Number style presence')
    if not expected:
        return
    style = matches[0]
    require(style.get(W + 'type') == 'character' and
            style.find(W + 'name').get(W + 'val') == 'line number', 'Line style identity')
    props = style.find(W + 'rPr')
    require(props.find(W + 'rFonts').get(W + 'ascii') == 'Courier New' and
            props.find(W + 'rFonts').get(W + 'hAnsi') == 'Courier New' and
            props.find(W + 'sz').get(W + 'val') == '28' and
            props.find(W + 'color').get(W + 'val') == 'CC2233' and
            props.find(W + 'b').get(W + 'val', '1') in ('1', 'true'),
            'Explicit Line Number source formatting')


def sdk_report(files, schema, key, filename, expected, failures):
    summary = schema[key]
    require(summary['hashesVerified'] and summary['inputsUnchanged'] and
            summary['files'] == len(expected) and summary['errors'] == failures and
            summary['report'] == filename and summary['reportSha256'] == sha(files['schema/' + filename]),
            'SDK summary/log binding: ' + key)
    raw = get_json(files, 'schema/' + filename)
    require(raw['Files'] == len(raw['Reports']) == len(expected) and raw['Failures'] == failures,
            'SDK file/error counts')
    seen = set()
    for report in raw['Reports']:
        name = report['File']
        require(name in expected and name not in seen, 'Unexpected SDK input')
        seen.add(name)
        require(report['Sha256'] == sha(files[expected[name]]) and 'Exception' not in report,
                'SDK output byte binding')
        if failures:
            error_id = {'invalid-child.docx': 'Sch_InvalidElementContentExpectingComplex',
                        'invalid-nowrap.docx': 'Sch_AttributeValueDataTypeDetailed'}[PurePosixPath(name).name]
            require(len(report['Errors']) == 1 and report['Errors'][0]['Id'] == error_id,
                    'Expected negative SDK error')
        else:
            require(report['Errors'] == [], 'SDK validation error')
    require(seen == set(expected), 'SDK coverage')


def render_binding(files, name, directory, document):
    render = get_json(files, name)
    rasters = get_json(files, directory + '/raster-manifest.json')
    require(rasters['status'] == 'complete' and rasters['storage'] == 'gzip' and
            rasters['rasterDpi'] == render['rasterDpi'] == 72 and
            rasters['rasterColorSpace'] == render['rasterColorSpace'] == 'RGB' and
            rasters['pdfSha256'] == render['pdfSha256'], 'Render settings/receipt')
    pdfs = [n for n in files if n.startswith(directory + '/') and n.endswith('.pdf')]
    require(len(pdfs) == 1 and sha(files[pdfs[0]]) == render['pdfSha256'], 'PDF bytes')
    require(files[directory + '/pages.txt'].decode() == render['text'], 'Extracted text bytes')
    require(render['rasterManifest']['path'] == 'raster-manifest.json' and
            render['rasterManifest']['sha256'] == sha(files[directory + '/raster-manifest.json']),
            'Raster manifest binding')
    require(len(rasters['pages']) == len(render['pages']) == rasters['expectedPages'] ==
            rasters['pdfPageCount'] and len(rasters['pages']) == 1, 'Control page count')
    # Independently parse the archived Poppler bbox output to bind exact word
    # coordinates to the measured render JSON, not only to its summary.
    root = ET.fromstring(files[directory + '/pages.xhtml'])
    namespace = '{http://www.w3.org/1999/xhtml}'
    actual_pages = []
    for page in root.iter(namespace + 'page'):
        actual_pages.append({'size': [float(page.get('width')), float(page.get('height'))],
                             'words': [{'text': word.text or '', 'box': [float(word.get(x)) for x in
                                        ('xMin', 'yMin', 'xMax', 'yMax')]}
                                       for word in page.iter(namespace + 'word')]})
    require(actual_pages == render['pages'], 'Poppler word/coordinate binding')
    require(render['rasterArtifacts'] == rasters['pages'] and
            render['rasterSha256'] == [p['uncompressedSha256'] for p in rasters['pages']],
            'Render raster inventory')
    for index, page in enumerate(rasters['pages'], 1):
        require(page['page'] == index and '/' not in page['path'], 'Raster page path/order')
        raw = files[directory + '/' + page['path']]
        decoded = gzip.decompress(raw)
        require(sha(raw) == page['sha256'] and len(raw) == page['sizeBytes'] and
                sha(decoded) == page['uncompressedSha256'] and len(decoded) == page['uncompressedSizeBytes'],
                'Lossless raster bytes')
    require(document in files, 'Missing rendered document')
    return render


def same_render(left, right):
    return (left['pages'] == right['pages'] and left['text'] == right['text'] and
            left['rasterSha256'] == right['rasterSha256'])


def verify_payloads(manifest, files):
    require(manifest['version'] == 1 and manifest['runtimeCommit'] == COMMIT and
            manifest['runtimeTree'] == TREE, 'Runtime identity')
    report = get_json(files, 'native/report.json')
    schema = get_json(files, 'schema/report.json')
    require(report['status'] == 'passed' and report['parserCommit'] == schema['gitHead'] == COMMIT and
            report['runtimeTree'] == TREE and report['parserWorktreeDirty'] is False and
            schema['gitWorktreeDirty'] is False, 'Clean committed source binding')
    require(report['wrapperSha256'] == sha(files['probes/runtime_acceptance.py']), 'Native wrapper hash')
    before = report['sourcesBefore']
    require(before == report['sourcesAfterCompilation'] == report['sourcesAfter'] and
            sha(json.dumps(before['files'], sort_keys=True, separators=(',', ':')).encode()) == before['sha256'],
            'Native source receipts differ')
    require(len(before['files']) == 138, 'Native source inventory')
    require(schema['source'] == schema['sourceAfter'] and len(schema['source']['files']) == 166,
            'Schema source receipts differ')
    require(sha(json.dumps(schema['source']['files'], sort_keys=True, separators=(',', ':')).encode()) ==
            schema['source']['aggregateSha256'], 'Schema source aggregate')
    expected_source = dict(before['files'])
    for name, digest in schema['source']['files'].items():
        require(name not in expected_source or expected_source[name] == digest, 'Cross-gate source difference')
        expected_source[name] = digest
    require(subtree(files, 'source/') == expected_source, 'Retained source files')

    # All recorded native shell commands are bound to stdout/stderr and exits.
    commands = ('git-head', 'git-status', 'git-tree', 'fonts', 'compile', 'focused-tests')
    require({PurePosixPath(name).name for name in files if name.startswith('native/') and
             name.endswith('.command.json')} == {name + '.command.json' for name in commands},
            'Native command inventory')
    for name in commands:
        command = get_json(files, 'native/' + name + '.command.json')
        require(command['exitCode'] == 0 and command['argv'] and
                command['stdoutSha256'] == sha(files['native/' + name + '.stdout.log']) and
                command['stderrSha256'] == sha(files['native/' + name + '.stderr.log']), 'Native command binding')
    expected_commands = {
        'git-head': ['git', 'rev-parse', 'HEAD'],
        'git-status': ['git', 'status', '--porcelain'],
        'git-tree': ['git', 'rev-parse', 'HEAD^{tree}'],
        'fonts': ['fc-list', '--format', '%{family}|%{style}|%{file}\n'],
        'focused-tests': [report['tools']['dart']['path'], 'test',
                          'test/legacy_word_line_number_style_test.dart',
                          'test/legacy_word_native_section_direction_test.dart',
                          'test/legacy_word_script_fonts_test.dart', '--reporter=expanded'],
    }
    compile_command = get_json(files, 'native/compile.command.json')
    require(len(compile_command['argv']) == 6 and compile_command['argv'][:5] ==
            [report['tools']['dart']['path'], 'compile', 'exe', 'tool/fidelity/convert.dart', '-o'],
            'Native compiler command')
    for name, argv in expected_commands.items():
        command = get_json(files, 'native/' + name + '.command.json')
        require(command['argv'] == argv and command['cwd'] == compile_command['cwd'],
                'Native exact command/cwd: ' + name)
    require(files['native/git-head.stdout.log'].decode().strip() == COMMIT and
            files['native/git-tree.stdout.log'].decode().strip() == TREE and
            files['native/git-status.stdout.log'] == b'', 'Native Git logs')
    require('+20: All tests passed!' in files['native/focused-tests.stdout.log'].decode(), 'Focused test result')
    require(report['tools']['dart']['sha256'] == schema['dart']['executableSha256'] and
            report['tools']['dart']['version'] == schema['dart']['version'], 'Dart identity across gates')
    fonts = files['native/fonts.stdout.log'].decode().splitlines()
    font_files = get_json(files, 'native/font-files.json')
    require(sha('\n'.join(sorted(fonts)).encode()) == report['fontInventorySha256'] and
            set(font_files) == {line.rsplit('|', 1)[-1] for line in fonts} and
            sha(json.dumps(font_files, sort_keys=True, separators=(',', ':')).encode()) ==
            report['fontFilesSha256'], 'Font inventory receipts')

    # Raw source identity and explicit style properties are checked without the
    # Dart parser and without using a native DOCX as the source of truth.
    source_doc = files['source/test/fixtures/word_native/line-number-style.doc']
    require(audit_control(source_doc) == get_json(files, 'source-audit.json'), 'Raw source audit')
    case = report['case']
    prefix = 'native/line-number-style/'
    require(case == get_json(files, prefix + 'result.json') and case['status'] == 'measured' and
            case['sourceFormat'] == 'doc' and case['sourceSha256'] == sha(source_doc) == case['binaryDocSha256'] and
            case['sourceUnchanged'] and case['binaryDocUnchanged'] and
            files[prefix + 'source.doc'] == source_doc and case['roundtripCyclesRequested'] == 3 and
            [cycle['index'] for cycle in case['roundtripCycles']] == [1, 2, 3], 'Native case/source identity')
    initial_stages = ['source-receipt', 'copy-binary-source', 'binary-render', 'native-docx',
                      'native-semantics', 'parser-import', 'converted-semantics', 'converted-render', 'native-render']
    expected_stages = initial_stages + [f'roundtrip-{index:02d}-' + name for index in (1, 2, 3)
                                      for name in ('bridge', 'native-docx', 'native-semantics', 'parser-import',
                                                   'converted-semantics', 'binary-render', 'converted-render')]
    require([stage['name'] for stage in case['stages']] == expected_stages and
            all(stage['status'] == 'complete' for stage in case['stages']), 'Incomplete native stage')
    require(case['convertedSha256'] == sha(files[prefix + 'converted.docx']), 'Parser output bytes')
    line_style(files[prefix + 'converted.docx'])
    render_values = {}
    require(set(case['renders']) == {'binary', 'converted', 'native',
            *(f'roundtrip-{index:02d}-' + suffix for index in (1, 2, 3) for suffix in ('binary', 'converted'))},
            'Native render inventory')
    for name, receipt in case['renders'].items():
        require(receipt['path'] == name + '-render.json' and
                receipt['sha256'] == sha(files[prefix + receipt['path']]), 'Native render receipt')
        document = {
            'binary': prefix + 'source.doc', 'converted': prefix + 'converted.docx',
            'native': prefix + 'native-docx/source.docx',
        }.get(name)
        if name.startswith('roundtrip-'):
            stem = name[:12]
            cycle = int(stem[-2:])
            document = (prefix + stem + '/import.docx' if name.endswith('-converted') else
                        prefix + stem + '/binary/' + ('converted.doc' if cycle == 1 else 'import.doc'))
        require(document is not None and receipt['documentSha256'] == sha(files[document]),
                'Rendered input document hash')
        render_values[name] = render_binding(files, prefix + receipt['path'], prefix + 'render-' + name, document)
    # The original independently authored source is also retained among probes;
    # the fixture provenance binds it to the compiled runtime's tracked DOC.
    original_data = files['diagnostic/line-style-control/line-style.docx']
    provenance = get_json(files, 'control-source/line-number-style.provenance.json')
    require(report['originalDocxSha256'] == provenance['sourceDocxSha256'] == sha(original_data) and
            original_data == files['control-source/line-number-style.docx'] and
            provenance['nativeDocSha256'] == sha(source_doc), 'Original DOCX identity')
    original = render_binding(files, 'native/original-render.json', 'native/original-render',
                              'diagnostic/line-style-control/line-style.docx')
    require(same_render(original, render_values['binary']) and report['originalToRetainedBinary']['exactOnThisRenderer'],
            'Original/native bridge equality')
    require(all(same_render(render_values['binary'], actual) for actual in render_values.values()) and
            report['renderExact'] and case['pagination']['exactOnThisRenderer'] and
            case['pagination']['maximumWordDriftPoints'] == 0.0 and
            case['nativeConversionPagination']['exactOnThisRenderer'], 'Native render equality')
    previous = files[prefix + 'converted.docx']
    for cycle in case['roundtripCycles']:
        stem = f"roundtrip-{cycle['index']:02d}"
        current = files[prefix + stem + '/import.docx']
        binary_path = prefix + stem + '/binary/' + ('converted.doc' if cycle['index'] == 1 else 'import.doc')
        require(cycle['status'] == 'measured' and cycle['inputUnchanged'] and cycle['binaryDocUnchanged'] and
                cycle['inputSha256'] == sha(previous) and cycle['binaryDocSha256'] == sha(files[binary_path]) and
                cycle['convertedSha256'] == sha(current), 'Repeated source/byte identity')
        line_style(current)
        require(all(cycle[key]['exactOnThisRenderer'] and cycle[key]['maximumWordDriftPoints'] == 0.0 for key in
                    ('paginationFromBinaryDoc', 'paginationFromPreviousImport', 'paginationFromFirstImport')),
                'Repeated comparison summaries')
        previous = current

    # Explicitly retain the discriminating failing control and output-only
    # restoration. Only styles.xml may differ; the rest of the package is exact.
    base = 'diagnostic/line-style-control/'
    require(files[base + 'binary/line-style.doc'] == source_doc, 'Baseline binary differs')
    baseline = package(files[base + 'converted.docx'])
    restored = package(files[base + 'restored-line-style.docx'])
    require(set(baseline) == set(restored) and [n for n in baseline if baseline[n] != restored[n]] ==
            ['word/styles.xml'], 'Counterfactual changed another package part')
    line_style(files[base + 'converted.docx'], expected=False)
    line_style(files[base + 'restored-line-style.docx'])
    base_tree = ET.fromstring(baseline['word/styles.xml'])
    restored_tree = ET.fromstring(restored['word/styles.xml'])
    restored_tree.remove(next(e for e in restored_tree if e.get(W + 'styleId') == 'LineNumber'))
    require(ET.tostring(base_tree) == ET.tostring(restored_tree), 'Counterfactual changed existing styles')
    baseline_render = get_json(files, base + 'converted-render.json')
    restored_render = get_json(files, base + 'restored-line-style-render.json')
    require(not same_render(render_values['binary'], baseline_render) and
            same_render(render_values['binary'], restored_render) and
            get_json(files, base + 'comparison.json')['exactOnThisRenderer'] is False and
            get_json(files, base + 'restored-line-style-comparison.json')['exactOnThisRenderer'] is True,
            'Discriminating baseline/counterfactual rendering')
    require([item['case'] for item in report['unchangedCases']] == ['word', 'word-compatibility', 'bookmarks'],
            'Old-case inventory')
    for item in report['unchangedCases']:
        path = 'native/unchanged/' + item['case'] + '/'
        source = files[path + 'source.doc']
        require(item['unchanged'] and item['sourceSha256'] == sha(source) and
                item['baselineSha256'] == item['currentSha256'] == sha(files[path + 'baseline.docx']) and
                files[path + 'baseline.docx'] == files[path + 'current.docx'], 'Changed old output')
        require(not any(style['builtinId'] == 40 for style in raw_styles(source)['styles']),
                'An old source has an unhandled explicit style')
        if item['case'] == 'bookmarks':
            require(raw_styles(source)['copts60'] == '0000', 'Bookmark source width-balance flag')

    # Full independent SDK gate, including both complete generated corpora.
    require(schema['passed'] and schema['selfTestPassed'] and
            tuple(s['name'] for s in schema['stages']) == SCHEMA_STAGES, 'SDK gate/stage inventory')
    # These are the commands of this immutable captured run. Bind actual argv
    # as well as names/exits/logs; a retained success log must not certify an
    # unrelated executable or generation/validation target.
    gate = RECORDED_ROOT + '/layout-next-probes/schema-a1784cde'
    dotnet = RECORDED_ROOT + '/toolchains/dotnet-8.0.428/dotnet'
    compiler = RECORDED_ROOT + '/toolchains/dotnet-8.0.428/sdk/8.0.428/Roslyn/bincore/csc.dll'
    validator = gate + '/validator/OfficeValidation.dll'
    dart = report['tools']['dart']['path']
    sdk_commands = {
        'git-head': ['git', 'rev-parse', 'HEAD'],
        'git-status': ['git', 'status', '--porcelain'],
        'dart-version': [dart, '--version'],
        'dotnet-sdks': [dotnet, '--list-sdks'],
        'compiler-version': [dotnet, 'exec', compiler, '-version'],
        'dotnet-runtimes': [dotnet, '--list-runtimes'],
        'validator-build': [dotnet, 'exec', compiler, '-noconfig', '@' + gate + '/compile.rsp'],
        'validator-self-test': [dotnet, validator, '--self-test'],
        'positive-control': [dotnet, validator, gate + '/controls/positive', gate + '/positive-control.json'],
        'negative-controls': [dotnet, validator, gate + '/controls/negative', gate + '/negative-controls.json'],
        'generate-corpus': [dart, 'run', 'tool/fidelity/schema_corpus.dart', gate + '/corpus'],
        'repeat-corpus': [dart, 'run', 'tool/fidelity/schema_corpus.dart', gate + '/corpus-repeat'],
        'schema-validation': [dotnet, validator, gate + '/corpus', gate + '/schema-validation.json'],
    }
    for stage in schema['stages']:
        require(stage['status'] == 'completed' and stage['returncode'] ==
                (1 if stage['name'] == 'negative-controls' else 0) and
                stage['log'] == stage['name'] + '.log' and
                stage['logSha256'] == sha(files['schema/' + stage['log']]), 'SDK command/log binding')
        require(stage['command'] == sdk_commands[stage['name']], 'SDK exact command: ' + stage['name'])
    require(files['schema/git-head.log'].decode().strip() == COMMIT and files['schema/git-status.log'] == b'',
            'SDK Git receipt')
    require(b'Open XML SDK controls passed: 8 valid Word packages, 4 invalid XML, 12 mismatched types, and exact discovery.'
            in files['schema/validator-self-test.log'], 'Independent SDK controls')
    deterministic = schema['determinism']
    require(deterministic['passed'] and deterministic['cases'] == 230 and deterministic['files'] == 488,
            'Schema corpus counts')
    hashes = deterministic['sha256ByRelativePath']
    require(len(hashes) == 488 and subtree(files, 'schema/corpus/') == hashes ==
            subtree(files, 'schema/corpus-repeat/'), 'Both full generated corpora')
    cases = schema['corpus']['cases']
    require(len(cases) == len({case['name'] for case in cases}) == 230 and
            sum(case['name'] == 'native-inputs/line-number-style' for case in cases) == 1, 'Required case inventory')
    require({case['output']: case['outputSha256'] for case in cases} ==
            {name: digest for name, digest in hashes.items() if name.endswith('.docx')}, 'Corpus output inventory')
    for case in cases:
        require(hashes[case['source']] == case['sourceSha256'] and case['producer'] in expected_source,
                'Corpus source/producer binding')
        if case['producer'].endswith('.doc'):
            require(expected_source[case['producer']] == case['sourceSha256'], 'Native source copy')
    corpus_root = next(s for s in schema['stages'] if s['name'] == 'generate-corpus')['command'][-1]
    expected = {corpus_root + '/' + case['output']: 'schema/corpus/' + case['output'] for case in cases}
    require(schema['corpus']['outputs'] == {name: sha(files[path]) for name, path in expected.items()},
            'Absolute SDK input inventory')
    sdk_report(files, schema, 'validation', 'schema-validation.json', expected, 0)
    original_root = corpus_root.rsplit('/', 1)[0]
    for key, filename, names, failures in [
        ('positiveControl', 'positive-control.json', ['positive/valid.docx'], 0),
        ('negativeControls', 'negative-controls.json', ['negative/invalid-child.docx', 'negative/invalid-nowrap.docx'], 2),
    ]:
        sdk_report(files, schema, key, filename,
                   {original_root + '/controls/' + n: 'schema/controls/' + n for n in names}, failures)
    build = schema['validatorBuild']
    require(build['mode'] == 'direct-sdk-compiler' and build['sdkVersion'] == '8.0.428' and
            build['frameworkVersion'] == '8.0.34' and
            sha(files['schema/compile.rsp']) == build['compilerResponseSha256'], 'Fresh SDK build identity')
    omitted = {item['path']: item for item in manifest['omittedReproducibleBinaries']}
    require(len(omitted) == 5 and set(omitted) == {'native/convert', *('schema/validator/' + n for n in SDK_BINARIES)},
            'Omitted reproducible binary inventory')
    require(omitted['native/convert']['sha256'] == report['executable']['sha256'] and
            omitted['native/convert']['size'] == report['executable']['sizeBytes'], 'Compiled parser identity')
    for name, digest in build['artifacts'].items():
        path = 'schema/validator/' + name
        actual = omitted[path]['sha256'] if name in SDK_BINARIES else sha(files[path])
        require(actual == digest, 'SDK build artifact identity')
    upstream = get_json(files, 'source/tool/office-validation/upstream.json')
    require(upstream == build['upstream'] and upstream['sdkPackage'] ==
            {'id': 'DocumentFormat.OpenXml', 'version': '3.3.0'}, 'SDK upstream identity')
    for name, item in upstream['files'].items():
        require(sha(files['source/tool/office-validation/' + name]) == item['sha256'], 'Validator source hash')
    for kind, oid in [('commit', COMMIT), ('tree', TREE)]:
        raw = files['source-identity/git-' + kind + '.raw']
        require(hashlib.sha1((kind + ' ' + str(len(raw)) + '\0').encode() + raw).hexdigest() == oid,
                'Git object identity')
    require(files['source-identity/git-commit.raw'].splitlines()[0] == ('tree ' + TREE).encode(), 'Git tree linkage')
    return {'verified': True, 'runtimeCommit': COMMIT, 'renderExact': True, 'roundtripCycles': 3,
            'unchangedOldCases': 3, 'focusedTests': 20, 'schemaOutputs': 230,
            'deterministicFilesPerRun': 488, 'schemaErrors': 0, 'retainedFiles': len(files)}


def load(directory=HERE):
    manifest = json.loads((directory / MANIFEST).read_bytes())
    archive = (directory / ARCHIVE).read_bytes()
    require(manifest['archive']['path'] == ARCHIVE and len(archive) == manifest['archive']['size'] and
            sha(archive) == manifest['archive']['sha256'], 'Archive receipt')
    expected = {item['path']: item for item in manifest['files']}
    require(len(expected) == len(manifest['files']), 'Duplicate manifest entry')
    files = {}
    with tarfile.open(fileobj=io.BytesIO(archive), mode='r:xz') as packed:
        for member in packed:
            safe_path(member.name)
            require(member.isfile() and member.name in expected and member.name not in files, 'Archive membership')
            data = packed.extractfile(member).read()
            require(len(data) == expected[member.name]['size'] and sha(data) == expected[member.name]['sha256'],
                    'Archive entry size/hash')
            files[member.name] = data
    require(set(files) == set(expected), 'Missing archive entry')
    for name, digest in manifest['helpers'].items():
        safe_path(name)
        require(sha((directory / name).read_bytes()) == digest, 'Verifier helper hash')
    return manifest, files


def check_git(root, files):
    for name, data in files.items():
        if not name.startswith('source/'):
            continue
        relative = name[len('source/'):]
        if relative in ('pubspec.lock', '.dart_tool/package_config.json'):
            continue
        raw = subprocess.check_output(['git', '-C', str(root), 'show', COMMIT + ':' + relative])
        require(raw == data, 'Captured source differs from pinned Git commit: ' + relative)
    for relative, name in [('test/fixtures/fidelity/line-number-style.docx', 'line-number-style.docx'),
                           ('test/fixtures/word_native/line-number-style.provenance.json',
                            'line-number-style.provenance.json')]:
        raw = subprocess.check_output(['git', '-C', str(root), 'show', COMMIT + ':' + relative])
        require(raw == files['control-source/' + name], 'Control fixture differs from runtime Git tree')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-git', type=Path)
    args = parser.parse_args()
    manifest, files = load()
    result = verify_payloads(manifest, files)
    if args.check_git:
        check_git(args.check_git, files)
        result['gitSourcesVerified'] = True
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
