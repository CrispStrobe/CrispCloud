#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Verify the retained hyperlink-field source, native, SDK and JS evidence."""
import argparse
import base64
from collections import Counter
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile
import zipfile
from xml.etree import ElementTree as ET

from source_oracle import verify_source

HERE = Path(__file__).resolve().parent
BASE = '/workspace/scratch/c1ca2a1344e9'
REPO = BASE + '/parser-hyperlink-probes'
RUN = BASE + '/hyperlink-validation-20261113'
DART = BASE + '/toolchains/dart-3.13.7/dart-sdk/bin/dart'
OFFICE = '/opt/codex/runtimes/codex-primary-runtime/dependencies/bin/override/soffice'
NODE = '/opt/codex/runtimes/codex-primary-runtime/dependencies/node/bin/node'
URL_PIN = '3c8d22d2a2e2277d53547378bf66e62e951f0ccf'
REF_PIN = 'd7e7883325d454a2bf01a44810c6f8336177d7a8'
REF_TREE = '59fcbba75c55f75a809ea2e317b15f5116cafba5'
OWNER_PIN = '8eaa15bbe7dc1564692e60427294ae546d177b68'
OWNER_TREE = '11541a87f558e926c8058ffc3a55ade1bf2a05ce'
W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
R = '{http://schemas.openxmlformats.org/officeDocument/2006/relationships}'
SUITES = {
    'test/legacy_word_binary_hyperlink_test.dart': 15,
    'test/legacy_word_external_hyperlink_test.dart': 23,
    'test/legacy_word_stories_fields_test.dart': 15,
    'test/legacy_word_display_field_revisions_test.dart': 7,
    'test/legacy_word_structured_conversion_test.dart': 9,
}


def require(value, message):
    if not value:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def js(value):
    return json.loads(value)


def opc(data):
    result = {}
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        require(len(z.namelist()) == len(set(z.namelist())), 'Unique OPC members')
        for name in z.namelist():
            if not (name.startswith('word/') and name.endswith('.xml') and name.count('/') == 1):
                continue
            root = ET.fromstring(z.read(name))
            relname = 'word/_rels/' + name.split('/')[-1] + '.rels'
            rels = {r.attrib['Id']: r.attrib for r in ET.fromstring(z.read(relname))} if relname in z.namelist() else {}
            result[name] = {'instructions': [e.text or '' for e in root.iter(W + 'instrText')],
                            'links': [{'text': ''.join(e.itertext()), 'anchor': e.get(W + 'anchor'),
                                       'relationship': rels.get(e.get(R + 'id'))} for e in root.iter(W + 'hyperlink')],
                            'text': ''.join(e.text or '' for e in root.iter(W + 't'))}
    return result


def elements(data, part, name):
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        return list(ET.fromstring(z.read(part)).iter(W + name))


def complex_fields(owner):
    result, current = [], None
    for element in owner.iter():
        if element.tag == W + 'fldChar':
            kind = element.get(W + 'fldCharType')
            if kind == 'begin':
                require(current is None, 'Flat fixture field ownership')
                current = {'instruction': '', 'storedResult': '', 'separated': False}
            elif kind == 'separate':
                require(current is not None and not current['separated'], 'Owner field separator')
                current['separated'] = True
            elif kind == 'end':
                require(current is not None and current.pop('separated'), 'Complete owner field')
                result.append(current)
                current = None
        elif current is not None and element.tag == W + 'instrText':
            require(not current['separated'], 'Owner instruction precedes cached text')
            current['instruction'] += element.text or ''
        elif current is not None and current['separated'] and element.tag == W + 't':
            current['storedResult'] += element.text or ''
    require(current is None, 'No unterminated owner field')
    return result


def external_owners(data):
    with zipfile.ZipFile(io.BytesIO(data)) as package:
        body = ET.fromstring(package.read('word/document.xml'))
        notes = list(body.iter(W + 'footnoteReference'))
        require(len(notes) == 1, 'Unique source footnote reference')
        note_id = notes[0].get(W + 'id')
        notes = [n for n in ET.fromstring(package.read('word/footnotes.xml')) if n.get(W + 'id') == note_id]
        require(len(notes) == 1, 'Exact referenced footnote owner')
        owners = {'main': ('word/document.xml', body), 'footnote-1': ('word/footnotes.xml', notes[0])}
        rels = {r.get('Id'): r for r in ET.fromstring(package.read('word/_rels/document.xml.rels'))}
        for kind, story in [('default', 'header-0-normal'), ('first', 'header-0-first')]:
            refs = [r for r in body.iter(W + 'headerReference') if r.get(W + 'type') == kind]
            require(len(refs) == 1, 'Unique ' + kind + ' header reference')
            target = rels[refs[0].get(R + 'id')].get('Target')
            require(target is not None and not target.startswith('/') and '..' not in target.split('/'), 'Local header target')
            name = 'word/' + target
            owners[story] = (name, ET.fromstring(package.read(name)))
        result = {}
        for story, (name, node) in owners.items():
            relname = 'word/_rels/' + name.split('/')[-1] + '.rels'
            relationships = {r.get('Id'): r for r in ET.fromstring(package.read(relname))} if relname in package.namelist() else {}
            links = []
            for link in node.iter(W + 'hyperlink'):
                rel = relationships.get(link.get(R + 'id'))
                links.append({'storedResult': ''.join(t.text or '' for t in link.iter(W + 't')),
                              'target': None if rel is None else rel.get('Target')})
            result[story] = {'fields': complex_fields(node), 'links': links}
        return result


def nodes(value, kind):
    if isinstance(value, dict):
        return int(value.get('t') == kind) + sum(nodes(v, kind) for v in value.values())
    if isinstance(value, list):
        return sum(nodes(v, kind) for v in value)
    return 0


def ast_links(value, owner='body'):
    def inline_text(node):
        if isinstance(node, list):
            return ''.join(inline_text(x) for x in node)
        if isinstance(node, dict):
            if node.get('t') == 'Str':
                return node['c']
            if node.get('t') in ('Space', 'SoftBreak', 'LineBreak'):
                return ' '
            return inline_text(node.get('c', []))
        return ''
    if isinstance(value, dict):
        if value.get('t') == 'Note':
            return ast_links(value['c'], 'note')
        own = []
        if value.get('t') == 'Link':
            own.append((owner, inline_text(value['c'][1]), value['c'][2][0]))
        return own + [link for child in value.values() for link in ast_links(child, owner)]
    if isinstance(value, list):
        return [link for child in value for link in ast_links(child, owner)]
    return []


def test_events(data, reference):
    events = [js(line) for line in data.splitlines()]
    expected = dict(SUITES)
    if reference:
        expected['test/legacy_word_reference_hyperlink_test.dart'] = 20
    suites, starts, done = {}, {}, {}
    for e in events:
        if e['type'] == 'suite':
            s = e['suite']
            require(s['id'] not in suites and s['platform'] == 'vm', 'Unique VM suite')
            suites[s['id']] = s['path']
        elif e['type'] == 'testStart':
            t = e['test']
            require(t['id'] not in starts and t['suiteID'] in suites, 'Unique test in declared suite')
            starts[t['id']] = t
        elif e['type'] == 'testDone':
            require(e['testID'] in starts and e['testID'] not in done, 'Unique test completion')
            require(e['result'] == 'success' and e['skipped'] is False, 'Actual successful test')
            done[e['testID']] = e
        elif e['type'] == 'error':
            raise ValueError('No hidden test errors')
    require(set(suites.values()) == set(expected) and len(suites) == len(expected), 'Exact test suites')
    require(set(starts) == set(done), 'All started tests completed')
    finals = [e for e in events if e['type'] == 'done']
    require(len(finals) == 1 and finals[0]['success'] is True, 'Final test success')
    counts = Counter()
    for id_, event in done.items():
        if not event['hidden']:
            test = starts[id_]
            path = suites[test['suiteID']]
            require(test['url'] == 'file://' + REPO + '/' + path, 'Visible test source association')
            counts[path] += 1
    require(dict(counts) == expected, 'Exact per-suite visible success counts')
    return sum(counts.values())


def command(files, prefix, stage, argv, inputs=()):
    r = js(files[prefix + '/' + stage + '.json'])
    require(r['argv'] == argv and r['cwd'] == REPO and r['exitCode'] == 0, 'Exact command ' + prefix + '/' + stage)
    require(r['stdoutSha256'] == sha(files[prefix + '/' + stage + '.stdout']) and
            r['stderrSha256'] == sha(files[prefix + '/' + stage + '.stderr']), 'Command log binding')
    if inputs or 'inputsBefore' in r or 'inputsAfter' in r:
        require('inputsBefore' in r and 'inputsAfter' in r, 'Required exact command input receipts')
        expected = {RUN + '/' + name: sha(files[name]) for name in inputs}
        require(r['inputsBefore'] == r['inputsAfter'] == expected, 'Unchanged exact command inputs')


def verify_payloads(files, repository=None):
    identities = js(files['runtime-identities.json'])
    require(identities['externalCommit'] == URL_PIN and identities['referenceCommit'] == REF_PIN and
            identities['referenceTree'] == REF_TREE, 'Published runtime identities')
    for group, expected_hash in [('external', '2d2943d799d3a48430a90bff0bee68d7ab30fc2e5c26666d793160439e1f483d'),
                                 ('reference-final', '20b4e506f40b733cd7d9467ec2e6f2844e0efe319a61e8c4822e371facee0292')]:
        require(sha(files[group + '/source.doc']) == expected_hash, 'Exact original native source')
    for group, name, ref in [('external', 'external', False), ('reference-final', 'reference', True)]:
        decoded = verify_source(files[group + '/source.doc'], js(files['inspections/' + name + '.json']), reference=ref)
        require(decoded == js(files['independent-' + name + '-source.json']), 'Independent raw source result')
    require(js(files['reference-final/checkout.json']) == {'commit': REF_PIN, 'tree': REF_TREE, 'status': ''}, 'Clean frozen reference source')
    require(files['reference-final/runtime.patch'] == b'', 'No uncommitted frozen runtime patch')
    test_counts = {}
    for group in ['external', 'reference', 'reference-final']:
        ref = group != 'external'
        source_map = js(files[group + '/runtime-sources.json'])
        fixture = 'reference-hyperlink-native.doc' if ref else 'external-hyperlinks-native.doc'
        expected_sources = {
            'lib/src/word_field_binary_metadata.dart', 'lib/src/word_story_writer.dart',
            'test/legacy_word_binary_hyperlink_test.dart', 'test/legacy_word_external_hyperlink_test.dart',
            'test/fixtures/word_native/' + fixture,
        }
        if ref:
            expected_sources.add('test/legacy_word_reference_hyperlink_test.dart')
        if group == 'reference-final':
            expected_sources.add('tool/field_metadata_web_acceptance.dart')
        require(set(source_map) == expected_sources, 'Exact measured source inventory')
        for path, digest in source_map.items():
            source = files['runtime-snapshots/' + group + '/' + path]
            require(sha(source) == digest, 'Measured runtime source ' + path)
            if repository:
                pin = REF_PIN if ref else URL_PIN
                committed = subprocess.check_output(['git', 'show', pin + ':' + path], cwd=repository)
                if group == 'reference' and path == 'lib/src/word_field_binary_metadata.dart':
                    committed = committed.replace(b'// field instruction and its actual CFData/CPicLocation artifact.',
                                                  b'// HYPERLINK instruction and its actual CFData/CPicLocation artifact.')
                require(source == committed, 'Source matches exact published Git content')
        target = 'reference' if ref else 'external'
        commands = {
            'analyze': [DART, 'analyze', 'lib', 'test/legacy_word_' + target + '_hyperlink_test.dart'],
            'tests': [DART, 'test', '--reporter=json', 'test/legacy_word_binary_hyperlink_test.dart',
                      *(['test/legacy_word_reference_hyperlink_test.dart'] if ref else []),
                      'test/legacy_word_external_hyperlink_test.dart', 'test/legacy_word_stories_fields_test.dart',
                      'test/legacy_word_display_field_revisions_test.dart', 'test/legacy_word_structured_conversion_test.dart'],
            'convert': [DART, 'tool/fidelity/convert.dart', RUN + '/' + group + '/source.doc', RUN + '/' + group + '/parser.docx'],
            'native-version': [OFFICE, '--version'],
            'native-export': [OFFICE, '-env:UserInstallation=file://' + RUN + '/' + group + '/profile', '--headless', '--norestore', '--nodefault',
                              '--convert-to', 'docx:Office Open XML Text', '--outdir', RUN + '/' + group + '/native', RUN + '/' + group + '/parser.docx'],
        }
        for name, argv in commands.items():
            inputs = [group + '/source.doc'] if name == 'convert' else [group + '/parser.docx'] if name == 'native-export' else []
            command(files, group, name, argv, inputs)
        for name, input_ in [('parser-pandoc', 'parser.docx'), ('native-pandoc', 'native/parser.docx')]:
            command(files, group, name, ['/usr/bin/pandoc', '+RTS', '-N1', '-M256m', '-K32m', '-RTS', '--from=docx', '--to=json', RUN + '/' + group + '/' + input_], [group + '/' + input_])
        require(b'No issues found!' in files[group + '/analyze.stdout'], 'Analyzer result')
        require(files[group + '/native-version.stdout'].strip() == b'LibreOfficeDev 26.8.0.0.alpha0 2c87e51eeaa2b413ff4ae097b2705eea1995d8e5', 'Exact native version')
        test_counts[group] = test_events(files[group + '/tests.stdout'], ref)
        observation = js(files[group + '/opc-observations.json'])
        package_names = ['authored.docx', 'baseline-parser.docx', 'baseline-native.docx', 'parser.docx', 'native/parser.docx']
        require(set(observation) == set(package_names), 'Complete distinct path observations')
        for package in package_names:
            require(opc(files[group + '/' + package]) == observation[package], 'Recomputed OPC ' + group + '/' + package)
        before, after, native = observation['baseline-parser.docx'], observation['parser.docx'], observation['native/parser.docx']
        require({p: v['text'] for p, v in before.items()} == {p: v['text'] for p, v in after.items()}, 'Parser cached visible results unchanged')
        begins = [e for p in after for e in elements(files[group + '/parser.docx'], p, 'fldChar') if e.get(W + 'fldCharType') == 'begin']
        require(len(begins) == (3 if ref else 4) and all(e.get(W + 'fldLock') == '1' and e.get(W + 'dirty') == '0' for e in begins), 'All restored fields locked')
        with zipfile.ZipFile(io.BytesIO(files[group + '/parser.docx'])) as z:
            records = js(z.read('word/evidence/manifest.json'))['records']
        if not ref:
            source = js(files['inspections/external.json'])['fields']
            expected = Counter(f['instruction'].replace('\x01', ' ') for f in source)
            require(Counter(s for p in after.values() for s in p['instructions']) == expected, 'Exact restored URL instructions')
            parser_owners = external_owners(files[group + '/parser.docx'])
            native_owners = external_owners(files[group + '/native/parser.docx'])
            raw_targets = {r['cp']: r['target'] for r in js(files['independent-external-source.json'])}
            for field in source:
                story = field['story']
                expected_field = {'instruction': field['instruction'].replace('\x01', ' '), 'storedResult': field['storedResult']}
                require(parser_owners[story]['fields'] == [expected_field], 'Parser URL story/text/target ownership: ' + story)
                cp = field['startCp'] + 1 + field['instruction'].index('\x01')
                expected_link = {'storedResult': field['storedResult'], 'target': raw_targets[cp]}
                require(native_owners[story]['links'] == [expected_link], 'Native URL story/text/target ownership: ' + story)
            require(not any(v['instructions'] or v['links'] for v in before.values()), 'Retained prior URL loss')
            targets = [link['relationship']['Target'] for p in native.values() for link in p['links']]
            require(Counter(targets) == Counter({'https://example.com/body': 1, 'https://example.com/note': 1, 'https://example.com/header': 2}), 'Native exact URL targets and occurrences')
            require(all(link['relationship']['Type'] == R[1:-1] + '/hyperlink' and
                        link['relationship'].get('TargetMode') == 'External'
                        for p in native.values() for link in p['links']), 'Native hyperlink relationship type')
            require(len([r for r in records if r['kind'] == 'binaryHyperlinkField']) == 4, 'URL evidence records')
            require(nodes(js(files[group + '/parser-pandoc.stdout']), 'Link') == 2 and
                    nodes(js(files[group + '/native-pandoc.stdout']), 'Link') == 2, 'Independent semantic URL reader')
            expected_links = Counter([('body', 'Body link', 'https://example.com/body'),
                                      ('note', 'Note link', 'https://example.com/note')])
            for stage in ['parser-pandoc', 'native-pandoc']:
                require(Counter(ast_links(js(files[group + '/' + stage + '.stdout']))) == expected_links,
                        'Independent AST owner/text/target binding')
        else:
            expected = [' REF Target_A \\h  ', ' HYPERLINK  \\l "Target_A" ', 'QUOTE "LITERAL-β"']
            require(after['word/document.xml']['instructions'] == expected, 'Exact restored reference instructions')
            with zipfile.ZipFile(io.BytesIO(files[group + '/parser.docx'])) as z:
                fields = complex_fields(ET.fromstring(z.read('word/document.xml')))
            require(fields == [{'instruction': instruction, 'storedResult': cached} for instruction, cached in
                               zip(expected, ['CACHED-REF', 'CACHED-LINK', 'CACHED-QUOTE'])], 'Exact reference field/result ownership')
            require(native['word/document.xml']['instructions'] == [' REF Target_A \\h ', 'QUOTE "LITERAL-β"'] and
                    native['word/document.xml']['links'] == [{'text': 'CACHED-LINK', 'anchor': 'Target_A', 'relationship': None}], 'Native reference instructions and bookmark link')
            require(len(before['word/document.xml']['instructions']) == 2, 'Retained prior REF loss')
            cached = 'ANCHOR-αREF:[CACHED-REF]LINK:[CACHED-LINK]QUOTE:[CACHED-QUOTE]'
            require(after['word/document.xml']['text'] == native['word/document.xml']['text'] == cached, 'Preserved cached REF through native re-export')
            require(observation['baseline-native.docx']['word/document.xml']['text'] == cached.replace('REF:[CACHED-REF]', 'REF:[ANCHOR-α]'), 'Retained native recalculation difference')
            refs = [r for r in records if r['kind'] == 'binaryReferenceField']
            require(len(refs) == 1 and refs[0]['recoveredNativeTerminator'] is True and
                    refs[0]['instruction'] == ' REF Target_A \\h \x01', 'Explicit reference padding evidence')
    for path in ['source.doc', 'authored.docx', 'baseline-parser.docx', 'baseline-native.docx', 'parser.docx']:
        require(files['reference/' + path] == files['reference-final/' + path], 'Earlier and final reference package identity')
    producer = js(files['producer-source.json'])
    require(producer['commit'] == '2c87e51eeaa2b413ff4ae097b2705eea1995d8e5' and
            producer['sha256'] == sha(files['LibreOffice-2c87e51-ww8atr.cxx']) == '3895da4595a2e5e0f8c6c7fd1a83546c62ecaaf4dc562d27904c8d7bea3a41c3', 'Exact native producer source')
    verify_schema(files)
    verify_javascript(files)
    verify_javascript(files, 'javascript-owner-bound', repository)
    return {'verified': True, 'externalFocusedTests': test_counts['external'],
            'finalFocusedTests': test_counts['reference-final'], 'nativeSources': 2,
            'preservedUrlFields': 4, 'restoredReferenceFields': 1, 'sdkPackages': 2,
            'sdkErrors': 0, 'javascriptNativeCases': 2, 'javascriptFields': 7,
            'javascriptOwnerSwapRejected': True}


def verify_schema(files):
    r = js(files['schema/command.json'])
    validator = BASE + '/parser-schema-final/validator/'
    expected = [BASE + '/toolchains/dotnet-8.0.428/dotnet', validator + 'OfficeValidation.dll', RUN + '/schema/corpus', RUN + '/schema/report.json']
    require(r['argv'] == expected and r['cwd'] == REPO and r['exitCode'] == 0, 'Exact SDK command')
    require(r['stdoutSha256'] == sha(files['schema/stdout.log']) and r['stderrSha256'] == sha(files['schema/stderr.log']), 'SDK logs')
    require(r['reportSha256'] == sha(files['schema/report.json']) and r['inputsBefore'] == r['inputsAfter'], 'SDK report/source binding')
    build = js(files['schema/original-build-report.json'])
    require(build['passed'] is True and build['selfTestPassed'] is True and build['validatorBuild']['frameworkVersion'] == '8.0.34', 'Reused successful SDK build')
    require({p['id']: p['version'] for p in build['validatorBuild']['packages']} == {
        'DocumentFormat.OpenXml': '3.3.0', 'DocumentFormat.OpenXml.Framework': '3.3.0',
        'System.IO.Packaging': '8.0.1'}, 'Exact reused SDK packages')
    for name in ['validator-build', 'compiler-version', 'validator-self-test', 'dotnet-sdks', 'dotnet-runtimes']:
        stage = next(s for s in build['stages'] if s['name'] == name)
        require(stage['returncode'] == 0 and sha(files['schema/' + stage['log']]) == stage['logSha256'], 'Reused SDK build log')
    expected_inputs = {validator + n: d for n, d in build['validatorBuild']['artifacts'].items()}
    for name in ['external', 'reference']:
        package = files['schema/corpus/' + name + '.docx']
        group = 'reference-final' if name == 'reference' else 'external'
        require(package == files[group + '/parser.docx'], 'SDK validates measured parser bytes')
        expected_inputs[RUN + '/schema/corpus/' + name + '.docx'] = sha(package)
    require(r['inputsBefore'] == expected_inputs, 'Exact SDK executable and package inventory')
    require(r['dotnetSha256'] == build['validatorBuild']['dotnetSha256'] and
            r['programSourceSha256'] == sha(files['schema/Program.cs']) == build['source']['files']['tool/office-validation/Program.cs'], 'Reused validator source identity')
    report = js(files['schema/report.json'])
    require(report['Files'] == 2 and report['Failures'] == 0 and len(report['Reports']) == 2, 'Two SDK successes')
    expected_rows = {RUN + '/schema/corpus/' + n + '.docx': sha(files['schema/corpus/' + n + '.docx']) for n in ['external', 'reference']}
    require({v['File'] for v in report['Reports']} == set(expected_rows), 'Exact SDK report paths')
    for row in report['Reports']:
        require(set(row) == {'File', 'Sha256', 'Errors'} and row['Errors'] == [] and
                row['Sha256'] == expected_rows[row['File']], 'Successful SDK row shape and exact bytes')


def verify_javascript(files, group='javascript-final', repository=None):
    owner_bound = group == 'javascript-owner-bound'
    pin, tree = (OWNER_PIN, OWNER_TREE) if owner_bound else (REF_PIN, REF_TREE)
    r = js(files[group + '/checkout.json'])
    require(r['commit'] == pin and r['tree'] == tree and r['trackedDiff'] == '', 'Frozen JS source')
    helper_group = group if owner_bound else 'reference-final'
    helper = files['runtime-snapshots/' + helper_group + '/tool/field_metadata_web_acceptance.dart']
    require(r['helperSha256'] == sha(helper), 'Exact JS helper source')
    if repository:
        require(helper == subprocess.check_output(['git', 'show', pin + ':tool/field_metadata_web_acceptance.dart'], cwd=repository), 'Exact published owner-bound JS helper')
        library_trees = subprocess.check_output(['git', 'rev-parse', REF_PIN + ':lib', pin + ':lib'], cwd=repository, text=True).splitlines()
        require(len(set(library_trees)) == 1, 'Production library unchanged in JS helper follow-up')
    commands = {
        'dart-version': [DART, '--version'], 'node-version': [NODE, '--version'],
        'compile': [DART, 'compile', 'js', '--packages=' + REPO + '/.dart_tool/package_config.json', '-O1', '-o', RUN + '/' + group + '/acceptance.js', RUN + '/' + group + '/acceptance.dart'],
        'node': [NODE, '-e', 'globalThis.self=globalThis; require(process.argv[1]);', RUN + '/' + group + '/acceptance.js'],
    }
    for name, argv in commands.items():
        command(files, group, name, argv)
    require(b'Dart SDK version: 3.13.7 ' in files[group + '/dart-version.stdout'] and
            files[group + '/node-version.stdout'].strip() == b'v24.22.1', 'JS tool versions')
    source = files[group + '/acceptance.dart'].decode()
    expected_cases = [{'name': name, 'base64': base64.b64encode(files[path + '/source.doc']).decode()}
                      for name, path in [('external', 'external'), ('reference', 'reference-final')]]
    encoded = base64.b64encode(json.dumps(expected_cases).encode()).decode()
    expected_source = "import 'dart:convert';\nimport 'file://" + REPO + "/tool/field_metadata_web_acceptance.dart';\nvoid main() { print(jsonEncode(verifyFieldMetadataWebAcceptance(jsonDecode(utf8.decode(base64Decode('" + encoded + "'))) as List))); }\n"
    require(source == expected_source, 'Exact executable JS entrypoint and native payload')
    match = re.search(r"base64Decode\('([A-Za-z0-9+/=]+)'\)", source)
    require(match is not None and "import 'file://" + REPO + "/tool/field_metadata_web_acceptance.dart';" in source, 'Actual JS entrypoint helper')
    cases = js(base64.b64decode(match[1], validate=True))
    require([c['name'] for c in cases] == ['external', 'reference'], 'Both actual JS cases')
    for case in cases:
        group_ = 'external' if case['name'] == 'external' else 'reference-final'
        require(base64.b64decode(case['base64'], validate=True) == files[group_ + '/source.doc'], 'JS executes exact native source')
    result = js(files[group + '/node.stdout'])
    expected_result = {'cases': {'external': {'fields': 4, 'sourceBytesUnchanged': True, 'representation': 'lockedFields'},
                                'reference': {'fields': 3, 'sourceBytesUnchanged': True, 'representation': 'lockedFields'}},
                       'fields': 7, 'fieldResultsEvaluated': False}
    if owner_bound:
        for case in expected_result['cases'].values():
            case['ownerBindingsChecked'] = True
        expected_result['bodyNoteTargetSwapRejected'] = True
    require(result == expected_result, 'Actual JS result')
    outputs = js(files[group + '/generated-outputs.json'])
    require({v['path'] for v in outputs} == {'acceptance.js', 'acceptance.js.deps', 'acceptance.js.map'} and
            all(v['bytes'] > 0 and re.fullmatch('[a-f0-9]{64}', v['sha256']) for v in outputs), 'Omitted reproducible JS identities')


def load_payloads(root=HERE):
    manifest = js((root / 'manifest.json').read_bytes())
    require(manifest.get('schema') == 1 and manifest.get('fileCount') == 183, 'Frozen evidence inventory version/count')
    archive = (root / 'records.tar.xz').read_bytes()
    require(sha(archive) == manifest['archiveSha256'] and len(archive) == manifest['archiveBytes'], 'Archive identity')
    with tarfile.open(fileobj=io.BytesIO(archive), mode='r:xz') as tf:
        members = tf.getmembers()
        require(all(m.isfile() and not PurePosixPath(m.name).is_absolute() and '..' not in PurePosixPath(m.name).parts for m in members), 'Safe regular archive paths')
        require(len(members) == len({m.name for m in members}), 'Unique archive members')
        files = {m.name: tf.extractfile(m).read() for m in members}
    expected = {r['path']: r for r in manifest['files']}
    require(len(expected) == len(manifest['files']) == manifest['fileCount'] == len(files) and set(files) == set(expected), 'Exact retained inventory')
    require(sum(map(len, files.values())) == manifest['rawBytes'], 'Retained raw size')
    for name, data in files.items():
        require(sha(data) == expected[name]['sha256'] and len(data) == expected[name]['bytes'], 'Exact retained member ' + name)
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', type=Path, help='Also compare measured source snapshots to exact published Git objects')
    args = parser.parse_args()
    receipt = js((HERE / 'receipt.json').read_bytes())
    require(receipt['schema'] == 1 and receipt['measuredRuntimeCommits'] == [URL_PIN, REF_PIN], 'Receipt runtime identities')
    require(receipt['javascriptHelperCommit'] == OWNER_PIN, 'Receipt owner-bound helper identity')
    require(set(receipt['files']) == {'README.md', 'verify.py', 'source_oracle.py', 'test_verifier.py', 'manifest.json', 'records.tar.xz'}, 'Complete helper/manifest/document seal')
    for path, digest in receipt['files'].items():
        require(sha((HERE / path).read_bytes()) == digest, 'Helper/manifest/document seal ' + path)
    files = load_payloads()
    result = verify_payloads(files, args.repository)
    require(result == receipt['result'], 'Receipt outcome')
    print(json.dumps({**result, 'records': len(files), 'gitChecked': args.repository is not None}, sort_keys=True))


if __name__ == '__main__':
    main()
