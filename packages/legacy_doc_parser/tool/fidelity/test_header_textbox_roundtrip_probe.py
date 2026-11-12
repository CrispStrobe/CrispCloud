# SPDX-License-Identifier: MPL-2.0
import copy
import hashlib
import json
import unittest

from header_textbox_roundtrip_probe import verify_import
from oracle import ROOT


class HeaderRoundtripPredicatesTest(unittest.TestCase):
    def setUp(self):
        self.expected = ['ALPHA', '', 'BETA', '']
        self.observation = {
            'titlePage': True,
            'headers': {name: {'boxes': [{'paragraphs': self.expected[:]}]}
                        for name in ('default', 'first')},
            'unreferencedBoxes': [],
        }

    def test_two_independent_occurrences_pass(self):
        self.assertEqual(verify_import(self.observation, {'textboxes': 2}, self.expected), [])

    def test_missing_first_occurrence_fails_even_if_counts_claim_two(self):
        del self.observation['headers']['first']
        self.assertTrue(verify_import(self.observation, {'textboxes': 2}, self.expected))

    def test_count_loss_fails_even_with_matching_xml(self):
        self.assertTrue(verify_import(self.observation, {'textboxes': 1}, self.expected))
        self.assertTrue(verify_import(self.observation, {}, self.expected))

    def test_first_header_blank_loss_fails_independently(self):
        self.observation['headers']['first']['boxes'][0]['paragraphs'].pop()
        self.assertTrue(verify_import(self.observation, {'textboxes': 2}, self.expected))

    def test_changed_activation_or_extra_occurrence_fails(self):
        inactive = copy.deepcopy(self.observation)
        inactive['titlePage'] = False
        self.assertTrue(verify_import(inactive, {'textboxes': 2}, self.expected))
        self.observation['headers']['first']['boxes'].append({'paragraphs': self.expected[:]})
        self.assertTrue(verify_import(self.observation, {'textboxes': 2}, self.expected))

    def test_exact_failed_native_input_matches_retained_provenance(self):
        path = ROOT / 'test/fixtures/word_native/header-textbox-first-roundtrip.doc'
        expected = '8beb2137004158fe373f032be53cfbbd802b237b308aa87b1802a6f2a979973d'
        receipt = json.loads(path.with_suffix('.json').read_text())
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), expected)
        self.assertEqual(receipt['sha256'], expected)
        self.assertEqual(receipt['observations']['shapeIDs'], [1025, 1025])
        self.assertEqual(receipt['observations']['globalAnchorCPs'], [7, 10])


if __name__ == '__main__':
    unittest.main()
