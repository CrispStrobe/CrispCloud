# SPDX-License-Identifier: MPL-2.0
"""Adversarial checks for the independently authored section-review probe."""
import copy
from pathlib import Path
import tempfile
import unittest
import zipfile

from section_review_probe import SOURCE_SHA256, W, section_review, verify_parser_review


def authored_xml():
    # These values describe section_review_fixture.dart's authored DOC. They are
    # not loaded from parser/native output, nor from the probe's expectations.
    def properties(left, columns, kind):
        return (f'<w:type w:val="{kind}"/><w:pgSz w:w="12240" w:h="15840"/>'
                f'<w:pgMar w:left="{left}"/><w:cols w:num="{columns}"/>')

    def section(identifier, current, previous):
        return (f'<w:sectPr>{properties(*current)}<w:sectPrChange w:id="{identifier}" '
                'w:author="Alice" w:date="2026-11-12T08:45:00">'
                f'<w:sectPr>{properties(*previous)}</w:sectPr></w:sectPrChange></w:sectPr>')

    first = section(0, (2880, 2, 'nextPage'), (1440, 1, 'nextPage'))
    second = section(1, (1440, 1, 'nextPage'), (1440, 1, 'continuous'))
    return (f'<w:document xmlns:w="{W}"><w:body><w:p><w:pPr>{first}</w:pPr>'
            f'<w:r><w:t>First</w:t></w:r></w:p><w:p/>{second}</w:body></w:document>')


class SectionReviewProbeTest(unittest.TestCase):
    def snapshot(self, xml=None):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'authored.docx'
            with zipfile.ZipFile(path, 'w') as package:
                package.writestr('word/document.xml', xml or authored_xml())
            return section_review(path)

    def test_authored_current_and_rejected_states_are_enforced(self):
        review = self.snapshot()
        self.assertEqual(2, len(review['sections']))
        self.assertEqual(2, review['sectionRevisionCount'])
        receipt = verify_parser_review(review, SOURCE_SHA256)
        self.assertTrue(receipt['passed'])
        self.assertFalse(receipt['nativeOutputUsedAsExpected'])
        self.assertEqual(SOURCE_SHA256, receipt['sourceReceiptSha256'])

    def test_shared_native_and_parser_loss_cannot_become_a_golden(self):
        review = self.snapshot()
        for section in review['sections']:
            section['revision'] = None
            section['previous'] = None
        review['sectionRevisionCount'] = 0
        report = {'ours': review, 'nativeSource': copy.deepcopy(review),
                  'nativeConverted': copy.deepcopy(review)}
        self.assertEqual(report['ours'], report['nativeSource'])
        with self.assertRaises(ValueError):
            verify_parser_review(report['ours'], SOURCE_SHA256)

    def test_old_and_current_values_break_shift_and_metadata_are_checked(self):
        for index, state, element, attribute, wrong in (
                (0, 'current', 'pgMar', 'left', '1440'),
                (0, 'previous', 'pgMar', 'left', '2880'),
                (0, 'current', 'cols', 'num', '1'),
                (0, 'previous', 'cols', 'num', '2'),
                (1, 'current', 'type', 'val', 'continuous'),
                (1, 'previous', 'type', 'val', 'nextPage')):
            with self.subTest(index=index, state=state, element=element):
                review = self.snapshot()
                review['sections'][index][state][element][attribute] = wrong
                with self.assertRaises(ValueError):
                    verify_parser_review(review, SOURCE_SHA256)
        for key, wrong in (('author', 'Bob'), ('date', '2026-11-13T08:45:00'), ('id', '0')):
            with self.subTest(key=key):
                review = self.snapshot()
                review['sections'][1]['revision'][key] = wrong
                with self.assertRaises(ValueError):
                    verify_parser_review(review, SOURCE_SHA256)

    def test_source_receipt_mismatch_and_missing_previous_state_fail(self):
        with self.assertRaises(ValueError):
            verify_parser_review(self.snapshot(), '0' * 64)
        review = self.snapshot()
        review['sections'][0]['previous'] = None
        with self.assertRaises(ValueError):
            verify_parser_review(review, SOURCE_SHA256)

    def test_missing_or_duplicate_previous_section_is_not_silently_selected(self):
        xml = authored_xml()
        start = xml.index('<w:sectPrChange')
        previous_start = xml.index('<w:sectPr>', start)
        previous_end = xml.index('</w:sectPr>', previous_start) + len('</w:sectPr>')
        for previous in ('', xml[previous_start:previous_end] * 2):
            with self.assertRaises(ValueError):
                self.snapshot(xml[:previous_start] + previous + xml[previous_end:])


if __name__ == '__main__':
    unittest.main()
