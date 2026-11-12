import shutil
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from zipfile import ZipFile

import bookmarks_oracle as oracle


class BookmarkOracleControls(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)

    def mutate(self, operation, part='word/document.xml'):
        target = self.folder / 'mutant.docx'
        with ZipFile(oracle.SOURCE) as source, ZipFile(target, 'w') as output:
            for name in source.namelist():
                payload = source.read(name)
                if name == part:
                    root = ET.fromstring(payload)
                    operation(root)
                    payload = ET.tostring(root)
                output.writestr(name, payload)
        return target

    def test_authored_positive(self):
        oracle.verify_file(oracle.SOURCE)

    def test_missing_endpoint(self):
        def remove(root):
            for parent in root.iter():
                for child in list(parent):
                    if child.tag == '{' + oracle.W + '}bookmarkEnd':
                        parent.remove(child)
                        return
        with self.assertRaises(AssertionError):
            oracle.verify_file(self.mutate(remove))

    def test_expanded_range(self):
        def expand(root):
            paragraph = root.findall('.//w:p', oracle.NS)[1]
            end = paragraph.find('w:bookmarkEnd', oracle.NS)
            paragraph.remove(end)
            paragraph.append(end)
        with self.assertRaises(AssertionError):
            oracle.verify_file(self.mutate(expand))

    def test_renamed_and_reidentified_range(self):
        for attribute, value in [('name', 'WrongName'), ('id', '999')]:
            with self.subTest(attribute=attribute):
                def replace(root):
                    root.find('.//w:bookmarkStart', oracle.NS).set('{' + oracle.W + '}' + attribute, value)
                with self.assertRaises(AssertionError):
                    oracle.verify_file(self.mutate(replace))

    def test_duplicate_endpoint(self):
        def duplicate(root):
            paragraph = root.findall('.//w:p', oracle.NS)[1]
            start = paragraph.find('w:bookmarkStart', oracle.NS)
            paragraph.insert(1, ET.fromstring(ET.tostring(start)))
        with self.assertRaises(AssertionError):
            oracle.verify_file(self.mutate(duplicate))

    def test_column_attributes_not_discarded(self):
        def remove(root):
            for start in root.findall('.//w:bookmarkStart', oracle.NS):
                start.attrib.pop('{' + oracle.W + '}colFirst', None)
        with self.assertRaises(AssertionError):
            oracle.verify_file(self.mutate(remove))

    def test_header_and_note_ranges_are_checked(self):
        def rename(root):
            root.find('.//w:bookmarkStart', oracle.NS).set('{' + oracle.W + '}name', 'WrongStory')
        for part in ['word/header1.xml', 'word/footnotes.xml', 'word/endnotes.xml']:
            with self.subTest(part=part), self.assertRaises(AssertionError):
                oracle.verify_file(self.mutate(rename, part))

    def test_missing_corpus_fails_closed(self):
        with self.assertRaises(AssertionError):
            oracle.verify_corpus(self.folder)

    def test_partial_and_unexpected_corpus_fail_closed(self):
        shutil.copyfile(oracle.SOURCE, self.folder / 'bookmarks-source.docx')
        with self.assertRaises(AssertionError):
            oracle.verify_corpus(self.folder)
        shutil.copyfile(oracle.SOURCE, self.folder / 'unexpected.docx')
        with self.assertRaises(AssertionError):
            oracle.verify_corpus(self.folder)

    def test_missing_editor_corpus_fails_closed(self):
        with self.assertRaises(AssertionError):
            oracle.verify_editor_corpus(self.folder)

    def test_unchanged_input_is_not_a_valid_editor_transition(self):
        with self.assertRaises(AssertionError):
            oracle.verify_editor_file(oracle.SOURCE)


if __name__ == '__main__':
    unittest.main()
