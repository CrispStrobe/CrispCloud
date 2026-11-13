#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Controls for incorrect format labels, lossy projections and failed paths."""
import json
from pathlib import Path
from types import SimpleNamespace
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from independent_semantic_cases import CASES, W, package
from path_matrix import (CFB_MAGIC, CommandFailure, ROOT, Runner, differences,
                         normalized_ast, package_facts, require_format, sniff)


class PathMatrixTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='path-matrix-test-', dir=ROOT)
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)

    def runner(self):
        return Runner(SimpleNamespace(output=self.directory / 'output', antiword_data=None,
                                      antiword=None, track_changes=['accept']))

    def test_extension_cannot_turn_rtf_into_binary_doc(self):
        source = self.directory / 'fake.doc'
        source.write_bytes(b'{\\rtf1\\ansi Plain text}')
        self.assertEqual('rtf', sniff(source))
        with self.assertRaisesRegex(ValueError, 'actual content is rtf'):
            require_format(source, 'cfb')
        source.write_bytes(CFB_MAGIC + bytes(64))
        self.assertEqual('cfb', sniff(source))
        # CFB detection deliberately is not a claim that the Word streams/FIB
        # are valid. That remains the selected DOC importer's responsibility.

    def test_docx_requires_actual_main_part_and_content_type(self):
        source = self.directory / 'control.docx'
        package(source, '<w:p><w:r><w:t>CONTROL</w:t></w:r></w:p>')
        self.assertEqual('docx', sniff(source))
        with zipfile.ZipFile(source) as archive:
            parts = {n: archive.read(n) for n in archive.namelist()}
        parts['[Content_Types].xml'] = parts['[Content_Types].xml'].replace(
            b'wordprocessingml.document.main+xml', b'wordprocessingml.template.main+xml')
        misleading = self.directory / 'template-named.docx'
        with zipfile.ZipFile(misleading, 'w') as archive:
            for name, data in parts.items():
                archive.writestr(name, data)
        self.assertEqual('word-zip-other', sniff(misleading))

    def test_duplicate_or_escaping_zip_members_are_rejected(self):
        for name in ('../escape', '/absolute'):
            path = self.directory / (name.replace('/', '_') + '.docx')
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr(name, b'data')
            with self.assertRaisesRegex(ValueError, 'Unsafe package'):
                sniff(path)
        path = self.directory / 'duplicate.docx'
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('same', b'a')
            with self.assertWarns(UserWarning):
                archive.writestr('same', b'b')
        with self.assertRaisesRegex(ValueError, 'duplicate package'):
            sniff(path)

    def test_missing_null_and_json_types_are_not_equal(self):
        self.assertFalse(differences({}, {'target': None})['equal'])
        self.assertFalse(differences({'flag': False}, {'flag': 0})['equal'])
        report = differences(list(range(100)), list(range(100, 200)), limit=2)
        self.assertEqual(100, report['count'])
        self.assertEqual(2, len(report['differences']))
        self.assertTrue(report['truncated'])

    def test_embedded_image_names_normalize_but_content_does_not(self):
        def document(name):
            return {'blocks': [{'t': 'Para', 'c': [{'t': 'Image', 'c': [['', [], []], [], [name, 'title']]}]}]}
        a, b = document('media/one.png'), document('media/renamed.png')
        first = normalized_ast(a, {'media/one.png': {'sha256': 'a' * 64}})
        same = normalized_ast(b, {'media/renamed.png': {'sha256': 'a' * 64}})
        changed = normalized_ast(b, {'media/renamed.png': {'sha256': 'b' * 64}})
        self.assertEqual(first, same)
        self.assertNotEqual(first, changed)
        self.assertEqual('media/one.png', a['blocks'][0]['c'][0]['c'][-1][0])

    def test_equal_markdown_ast_cannot_hide_note_kind_loss(self):
        footnote = self.directory / 'footnote.docx'
        CASES['note-joins'](footnote)
        with zipfile.ZipFile(footnote) as archive:
            parts = {n: archive.read(n).decode('utf-8') for n in archive.namelist()}
        endnote = self.directory / 'endnote.docx'
        with zipfile.ZipFile(endnote, 'w') as archive:
            for name, data in parts.items():
                archive.writestr(name.replace('footnotes', 'endnotes'), data.replace('footnote', 'endnote'))
        # Pandoc Note blocks have no footnote/endnote discriminator. Keeping
        # that AST equal must not erase the independent package distinction.
        same_ast = {'blocks': [{'t': 'Note', 'c': [{'t': 'Para', 'c': [{'t': 'Str', 'c': 'NOTE'}]}]}]}
        self.assertEqual(normalized_ast(same_ast, {}), normalized_ast(same_ast, {}))
        first, second = package_facts(footnote), package_facts(endnote)
        self.assertEqual(2, first['counts']['footnote'])
        self.assertEqual(2, second['counts']['endnote'])
        self.assertFalse(differences(first, second)['equal'])

    def test_namespace_alias_does_not_hide_features(self):
        source = self.directory / 'notes.docx'
        CASES['note-joins'](source)
        alias = self.directory / 'alias.docx'
        with zipfile.ZipFile(source) as archive, zipfile.ZipFile(alias, 'w') as output:
            for name in archive.namelist():
                data = archive.read(name).decode('utf-8')
                data = data.replace('xmlns:w=', 'xmlns:z=').replace('w:', 'z:')
                output.writestr(name, data)
        self.assertEqual('docx', sniff(alias))
        self.assertEqual(package_facts(source), package_facts(alias))

    def test_equal_body_cannot_hide_markdown_metadata_loss(self):
        # An actual Pandoc 3.1.11.1 counterexample: non-standalone Markdown
        # keeps BODY while dropping title/author. The runner must report both
        # observations, not turn the body equality into a document-wide claim.
        source = self.directory / 'metadata.docx'
        package(source, '<w:p><w:r><w:t>BODY</w:t></w:r></w:p>')
        ast = {'pandoc-api-version': [1, 23, 1],
               'meta': {'title': {'t': 'MetaInlines', 'c': [{'t': 'Str', 'c': 'KEPT-TITLE'}]},
                        'author': {'t': 'MetaList', 'c': [{'t': 'MetaInlines', 'c': [{'t': 'Str', 'c': 'KEPT-AUTHOR'}]}]}},
               'blocks': [{'t': 'Para', 'c': [{'t': 'Str', 'c': 'BODY'}]}]}
        reread = {**ast, 'meta': {}}
        runner = self.runner()
        runner.options.pandoc = Path('/not-invoked/pandoc')
        node = {'id': 'source', 'format': 'docx', 'path': str(source)}
        with patch.object(runner, 'command', side_effect=[json.dumps(ast).encode(), b'BODY\n', json.dumps(reread).encode()]):
            runner.project(node, runner.output / 'source')
        result = node['pandoc']['accept']
        self.assertEqual('success', result['status'])
        self.assertTrue(result['markdownRoundtrip']['equal'])
        self.assertFalse(result['markdownMetadataRoundtrip']['equal'])
        self.assertEqual({}, result['markdownMetadata'])
        self.assertEqual(ast['meta'], result['metadata'])
        retained = json.loads((runner.output / 'source/pandoc/accept/markdown-ast.json').read_text())
        self.assertEqual(reread, retained)
        runner.report['cases'] = [{'nodes': {'source': node}, 'comparisons': []}]
        self.assertEqual(0, runner.finish())
        self.assertEqual(0, runner.report['summary']['changedMarkdownBodies'])
        self.assertEqual(1, runner.report['summary']['changedMarkdownMetadata'])

    def test_failed_dependency_is_unavailable_not_an_equality_pass(self):
        runner = self.runner()
        case = {'comparisons': [], 'nodes': {'a': {'status': 'error'}, 'b': {'status': 'success', 'format': 'docx'}}}
        runner.compare(case, 'failure', 'a', 'b', 'same binary')
        self.assertEqual('blocked', case['comparisons'][0]['status'])
        self.assertIsNone(case['comparisons'][0]['equal'])

    def test_two_failed_readers_do_not_agree_on_empty_documents(self):
        runner = self.runner()
        node = {'status': 'success', 'format': 'docx', 'facts': None,
                'xmlSnapshot': None, 'pandoc': {'accept': {'status': 'error'}}}
        case = {'comparisons': [], 'nodes': {'a': node, 'b': node}}
        runner.compare(case, 'reader-failure', 'a', 'b', 'same binary')
        result = case['comparisons'][0]
        self.assertEqual('measured', result['status'])
        self.assertEqual('unavailable', result['xmlStatus'])
        self.assertIsNone(result['xmlFindings'])
        self.assertIsNone(result['packageFacts']['equal'])
        self.assertIsNone(result['pandoc']['accept']['equal'])

    def test_command_failure_and_timeout_retain_actual_outputs(self):
        runner = self.runner()
        command = self.directory / 'output' / 'failed'
        with self.assertRaises(CommandFailure):
            runner.command([sys.executable, '-c', 'print("EARLY-OUTPUT", flush=True); raise SystemExit(7)'], command)
        result = json.loads((command / 'command.json').read_text())
        self.assertEqual(7, result['returncode'])
        self.assertIn(b'EARLY-OUTPUT', (command / 'stdout').read_bytes())
        timeout = self.directory / 'output' / 'timeout'
        with self.assertRaises(CommandFailure):
            runner.command([sys.executable, '-c', 'import time; print("BEFORE-TIMEOUT", flush=True); time.sleep(10)'], timeout, timeout=1)
        self.assertTrue(json.loads((timeout / 'command.json').read_text())['timedOut'])
        self.assertIn(b'BEFORE-TIMEOUT', (timeout / 'stdout').read_bytes())

    def test_missing_executable_is_a_recorded_failure(self):
        runner = self.runner()
        command = self.directory / 'output' / 'missing'
        with self.assertRaises(CommandFailure):
            runner.command([self.directory / 'missing-executable'], command)
        self.assertEqual('error', json.loads((command / 'command.json').read_text())['status'])


if __name__ == '__main__':
    unittest.main()
