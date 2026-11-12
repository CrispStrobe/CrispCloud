#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
import copy
import unittest

from table_width_probe import compare_golden


class TableWidthGoldenTest(unittest.TestCase):
    def setUp(self):
        point = {'page': 1, 'xMin': 72, 'yMin': 72, 'xMax': 110, 'yMax': 84}
        native = [{'grid': [2400], 'cells': [{'widthType': 'dxa', 'width': '2400',
                                             'noWrap': False}]}]
        converted = [{'grid': [2400], 'cells': [{'widthType': 'auto', 'width': '0',
                                                'noWrap': True}]}]
        self.golden = {'cases': [{
            'name': 'auto', 'sourceSha256': 'source', 'native': native,
            'converted': converted, 'layout': {'pages': 1, 'words': {'CELL': point}},
        }]}
        self.actual = [{
            **copy.deepcopy(self.golden['cases'][0]),
            'sourceLayout': {'pages': 1, 'words': {'CELL': dict(point)}},
            'convertedLayout': {'pages': 1, 'words': {'CELL': dict(point)}},
        }]

    def test_separate_expected_native_loss_and_preserved_output_can_pass(self):
        self.assertEqual(compare_golden(self.actual, self.golden), [])

    def test_rejects_copying_lossy_native_projection_even_with_identical_pixels(self):
        self.actual[0]['converted'] = copy.deepcopy(self.actual[0]['native'])
        self.assertIn('auto: converted properties', compare_golden(self.actual, self.golden))

    def test_rejects_native_change_and_source_replacement(self):
        self.actual[0]['native'][0]['cells'][0]['width'] = '1200'
        self.actual[0]['sourceSha256'] = 'replaced'
        failures = compare_golden(self.actual, self.golden)
        self.assertIn('auto: native properties', failures)
        self.assertIn('auto: source bytes changed', failures)

    def test_rejects_layout_drift_missing_words_and_different_pages(self):
        self.actual[0]['sourceLayout']['words']['CELL']['xMin'] += 0.2
        self.actual[0]['convertedLayout']['words']['CELL']['page'] = 2
        failures = compare_golden(self.actual, self.golden)
        self.assertIn('auto: sourceLayout', failures)
        self.assertIn('auto: convertedLayout', failures)
        self.actual[0]['convertedLayout']['words'] = {}
        self.assertIn('auto: convertedLayout', compare_golden(self.actual, self.golden))

    def test_rejects_missing_and_duplicate_cases(self):
        self.assertIn('fixture names differ', compare_golden([], self.golden))
        self.assertIn('fixture names differ', compare_golden(self.actual * 2, self.golden))


if __name__ == '__main__':
    unittest.main()
