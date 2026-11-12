# SPDX-License-Identifier: MPL-2.0
import copy
import unittest

from shape_render import check_geometry


class ShapeRenderTest(unittest.TestCase):
    def test_line_direction_cannot_hide_behind_identical_bounds(self):
        path = {'color': [0, 0, 0], 'fill': None, 'width': 2,
                'bounds': [6, 84, 78, 84],
                'items': [['l', [78, 84], [6, 84]]]}
        self.assertTrue(check_geometry('line-h-x', [path])['passes'])
        with self.assertRaises(ValueError):
            check_geometry('line-h-none', [path])
        missing = copy.deepcopy(path)
        missing['items'] = []
        with self.assertRaises(ValueError):
            check_geometry('line-h-x', [missing])

    def test_same_bounds_cannot_hide_the_native_coordinate_truncation(self):
        corners = [[6, 84], [78, 84], [78, 120], [6, 120]]
        path = {'color': [0, 0, 0], 'fill': [0.2, 0.4, 0.8], 'width': 2,
                'bounds': [6, 84, 78, 120],
                'items': [['l', point, corners[(index + 1) % 4]]
                          for index, point in enumerate(corners)]}
        self.assertTrue(check_geometry('rect', [path])['passes'])
        broken = copy.deepcopy(path)
        # Observed host parsing defect with whitespace after a VML command.
        broken['items'][0][2] = [13.2, 84]
        broken['items'][1][1] = [13.2, 84]
        with self.assertRaises(ValueError):
            check_geometry('rect', [broken])


if __name__ == '__main__':
    unittest.main()
