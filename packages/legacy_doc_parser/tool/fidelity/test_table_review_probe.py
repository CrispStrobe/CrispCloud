# SPDX-License-Identifier: MPL-2.0
import copy
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile

from table_review_probe import W, check_render, project_review, read_document, row_state, verify_review


def authored():
    # Independent literal expectations; not built from the probe's constants.
    return ET.fromstring(f'''<w:document xmlns:w="{W[1:-1]}"
      xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
      xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml" mc:Ignorable="w14">
      <w:body><w:tbl><w:tr><w:trPr>
        <w:trHeight w:val="720" w:hRule="atLeast"/><w:cantSplit w:val="on"/>
        <w:trPrChange w:id="7" w:author="Alice" w:date="2026-11-12T08:45:00">
          <w:trPr><w:trHeight w:val="240" w:hRule="atLeast"/>
            <w:cantSplit w:val="off"/></w:trPr>
        </w:trPrChange>
      </w:trPr><w:tc><w:p><w:r><w:t>CELL</w:t></w:r></w:p></w:tc></w:tr>
      <w:tr><w:tc><w:p><w:r><w:t>NEXT</w:t></w:r></w:p></w:tc></w:tr>
      </w:tbl></w:body></w:document>''')


class TableReviewProbeTest(unittest.TestCase):
    def test_authored_before_and_after_states_are_enforced(self):
        result = verify_review(authored(), 'height')
        self.assertTrue(result['passed'])
        self.assertFalse(result['nativeOutputUsedAsExpected'])

    def test_shared_native_history_loss_is_rejected(self):
        document = authored()
        properties = document.find('.//' + W + 'trPr')
        properties.remove(properties.find(W + 'trPrChange'))
        with self.assertRaises(ValueError):
            verify_review(document, 'height')

    def test_wrong_old_current_metadata_and_parent_are_rejected(self):
        for old, tag, attribute, value in (
                (False, 'trHeight', 'val', '240'), (True, 'trHeight', 'val', '720'),
                (False, 'cantSplit', 'val', 'off'), (True, 'cantSplit', 'val', 'on')):
            document = authored()
            properties = document.find('.//' + W + 'trPr')
            if old:
                properties = properties.find(W + 'trPrChange/' + W + 'trPr')
            properties.find(W + tag).set(W + attribute, value)
            with self.subTest(old=old, tag=tag), self.assertRaises(ValueError):
                verify_review(document, 'height')
        for name, value in [('author', 'Bob'), ('date', '2026-11-13T08:45:00'), ('id', 'bad')]:
            document = authored()
            document.find('.//' + W + 'trPrChange').set(W + name, value)
            with self.subTest(name=name), self.assertRaises(ValueError):
                verify_review(document, 'height')
        document = authored()
        rows = document.findall('.//' + W + 'tr')
        properties = rows[0].find(W + 'trPr')
        rows[0].remove(properties)
        rows[1].insert(0, properties)
        with self.assertRaises(ValueError):
            verify_review(document, 'height')

    def test_other_revision_kinds_and_duplicate_properties_are_rejected(self):
        document = authored()
        ET.SubElement(document.find('.//' + W + 'p'), W + 'ins')
        with self.assertRaises(ValueError):
            verify_review(document, 'height')
        document = authored()
        properties = document.find('.//' + W + 'trPr')
        properties.append(copy.deepcopy(properties.find(W + 'trHeight')))
        with self.assertRaises(ValueError):
            verify_review(document, 'height')

    def test_projection_writes_copies_and_keeps_other_parts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'review.docx'
            xml = ET.tostring(authored(), encoding='unicode')
            # The unused ignorable prefix must survive a real XML rewrite.
            xml = xml.replace('>', ' xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml">', 1)
            with zipfile.ZipFile(source, 'w') as package:
                package.writestr('word/document.xml', xml)
                package.writestr('unchanged.bin', b'unchanged')
            before = source.read_bytes()
            for reject, height in [(False, 720), (True, 240)]:
                target = root / f'{reject}.docx'
                project_review(source, target, 'height', reject=reject)
                document = read_document(target)
                self.assertFalse(document.findall('.//' + W + 'trPrChange'))
                self.assertEqual(height, row_state(document.find('.//' + W + 'trPr'))[0])
                with zipfile.ZipFile(target) as package:
                    self.assertEqual(b'unchanged', package.read('unchanged.bin'))
                    self.assertIn(b'xmlns:w14=', package.read('word/document.xml'))
                with self.assertRaises(ValueError):
                    project_review(source, target, 'height', reject=reject)
            self.assertEqual(before, source.read_bytes())

    def test_geometry_gate_cannot_swallow_text_page_or_position_loss(self):
        good = {'referencePages': 1, 'actualPages': 1, 'pageDimensionsMatch': True,
                'pageTextMatches': True, 'maximumWordDriftPoints': 0.0}
        self.assertTrue(check_render(good))
        for key, value in [('referencePages', 0), ('actualPages', 2),
                           ('pageDimensionsMatch', False), ('pageTextMatches', False),
                           ('maximumWordDriftPoints', None), ('maximumWordDriftPoints', 0.101)]:
            with self.subTest(key=key):
                self.assertFalse(check_render({**good, key: value}))


if __name__ == '__main__':
    unittest.main()
