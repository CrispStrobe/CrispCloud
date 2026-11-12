# SPDX-License-Identifier: MPL-2.0
"""Runner predicates and orchestration, without starting a native Office app."""
import copy
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import run
from goldens import ENVIRONMENT_KEYS


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
                shift_at_bridge=None, shift_at_parser=None, flatten_at_native_docx=None,
                raster_storage='ppm'):
        root = Path(directory)
        source = root / ('authored' + source_suffix)
        source.write_text(json.dumps(authored_state()))
        case = {'id': 'authored', 'path': source.name, 'sha256': run.digest(source),
                'features': ['revisions']}
        args = SimpleNamespace(office=Path('/mock/office'), dpi=72,
                               no_roundtrip=False, roundtrip_cycles=cycles,
                               raster_storage=raster_storage)
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

        def render(_office, current, output, _dpi, *, raster_storage):
            calls.append(('render', current, output))
            self.assertEqual(args.raster_storage, raster_storage)
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

    def test_requested_storage_reaches_every_render_in_three_cycles(self):
        with tempfile.TemporaryDirectory() as directory:
            result, _, calls = self.measure(directory, raster_storage='gzip')
            self.assertFalse(run.case_has_errors(result))
            self.assertEqual('gzip', result['rasterStorage'])
            self.assertEqual(10, sum(call[0] == 'render' for call in calls))

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
                self.assertEqual('ppm', report['rasterStorage'])
                if changed_inputs:
                    self.assertFalse(report['build']['sourcesUnchangedDuringCompilation'])
                    self.assertEqual(after, report['build']['sourcesAfterCompilation'])
                    self.assertEqual(run.digest(output / 'convert'), report['build']['executable']['sha256'])
                else:
                    self.assertEqual('compile', report['stages'][-1]['name'])
                    self.assertEqual('error', report['stages'][-1]['status'])


class RasterStorageTest(unittest.TestCase):
    """Independent PPM bytes exercise storage without claiming native rendering."""

    @staticmethod
    def page_bytes(index):
        return b'P6\n2 1\n255\n' + bytes((index, 0, 255, 255, 255, 255))

    def render(self, root, storage='ppm', *, page_count=2, fail_page=None,
               omit_page=None, observations=None, recorder=None, pdf_info=None):
        output = root / storage

        def native(_office, _source, directory, kind):
            self.assertEqual('pdf', kind)
            directory.mkdir()
            pdf = directory / 'authored.pdf'
            pdf.write_bytes(b'%PDF-test-double; no native renderer was invoked')
            return pdf

        def command(argv):
            if argv[0] == 'pdfinfo':
                return pdf_info if pdf_info is not None else f'Pages: {page_count}\n'
            if argv[0] == 'pdftotext':
                if '-bbox-layout' in argv:
                    Path(argv[-1]).write_text('<html><doc>' + ''.join(
                        f'<page width="612" height="792"><word xMin="10" yMin="20" '
                        f'xMax="30" yMax="40">Page{index}</word></page>'
                        for index in range(1, page_count + 1)) + '</doc></html>')
                    return ''
                return '\n'.join(f'Page{index}' for index in range(1, page_count + 1))
            self.assertEqual('pdftoppm', argv[0])
            self.assertEqual(['-r', '72'], argv[1:3])
            prefix = Path(argv[-1])
            if '-singlefile' in argv:
                index = int(argv[argv.index('-f') + 1])
                self.assertEqual(str(index), argv[argv.index('-l') + 1])
                if observations is not None:
                    observations.append((index, sorted(path.name for path in output.glob('*.ppm'))))
                if index == fail_page:
                    prefix.with_suffix('.ppm').write_bytes(b'incomplete raster')
                    raise RuntimeError('Deliberate later-page raster failure')
                if index != omit_page:
                    prefix.with_suffix('.ppm').write_bytes(self.page_bytes(index))
            else:
                for index in range(1, page_count + 1):
                    (output / f'page-{index:0{len(str(page_count))}d}.ppm').write_bytes(self.page_bytes(index))
            return ''

        with patch.object(run, 'office_convert', native), patch.object(run, 'command', command):
            action = lambda: run.render(Path('/mock/office'), root / 'authored.docx', output, 72,
                                        raster_storage=storage)
            return recorder('native-render', action) if recorder else action()

    def verify_receipt(self, directory, receipt):
        stored = directory / receipt['path']
        self.assertEqual(receipt['sha256'], run.digest(stored))
        self.assertEqual(receipt['sizeBytes'], stored.stat().st_size)
        with gzip.open(stored, 'rb') as source:
            raw = source.read()
        self.assertEqual(self.page_bytes(receipt['page']), raw)
        self.assertEqual(receipt['uncompressedSha256'], hashlib.sha256(raw).hexdigest())
        self.assertEqual(receipt['uncompressedSizeBytes'], len(raw))

    def test_default_ppm_storage_keeps_existing_render_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = self.render(root)
            self.assertEqual(['page-1.ppm', 'page-2.ppm'],
                             sorted(path.name for path in (root / 'ppm').glob('*.ppm')))
            self.assertFalse(list((root / 'ppm').glob('*.gz')))
            self.assertFalse((root / 'ppm/raster-manifest.json').exists())
            self.assertNotIn('rasterArtifacts', result)
            self.assertEqual([hashlib.sha256(self.page_bytes(index)).hexdigest() for index in (1, 2)],
                             result['rasterSha256'])

    def test_gzip_keeps_ppm_hashes_comparisons_and_source_goldens_compatible(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = self.render(root)
            compressed = self.render(root, 'gzip')
            self.assertTrue(run.render_comparison(original, compressed)['exactOnThisRenderer'])
            for key in original:
                self.assertEqual(original[key], compressed[key])
            environment = {key: 'same pinned environment' for key in ENVIRONMENT_KEYS}
            catalog = {'environment': environment, 'cases': {
                'authored': {'source': {'sha256': 'source'}, 'expectedRender': original}}}
            self.assertEqual('matched', run.compare_golden(
                'authored', 'source', compressed, environment, catalog)['status'])
            manifest_path = root / 'gzip' / compressed['rasterManifest']['path']
            self.assertEqual(compressed['rasterManifest']['sha256'], run.digest(manifest_path))
            manifest = json.loads(manifest_path.read_text())
            self.assertEqual('complete', manifest['status'])
            self.assertEqual(compressed['rasterArtifacts'], manifest['pages'])
            self.assertEqual(original['pdfSha256'], manifest['pdfSha256'])
            self.assertEqual(len(original['pages']), manifest['pdfPageCount'])
            self.assertEqual(manifest['pdfInfo']['sha256'], run.digest(root / 'gzip/pdfinfo.txt'))
            for receipt in manifest['pages']:
                self.verify_receipt(root / 'gzip', receipt)

    def test_many_pages_are_numbered_and_stored_with_only_one_raw_page_at_a_time(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            observations = []
            result = self.render(root, 'gzip', page_count=12, observations=observations)
            self.assertEqual([(index, []) for index in range(1, 13)], observations)
            self.assertEqual(list(range(1, 13)), [item['page'] for item in result['rasterArtifacts']])
            self.assertEqual([hashlib.sha256(self.page_bytes(index)).hexdigest()
                              for index in range(1, 13)], result['rasterSha256'])
            self.assertFalse(list((root / 'gzip').glob('*.ppm')))
            self.assertEqual(12, len(list((root / 'gzip').glob('*.ppm.gz'))))
            self.assertNotIn('activePage', json.loads((root / 'gzip/raster-manifest.json').read_text()))

    def test_late_raster_failure_keeps_completed_page_receipts_and_parent_checkpoint(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            case = {'priorSemantics': {'path': 'prior-semantic.json', 'sha256': 'retained'}}
            recorder = run.StageRecorder(case, root / 'result.json')
            with self.assertRaisesRegex(RuntimeError, 'later-page'):
                self.render(root, 'gzip', fail_page=2, recorder=recorder)
            saved = json.loads((root / 'result.json').read_text())
            self.assertEqual(case, saved)
            self.assertEqual('retained', saved['priorSemantics']['sha256'])
            self.assertEqual('error', saved['stages'][-1]['status'])
            manifest = json.loads((root / 'gzip/raster-manifest.json').read_text())
            self.assertEqual('error', manifest['status'])
            self.assertEqual(2, manifest['activePage'])
            self.assertEqual([1], [item['page'] for item in manifest['pages']])
            self.verify_receipt(root / 'gzip', manifest['pages'][0])
            self.assertEqual(b'incomplete raster', (root / 'gzip/page-0002.ppm').read_bytes())
            self.assertFalse((root / 'gzip/page-0002.ppm.gz').exists())
            for name in ('authored.pdf', 'pages.xhtml', 'pages.txt'):
                self.assertTrue((root / 'gzip' / name).is_file())

    def test_missing_page_cannot_claim_complete_compressed_render(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaises(FileNotFoundError):
                self.render(root, 'gzip', omit_page=2)
            manifest = json.loads((root / 'gzip/raster-manifest.json').read_text())
            self.assertEqual('error', manifest['status'])
            self.assertEqual(2, manifest['expectedPages'])
            self.assertEqual(1, len(manifest['pages']))
            self.verify_receipt(root / 'gzip', manifest['pages'][0])

    def test_missing_extra_or_unverifiable_pdf_pages_fail_before_rasterization(self):
        for info in ('Pages: 1\n', 'Pages: 3\n', 'Pages: 0\n',
                     'Pages: 2\nPages: 2\n', 'No readable page count\n'):
            with self.subTest(pdf_info=info), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                observations = []
                with self.assertRaises(RuntimeError):
                    self.render(root, 'gzip', pdf_info=info, observations=observations)
                self.assertEqual([], observations)
                manifest = json.loads((root / 'gzip/raster-manifest.json').read_text())
                self.assertEqual('error', manifest['status'])
                self.assertEqual([], manifest['pages'])
                self.assertEqual(info, (root / 'gzip/pdfinfo.txt').read_text())

    def test_corrupt_copy_or_changed_raw_page_keeps_original_instead_of_publishing(self):
        copy_stream = run.shutil.copyfileobj
        for mutation in ('copied-bytes', 'source-after-copy'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                source = root / 'page.ppm'
                original = self.page_bytes(1)
                source.write_bytes(original)

                def copy(raw, compressed, **kwargs):
                    if mutation == 'copied-bytes':
                        compressed.write(b'silent wrong output')
                    else:
                        copy_stream(raw, compressed, **kwargs)
                        source.write_bytes(b'concurrent page change')

                with patch.object(run.shutil, 'copyfileobj', copy), \
                        self.assertRaisesRegex(ValueError, 'unchanged PPM'):
                    run.gzip_raster(source)
                self.assertEqual(original if mutation == 'copied-bytes' else b'concurrent page change',
                                 source.read_bytes())
                self.assertFalse((root / 'page.ppm.gz').exists())
                self.assertFalse((root / 'page.ppm.gz.tmp').exists())

    def test_interrupted_second_compression_retains_first_page_and_current_raw_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            copy_stream = run.shutil.copyfileobj
            copied = 0

            def copy(raw, compressed, **kwargs):
                nonlocal copied
                copied += 1
                if copied == 2:
                    compressed.write(raw.read(8))
                    raise OSError('Deliberate compression write failure')
                return copy_stream(raw, compressed, **kwargs)

            with patch.object(run.shutil, 'copyfileobj', copy), \
                    self.assertRaisesRegex(OSError, 'compression write failure'):
                self.render(root, 'gzip')
            manifest = json.loads((root / 'gzip/raster-manifest.json').read_text())
            self.assertEqual('error', manifest['status'])
            self.assertEqual(1, len(manifest['pages']))
            self.verify_receipt(root / 'gzip', manifest['pages'][0])
            self.assertEqual(self.page_bytes(2), (root / 'gzip/page-0002.ppm').read_bytes())
            self.assertFalse((root / 'gzip/page-0002.ppm.gz').exists())
            self.assertFalse((root / 'gzip/page-0002.ppm.gz.tmp').exists())

    def test_failed_receipt_write_keeps_raw_and_verified_compressed_page(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write_json = run.write_json

            def fail_receipt(path, value):
                if value.get('status') == 'running' and len(value.get('pages', [])) == 1:
                    raise OSError('Deliberate receipt write failure')
                return write_json(path, value)

            with patch.object(run, 'write_json', fail_receipt), \
                    self.assertRaisesRegex(OSError, 'receipt write failure'):
                self.render(root, 'gzip')
            self.assertEqual(self.page_bytes(1), (root / 'gzip/page-0001.ppm').read_bytes())
            manifest = json.loads((root / 'gzip/raster-manifest.json').read_text())
            self.assertEqual('error', manifest['status'])
            self.verify_receipt(root / 'gzip', manifest['pages'][0])

    def test_existing_gzip_and_temporary_files_are_never_overwritten_or_removed(self):
        for name in ('page.ppm.gz', 'page.ppm.gz.tmp'):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                source = root / 'page.ppm'
                source.write_bytes(self.page_bytes(1))
                existing = root / name
                existing.write_bytes(b'previous recovery artifact')
                with self.assertRaises(FileExistsError):
                    run.gzip_raster(source)
                self.assertEqual(b'previous recovery artifact', existing.read_bytes())
                self.assertEqual(self.page_bytes(1), source.read_bytes())

    def test_json_checkpoint_publish_failure_preserves_previous_complete_report(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'raster-manifest.json'
            prior = {'status': 'running', 'pages': [{'page': 1}]}
            run.write_json(target, prior)
            with patch.object(Path, 'replace', side_effect=OSError('Deliberate publish failure')), \
                    self.assertRaisesRegex(OSError, 'publish failure'):
                run.write_json(target, {'status': 'complete', 'pages': [{'page': 1}, {'page': 2}]})
            self.assertEqual(prior, json.loads(target.read_text()))

    def test_standard_gzip_and_tar_consumers_recover_original_bytes_and_receipts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = self.render(root, 'gzip')
            archive_bytes = io.BytesIO()
            with tarfile.open(fileobj=archive_bytes, mode='w:xz') as archive:
                archive.add(root / 'gzip', arcname='render')
            archive_bytes.seek(0)
            with tarfile.open(fileobj=archive_bytes, mode='r:xz') as archive:
                with archive.extractfile('render/raster-manifest.json') as source:
                    manifest = json.load(source)
                for index, receipt in enumerate(manifest['pages'], 1):
                    with archive.extractfile('render/' + receipt['path']) as source:
                        compressed = source.read()
                    self.assertEqual(receipt['sha256'], hashlib.sha256(compressed).hexdigest())
                    raw = gzip.decompress(compressed)
                    self.assertEqual(self.page_bytes(index), raw)
                    self.assertEqual(result['rasterSha256'][index - 1], hashlib.sha256(raw).hexdigest())

    def test_compression_headers_do_not_depend_on_filename_or_clock(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ('first.ppm', 'second.ppm'):
                source = root / name
                source.write_bytes(self.page_bytes(1))
                run.gzip_raster(source)
                self.assertEqual(self.page_bytes(1), source.read_bytes())
            first = (root / 'first.ppm.gz').read_bytes()
            self.assertEqual(first, (root / 'second.ppm.gz').read_bytes())
            self.assertEqual(bytes(4), first[4:8])  # gzip MTIME

    def test_unknown_storage_is_rejected_before_starting_office(self):
        with patch.object(run, 'office_convert') as office, self.assertRaises(ValueError):
            run.render(Path('/mock/office'), Path('source.doc'), Path('unused'), 72,
                       raster_storage='jpeg')
        office.assert_not_called()


if __name__ == '__main__':
    unittest.main()
