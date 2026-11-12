"""Independent negative controls for copied bookmark native XML."""
from __future__ import annotations

from pathlib import Path
import shutil
import tempfile
import unittest
import xml.etree.ElementTree as ET

import bookmark_copy_oracle as oracle

W, NS = oracle.W, oracle.NS


def marker(root, bookmark_id, start=True):
    kind = 'bookmarkStart' if start else 'bookmarkEnd'
    return next(node for node in root.findall('.//w:' + kind, NS)
                if oracle.attr(node, 'id') == bookmark_id)


def parent(root, node):
    return next(candidate for candidate in root.iter() if node in candidate)


class BookmarkCopyOracleControls(unittest.TestCase):
    def reject(self, change):
        root = oracle.authored_root(True)
        change(root)
        with self.assertRaises((AssertionError, ValueError)):
            oracle.verify_xml(ET.tostring(root), copied=True)

    def test_authored_source_and_reference_match_explicit_ranges(self):
        for copied in (False, True):
            oracle.verify_xml(ET.tostring(oracle.authored_root(copied)), copied=copied)

    def test_all_five_engine_packages_are_verified(self):
        self.assertEqual(oracle.verify(oracle.ROOT / 'build/fidelity-bookmark-copy')['files_verified'], 5)

    def test_tracked_native_reference_matches_authored_xml_intent(self):
        from zipfile import ZipFile
        with ZipFile(oracle.FIXTURES / 'bookmark_copy_expected.docx') as package:
            oracle.verify_xml(package.read('word/document.xml'), copied=True)

    def test_missing_independent_reference_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=oracle.ROOT / 'build') as temp:
            for path in (oracle.ROOT / 'build/fidelity-bookmark-copy').glob('*.docx'):
                if path.name != 'copied-expected.docx':
                    shutil.copyfile(path, Path(temp) / path.name)
            with self.assertRaises(AssertionError):
                oracle.verify(Path(temp))

    def test_duplicate_source_identity_is_rejected(self):
        def change(root):
            for start in (True, False):
                marker(root, '3', start).set('{' + W + '}id', '000')
        self.reject(change)

    def test_source_id_spelling_change_is_rejected(self):
        def change(root):
            for start in (True, False):
                marker(root, '000', start).set('{' + W + '}id', '0')
        self.reject(change)

    def test_duplicate_name_is_rejected(self):
        self.reject(lambda root: marker(root, '3').set('{' + W + '}name', 'Alpha'))

    def test_missing_copied_endpoint_is_rejected(self):
        self.reject(lambda root: parent(root, marker(root, '8', False)).remove(marker(root, '8', False)))

    def test_lost_native_column_metadata_is_rejected(self):
        self.reject(lambda root: marker(root, '3').attrib.pop('{' + W + '}colLast'))

    def test_lost_native_end_displacement_is_rejected(self):
        self.reject(lambda root: marker(root, '3', False).attrib.pop('{' + W + '}displacedByCustomXml'))

    def test_range_expansion_into_prefix_is_rejected(self):
        def change(root):
            start = marker(root, '3')
            paragraph = parent(root, start)
            paragraph.remove(start)
            paragraph.insert(0, start)
        self.reject(change)

    def test_retargeted_ref_is_rejected(self):
        self.reject(lambda root: root.findall('.//w:fldSimple', NS)[-1].set(
            '{' + W + '}instr', ' REF Alpha_copy3 '))

    def test_retargeted_hyperlink_is_rejected(self):
        self.reject(lambda root: root.findall('.//w:hyperlink', NS)[-1].set(
            '{' + W + '}anchor', 'Alpha_copy3'))

    def test_lost_copied_bold_format_is_rejected(self):
        def change(root):
            bold = root.findall('.//w:rPr/w:b', NS)[-1]
            parent(root, bold).remove(bold)
        self.reject(change)

    def test_missing_export_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=oracle.ROOT / 'build') as temp:
            source = oracle.ROOT / 'build/fidelity-bookmark-copy'
            for path in source.glob('*.docx'):
                if path.name != 'copied-3.docx':
                    shutil.copyfile(path, Path(temp) / path.name)
            with self.assertRaises(AssertionError):
                oracle.verify(Path(temp))

    def test_stale_extra_export_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=oracle.ROOT / 'build') as temp:
            source = oracle.ROOT / 'build/fidelity-bookmark-copy'
            for path in source.glob('*.docx'):
                shutil.copyfile(path, Path(temp) / path.name)
            shutil.copyfile(source / 'source.docx', Path(temp) / 'stale.docx')
            with self.assertRaises(AssertionError):
                oracle.verify(Path(temp))


if __name__ == '__main__':
    unittest.main()
