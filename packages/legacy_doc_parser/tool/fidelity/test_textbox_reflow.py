# SPDX-License-Identifier: MPL-2.0
import copy
import unittest

from textbox_reflow import MARKERS, frame_assignment, verify_placement, verify_relative_reflow, verify_resize


def pages(split):
    return [{'size': [612, 792], 'words': [
        {'text': text, 'box': [73 if index < split else 361,
                              73 + (index if index < split else index - split) * 14,
                              170 if index < split else 460,
                              85 + (index if index < split else index - split) * 14]}
        for index, text in enumerate(MARKERS)]}]


class TextboxReflowTest(unittest.TestCase):
    def test_common_translation_does_not_mask_absolute_placement_failure(self):
        small, large = pages(2), pages(4)
        shifted_small, shifted_large = copy.deepcopy(small), copy.deepcopy(large)
        for page in shifted_small + shifted_large:
            for word in page['words']:
                word['box'] = [number + 72 for number in word['box']]
        reflow = verify_relative_reflow(shifted_small, shifted_large, small, large)
        self.assertEqual([72, 72], reflow['translationFromAuthoredDocxPoints'])
        self.assertEqual(MARKERS[2:4], reflow['movedBack'])
        with self.assertRaises(ValueError):
            verify_placement(shifted_small, shifted_large)
        shifted_large[0]['words'][0]['box'][0] += 1
        with self.assertRaises(ValueError):
            verify_relative_reflow(shifted_small, shifted_large, small, large)

    def test_relative_reflow_still_checks_both_frame_positions(self):
        small, large = pages(2), pages(4)
        damaged = copy.deepcopy(large)
        for word in damaged[0]['words'][4:]:
            word['box'][0] += 145
            word['box'][2] += 145
        with self.assertRaises(ValueError):
            verify_relative_reflow(small, damaged, small, large)

    def test_real_positions_and_resize_are_required(self):
        self.assertEqual(MARKERS[2:4], verify_resize(pages(2), pages(4))['movedBack'])
        for before, after in ((pages(2), pages(2)), (pages(4), pages(2))):
            with self.assertRaises(ValueError):
                verify_resize(before, after)

    def test_lost_duplicated_or_unlinked_text_cannot_pass(self):
        lost = copy.deepcopy(pages(2))
        lost[0]['words'].pop()
        duplicated = copy.deepcopy(pages(2))
        duplicated[0]['words'].append(duplicated[0]['words'][0])
        for damaged in (lost, duplicated, pages(0), pages(8)):
            with self.assertRaises(ValueError):
                frame_assignment(damaged, 42)

    def test_overflow_wrong_order_and_additional_pages_fail(self):
        overflow = pages(2)
        overflow[0]['words'][1]['box'][3] = 120
        wrong_order = pages(2)
        wrong_order[0]['words'][0]['text'], wrong_order[0]['words'][1]['text'] = MARKERS[1], MARKERS[0]
        for damaged in (overflow, wrong_order, pages(2) * 2):
            with self.assertRaises(ValueError):
                frame_assignment(damaged, 42)


if __name__ == '__main__':
    unittest.main()
