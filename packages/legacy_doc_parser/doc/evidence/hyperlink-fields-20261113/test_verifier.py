#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Resealed semantic corruption controls; the frozen original is never edited."""
import base64
import io
import json
from pathlib import Path
import re
import tarfile
import tempfile
import unittest
import zipfile
from xml.etree import ElementTree as ET

import verify


def change_json(files, name, fn):
    value = json.loads(files[name])
    fn(value)
    files[name] = (json.dumps(value, ensure_ascii=False) + '\n').encode()


def package_member(files, name, member, fn):
    old = files[name]
    buf = io.BytesIO()
    with zipfile.ZipFile(io.BytesIO(old)) as source, zipfile.ZipFile(buf, 'w', compression=zipfile.ZIP_DEFLATED) as target:
        for info in source.infolist():
            data = source.read(info.filename)
            target.writestr(info, fn(data) if info.filename == member else data)
    files[name] = buf.getvalue()
    group = name.split('/')[0]
    package = name[len(group) + 1:]
    if group in ('external', 'reference', 'reference-final'):
        change_json(files, group + '/opc-observations.json', lambda v: v.__setitem__(package, verify.opc(files[name])))
        for path in list(files):
            if not (path.startswith(group + '/') and path.endswith('.json')):
                continue
            value = json.loads(files[path])
            if isinstance(value, dict) and 'inputsBefore' in value and verify.RUN + '/' + name in value['inputsBefore']:
                for key in ('inputsBefore', 'inputsAfter'):
                    value[key][verify.RUN + '/' + name] = verify.sha(files[name])
                files[path] = (json.dumps(value) + '\n').encode()


def xml_replace(data, old, new):
    if old not in data:
        raise ValueError('Control target was not found')
    return data.replace(old, new, 1)


def schema_change(files, fn):
    change_json(files, 'schema/report.json', fn)
    change_json(files, 'schema/command.json', lambda r: r.__setitem__('reportSha256', verify.sha(files['schema/report.json'])))


def events_change(files, fn):
    name = 'reference-final/tests.stdout'
    events = [json.loads(x) for x in files[name].splitlines()]
    fn(events)
    files[name] = b''.join((json.dumps(e) + '\n').encode() for e in events)
    change_json(files, 'reference-final/tests.json', lambda r: r.__setitem__('stdoutSha256', verify.sha(files[name])))


class EvidenceControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original = verify.load_payloads()

    def reject(self, mutate, expected, *, git=False):
        files = dict(self.original)
        mutate(files)
        # Rebuild the whole archive/manifest so simple hash mismatch is not the
        # reason these controls fail. Run exactly the same production decoder.
        with tempfile.TemporaryDirectory(prefix='hyperlink-proof-control-') as d:
            root = Path(d)
            buf = io.BytesIO()
            with tarfile.open(fileobj=buf, mode='w:xz', preset=0) as tf:
                for path, data in sorted(files.items()):
                    item = tarfile.TarInfo(path)
                    item.size = len(data)
                    tf.addfile(item, io.BytesIO(data))
            archive = buf.getvalue()
            (root / 'records.tar.xz').write_bytes(archive)
            manifest = {'schema': 1, 'fileCount': len(files), 'rawBytes': sum(map(len, files.values())),
                        'archiveBytes': len(archive), 'archiveSha256': verify.sha(archive),
                        'files': [{'path': p, 'bytes': len(v), 'sha256': verify.sha(v)} for p, v in sorted(files.items())]}
            (root / 'manifest.json').write_text(json.dumps(manifest))
            reloaded = verify.load_payloads(root)
            with self.assertRaisesRegex(ValueError, expected):
                verify.verify_payloads(reloaded, verify.HERE.parents[2] if git else None)

    def test_original(self):
        self.assertTrue(verify.verify_payloads(self.original, verify.HERE.parents[2])['verified'])

    def test_native_target(self):
        self.reject(lambda f: package_member(f, 'external/native/parser.docx', 'word/_rels/document.xml.rels',
                    lambda b: xml_replace(b, b'https://example.com/body', b'https://wrong.example/body')), 'Native URL story/text/target ownership')

    def test_parser_target(self):
        self.reject(lambda f: package_member(f, 'external/parser.docx', 'word/document.xml',
                    lambda b: xml_replace(b, b'https://example.com/body', b'https://wrong.example/body')), 'Exact restored URL instructions')

    def test_native_owner_target_swap(self):
        def mutate(f):
            package_member(f, 'external/native/parser.docx', 'word/_rels/document.xml.rels',
                           lambda b: xml_replace(b, b'https://example.com/body', b'https://example.com/note'))
            package_member(f, 'external/native/parser.docx', 'word/_rels/footnotes.xml.rels',
                           lambda b: xml_replace(b, b'https://example.com/note', b'https://example.com/body'))
        self.reject(mutate, 'Native URL story/text/target ownership')

    def test_parser_owner_target_swap(self):
        def mutate(f):
            package_member(f, 'external/parser.docx', 'word/document.xml',
                           lambda b: xml_replace(b, b'https://example.com/body', b'https://example.com/note'))
            package_member(f, 'external/parser.docx', 'word/footnotes.xml',
                           lambda b: xml_replace(b, b'https://example.com/note', b'https://example.com/body'))
        self.reject(mutate, 'Parser URL story/text/target ownership')

    def test_ast_owner_target_swap(self):
        def mutate(f):
            name = 'external/parser-pandoc.stdout'
            ast = json.loads(f[name])
            def swap(node):
                if isinstance(node, dict):
                    if node.get('t') == 'Link':
                        target = node['c'][2][0]
                        node['c'][2][0] = {'https://example.com/body': 'https://example.com/note',
                                         'https://example.com/note': 'https://example.com/body'}[target]
                    for child in node.values(): swap(child)
                elif isinstance(node, list):
                    for child in node: swap(child)
            swap(ast); f[name] = json.dumps(ast).encode()
            change_json(f, 'external/parser-pandoc.json', lambda r: r.__setitem__('stdoutSha256', verify.sha(f[name])))
        self.reject(mutate, 'Independent AST owner/text/target binding')

    def test_raw_data_pointer(self):
        self.reject(lambda f: change_json(f, 'inspections/external.json',
                    lambda r: r['binaryData'][0].__setitem__('offset', r['binaryData'][0]['offset'] + 1)), 'CPicLocation points')

    def test_raw_instruction(self):
        self.reject(lambda f: change_json(f, 'inspections/external.json',
                    lambda r: r['fields'][0].__setitem__('instruction', ' HYPERLINK "different"\x01')), 'CLX literal instruction')

    def test_duplicate_source_field(self):
        self.reject(lambda f: change_json(f, 'inspections/reference.json',
                    lambda r: r['fields'].append(dict(r['fields'][-1]))), 'Exact native field inspection inventory')

    def test_reference_padding_disclosure(self):
        def mutate(f):
            def record(b):
                value = json.loads(b)
                next(r for r in value['records'] if r['kind'] == 'binaryReferenceField')['recoveredNativeTerminator'] = False
                return json.dumps(value).encode()
            package_member(f, 'reference-final/parser.docx', 'word/evidence/manifest.json', record)
        self.reject(mutate, 'Explicit reference padding evidence')

    def test_reference_cached_result(self):
        self.reject(lambda f: package_member(f, 'reference-final/parser.docx', 'word/document.xml',
                    lambda b: xml_replace(b, b'CACHED-REF', b'REPLACED-REF')), 'cached visible results unchanged')

    def test_native_cached_result(self):
        self.reject(lambda f: package_member(f, 'reference-final/native/parser.docx', 'word/document.xml',
                    lambda b: xml_replace(b, b'CACHED-REF', b'REPLACED-REF')), 'cached REF through native')

    def test_native_reference_instruction(self):
        self.reject(lambda f: package_member(f, 'reference-final/native/parser.docx', 'word/document.xml',
                    lambda b: xml_replace(b, b'REF Target_A', b'REF Other_A')), 'Native reference instructions')

    def test_schema_exception(self):
        self.reject(lambda f: schema_change(f, lambda r: r['Reports'][0].__setitem__('Exception', 'validation failed')), 'Successful SDK row shape')

    def test_schema_hash(self):
        self.reject(lambda f: schema_change(f, lambda r: r['Reports'][0].__setitem__('Sha256', '0' * 64)), 'Successful SDK row shape')

    def test_schema_command(self):
        self.reject(lambda f: change_json(f, 'schema/command.json', lambda r: r.__setitem__('argv', ['true'])), 'Exact SDK command')

    def test_native_command(self):
        self.reject(lambda f: change_json(f, 'reference-final/native-export.json', lambda r: r.__setitem__('argv', ['true'])), 'Exact command')

    def test_missing_command_input_receipts(self):
        def mutate(f):
            def remove(r):
                r.pop('inputsBefore')
                r.pop('inputsAfter')
            change_json(f, 'reference-final/native-export.json', remove)
        self.reject(mutate, 'Required exact command input receipts')

    def test_test_command(self):
        self.reject(lambda f: change_json(f, 'reference-final/tests.json', lambda r: r.__setitem__('argv', ['true'])), 'Exact command')

    def test_suite_association(self):
        self.reject(lambda f: events_change(f, lambda e: next(v['suite'] for v in e if v['type'] == 'suite').__setitem__('path', 'unrelated_suite.dart')), 'Exact test suites')

    def test_hidden_failure(self):
        self.reject(lambda f: events_change(f, lambda e: next(v for v in e if v['type'] == 'testDone' and v['hidden']).__setitem__('result', 'failure')), 'Actual successful test')

    def test_skipped_visible_test(self):
        self.reject(lambda f: events_change(f, lambda e: next(v for v in e if v['type'] == 'testDone' and not v['hidden']).__setitem__('skipped', True)), 'Actual successful test')

    def test_js_result(self):
        def mutate(f):
            change_json(f, 'javascript-final/node.stdout', lambda r: r.__setitem__('fields', 6))
            change_json(f, 'javascript-final/node.json', lambda r: r.__setitem__('stdoutSha256', verify.sha(f['javascript-final/node.stdout'])))
        self.reject(mutate, 'Actual JS result')

    def test_owner_js_negative_control(self):
        def mutate(f):
            name = 'javascript-owner-bound/node.stdout'
            change_json(f, name, lambda r: r.__setitem__('bodyNoteTargetSwapRejected', False))
            change_json(f, 'javascript-owner-bound/node.json', lambda r: r.__setitem__('stdoutSha256', verify.sha(f[name])))
        self.reject(mutate, 'Actual JS result')

    def test_js_compile_command(self):
        self.reject(lambda f: change_json(f, 'javascript-final/compile.json', lambda r: r.__setitem__('argv', ['true'])), 'Exact command')

    def test_js_source(self):
        def mutate(f):
            source = f['javascript-final/acceptance.dart'].decode()
            match = re.search(r"base64Decode\('([A-Za-z0-9+/=]+)'\)", source)
            cases = json.loads(base64.b64decode(match[1]))
            raw = bytearray(base64.b64decode(cases[0]['base64'])); raw[100] ^= 1
            cases[0]['base64'] = base64.b64encode(raw).decode()
            replacement = base64.b64encode(json.dumps(cases).encode()).decode()
            f['javascript-final/acceptance.dart'] = source.replace(match[1], replacement).encode()
        self.reject(mutate, 'Exact executable JS entrypoint')

    def test_commented_js_invocation(self):
        def mutate(f):
            name = 'javascript-final/acceptance.dart'
            source = f[name].decode().replace('void main()', '// void main()', 1)
            source += 'void main() { print(' + json.dumps(f['javascript-final/node.stdout'].decode().strip()) + '); }\n'
            f[name] = source.encode()
        self.reject(mutate, 'Exact executable JS entrypoint')

    def test_producer_source(self):
        def mutate(f):
            name = 'LibreOffice-2c87e51-ww8atr.cxx'
            f[name] = xml_replace(f[name], b'SwWW8Writer::WriteLong( rStrm, 0 );', b'SwWW8Writer::WriteLong( rStrm, 1 );')
            change_json(f, 'producer-source.json', lambda r: r.__setitem__('sha256', verify.sha(f[name])))
        self.reject(mutate, 'Exact native producer source')

    def test_frozen_commit(self):
        self.reject(lambda f: change_json(f, 'reference-final/checkout.json', lambda r: r.__setitem__('commit', '0' * 40)), 'Clean frozen reference source')

    def test_git_source(self):
        def mutate(f):
            path = 'lib/src/word_field_binary_metadata.dart'
            name = 'runtime-snapshots/reference-final/' + path
            f[name] += b'\n// altered source\n'
            change_json(f, 'reference-final/runtime-sources.json', lambda r: r.__setitem__(path, verify.sha(f[name])))
        self.reject(mutate, 'Source matches exact published Git content', git=True)

    def test_missing_source_binding(self):
        self.reject(lambda f: change_json(f, 'reference-final/runtime-sources.json',
                    lambda r: r.pop('lib/src/word_field_binary_metadata.dart')), 'Exact measured source inventory')


if __name__ == '__main__':
    unittest.main()
