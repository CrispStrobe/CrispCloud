# SPDX-License-Identifier: MPL-2.0
import copy
import unittest
from oracle import ROOT, compare_layout, compare_semantics, load_corpus, snapshot


class OracleRegressionTest(unittest.TestCase):
    def test_pinned_corpus_is_not_replaced_with_converter_output(self):
        manifest = load_corpus()
        self.assertEqual(11, len(manifest['cases']))
        self.assertEqual('ca9853b5b08784beac50df5680176cb4e5b3cb25', manifest['sources']['quds']['commit'])
        for case in manifest['cases']:
            if case['path'].endswith('.docx'):
                self.assertTrue(snapshot(ROOT / case['path'])['stories'])

    def test_lost_story_image_and_last_table_are_detected(self):
        original = snapshot(ROOT / 'test/fixtures/fidelity/word.docx')
        damaged = copy.deepcopy(original)
        damaged['stories'] = [s for s in damaged['stories'] if s['kind'] == 'main']
        damaged['imageDigests'] = []
        damaged['counts']['tbl'] = 0
        keys = {d['property'] for d in compare_semantics(original, damaged)}
        self.assertTrue({'stories', 'imageDigests', 'counts.tbl'} <= keys)

    def test_relocated_thread_parts_are_followed(self):
        result = snapshot(ROOT / 'test/fixtures/fidelity/comment-threads.docx')
        self.assertEqual(3, result['counts']['comment'])
        self.assertEqual(1, result['counts']['commentThreads'])
        self.assertTrue(any('Reply arrived first' in story['text'] for story in result['stories']))

    def test_same_text_on_different_pages_is_not_exact_pagination(self):
        page = {'size': [612.0, 792.0], 'words': [{'text': 'Marker', 'box': [10., 20., 30., 40.]}]}
        self.assertFalse(compare_layout([page], [page, page])['matchesWithinTolerance'])
        changed = copy.deepcopy(page)
        changed['words'][0]['box'][1] += 1
        self.assertFalse(compare_layout([page], [changed])['matchesWithinTolerance'])
        changed['words'][0]['box'][1] -= .9
        self.assertTrue(compare_layout([page], [changed])['matchesWithinTolerance'])


if __name__ == '__main__':
    unittest.main()
