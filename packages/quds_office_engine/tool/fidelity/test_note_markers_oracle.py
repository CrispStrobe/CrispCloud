import copy
import unittest
import xml.etree.ElementTree as ET

import note_markers_oracle as oracle


class NoteMarkerOracleControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = oracle.ROOT/'build/fidelity-note-markers'
        cls.parts = oracle.read_parts(cls.root/'imported-1.docx')
        oracle.verify_parts(cls.parts, 'imported')

    def reject(self, mutate, part='word/footnotes.xml'):
        parts = copy.deepcopy(self.parts)
        root = ET.fromstring(parts[part])
        mutate(root)
        parts[part] = ET.tostring(root)
        with self.assertRaises(AssertionError):
            oracle.verify_parts(parts, 'imported')

    def note(self, root, note_id):
        return root.find(f"w:footnote[@w:id='{note_id}']", oracle.NS)

    def test_source_and_nine_exports_pass_authored_expectations(self):
        self.assertEqual(oracle.verify(self.root)['files_verified'], 10)

    def test_invented_separator_definitions_fail(self):
        for kind in ('footnote', 'endnote'):
            for separator in sorted(oracle.SEPARATOR_TYPES):
                with self.subTest(kind=kind, separator=separator):
                    def inject(root):
                        note = ET.Element('{'+oracle.W+'}'+kind,
                                          {'{'+oracle.W+'}id': '-1',
                                           '{'+oracle.W+'}type': separator})
                        run = ET.SubElement(ET.SubElement(note, '{'+oracle.W+'}p'),
                                            '{'+oracle.W+'}r')
                        ET.SubElement(run, '{'+oracle.W+'}separator')
                        root.insert(0, note)
                    self.reject(inject, f'word/{kind}s.xml')

    def test_late_marker_moved_to_first_paragraph_fails(self):
        def change(root):
            note = self.note(root, 1)
            paras = note.findall('w:p', oracle.NS)
            run = paras[1].find('w:r', oracle.NS)
            paras[1].remove(run)
            paras[0].append(run)
        self.reject(change)

    def test_mid_run_marker_moved_to_prefix_fails(self):
        def change(root):
            p = self.note(root, 2).find('w:p', oracle.NS)
            run = next(r for r in p.findall('w:r', oracle.NS) if r.find('w:footnoteRef', oracle.NS) is not None)
            p.remove(run)
            p.insert(0, run)
        self.reject(change)

    def test_empty_marker_paragraph_lost_fails(self):
        def change(root):
            note = self.note(root, 3)
            note.remove(note.find('w:p', oracle.NS))
        self.reject(change)

    def test_nested_marker_moved_between_cells_fails(self):
        def change(root):
            cells = self.note(root, 4).findall('.//w:tc', oracle.NS)
            source = cells[1].find('w:p', oracle.NS)
            marker = next(r for r in source.findall('w:r', oracle.NS) if r.find('w:footnoteRef', oracle.NS) is not None)
            source.remove(marker)
            cells[0].find('w:p', oracle.NS).append(marker)
        self.reject(change)

    def test_absent_source_marker_injected_fails(self):
        def change(root):
            paragraph = self.note(root, 5).find('w:p', oracle.NS)
            run = ET.Element('{'+oracle.W+'}r')
            ET.SubElement(run, '{'+oracle.W+'}footnoteRef')
            paragraph.insert(0, run)
        self.reject(change)

    def test_duplicate_marker_collapsed_fails(self):
        def change(root):
            p = self.note(root, 6).find('w:p', oracle.NS)
            run = next(r for r in p.findall('w:r', oracle.NS) if r.find('w:footnoteRef', oracle.NS) is not None)
            p.remove(run)
        self.reject(change)

    def test_wrong_marker_kind_fails(self):
        self.reject(lambda r: setattr(r.find('.//w:footnoteRef', oracle.NS), 'tag', '{'+oracle.W+'}endnoteRef'))

    def test_marker_run_properties_drift_fails(self):
        self.reject(lambda r: r.find('.//w:color', oracle.NS).set('{'+oracle.W+'}val', 'FFFFFF'))

    def test_injected_rpr_on_unformatted_marker_fails(self):
        def change(root):
            run = self.note(root, 3).find('.//w:r', oracle.NS)
            run.insert(0, ET.Element('{'+oracle.W+'}rPr'))
        self.reject(change)

    def test_inserted_leading_paragraph_before_table_fails(self):
        self.reject(lambda r: self.note(r, 4).insert(0, ET.Element('{'+oracle.W+'}p')))

    def test_intentional_source_whitespace_removed_fails(self):
        def change(root):
            t = self.note(root, 5).find('.//w:t', oracle.NS)
            t.text = t.text.lstrip()
        self.reject(change)

    def test_note_body_reference_retargeted_fails(self):
        self.reject(lambda r: r.find('.//w:footnoteReference', oracle.NS).set('{'+oracle.W+'}id', '99'), 'word/document.xml')

    def test_note_relationship_retargeted_fails(self):
        def change(root):
            rel = next(r for r in root if r.get('Type', '').endswith('/footnotes'))
            rel.set('Target', 'missing.xml')
        self.reject(change, 'word/_rels/document.xml.rels')


if __name__ == '__main__':
    unittest.main()
