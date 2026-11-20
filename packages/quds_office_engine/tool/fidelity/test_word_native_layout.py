import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw

spec = importlib.util.spec_from_file_location('word_native_layout', Path(__file__).with_name('word_native_layout.py'))
layout = importlib.util.module_from_spec(spec)
spec.loader.exec_module(layout)


class NativeWordMetricTest(unittest.TestCase):
    def test_tab_fields_and_native_trailing_spaces_form_the_same_visual_row(self):
        native = [{'text': 'Right ', 'x': 140, 'y': 72},
                  {'text': 'Left ', 'x': 20, 'y': 72},
                  {'text': 'Next line ', 'x': 20, 'y': 90}]
        candidate = [{'text': 'Left\tRight', 'x': 20, 'y': 72},
                     {'text': 'Next line', 'x': 20, 'y': 90}]
        self.assertEqual(layout.visual_rows(native), layout.visual_rows(candidate))

    def test_row_normalization_does_not_hide_wrong_wraps_or_lost_words(self):
        native = [{'text': 'First word', 'x': 20, 'y': 72},
                  {'text': 'Second word', 'x': 20, 'y': 90}]
        for wrong in [[{'text': 'First word Second word', 'x': 20, 'y': 72}],
                      [{'text': 'First', 'x': 20, 'y': 72},
                       {'text': 'word Second word', 'x': 20, 'y': 90}],
                      [{'text': 'First word', 'x': 20, 'y': 72}]]:
            self.assertNotEqual(layout.visual_rows(native), layout.visual_rows(wrong))

    def page(self, shift=0, extra=False):
        page = Image.new('RGB', (200, 200), 'white')
        draw = ImageDraw.Draw(page)
        draw.rectangle((30 + shift, 30, 60 + shift, 40), fill='black')
        if extra:
            draw.rectangle((90, 90, 120, 110), fill='black')
        return page

    def test_same_ink_passes(self):
        self.assertEqual(layout.ink_score(self.page(), self.page())['f1'], 1)

    def test_fixed_one_pixel_tolerance(self):
        self.assertEqual(layout.ink_score(self.page(), self.page(shift=1))['f1'], 1)
        self.assertLess(layout.ink_score(self.page(), self.page(shift=12))['f1'], .95)

    def test_added_ink_lowers_precision(self):
        score = layout.ink_score(self.page(), self.page(extra=True))
        self.assertEqual(score['recall'], 1)
        self.assertLess(score['precision'], .95)

    def test_missing_ink_lowers_recall(self):
        score = layout.ink_score(self.page(extra=True), self.page())
        self.assertEqual(score['precision'], 1)
        self.assertLess(score['recall'], .95)

    def test_blank_whitespace_cannot_inflate_score(self):
        blank = Image.new('RGB', (200, 200), 'white')
        with self.assertRaises(ValueError):
            layout.ink_score(blank, blank)
        with self.assertRaises(ValueError):
            layout.ink_score(self.page(), blank)

    def test_page_size_is_not_rescaled_to_match(self):
        with self.assertRaises(ValueError):
            layout.ink_score(self.page(), Image.new('RGB', (201, 200), 'white'))

    def test_missing_and_empty_corpora_fail(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            with self.assertRaises(FileNotFoundError):
                layout.read_cases(path)
            (path / 'manifest.json').write_text('[]')
            with self.assertRaises(ValueError):
                layout.read_cases(path)

    def test_duplicate_and_unsafe_fixture_names_fail(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            for cases in [[{'name': '../outside'}], [{'name': 'case'}, {'name': 'case'}]]:
                (path / 'manifest.json').write_text(json.dumps(cases))
                with self.assertRaises(ValueError):
                    layout.read_cases(path)


if __name__ == '__main__':
    unittest.main()
