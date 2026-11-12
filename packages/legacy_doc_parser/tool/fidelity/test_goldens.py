# SPDX-License-Identifier: MPL-2.0
import copy
import json
from pathlib import Path
import shutil
import tempfile
import unittest

from goldens import MANIFEST, compare_golden, compare_render, load_goldens
from oracle import ROOT


class GoldenRegressionTest(unittest.TestCase):
    def setUp(self):
        self.catalog = load_goldens()
        self.expected = self.catalog['cases']['formatting']

    def compare(self, *, render=None, source=None, environment=None):
        return compare_golden('formatting', source or self.expected['source']['sha256'],
                              render or self.expected['expectedRender'],
                              environment or self.catalog['environment'], self.catalog)

    def test_reviewed_source_evidence_matches_only_the_identical_environment(self):
        self.assertEqual('matched', self.compare()['status'])
        for key in self.catalog['environment']:
            altered = {**self.catalog['environment'], key: 'different'}
            self.assertEqual('environment-mismatch', self.compare(environment=altered)['status'])
        missing = {**self.catalog['environment'], 'fontFilesSha256': None}
        self.assertEqual('environment-mismatch', self.compare(environment=missing)['status'])
        self.assertEqual('source-mismatch', self.compare(source='0' * 64)['status'])

    def test_same_text_with_changed_color_raster_or_position_is_not_exact(self):
        original = self.expected['expectedRender']
        for key, value in [('rasterSha256', ['0' * 64]), ('rasterDpi', 96),
                           ('rasterColorSpace', 'Gray')]:
            changed = {**original, key: value}
            self.assertFalse(compare_render(original, changed)['exactOnThisRenderer'])
        changed = copy.deepcopy(original)
        changed['pages'][0]['words'][0]['box'][0] += 0.01
        comparison = self.compare(render=changed)
        self.assertTrue(comparison['matchesWithinTolerance'])
        self.assertEqual('different', comparison['status'])

    def test_unreviewed_cases_and_legacy_gray_records_are_never_certified(self):
        self.assertEqual({'status': 'not-recorded'}, compare_golden(
            'unreviewed', 'unused', {}, {}, self.catalog))
        gray = {**self.expected['expectedRender'], 'rasterColorSpace': 'Gray'}
        self.assertFalse(compare_render(gray, gray)['exactOnThisRenderer'])

    def test_tampered_review_images_and_converter_provenance_are_rejected(self):
        with tempfile.TemporaryDirectory(prefix='source-golden-', dir=ROOT) as temporary:
            root = Path(temporary)
            manifest = json.loads((ROOT / MANIFEST).read_text())
            files = [MANIFEST]
            for case in manifest['cases']:
                files += [case['source']['path'], case['render']['path']]
                files += [image['path'] for image in case['images']]
            for name in files:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / name, target)
            image = root / manifest['cases'][0]['images'][0]['path']
            original = image.read_bytes()
            image.write_bytes(original + b'changed')
            with self.assertRaisesRegex(ValueError, 'artifact changed'):
                load_goldens(root)
            image.write_bytes(original)
            manifest['cases'][0]['origin'] = 'converter-output'
            (root / MANIFEST).write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, 'Converter output'):
                load_goldens(root)


if __name__ == '__main__':
    unittest.main()
