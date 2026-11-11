"""Negative controls for branch selection and unknown section data retention."""
from copy import deepcopy
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

from corpus import FIXTURES, NS, W, read_zip
from word_compatibility_oracle import MC, verify_directory, verify_document


def selected_fixture():
    """Build the positive control from authored XML, never from engine output."""
    parts = read_zip(FIXTURES / 'word-compatibility.docx')

    def select(parent):
        for child in list(parent):
            if child.tag == MC + 'AlternateContent':
                branch = next((choice for choice in child.findall(MC + 'Choice')
                               if set(choice.get('Requires', '').split()) <= {'w', 'alias'}), None)
                if branch is None:
                    branch = child.find(MC + 'Fallback')
                index = list(parent).index(child)
                parent.remove(child)
                if branch is not None:
                    select(branch)
                    for offset, item in enumerate(list(branch)):
                        parent.insert(index + offset, deepcopy(item))
            else:
                select(child)

    for name in ('word/document.xml', 'word/header-compat.xml',
                 'word/header-first.xml', 'word/footnotes.xml'):
        root = ET.fromstring(parts[name])
        select(root)
        if name == 'word/document.xml':
            root.find('w:body/w:p/w:r/w:t', NS).text = 'Edited compatibility text'
        parts[name] = ET.tostring(root)
    return parts


class WordCompatibilityOracleTests(unittest.TestCase):
    def setUp(self):
        self.parts = selected_fixture()

    def change_body(self, change):
        root = ET.fromstring(self.parts['word/document.xml'])
        change(root.find('w:body', NS))
        self.parts['word/document.xml'] = ET.tostring(root)

    def test_independent_positive_control(self):
        verify_document(self.parts)

    def test_missing_outputs_fail_closed(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(AssertionError, 'missing='):
                verify_directory(folder)

    def test_extra_output_fails_closed(self):
        with tempfile.TemporaryDirectory() as folder:
            Path(folder, 'unexpected.docx').write_bytes(b'')
            with self.assertRaisesRegex(AssertionError, 'unexpected.docx'):
                verify_directory(folder)

    def test_both_alternate_branches_are_rejected(self):
        def duplicate(body):
            paragraph = ET.fromstring(f'<w:p xmlns:w="{W}"><w:r><w:t>UNSELECTED fallback</w:t></w:r></w:p>')
            body.insert(1, paragraph)
        self.change_body(duplicate)
        with self.assertRaisesRegex(AssertionError, 'Wrong branch'):
            verify_document(self.parts)

    def test_deleted_document_grid_is_rejected(self):
        def remove(body):
            section = body.find('w:sectPr', NS)
            section.remove(section.find('w:docGrid', NS))
        self.change_body(remove)
        with self.assertRaisesRegex(AssertionError, 'docGrid'):
            verify_document(self.parts)

    def test_reset_page_number_is_rejected(self):
        self.change_body(lambda body: body.find('w:p/w:pPr/w:sectPr/w:pgNumType', NS).set(f'{{{W}}}start', '1'))
        with self.assertRaisesRegex(AssertionError, 'pgNumType'):
            verify_document(self.parts)

    def test_lost_unknown_margin_attribute_is_rejected(self):
        self.change_body(lambda body: body.find('w:sectPr/w:pgMar', NS).attrib.pop(f'{{{W}}}gutter'))
        with self.assertRaisesRegex(AssertionError, 'pgMar'):
            verify_document(self.parts)

    def test_historical_section_overwrites_active_page_size_is_rejected(self):
        self.change_body(lambda body: body.find('w:p/w:pPr/w:sectPr/w:pgSz', NS).set(f'{{{W}}}w', '20000'))
        with self.assertRaisesRegex(AssertionError, 'pgSz'):
            verify_document(self.parts)

    def test_wrong_header_branch_is_rejected(self):
        self.parts['word/header-compat.xml'] = self.parts['word/header-compat.xml'].replace(
            b'Selected header fallback', b'UNSELECTED header')
        with self.assertRaisesRegex(AssertionError, 'Header branch'):
            verify_document(self.parts)

    def test_ignored_explicit_column_edit_is_rejected(self):
        with self.assertRaisesRegex(AssertionError, 'modeled .* edit'):
            verify_document(self.parts, edited=True)


if __name__ == '__main__':
    unittest.main()
