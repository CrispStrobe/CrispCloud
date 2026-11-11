"""Mutations which the independent native comment mapping oracle must reject."""
import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET
from zipfile import ZipFile

import comment_threads_oracle as oracle


class CommentThreadOracleTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.output = Path(self.temporary.name) / 'mutated.docx'
        self.expected = json.loads((oracle.FIXTURES / 'comment_threads_expected.json').read_text())
        with ZipFile(oracle.FIXTURES / 'comment-threads.docx') as package:
            self.parts = {name: package.read(name) for name in package.namelist()}

    def reject(self, part, mutation):
        tree = ET.fromstring(self.parts[part])
        mutation(tree)
        self.parts[part] = ET.tostring(tree)
        with ZipFile(self.output, 'w') as package:
            for name, contents in self.parts.items():
                package.writestr(name, contents)
        with self.assertRaises(AssertionError):
            oracle.verify_file(self.output, self.expected, 'imported')

    def test_authored_fixture_is_a_positive_control(self):
        oracle.verify_file(oracle.FIXTURES / 'comment-threads.docx', self.expected, 'imported')

    def test_numeric_comment_id_is_not_a_paragraph_anchor(self):
        self.reject('review/thread-state.xml', lambda root: root[0].set('{' + oracle.W15 + '}paraId', '00000007'))

    def test_numeric_parent_comment_id_does_not_join(self):
        self.reject('review/thread-state.xml', lambda root: root[0].set('{' + oracle.W15 + '}paraIdParent', '00000029'))

    def test_first_paragraph_is_not_the_comment_anchor(self):
        self.reject('review/thread-state.xml', lambda root: root[1].set('{' + oracle.W15 + '}paraId', '00112233'))

    def test_lost_last_paragraph_anchor_fails(self):
        def mutate(root):
            del root[1][-1].attrib['{' + oracle.W14 + '}paraId']
        self.reject('review/threads.xml', mutate)

    def test_dropped_resolved_flag_fails(self):
        self.reject('review/thread-state.xml', lambda root: root[1].set('{' + oracle.W15 + '}done', '0'))

    def test_valid_but_wrong_parent_fails_authored_mapping(self):
        self.reject('review/thread-state.xml', lambda root: root[0].set('{' + oracle.W15 + '}paraIdParent', '00000001'))

    def test_duplicate_extension_cannot_hide_missing_comment(self):
        self.reject('review/thread-state.xml', lambda root: root[2].set('{' + oracle.W15 + '}paraId', '0077BB07'))

    def test_stale_mime_type_fails(self):
        def mutate(root):
            for node in root:
                if node.get('PartName') == '/review/thread-state.xml':
                    node.set('ContentType', 'application/xml')
        self.reject('[Content_Types].xml', mutate)

    def test_changed_relocated_part_target_fails(self):
        self.reject('custom/_rels/document-main.xml.rels',
                    lambda root: root[0].set('Target', 'threads.xml'))

    def test_missing_bold_run_fails(self):
        def mutate(root):
            run_properties = root[0].find('w:p/w:r/w:rPr', oracle.NS)
            run_properties.clear()
        self.reject('review/threads.xml', mutate)

    def test_explicit_false_bold_cannot_pass_as_bold(self):
        def mutate(root):
            root[0].find('w:p/w:r/w:rPr/w:b', oracle.NS).set('{' + oracle.W + '}val', '0')
        self.reject('review/threads.xml', mutate)

    def test_synthetic_paragraph_spacing_fails(self):
        def mutate(root):
            paragraph = root.find('w:body/w:p', oracle.NS)
            properties = ET.Element('{' + oracle.W + '}pPr')
            ET.SubElement(properties, '{' + oracle.W + '}spacing', {'{' + oracle.W + '}after': '160'})
            paragraph.insert(0, properties)
        self.reject('custom/document-main.xml', mutate)

    def test_unreferenced_global_styles_relationship_fails(self):
        def mutate(root):
            ET.SubElement(root, '{' + oracle.REL + '}Relationship',
                          {'Id': 'styles', 'Type': oracle.R + '/styles', 'Target': 'styles.xml'})
        self.reject('custom/_rels/document-main.xml.rels', mutate)

    def test_copied_source_cannot_be_omitted_from_corpus(self):
        folder = Path(self.temporary.name)
        source = (oracle.FIXTURES / 'comment-threads.docx').read_bytes()
        for mode in ('imported', 'edited'):
            for cycle in (1, 2, 3):
                (folder / f'threads-{mode}-{cycle}.docx').write_bytes(source)
        with self.assertRaisesRegex(AssertionError, 'missing=.*threads-source.docx'):
            oracle.verify_corpus(folder, self.expected)

    def test_copied_source_cannot_be_a_reexported_replacement(self):
        folder = Path(self.temporary.name)
        source = (oracle.FIXTURES / 'comment-threads.docx').read_bytes()
        for mode in ('imported', 'edited'):
            for cycle in (1, 2, 3):
                (folder / f'threads-{mode}-{cycle}.docx').write_bytes(source)
        (folder / 'threads-source.docx').write_bytes(source + b'changed')
        with self.assertRaisesRegex(AssertionError, 'modified instead of copied'):
            oracle.verify_corpus(folder, self.expected)


if __name__ == '__main__':
    unittest.main()
