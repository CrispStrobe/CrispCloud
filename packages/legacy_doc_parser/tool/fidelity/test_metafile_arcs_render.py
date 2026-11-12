# SPDX-License-Identifier: MPL-2.0
import unittest

from metafile_arcs_render import assert_colors, check_arcto_endpoint, check_bounds, color_name, expectations


class ArcOracleTests(unittest.TestCase):
    def test_expected_chord_and_pie_interiors_are_distinct(self):
        chord = expectations('chord', 'counterclockwise')
        pie = expectations('pie', 'counterclockwise')
        self.assertEqual(chord['innerUpper'], 'white')
        self.assertEqual(pie['innerUpper'], 'black')
        with self.assertRaises(ValueError):
            assert_colors('pie', 'counterclockwise', chord)

    def test_reversed_sweep_or_invented_fill_cannot_pass(self):
        with self.assertRaises(ValueError):
            assert_colors('chord', 'clockwise', expectations('chord', 'counterclockwise'))
        with self.assertRaises(ValueError):
            assert_colors('arc', 'full', expectations('chord', 'full'))

    def test_missing_extra_and_wrong_color_samples_are_rejected(self):
        for samples in [{}, {'upperCurve': 'red'},
                        dict(expectations('arc', 'full'), extra='white')]:
            with self.assertRaises(ValueError):
                assert_colors('arc', 'full', samples)
        with self.assertRaises(ValueError):
            color_name((255, 0, 255))

    def test_reference_geometry_does_not_fit_arbitrary_shape_bounds(self):
        check_bounds('arc', 'counterclockwise', [100, 10, 180, 50])
        for bounds in ([], [100, 10, 180], [float('nan'), 10, 180, 50],
                       [0, 0, 0, 0], [20, 10, 180, 90], [100, 10, 420, 50]):
            with self.assertRaises(ValueError):
                check_bounds('arc', 'counterclockwise', bounds)

    def test_arcto_requires_projected_current_point_and_ordered_endpoints(self):
        check_arcto_endpoint([100, 10, 20, 80])
        for line in ([100, -110, 20, 80], [20, 80, 100, 10], [150, 95, 20, 80], []):
            with self.assertRaises(ValueError):
                check_arcto_endpoint(line)


if __name__ == '__main__':
    unittest.main()
