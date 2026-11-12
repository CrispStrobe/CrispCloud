#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
import copy
import unittest

from table_layout_probe import compare_golden


class TableLayoutGoldenTest(unittest.TestCase):
    def setUp(self):
        point = {'page': 2, 'xMin': 36, 'yMin': 36, 'xMax': 60, 'yMax': 48}
        self.golden = {'cases': [{
            'name': 'keep-row', 'sourceSha256': 'reviewed-source',
            'rows': [{'heightTwips': 720, 'heightRule': 'exact', 'cantSplit': True}],
            'layout': {'pages': 2, 'words': {'CELL': point}},
        }]}
        self.actual = [{
            'name': 'keep-row', 'sourceSha256': 'reviewed-source',
            'native': {'rows': [{'trHeight': {'val': '720', 'hRule': 'exact'},
                                 'cantSplit': {'val': True}}]},
            'converted': {'rows': [{'trHeight': {'val': '720', 'hRule': 'exact'},
                                    'cantSplit': {'val': True}}]},
            'sourceLayout': {'pages': 2, 'words': {'CELL': dict(point)}},
            'convertedLayout': {'pages': 2, 'words': {'CELL': dict(point)}},
        }]

    def test_accepts_matching_reviewed_source_and_output(self):
        self.assertEqual(compare_golden(self.actual, self.golden), [])

    def test_rejects_properties_even_when_pixels_still_match(self):
        self.actual[0]['converted']['rows'][0]['trHeight']['hRule'] = 'atLeast'
        self.assertIn('keep-row: converted row properties',
                      compare_golden(self.actual, self.golden))

    def test_rejects_changed_native_layout_and_parser_page_break(self):
        self.actual[0]['sourceLayout']['words']['CELL']['yMin'] += 1
        self.actual[0]['convertedLayout']['words']['CELL']['page'] = 1
        failures = compare_golden(self.actual, self.golden)
        self.assertIn('keep-row: sourceLayout CELL', failures)
        self.assertIn('keep-row: convertedLayout CELL', failures)

    def test_rejects_different_source_and_missing_case(self):
        self.actual[0]['sourceSha256'] = 'replaced'
        failures = compare_golden(self.actual, self.golden)
        self.assertIn('keep-row: source bytes changed', failures)
        missing = copy.deepcopy(self.golden)
        missing['cases'].append({**missing['cases'][0], 'name': 'missing'})
        self.assertIn('fixture names differ', compare_golden(self.actual, missing))


if __name__ == '__main__':
    unittest.main()
