#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
import copy
import unittest
from PIL import Image

from table_borders_probe import colored_mask, compare_golden


class TableBorderGoldenTest(unittest.TestCase):
    def setUp(self):
        borders = [{'top': {'style': 'single', 'width': 8, 'color': 'FF0000'}}]
        mask = {'size': [4, 4], 'bounds': [0, 0, 4, 1],
                'pixelCount': 4, 'sha256': 'reviewed-pixels'}
        self.golden = {'cases': [{'name': 'row', 'sourceSha256': 'source',
                                  'borders': borders, 'coloredMask': mask}]}
        self.actual = [{'name': 'row', 'sourceSha256': 'source',
                        'nativeBorders': copy.deepcopy(borders),
                        'convertedBorders': copy.deepcopy(borders),
                        'sourceMask': dict(mask), 'convertedMask': dict(mask)}]

    def test_colored_mask_excludes_grayscale_text(self):
        image = Image.frombytes('RGB', (5, 1), bytes([
            0, 0, 0, 127, 127, 127, 255, 255, 255, 255, 0, 0, 0, 128, 0]))
        self.assertEqual(colored_mask(image), bytes([0, 0, 0, 255, 255]))

    def test_accepts_reviewed_native_and_converted_values(self):
        self.assertEqual(compare_golden(self.actual, self.golden), [])

    def test_rejects_lost_border_even_if_image_were_reused(self):
        self.actual[0]['convertedBorders'] = [{}]
        self.assertIn('row: convertedBorders', compare_golden(self.actual, self.golden))

    def test_rejects_changed_source_render_and_converted_pixels(self):
        self.actual[0]['nativeBorders'][0]['top']['width'] = 16
        self.actual[0]['convertedMask']['sha256'] = 'changed'
        failures = compare_golden(self.actual, self.golden)
        self.assertIn('row: nativeBorders', failures)
        self.assertIn('row: convertedMask', failures)

    def test_rejects_changed_source_bytes_missing_and_duplicate_cases(self):
        self.actual[0]['sourceSha256'] = 'changed'
        self.assertIn('row: source bytes changed', compare_golden(self.actual, self.golden))
        self.assertIn('fixture names differ', compare_golden([], self.golden))
        self.assertIn('fixture names differ', compare_golden(self.actual * 2, self.golden))


if __name__ == '__main__':
    unittest.main()
