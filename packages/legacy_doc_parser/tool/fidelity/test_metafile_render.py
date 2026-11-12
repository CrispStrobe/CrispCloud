# SPDX-License-Identifier: MPL-2.0
import unittest

from metafile_render import color_name, fill_expectations


class MetafileRenderTest(unittest.TestCase):
    def test_native_samples_must_distinguish_a_hole_from_a_solid_center(self):
        self.assertTrue(fill_expectations('alternate', {'outer': 'black', 'center': 'white'})['passes'])
        self.assertTrue(fill_expectations('winding', {'outer': 'black', 'center': 'black'})['passes'])
        for mode, samples in [
            ('alternate', {'outer': 'black', 'center': 'black'}),
            ('winding', {'outer': 'black', 'center': 'white'}),
            ('alternate', {'outer': 'white', 'center': 'white'}),
        ]:
            with self.assertRaises(ValueError):
                fill_expectations(mode, samples)
        with self.assertRaises(ValueError):
            color_name((127, 127, 127))


if __name__ == '__main__':
    unittest.main()
