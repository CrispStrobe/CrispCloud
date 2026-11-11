"""Controls against reporting incomplete/wrong-source LCOV as host coverage."""
from pathlib import Path
import tempfile
import unittest
from office_host_coverage import report_coverage


class HostCoverageControls(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in ('lib/widgets/office_editor_dialog.dart', 'lib/services/office_search_text.dart'):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('one\ntwo\nthree\n')

    def test_merges_records_without_doubling_denominator_and_lists_absent_files(self):
        result = report_coverage(
            'SF:lib/widgets/office_editor_dialog.dart\nDA:1,0\nDA:2,2\nend_of_record\n'
            f'SF:{self.root}/lib/widgets/office_editor_dialog.dart\nDA:1,1\nDA:3,0\nend_of_record\n',
            self.root)
        self.assertEqual((result['covered_lines'], result['instrumented_lines']), (2, 3))
        self.assertEqual(result['files'][0]['uncovered_lines'], [3])
        self.assertEqual(result['uninstrumented_files'], ['lib/services/office_search_text.dart'])
        self.assertEqual(len(result['source_sha256']), 2)

    def test_empty_or_wrong_scope_cannot_pass(self):
        for data in ('', 'SF:lib/main.dart\nDA:1,1\n', 'SF:/outside/office_editor_dialog.dart\nDA:1,1\n'):
            with self.subTest(data=data), self.assertRaisesRegex(ValueError, 'No Office host line'):
                report_coverage(data, self.root)

    def test_invalid_and_stale_line_numbers_fail(self):
        for record in ('DA:0,1', 'DA:1,-1', 'DA:4,1', 'DA:1'):
            with self.subTest(record=record), self.assertRaises(ValueError):
                report_coverage('SF:lib/widgets/office_editor_dialog.dart\n' + record, self.root)

    def test_source_fingerprint_changes_with_uninstrumented_source(self):
        lcov = 'SF:lib/widgets/office_editor_dialog.dart\nDA:1,1\n'
        before = report_coverage(lcov, self.root)
        (self.root / 'lib/services/office_search_text.dart').write_text('changed\n')
        after = report_coverage(lcov, self.root)
        self.assertNotEqual(before['source_tree_sha256'], after['source_tree_sha256'])


if __name__ == '__main__':
    unittest.main()
