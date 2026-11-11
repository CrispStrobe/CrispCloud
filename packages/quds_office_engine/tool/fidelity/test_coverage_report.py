"""Controls against incomplete, malformed or stale engine coverage reports."""
import json
from pathlib import Path
import tempfile
import unittest

from coverage_report import report_coverage


class CoverageReportControls(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.coverage = self.root / 'coverage'
        self.coverage.mkdir()
        for name in ('lib/src/word/document.dart', 'lib/src/sheet/workbook.dart'):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('one\ntwo\nthree\n')

    def write_coverage(self, items, name='one.json'):
        (self.coverage / name).write_text(json.dumps({'coverage': items}))

    def entry(self, hits, source='src/word/document.dart'):
        return {'source': 'package:quds_office_engine/' + source, 'hits': hits}

    def test_merges_records_without_doubling_denominator_and_lists_absent_files(self):
        self.write_coverage([self.entry([1, 0, 2, 2])])
        self.write_coverage([self.entry([1, 1, 3, 0])], 'two.json')
        result = report_coverage(self.coverage, self.root)
        self.assertEqual((result['covered_lines'], result['instrumented_lines']), (2, 3))
        self.assertEqual(result['files'][0]['uncovered_lines'], [3])
        self.assertEqual(result['uninstrumented_files'], ['lib/src/sheet/workbook.dart'])
        self.assertEqual(result['components']['word']['covered_lines'], 2)
        self.assertEqual(result['components']['sheet']['uninstrumented_files'],
                         ['lib/src/sheet/workbook.dart'])

    def test_empty_and_wrong_package_cannot_pass(self):
        for items in ([], [self.entry([])],
                      [{'source': 'package:other/document.dart', 'hits': [1, 1]}]):
            with self.subTest(items=items):
                self.write_coverage(items)
                with self.assertRaisesRegex(ValueError, 'No engine coverage'):
                    report_coverage(self.coverage, self.root)

    def test_malformed_or_stale_hit_pairs_fail(self):
        for hits in ([1], [0, 1], [1, -1], [4, 1], [True, 1], [1, 0.5], '1,1'):
            with self.subTest(hits=hits):
                self.write_coverage([self.entry(hits)])
                with self.assertRaises(ValueError):
                    report_coverage(self.coverage, self.root)

    def test_missing_or_traversing_source_cannot_pass(self):
        for source in ('src/word/removed.dart', '../elsewhere.dart'):
            with self.subTest(source=source):
                self.write_coverage([self.entry([1, 1], source)])
                with self.assertRaisesRegex(ValueError, 'missing or invalid engine source'):
                    report_coverage(self.coverage, self.root)

    def test_source_fingerprint_includes_uninstrumented_files(self):
        self.write_coverage([self.entry([1, 1])])
        before = report_coverage(self.coverage, self.root)
        (self.root / 'lib/src/sheet/workbook.dart').write_text('changed\n')
        after = report_coverage(self.coverage, self.root)
        self.assertNotEqual(before['source_tree_sha256'], after['source_tree_sha256'])


if __name__ == '__main__':
    unittest.main()
