"""Controls against reporting incomplete/wrong-source LCOV as host coverage."""
from pathlib import Path
import tempfile
import unittest
from office_host_coverage import report_coverage, require_all_sources


class HostCoverageControls(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in ('lib/widgets/office_editor_dialog.dart', 'lib/services/office_document_service.dart'):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('one\ntwo\nthree\n')

    def test_merges_records_without_doubling_denominator_and_lists_absent_files(self):
        result = report_coverage(
            'SF:lib/widgets/office_editor_dialog.dart\nDA:1,0\nDA:2,2\nLF:2\nLH:1\nend_of_record\n'
            f'SF:{self.root}/lib/widgets/office_editor_dialog.dart\nDA:1,1\nDA:3,0\nLF:2\nLH:1\nend_of_record\n',
            self.root)
        self.assertEqual((result['covered_lines'], result['instrumented_lines']), (2, 3))
        self.assertEqual(result['files'][0]['uncovered_lines'], [3])
        self.assertEqual(result['uninstrumented_files'], ['lib/services/office_document_service.dart'])
        self.assertEqual(len(result['source_sha256']), 2)

    def test_empty_or_wrong_scope_cannot_pass(self):
        for data in ('', 'SF:lib/main.dart\nDA:1,1\n', 'SF:/outside/office_editor_dialog.dart\nDA:1,1\n'):
            with self.subTest(data=data), self.assertRaisesRegex(ValueError, 'No Office host line'):
                report_coverage(data, self.root)

    def test_invalid_and_stale_line_numbers_fail(self):
        for record in ('DA:0,1', 'DA:1,-1', 'DA:4,1', 'DA:1'):
            with self.subTest(record=record), self.assertRaises(ValueError):
                report_coverage('SF:lib/widgets/office_editor_dialog.dart\n' + record
                                + '\nLF:1\nLH:1\nend_of_record\n', self.root)

    def test_incomplete_or_contradictory_scoped_records_cannot_look_fully_covered(self):
        first = 'SF:lib/widgets/office_editor_dialog.dart\nDA:1,1\nLF:1\nLH:1\nend_of_record\n'
        second = 'SF:lib/services/office_document_service.dart\nDA:1,1\nLF:1\nLH:1\nend_of_record\n'
        for data in (
                first.replace('LF:1\nLH:1', 'LF:100\nLH:100') + second,
                first + second.removesuffix('end_of_record\n'),
                first.removesuffix('end_of_record\n') + second,
                first + second.replace('LF:1\n', ''),
                first + second.replace('LH:1\n', ''),
                first + second.replace('LH:1\n', 'LH:0\n'),
                first + second.replace('LF:1\n', 'LF:1\nLF:1\n'),
                first + second.replace('DA:1,1\n', 'DA:1,1\nDA:1,1\n'),
                first + second.replace('DA:1,1\n', 'DA:1,1,checksum,extra\n')):
            with self.subTest(data=data), self.assertRaises(ValueError):
                require_all_sources(report_coverage(data, self.root))

    def test_source_fingerprint_changes_with_uninstrumented_source(self):
        lcov = 'SF:lib/widgets/office_editor_dialog.dart\nDA:1,1\nLF:1\nLH:1\nend_of_record\n'
        before = report_coverage(lcov, self.root)
        (self.root / 'lib/services/office_document_service.dart').write_text('changed\n')
        after = report_coverage(lcov, self.root)
        self.assertNotEqual(before['source_tree_sha256'], after['source_tree_sha256'])

    def test_gate_rejects_an_instrumented_subset_but_keeps_the_gap_report(self):
        lcov = 'SF:lib/widgets/office_editor_dialog.dart\nDA:1,1\nLF:1\nLH:1\nend_of_record\n'
        report = report_coverage(lcov, self.root)
        with self.assertRaisesRegex(ValueError, 'lib/services/office_document_service.dart'):
            require_all_sources(report)
        self.assertEqual(report['covered_lines'], 1)

    def test_gate_accepts_every_source_without_claiming_every_line_is_hit(self):
        report = report_coverage(
            'SF:lib/widgets/office_editor_dialog.dart\nDA:1,0\nLF:1\nLH:0\nend_of_record\n'
            'SF:lib/services/office_document_service.dart\nDA:2,1\nLF:1\nLH:1\nend_of_record\n', self.root)
        require_all_sources(report)
        self.assertEqual(report['covered_lines'], 1)
        self.assertEqual(report['instrumented_lines'], 2)

    def test_new_office_host_helper_cannot_silently_disappear_from_instrumentation(self):
        helper = 'lib/services/office_new_feature.dart'
        (self.root / helper).write_text('capture\nvalidate\n')
        original_scope = (
            'SF:lib/widgets/office_editor_dialog.dart\nDA:1,1\nLF:1\nLH:1\nend_of_record\n'
            'SF:lib/services/office_document_service.dart\nDA:1,1\nLF:1\nLH:1\nend_of_record\n')
        incomplete = report_coverage(original_scope, self.root)
        self.assertEqual(incomplete['uninstrumented_files'], [helper])
        self.assertIn(helper, incomplete['source_sha256'])
        with self.assertRaisesRegex(ValueError, 'office_new_feature.dart'):
            require_all_sources(incomplete)
        complete = report_coverage(
            original_scope + f'SF:{helper}\nDA:1,1\nDA:2,0\nLF:2\nLH:1\nend_of_record\n',
            self.root)
        require_all_sources(complete)
        details = next(file for file in complete['files'] if file['path'] == helper)
        self.assertEqual(details['uncovered_lines'], [2])

    def test_report_declares_migrated_engine_scope_without_counting_it_as_host(self):
        report = report_coverage(
            'SF:lib/widgets/office_editor_dialog.dart\nDA:1,1\nLF:1\nLH:1\nend_of_record\n'
            'SF:lib/services/office_document_service.dart\nDA:1,1\nLF:1\nLH:1\nend_of_record\n', self.root)
        self.assertEqual(len(report['migrated_engine_sources']), 6)
        self.assertIn('packages/quds_office_engine/lib/src/opc/office_package_parts.dart', report['migrated_engine_sources'])
        self.assertIn('packages/quds_office_engine/lib/src/extract/office_search_text.dart', report['migrated_engine_sources'])
        self.assertIn('packages/quds_office_engine/lib/src/word/legacy/legacy_word_conversion.dart', report['migrated_engine_sources'])
        self.assertIn('not directly comparable', report['scope_note'])
        self.assertEqual(report['scope'], [
            'lib/services/office_*.dart', 'lib/widgets/office_*.dart',
            'lib/services/legacy_word_copy_target.dart',
            'lib/widgets/legacy_word_conversion_action.dart',
            'lib/widgets/legacy_word_conversion_dialog.dart',
        ])
        require_all_sources(report)

    def test_conversion_ui_without_office_prefix_is_required_and_fingerprinted(self):
        helper = 'lib/widgets/legacy_word_conversion_dialog.dart'
        (self.root / helper).write_text('disclose\nconvert\nsave\n')
        lcov = (
            'SF:lib/widgets/office_editor_dialog.dart\nDA:1,1\nLF:1\nLH:1\nend_of_record\n'
            'SF:lib/services/office_document_service.dart\nDA:1,1\nLF:1\nLH:1\nend_of_record\n')
        incomplete = report_coverage(lcov, self.root)
        self.assertEqual(incomplete['uninstrumented_files'], [helper])
        with self.assertRaisesRegex(ValueError, 'legacy_word_conversion_dialog.dart'):
            require_all_sources(incomplete)
        complete = report_coverage(
            lcov + f'SF:{helper}\nDA:1,1\nDA:2,0\nLF:2\nLH:1\nend_of_record\n', self.root)
        require_all_sources(complete)
        (self.root / helper).write_text('disclose differently\nconvert\nsave\n')
        changed = report_coverage(lcov, self.root)
        self.assertNotEqual(incomplete['source_tree_sha256'], changed['source_tree_sha256'])


if __name__ == '__main__':
    unittest.main()
