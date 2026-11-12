"""Destructive controls for the independent native section XML oracle."""
import copy
from pathlib import Path
import tempfile
import unittest
from xml.etree import ElementTree as E

import slide_sections_oracle as oracle


class SlideSectionOracleControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.parts = {scenario: oracle.read_zip(Path('build/fidelity-slide-sections/direct') / f'{scenario}-1.pptx')
                     for scenario in oracle.EXPECTED}
        for scenario, parts in cls.parts.items():
            oracle.inspect_parts(parts, scenario)

    def corrupt(self, change, scenario='forward'):
        parts = copy.deepcopy(self.parts[scenario])
        root = E.fromstring(parts['ppt/presentation.xml'])
        change(root)
        parts['ppt/presentation.xml'] = E.tostring(root)
        with self.assertRaises(AssertionError):
            oracle.inspect_parts(parts, scenario)

    def sections(self, root):
        return root.find(oracle.P + 'extLst/' + oracle.P + f'ext[@uri="{oracle.SECTION_URI}"]/' + oracle.Q + 'sectionLst')

    def test_changed_native_guid_is_rejected(self):
        self.corrupt(lambda root: self.sections(root)[1].set('id', '{00000000-0000-4000-8000-000000000001}'))

    def test_dropped_empty_section_is_rejected(self):
        self.corrupt(lambda root: self.sections(root).remove(self.sections(root)[2]))

    def test_wrong_section_order_is_rejected(self):
        self.corrupt(lambda root: self.sections(root).__setitem__(slice(None), list(reversed(self.sections(root)))))

    def test_stale_positional_membership_is_rejected(self):
        def change(root):
            sections = self.sections(root)
            E.SubElement(sections[1].find(oracle.Q + 'sldIdLst'), oracle.Q + 'sldId', id='907')
            members = sections[3].find(oracle.Q + 'sldIdLst')
            members.remove(members[0])
        self.corrupt(change)

    def test_wrong_within_section_order_is_rejected(self):
        def change(root):
            members = self.sections(root)[1].find(oracle.Q + 'sldIdLst')
            members[:] = list(reversed(members))
        self.corrupt(change, 'within')

    def test_wrong_slide_order_is_rejected(self):
        def change(root):
            slides = root.find(oracle.P + 'sldIdLst')
            slides[:] = list(reversed(slides))
        self.corrupt(change)

    def test_foreign_section_like_extension_loss_is_rejected(self):
        def change(root):
            extensions = root.find(oracle.P + 'extLst')
            extensions.remove(next(ext for ext in extensions if ext.find(oracle.DECOY + 'sectionLst') is not None))
        self.corrupt(change)

    def test_opaque_section_properties_loss_is_rejected(self):
        self.corrupt(lambda root: self.sections(root)[1].find('.//' + oracle.KEPT + 'property').set('token', 'lost'))

    def test_slide_relationship_ownership_drift_is_rejected(self):
        def change(root):
            slides = root.find(oracle.P + 'sldIdLst')
            slides[0].set(oracle.R + 'id', slides[1].get(oracle.R + 'id'))
        self.corrupt(change)

    def test_custom_show_identity_drift_is_rejected(self):
        self.corrupt(lambda root: root.find(oracle.P + 'custShowLst/' + oracle.P + 'custShow/' + oracle.P + 'sldLst')[0].set(
            oracle.R + 'id', root.find(oracle.P + 'sldIdLst')[0].get(oracle.R + 'id')))

    def test_opaque_package_part_loss_is_rejected(self):
        parts = copy.deepcopy(self.parts['forward'])
        parts['customXml/section-proof.xml'] = b'<lost/>'
        with self.assertRaises(AssertionError):
            oracle.inspect_parts(parts, 'forward')

    def test_note_ownership_drift_is_rejected(self):
        parts = copy.deepcopy(self.parts['forward'])
        root = E.fromstring(parts['ppt/notesSlides/notesSlide1.xml'])
        for node in root.iter(oracle.A + 't'):
            node.text = 'Other slide note'
        parts['ppt/notesSlides/notesSlide1.xml'] = E.tostring(root)
        with self.assertRaises(AssertionError):
            oracle.inspect_parts(parts, 'forward')

    def test_missing_cycles_cannot_satisfy_inventory(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(AssertionError, 'incomplete section corpus'):
                oracle.verify_directory(Path(directory))


if __name__ == '__main__':
    unittest.main()
