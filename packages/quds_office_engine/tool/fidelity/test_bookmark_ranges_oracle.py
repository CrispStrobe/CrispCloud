"""Negative controls: semantic corruption must fail the independent oracle."""
from __future__ import annotations

import copy
from pathlib import Path
import shutil
import tempfile
import unittest
import xml.etree.ElementTree as ET

import bookmark_ranges_oracle as oracle

ROOT = oracle.ROOT/'build/fidelity-bookmarks'
W, NS = oracle.W, oracle.NS


def boundary(root, bookmark_id, start=True):
    kind = 'bookmarkStart' if start else 'bookmarkEnd'
    return next(node for node in root.findall('.//w:'+kind, NS)
                if oracle.attr(node, 'id') == bookmark_id)


def parent(root, node):
    return next(candidate for candidate in root.iter() if node in candidate)


class BookmarkOracleControls(unittest.TestCase):
    def reject(self, change, phase='imported', part='word/document.xml'):
        parts = oracle.read_parts(ROOT/f'{phase}-1.docx')
        root = ET.fromstring(parts[part])
        change(root)
        parts[part] = ET.tostring(root)
        with self.assertRaises((AssertionError, ValueError)):
            oracle.verify_parts(parts, phase)

    def reject_frame(self, change):
        parts = oracle.read_parts(ROOT/'frame-1.docx')
        root = ET.fromstring(parts['word/document.xml'])
        change(root)
        parts['word/document.xml'] = ET.tostring(root)
        with self.assertRaises((AssertionError, ValueError)):
            oracle.verify_frame_parts(parts)

    def test_all_fourteen_authored_packages_are_accepted(self):
        self.assertEqual(oracle.verify(ROOT)['files_verified'], 14)

    def test_missing_evidence_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=oracle.ROOT/'build') as path:
            for source in ROOT.glob('*.docx'):
                if source.name != 'cloned-3.docx':
                    shutil.copyfile(source, Path(path)/source.name)
            with self.assertRaises(AssertionError):
                oracle.verify(Path(path))

    def test_unexpected_evidence_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=oracle.ROOT/'build') as path:
            for source in ROOT.glob('*.docx'):
                shutil.copyfile(source, Path(path)/source.name)
            shutil.copyfile(ROOT/'source.docx', Path(path)/'stale.docx')
            with self.assertRaises(AssertionError):
                oracle.verify(Path(path))

    def test_missing_start_is_rejected(self):
        self.reject(lambda root: parent(root, boundary(root, '000')).remove(boundary(root, '000')))

    def test_missing_end_is_rejected(self):
        self.reject(lambda root: parent(root, boundary(root, '000', False)).remove(boundary(root, '000', False)))

    def test_wrong_endpoint_id_is_rejected(self):
        self.reject(lambda root: boundary(root, '000', False).set('{'+W+'}id', '999'))

    def test_id_spelling_loss_is_rejected(self):
        def change(root):
            for start in (True, False):
                boundary(root, '000', start).set('{'+W+'}id', '0')
        self.reject(change)

    def test_renamed_bookmark_is_rejected(self):
        self.reject(lambda root: boundary(root, '000').set('{'+W+'}name', 'Renamed'))

    def test_column_metadata_loss_is_rejected(self):
        self.reject(lambda root: boundary(root, '000').attrib.pop('{'+W+'}colFirst'))

    def test_end_displacement_metadata_loss_is_rejected(self):
        self.reject(lambda root: boundary(root, '000', False).attrib.pop('{'+W+'}displacedByCustomXml'))

    def test_expansion_into_prefix_is_rejected(self):
        def change(root):
            start = boundary(root, '000')
            paragraph = parent(root, start)
            paragraph.remove(start)
            paragraph.insert(1, start)
        self.reject(change)

    def test_expansion_into_suffix_is_rejected(self):
        def change(root):
            end = boundary(root, '000', False)
            paragraph = parent(root, end)
            paragraph.remove(end)
            paragraph.append(end)
        self.reject(change)

    def test_overlapping_end_order_change_is_rejected(self):
        def change(root):
            left, right = boundary(root, '13', False), boundary(root, '14', False)
            left.set('{'+W+'}id', '14')
            right.set('{'+W+'}id', '13')
        self.reject(change)

    def test_cross_paragraph_range_collapse_is_rejected(self):
        def change(root):
            end = boundary(root, '12', False)
            parent(root, end).remove(end)
            parent(root, boundary(root, '12')).append(end)
        self.reject(change)

    def test_empty_point_expansion_is_rejected(self):
        def change(root):
            end = boundary(root, '15', False)
            paragraph = parent(root, end)
            paragraph.remove(end)
            paragraph.append(end)
        self.reject(change)

    def test_emoji_endpoint_uses_utf16_units(self):
        snapshot = oracle.snapshot(ET.fromstring((oracle.FIXTURES/'bookmark_ranges.xml').read_bytes()))
        self.assertEqual(snapshot['ranges']['Emoji']['end'], [12, 9])
        self.assertEqual(oracle.utf16('🙂é'), 3)
        def change(root):
            end = boundary(root, '20', False)
            paragraph = parent(root, end)
            paragraph.remove(end)
            paragraph.insert(list(paragraph).index(boundary(root, '20')) + 1, end)
        self.reject(change)

    def test_duplicate_native_copy_is_rejected(self):
        self.reject(lambda root: root.find('w:body', NS).append(copy.deepcopy(parent(root, boundary(root, '000')))))

    def test_invented_range_in_unmarked_paragraph_is_rejected(self):
        def change(root):
            paragraph = root.findall('.//w:p', NS)[7]
            paragraph.insert(1, ET.Element('{'+W+'}bookmarkStart', {'{'+W+'}id': '999', '{'+W+'}name': 'Invented'}))
            paragraph.append(ET.Element('{'+W+'}bookmarkEnd', {'{'+W+'}id': '999'}))
        self.reject(change)

    def test_stale_ref_cache_is_rejected(self):
        self.reject(lambda root: setattr(root.findall('.//w:p', NS)[15].find('.//w:t', NS), 'text', 'Alpha'), phase='edited')

    def test_wrong_ref_target_is_rejected(self):
        self.reject(lambda root: setattr(root.findall('.//w:p', NS)[15].find('.//w:instrText', NS), 'text', ' REF Beta '), phase='edited')

    def test_empty_ref_cache_cannot_be_fabricated(self):
        def change(root):
            paragraph = root.findall('.//w:p', NS)[18]
            run = ET.Element('{'+W+'}r')
            ET.SubElement(run, '{'+W+'}t').text = 'EmptyPoint'
            paragraph.insert(len(paragraph) - 1, run)
        self.reject(change, phase='edited')

    def test_unclosed_native_ref_is_rejected(self):
        def change(root):
            paragraph = root.findall('.//w:p', NS)[15]
            end = next(node for node in paragraph.findall('.//w:fldChar', NS)
                       if oracle.attr(node, 'fldCharType') == 'end')
            parent(root, end).remove(end)
        self.reject(change, phase='edited')

    def test_hyperlink_relationship_target_change_is_rejected(self):
        def change(root):
            next(rel for rel in root if rel.get('Type') == oracle.R+'/hyperlink').set('Target', 'https://wrong.example/')
        self.reject(change, part='word/_rels/document.xml.rels')

    def test_textbox_text_cannot_enter_body_ref_cache(self):
        def change(root):
            paragraph = root.find('w:body', NS).findall('w:p', NS)[3]
            paragraph.find('.//w:t', NS).text = 'Body before\nTextbox content\nBody after'
        self.reject_frame(change)

    def test_body_anchor_paragraph_break_cannot_disappear(self):
        def change(root):
            paragraph = root.find('w:body', NS).findall('w:p', NS)[3]
            br = paragraph.find('.//w:br', NS)
            parent(root, br).remove(br)
        self.reject_frame(change)

    def test_textbox_endpoint_cannot_move_into_body(self):
        def change(root):
            box = root.find('.//w:txbxContent', NS)
            endpoint = box.find('.//w:bookmarkEnd', NS)
            parent(root, endpoint).remove(endpoint)
            root.find('w:body', NS).findall('w:p', NS)[2].append(endpoint)
        self.reject_frame(change)


if __name__ == '__main__':
    unittest.main()
