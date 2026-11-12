"""Mutation controls must first accept their independently specified baseline."""
import copy
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET
from zipfile import ZipFile

import word_structure_oracle as oracle


class WordStructureOracleControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.parts = {}
        for phase in ('create', 'edit', 'remove'):
            path = oracle.ROOT / 'build/fidelity-structure' / phase / 'edited.docx'
            with ZipFile(path) as package:
                cls.parts[phase] = {name: package.read(name) for name in package.namelist()}
            oracle.verify_parts(cls.parts[phase], phase)

    def reject(self, phase, part, mutate):
        parts = copy.deepcopy(self.parts[phase])
        root = ET.fromstring(parts[part])
        mutate(root)
        parts[part] = ET.tostring(root)
        with self.assertRaises(AssertionError):
            oracle.verify_parts(parts, phase)

    def test_all_twelve_outputs_pass_the_authored_oracle(self):
        self.assertEqual(oracle.verify(oracle.ROOT/'build/fidelity-structure')['files_verified'], 12)

    def test_comment_text_corruption_fails(self):
        self.reject('create', 'word/comments.xml', lambda r: setattr(r.find('.//w:t', oracle.NS), 'text', 'lost'))

    def test_comment_anchor_corruption_fails(self):
        def change(r):
            r.find('.//w:commentRangeStart', oracle.NS).set('{'+oracle.NS['w']+'}id', '99')
        self.reject('create', 'word/document.xml', change)

    def test_dangling_comment_reference_fails(self):
        self.reject('create', 'word/document.xml', lambda r:
                    r.find('.//w:commentReference', oracle.NS).set('{'+oracle.NS['w']+'}id', '999'))

    def test_missing_comment_endpoint_fails(self):
        def change(r):
            for p in r.findall('.//w:p', oracle.NS):
                for end in p.findall('w:commentRangeEnd', oracle.NS):
                    p.remove(end)
        self.reject('create', 'word/document.xml', change)

    def test_reply_parent_corruption_fails(self):
        def change(r):
            r.findall('w15:commentEx', oracle.NS)[1].set('{'+oracle.NS['w15']+'}paraIdParent', 'FFFFFFFF')
        self.reject('create', 'word/commentsExtended.xml', change)

    def test_resolved_state_loss_fails(self):
        self.reject('edit', 'word/commentsExtended.xml', lambda r: r[0].set('{'+oracle.NS['w15']+'}done', '0'))

    def test_duplicate_comment_metadata_fails(self):
        self.reject('create', 'word/commentsExtended.xml', lambda r: r.append(copy.deepcopy(r[0])))

    def test_reference_field_loss_fails(self):
        self.reject('create', 'word/document.xml', lambda r: setattr(r.find('.//w:instrText', oracle.NS), 'text', 'REF Missing'))

    def test_reference_field_boundary_loss_fails(self):
        def change(r):
            reference = r.find('w:body', oracle.NS).findall('w:p', oracle.NS)[2]
            for run in reference.findall('w:r', oracle.NS):
                for boundary in run.findall('w:fldChar', oracle.NS):
                    run.remove(boundary)
        self.reject('create', 'word/document.xml', change)

    def test_missing_toc_field_end_fails(self):
        def change(r):
            boundary = r.findall('.//w:fldChar', oracle.NS)[-1]
            for parent in r.iter():
                if boundary in list(parent):
                    parent.remove(boundary)
        self.reject('create', 'word/document.xml', change)

    def test_drawing_coordinate_drift_fails(self):
        def change(r):
            frame = next(a for a in r.findall('.//wp:anchor', oracle.NS) if a.find('.//wps:wsp', oracle.NS) is not None)
            frame.find('wp:positionH/wp:posOffset', oracle.NS).text = '0'
        self.reject('create', 'word/document.xml', change)

    def test_picture_wrap_drift_fails(self):
        def change(r):
            picture = next(a for a in r.findall('.//wp:anchor', oracle.NS) if a.find('.//pic:pic', oracle.NS) is not None)
            picture.set('distL', '114300')
        self.reject('create', 'word/document.xml', change)

    def test_picture_relationship_with_wrong_type_fails(self):
        def change(r):
            picture = next(rel for rel in r if rel.get('Type', '').endswith('/image'))
            picture.set('Type', oracle.NS['r'] + '/hyperlink')
        self.reject('create', 'word/_rels/document.xml.rels', change)

    def test_table_merge_loss_fails(self):
        self.reject('edit', 'word/document.xml', lambda r: r.find('.//w:gridSpan', oracle.NS).set('{'+oracle.NS['w']+'}val', '1'))

    def test_numeric_table_direction_is_schema_invalid(self):
        # bidiVisual is OnOffOnlyType: numeric boolean values are not allowed.
        self.reject('create', 'word/document.xml', lambda r:
                    r.find('.//w:bidiVisual', oracle.NS).set('{'+oracle.NS['w']+'}val', '1'))

    def test_disabled_row_cant_split_fails(self):
        self.reject('create', 'word/document.xml', lambda r:
                    r.find('.//w:cantSplit', oracle.NS).set('{'+oracle.NS['w']+'}val', '0'))

    def test_explicit_spacing_loss_fails(self):
        def change(r):
            p = r.find('w:body', oracle.NS).findall('w:p', oracle.NS)[1]
            p.find('w:pPr/w:spacing', oracle.NS).set('{'+oracle.NS['w']+'}after', '160')
        self.reject('edit', 'word/document.xml', change)

    def test_toc_switch_loss_fails(self):
        def change(r):
            for instr in r.findall('.//w:instrText', oracle.NS):
                if (instr.text or '').strip().startswith('TOC '):
                    instr.text = instr.text.replace('\\n', '')
        self.reject('edit', 'word/document.xml', change)

    def test_toc_link_to_missing_bookmark_fails(self):
        self.reject('create', 'word/document.xml', lambda r:
                    r.find('.//w:hyperlink', oracle.NS).set('{'+oracle.NS['w']+'}anchor', 'MissingBookmark'))

    def test_toc_link_to_wrong_existing_bookmark_fails(self):
        self.reject('create', 'word/document.xml', lambda r:
                    r.find('.//w:hyperlink', oracle.NS).set('{'+oracle.NS['w']+'}anchor', 'Evidence'))

    def test_toc_link_removed_but_text_retained_fails(self):
        def change(r):
            for p in r.findall('.//w:p', oracle.NS):
                link = p.find('w:hyperlink', oracle.NS)
                if link is not None:
                    index = list(p).index(link)
                    p.remove(link)
                    for child in reversed(list(link)):
                        p.insert(index, child)
                    return
        self.reject('create', 'word/document.xml', change)

    def test_duplicate_heading_bookmark_fails(self):
        def change(r):
            starts = r.findall('.//w:bookmarkStart', oracle.NS)
            starts[-1].set('{'+oracle.NS['w']+'}name', oracle.attr(starts[0], 'name'))
        self.reject('create', 'word/document.xml', change)

    def test_missing_heading_bookmark_end_fails(self):
        def change(r):
            p = r.find('w:body', oracle.NS).findall('w:p', oracle.NS)[0]
            p.remove(p.find('w:bookmarkEnd', oracle.NS))
        self.reject('create', 'word/document.xml', change)

    def test_removed_comment_cannot_reappear(self):
        parts = copy.deepcopy(self.parts['remove'])
        parts['word/comments.xml'] = self.parts['create']['word/comments.xml']
        with self.assertRaises(AssertionError):
            oracle.verify_parts(parts, 'remove')


if __name__ == '__main__':
    unittest.main()
