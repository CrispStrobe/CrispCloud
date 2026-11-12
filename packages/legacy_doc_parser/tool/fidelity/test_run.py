# SPDX-License-Identifier: MPL-2.0
"""Runner predicates and orchestration, without starting a native Office app."""
import copy
import json
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import run


def authored_state():
    return {'stories': [{'kind': 'main', 'text': 'Current result', 'textWithDeletions': 'Old Current result'}],
            'counts': {'sectPrChange': 1, 'footnoteTables': 1}, 'sections': [], 'imageDigests': [],
            'externalLinks': [], 'structure': {'reviewAuthor': 'Alice',
                                               'footnoteTables': [{'rows': [['CELL']]}]}}


def render_state():
    return {'pdfSha256': 'pdf', 'pages': [
        {'size': [612, 792], 'words': [{'text': 'Current', 'box': [10, 20, 50, 30]}]}],
        'text': 'Current', 'rasterSha256': ['raster'], 'rasterDpi': 72,
        'rasterColorSpace': 'RGB'}


class RunnerTest(unittest.TestCase):
    def measure(self, directory, *, cycles=3, lose_at_bridge=None, lose_at_parser=None,
                fail_at_parser=None, fail_render=None, source_suffix='.docx',
                shift_at_bridge=None, shift_at_parser=None, flatten_at_native_docx=None):
        root = Path(directory)
        source = root / ('authored' + source_suffix)
        source.write_text(json.dumps(authored_state()))
        case = {'id': 'authored', 'path': source.name, 'sha256': run.digest(source),
                'features': ['revisions']}
        args = SimpleNamespace(office=Path('/mock/office'), dpi=72,
                               no_roundtrip=False, roundtrip_cycles=cycles)
        calls = []

        def cycle_of(path):
            for part in path.parts:
                if part.startswith('roundtrip-'):
                    return int(part.split('-')[1])
            return 0

        def loss(state):
            state['counts']['sectPrChange'] = 0
            state['structure'].pop('reviewAuthor', None)

        def native(_office, current, output, kind):
            calls.append(('native', current, output, kind))
            output.mkdir(parents=True, exist_ok=False)
            state = json.loads(current.read_text())
            if kind == 'doc' and cycle_of(output) == lose_at_bridge:
                loss(state)
            if kind == 'doc' and cycle_of(output) == shift_at_bridge:
                state['mockRenderShift'] = state.get('mockRenderShift', 0) + 12
            if kind == 'docx' and cycle_of(output) == flatten_at_native_docx:
                state['counts']['footnoteTables'] = 0
                state['structure']['footnoteTables'] = []
            destination = output / (current.stem + '.' + kind)
            destination.write_text(json.dumps(state))
            return destination

        def convert(_executable, current, destination):
            calls.append(('parser', current, destination))
            cycle = cycle_of(destination)
            if cycle == fail_at_parser:
                raise RuntimeError('Deliberate late parser failure')
            state = json.loads(current.read_text())
            if cycle == lose_at_parser:
                loss(state)
            if cycle == shift_at_parser:
                state['mockRenderShift'] = state.get('mockRenderShift', 0) + 12
            destination.write_text(json.dumps(state))
            return {'counts': {'sectionFormattingRevisions': state['counts']['sectPrChange']}}

        def render(_office, current, output, _dpi):
            calls.append(('render', current, output))
            if output.name == fail_render:
                raise ValueError('Deliberate render failure')
            value = render_state()
            shift = json.loads(current.read_text()).get('mockRenderShift', 0)
            if shift:
                value['rasterSha256'] = ['raster-at-' + str(shift)]
                box = value['pages'][0]['words'][0]['box']
                box[0] += shift
                box[2] += shift
            return value

        output = root / 'measurement'
        with patch.object(run, 'ROOT', root), patch.object(run, 'office_convert', native), \
                patch.object(run, 'parser_convert', convert), patch.object(run, 'render', render), \
                patch.object(run, 'snapshot', lambda path: json.loads(path.read_text())):
            result = run.measure_case(case, args, root / 'converter', output)
        self.assertEqual(result, json.loads((output / 'result.json').read_text()))
        return result, output, calls

    def test_three_cycle_flow_uses_previous_output_and_retains_each_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            result, output, calls = self.measure(directory)
            self.assertFalse(run.case_has_errors(result))
            self.assertTrue(run.case_is_exact(result))
            self.assertEqual([1, 2, 3], [cycle['index'] for cycle in result['roundtripCycles']])
            bridge_inputs = [call[1].relative_to(output).as_posix() for call in calls
                             if call[0] == 'native' and call[3] == 'doc'
                             and 'roundtrip-' in str(call[2])]
            self.assertEqual(['converted.docx', 'roundtrip-01/import.docx', 'roundtrip-02/import.docx'],
                             bridge_inputs)
            self.assertEqual(9, len(result['snapshots']))
            self.assertEqual(10, len(result['renders']))
            for receipts in (result['snapshots'], result['renders']):
                for receipt in receipts.values():
                    self.assertEqual(receipt['sha256'], run.digest(output / receipt['path']))
            self.assertEqual(result['secondConverter'], result['roundtripCycles'][0]['converter'])
            self.assertEqual([], result['roundtripDifferences'])

    def test_original_and_binary_renders_precede_parser_import_with_separate_receipts(self):
        with tempfile.TemporaryDirectory() as directory:
            result, output, calls = self.measure(directory, cycles=0)
            original = next(index for index, call in enumerate(calls)
                            if call[0] == 'render' and call[2].name == 'render-original')
            bridge = next(index for index, call in enumerate(calls)
                          if call[0] == 'native' and call[3] == 'doc')
            binary = next(index for index, call in enumerate(calls)
                          if call[0] == 'render' and call[2].name == 'render-binary')
            parser = next(index for index, call in enumerate(calls) if call[0] == 'parser')
            self.assertLess(original, bridge)
            self.assertLess(bridge, binary)
            self.assertLess(binary, parser)
            self.assertEqual(result['sourceSha256'], result['renders']['original']['documentSha256'])
            self.assertEqual(result['binaryDocSha256'], result['renders']['binary']['documentSha256'])
            self.assertTrue((output / 'original-render.json').is_file())
            self.assertTrue((output / 'binary-render.json').is_file())
            attribution = result['comparisonAttribution']['bridgePagination']
            self.assertEqual('original', attribution['referenceRender'])
            self.assertEqual('binary', attribution['actualRender'])
            self.assertFalse(attribution['parserInvolved'])

    def test_initial_native_bridge_visual_loss_is_separate_from_parser_visual_loss(self):
        for culprit in ('bridge', 'parser'):
            with self.subTest(culprit=culprit), tempfile.TemporaryDirectory() as directory:
                result, _, _ = self.measure(directory, **{'shift_at_' + culprit: 0})
                self.assertFalse(run.case_has_errors(result))
                self.assertFalse(run.case_is_exact(result))
                self.assertEqual([], result['bridgeChanges'])
                self.assertEqual([], result['semanticDifferencesFromNativeDoc'])
                self.assertEqual(culprit != 'bridge', result['bridgePagination']['exactOnThisRenderer'])
                self.assertEqual(culprit != 'parser', result['pagination']['exactOnThisRenderer'])
                self.assertTrue(result['nativeConversionPagination']['exactOnThisRenderer'])
                # Subsequent stable imports must not hide the initial visual loss.
                for cycle in result['roundtripCycles']:
                    self.assertTrue(cycle['paginationFromBinaryDoc']['exactOnThisRenderer'])
                    self.assertTrue(cycle['paginationFromFirstImport']['exactOnThisRenderer'])

    def test_original_render_failure_keeps_structure_and_never_invokes_conversion(self):
        with tempfile.TemporaryDirectory() as directory:
            result, output, calls = self.measure(directory, fail_render='render-original')
            self.assertTrue(run.case_has_errors(result))
            self.assertEqual('original-render', result['stages'][-1]['name'])
            self.assertEqual('error', result['stages'][-1]['status'])
            self.assertTrue((output / 'original-semantic.json').is_file())
            self.assertFalse((output / 'original-render.json').exists())
            self.assertFalse(any(call[0] in ('native', 'parser') for call in calls))

    def test_native_docx_export_can_flatten_a_table_that_parser_retains(self):
        with tempfile.TemporaryDirectory() as directory:
            result, output, _ = self.measure(directory, cycles=0, flatten_at_native_docx=0)
            original = json.loads((output / 'original-semantic.json').read_text())
            converted = json.loads((output / 'converted-semantic.json').read_text())
            self.assertEqual([], run.compare_semantics(original, converted))
            native_loss = next(change for change in result['bridgeChanges']
                               if change['property'] == 'counts.footnoteTables')
            parser_difference = next(change for change in result['semanticDifferencesFromNativeDoc']
                                     if change['property'] == 'counts.footnoteTables')
            self.assertEqual((1, 0), (native_loss['reference'], native_loss['actual']))
            self.assertEqual((0, 1), (parser_difference['reference'], parser_difference['actual']))
            self.assertFalse(result['comparisonAttribution']['bridgeChanges']['parserInvolved'])
            self.assertIn('native DOCX export may discard',
                          result['comparisonAttribution']['semanticDifferencesFromNativeDoc']['caveat'])
            self.assertTrue(result['bridgePagination']['exactOnThisRenderer'])
            self.assertTrue(result['pagination']['exactOnThisRenderer'])
            self.assertFalse(run.case_is_exact(result))

    def test_parser_failure_keeps_already_measured_native_bridge_visual_loss(self):
        with tempfile.TemporaryDirectory() as directory:
            result, output, _ = self.measure(directory, shift_at_bridge=0, fail_at_parser=0)
            self.assertTrue(run.case_has_errors(result))
            self.assertEqual('parser-import', result['stages'][-1]['name'])
            self.assertFalse(result['bridgePagination']['exactOnThisRenderer'])
            self.assertEqual(12, result['bridgePagination']['maximumWordDriftPoints'])
            self.assertTrue((output / 'original-render.json').is_file())
            self.assertTrue((output / 'binary-render.json').is_file())
            self.assertFalse((output / 'converted-render.json').exists())

    def test_existing_case_directory_and_receipts_are_never_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            result, output, _ = self.measure(directory, cycles=0)
            receipt = (output / 'result.json').read_bytes()
            with patch.object(run, 'ROOT', Path(directory)), self.assertRaises(FileExistsError):
                run.measure_case({'id': 'authored', 'features': [], 'path': 'authored.docx'},
                                 SimpleNamespace(no_roundtrip=True), Path('converter'), output)
            self.assertEqual(receipt, (output / 'result.json').read_bytes())
            self.assertEqual(result, json.loads(receipt))

    def test_initial_loss_cannot_be_hidden_by_stable_second_and_third_imports(self):
        for culprit in ('bridge', 'parser'):
            with self.subTest(culprit=culprit), tempfile.TemporaryDirectory() as directory:
                result, _, _ = self.measure(directory, **{'lose_at_' + culprit: 1})
                self.assertFalse(run.case_has_errors(result))
                self.assertFalse(run.case_is_exact(result))
                cycles = result['roundtripCycles']
                first = cycles[0]
                self.assertTrue(first['semanticDifferencesFromFirstImport'])
                self.assertEqual(culprit == 'bridge', bool(first['bridgeChanges']))
                self.assertEqual(culprit == 'parser', bool(first['semanticDifferencesFromNativeDoc']))
                for cycle in cycles[1:]:
                    self.assertEqual([], cycle['semanticDifferencesFromPreviousImport'])
                    self.assertTrue(cycle['semanticDifferencesFromFirstImport'])
                # A reader cannot erase the first-cycle finding and turn later
                # stable, already damaged output into an exact result.
                for key in ('bridgeChanges', 'semanticDifferencesFromNativeDoc',
                            'semanticDifferencesFromPreviousImport', 'semanticDifferencesFromFirstImport'):
                    first[key] = []
                self.assertFalse(run.case_is_exact(result))

    def test_late_failure_preserves_completed_cycles_and_identifies_failed_stage(self):
        with tempfile.TemporaryDirectory() as directory:
            result, output, _ = self.measure(directory, fail_at_parser=3)
            self.assertTrue(run.case_has_errors(result))
            self.assertFalse(run.case_is_exact(result))
            self.assertEqual(['measured', 'measured', 'error'],
                             [cycle['status'] for cycle in result['roundtripCycles']])
            self.assertEqual('roundtrip-03-parser-import', result['stages'][-1]['name'])
            self.assertEqual('error', result['stages'][-1]['status'])
            self.assertTrue((output / 'roundtrip-02-converted-semantic.json').is_file())
            self.assertTrue((output / 'roundtrip-02-converted-render.json').is_file())
            self.assertTrue((output / 'roundtrip-03-native-semantic.json').is_file())
            self.assertFalse((output / 'roundtrip-03-converted-semantic.json').exists())

    def test_render_failure_does_not_discard_prior_semantics_or_binary_render(self):
        with tempfile.TemporaryDirectory() as directory:
            result, output, _ = self.measure(directory, fail_render='render-converted')
            self.assertTrue(run.case_has_errors(result))
            self.assertEqual('converted-render', result['stages'][-1]['name'])
            self.assertTrue((output / 'converted-semantic.json').is_file())
            self.assertTrue((output / 'native-semantic.json').is_file())
            self.assertTrue((output / 'binary-render.json').is_file())
            self.assertFalse((output / 'converted-render.json').exists())

    def test_skipped_roundtrip_does_not_claim_a_checked_cycle(self):
        with tempfile.TemporaryDirectory() as directory:
            result, _, calls = self.measure(directory, cycles=0, source_suffix='.doc')
            self.assertFalse(run.case_has_errors(result))
            self.assertTrue(run.case_is_exact(result))
            self.assertEqual([], result['roundtripCycles'])
            self.assertEqual(1, sum(call[0] == 'parser' for call in calls))
            self.assertEqual('doc', result['sourceFormat'])
            self.assertIsNone(result['bridgePagination'])
            self.assertIsNone(result['comparisonAttribution']['bridgePagination'])
            self.assertNotIn('original', result['renders'])
        self.assertEqual(1, run.requested_roundtrips(SimpleNamespace(no_roundtrip=False)))
        self.assertEqual(0, run.requested_roundtrips(SimpleNamespace(no_roundtrip=True, roundtrip_cycles=3)))

    def test_exact_predicate_rejects_bridge_native_render_incomplete_and_missing_results(self):
        with tempfile.TemporaryDirectory() as directory:
            original, _, _ = self.measure(directory, cycles=1)
        mutations = [
            lambda value: value.update(sourceUnchanged=False),
            lambda value: value.update(binaryDocUnchanged=False),
            lambda value: value.update(bridgeChanges=[{'property': 'review'}]),
            lambda value: value.pop('bridgePagination'),
            lambda value: value['bridgePagination'].update(exactOnThisRenderer=False),
            lambda value: value['renders'].pop('original'),
            lambda value: value.pop('sourceFormat'),
            lambda value: value['nativeConversionPagination'].update(exactOnThisRenderer=False),
            lambda value: value['roundtripCycles'].clear(),
            lambda value: value['roundtripCycles'][0].update(index=2),
            lambda value: value['roundtripCycles'][0].update(inputUnchanged=False),
            lambda value: value['roundtripCycles'][0]['paginationFromFirstImport'].update(exactOnThisRenderer=False),
            lambda value: value['roundtripCycles'][0].pop('semanticDifferencesFromNativeDoc'),
            lambda value: value['stages'][-1].update(status='running'),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(mutation=index):
                damaged = copy.deepcopy(original)
                mutate(damaged)
                self.assertFalse(run.case_is_exact(damaged))

    def test_source_receipts_bind_dirty_content_and_added_files_without_a_git_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'lib').mkdir()
            (root / 'tool/fidelity').mkdir(parents=True)
            (root / 'lib/parser.dart').write_text('first implementation')
            (root / 'pubspec.lock').write_text('pinned dependency')
            first = run.source_receipt(root)
            (root / 'lib/parser.dart').write_text('second implementation')
            second = run.source_receipt(root)
            self.assertNotEqual(first['sha256'], second['sha256'])
            (root / 'lib/new.dart').write_text('previously untracked source')
            third = run.source_receipt(root)
            self.assertNotEqual(second['sha256'], third['sha256'])
            self.assertIn('lib/new.dart', third['files'])
            self.assertIn('pubspec.lock', third['files'])
            self.assertEqual(third, run.source_receipt(root))

    def test_compiler_receipt_captures_stderr_version_and_actual_executable_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            compiler = Path(directory) / 'dart'
            compiler.write_bytes(b'compiler binary A')
            completed = subprocess.CompletedProcess([], 0, '', 'Dart SDK version: reviewed\n')
            with patch.object(run.subprocess, 'run', return_value=completed):
                first = run.tool_receipt(compiler)
                compiler.write_bytes(b'compiler binary B')
                second = run.tool_receipt(compiler)
            self.assertEqual('Dart SDK version: reviewed', first['version'])
            self.assertNotEqual(first['sha256'], second['sha256'])
            self.assertEqual(run.digest(compiler), second['sha256'])

    def test_missing_source_still_leaves_a_failure_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(run, 'ROOT', root):
                result = run.measure_case(
                    {'id': 'missing', 'path': 'missing.doc', 'sha256': '0' * 64, 'features': []},
                    SimpleNamespace(no_roundtrip=False, roundtrip_cycles=3),
                    root / 'converter', root / 'result')
            self.assertEqual('error', result['status'])
            self.assertEqual('source-receipt', result['stages'][-1]['name'])
            self.assertEqual('error', result['stages'][-1]['status'])
            self.assertFalse(result['sourceUnchanged'])
            self.assertEqual(result, json.loads((root / 'result/result.json').read_text()))

    def test_compile_failure_and_inputs_changed_during_build_keep_global_report(self):
        for changed_inputs in (False, True):
            with self.subTest(changed_inputs=changed_inputs), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / 'tool/fidelity').mkdir(parents=True)
                (root / 'tool/fidelity/corpus.json').write_text('{"cases": []}')
                (root / run.GOLDEN_MANIFEST).parent.mkdir(parents=True)
                (root / run.GOLDEN_MANIFEST).write_text('{"cases": []}')
                output = root / 'output'
                before = {'files': {'lib/parser.dart': 'before'}, 'sha256': 'before'}
                after = {'files': {'lib/parser.dart': 'after'}, 'sha256': 'after'}

                def command(argv, **_kwargs):
                    if argv[:2] == ['git', 'rev-parse']:
                        return 'reviewed-commit\n'
                    if argv[0] == 'git':
                        return ' M lib/parser.dart\n'
                    if not changed_inputs:
                        raise RuntimeError('Deliberate compile failure')
                    Path(argv[-1]).write_bytes(b'compiled parser')
                    return 'Compiled parser\n'

                tool = {'path': '/mock/compiler', 'sha256': 'binary-hash', 'version': 'Reviewed version'}
                argv = ['run.py', '--office', str(root / 'office'), '--dart', str(root / 'dart'),
                        '--output', str(output), '--roundtrip-cycles', '3']
                with patch.object(run, 'ROOT', root), patch.object(run, 'load_corpus', return_value={'cases': []}), \
                        patch.object(run, 'load_goldens', return_value={'cases': {}}), \
                        patch.object(run, 'source_receipt', side_effect=[before, after]), \
                        patch.object(run, 'tool_receipt', return_value=tool), patch.object(run, 'command', command), \
                        patch.object(run.sys, 'argv', argv), patch.dict(os.environ, {'TMPDIR': str(root / 'tmp')}):
                    self.assertEqual(1, run.main())
                report = json.loads((output / 'report.json').read_text())
                self.assertEqual('error', report['status'])
                self.assertEqual(tool, report['build']['compiler'])
                self.assertEqual(before, report['build']['sources'])
                self.assertEqual([], report['cases'])
                if changed_inputs:
                    self.assertFalse(report['build']['sourcesUnchangedDuringCompilation'])
                    self.assertEqual(after, report['build']['sourcesAfterCompilation'])
                    self.assertEqual(run.digest(output / 'convert'), report['build']['executable']['sha256'])
                else:
                    self.assertEqual('compile', report['stages'][-1]['name'])
                    self.assertEqual('error', report['stages'][-1]['status'])


if __name__ == '__main__':
    unittest.main()
