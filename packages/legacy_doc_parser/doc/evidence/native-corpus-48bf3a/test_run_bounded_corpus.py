"""Scratch lifecycle controls; no native application or production repo is mutated."""
import copy
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import run_bounded_corpus as bounded


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.repo = self.root / 'parser'
        (self.repo / 'tool/fidelity').mkdir(parents=True)
        self.commit, self.tree = 'a' * 40, 'b' * 40
        self.cases = [{'id': name, 'path': name + '.doc', 'sha256': name + '-source'}
                      for name in ('first', 'second')]
        (self.repo / 'tool/fidelity/corpus.json').write_text(json.dumps({'cases': self.cases}))
        self.output = self.root / 'result'
        self.sealer, self.verifier = self.root / 'seal.py', self.root / 'verify.py'
        self.sealer.write_text('test sealer')
        self.verifier.write_text('test verifier')
        self.sources = {'files': {'lib/parser.dart': 'source'}, 'sha256': 'source-files'}
        self.calls = []
        self.fail = None
        self.dirty = False

    def tearDown(self):
        self.temporary.cleanup()

    def git(self, _repo, *args):
        if args == ('rev-parse', 'HEAD'):
            return self.commit
        if args == ('rev-parse', 'HEAD^{tree}'):
            return self.tree
        return ' M changed.dart' if self.dirty else ''

    def logged(self, command, _log, **_kwargs):
        name = Path(command[1]).name
        self.calls.append(name)
        if name == 'run.py':
            raw = Path(command[command.index('--output') + 1])
            raw.mkdir()
            (raw / 'convert').write_bytes(b'measured executable')
            (raw / 'source.doc').write_bytes(b'recoverable native document')
            case_id = command[command.index('--case') + 1]
            case = next(case for case in self.cases if case['id'] == case_id)
            measured = {'id': case_id, 'status': 'measured',
                        'roundtripCyclesRequested': 3, 'rasterStorage': 'gzip',
                        'sourceSha256': case['sha256'],
                        'roundtripCycles': [{'index': index} for index in range(1, 4)]}
            report = {'schema': 'legacy-doc-parser/fidelity-report', 'version': 4,
                      'status': 'measured', 'parserCommit': self.commit, 'parserWorktreeDirty': False,
                      'corpusSha256': bounded.digest(self.repo / 'tool/fidelity/corpus.json'),
                      'rasterStorage': 'gzip', 'roundtripCyclesRequested': 3,
                      'stages': [{'name': 'compile', 'status': 'complete'}], 'cases': [measured],
                      'build': {'sources': self.sources, 'sourcesUnchangedDuringCompilation': True,
                                'executable': {'path': 'convert', 'sha256': bounded.digest(raw / 'convert')},
                                'python': 'test', 'platform': 'test',
                                **{key: {'sha256': key, 'version': 'test'} for key in
                                   ('compiler', 'office', 'pdftotext', 'pdftoppm', 'pdfinfo')}},
                      'sourceGoldens': {}, 'goldenEnvironment': {}, 'exactOnThisRenderer': False}
            if self.fail == 'incomplete-cycles':
                measured['roundtripCycles'].pop()
            if self.fail == 'measurement':
                report['status'] = 'error'
            bounded.write_json(raw / 'report.json', report)
            if self.fail == 'measurement':
                raise ValueError('fake measurement exited 1')
        elif name == 'seal.py':
            raw = Path(command[command.index('--run') + 1])
            sealed = Path(command[command.index('--output') + 1])
            sealed.mkdir()
            (sealed / 'archive').write_bytes(b'verified archive')
            if self.fail == 'sealing':
                raise OSError('fake sealing interrupted')
            manifest = {'sourceCommit': self.commit, 'sourceWorktreeDirty': False,
                        'report': {'uncompressedSha256': bounded.digest(raw / 'report.json')},
                        'archive': {'sha256': bounded.digest(sealed / 'archive')}, 'fileCount': 3}
            bounded.write_json(sealed / 'native-artifacts.manifest.json', manifest)
        else:
            self.assertEqual('verify.py', name)
            sealed = Path(command[command.index('--directory') + 1])
            self.assertTrue((sealed / 'native-artifacts.manifest.json').is_file())
            if self.fail == 'verification':
                raise ValueError('fake artifact verifier rejected changed bytes')

    def invoke(self, *, resume=False, free=1024 * bounded.MIB):
        runner = SimpleNamespace(source_receipt=lambda: copy.deepcopy(self.sources),
                                 case_has_errors=lambda case: len(case['roundtripCycles']) != 3)
        argv = ['run_bounded_corpus.py', '--parser', str(self.repo), '--expected-commit', self.commit,
                '--office', str(self.root / 'office'), '--dart', str(self.root / 'dart'),
                '--output', str(self.output), '--sealer', str(self.sealer), '--verifier', str(self.verifier)]
        if resume:
            argv.append('--resume')
        with patch.object(bounded.sys, 'argv', argv), patch.object(bounded, 'git', self.git), \
                patch.object(bounded, 'load_runner', return_value=runner), \
                patch.object(bounded, 'free_bytes', return_value=free), \
                patch.object(bounded, 'run_logged', self.logged):
            return bounded.main()

    def index(self):
        return json.loads((self.output / 'index.json').read_text())

    def test_two_separate_runs_verify_before_reclaiming_and_resume_reuses_seals(self):
        self.assertEqual(0, self.invoke())
        index = self.index()
        self.assertEqual('complete', index['status'])
        self.assertEqual(2, index['completedCases'])
        self.assertEqual(6, index['completedRoundtripCycles'])
        self.assertEqual(self.tree, index['sourceTree'])
        self.assertEqual([], list((self.output / 'runs').iterdir()))
        self.assertEqual(['run.py', 'seal.py', 'verify.py'] * 2, self.calls)
        for entry in index['cases']:
            sealed = self.output / entry['sealedDirectory']
            self.assertEqual(entry['sealedManifestSha256'],
                             bounded.digest(sealed / 'native-artifacts.manifest.json'))
            self.assertEqual('measured', entry['summary']['reportStatus'])
        self.calls.clear()
        self.assertEqual(0, self.invoke(resume=True, free=50 * bounded.MIB))
        self.assertEqual(['verify.py', 'verify.py'], self.calls)

    def test_each_failure_keeps_raw_case_and_stops_before_next_case(self):
        for stage in ('measurement', 'incomplete-cycles', 'sealing', 'verification'):
            with self.subTest(stage=stage):
                self.fail = stage
                self.output = self.root / ('failure-' + stage)
                self.calls.clear()
                with self.assertRaises((ValueError, OSError)):
                    self.invoke()
                index = self.index()
                self.assertEqual('error', index['status'])
                self.assertEqual(1, len(index['cases']))
                raw = self.output / index['cases'][0]['rawDirectory']
                self.assertTrue((raw / 'report.json').is_file())
                self.assertTrue((raw / 'source.doc').is_file())
                self.assertEqual(1, self.calls.count('run.py'))
                self.assertFalse((self.output / 'wrapper.lock').exists())

    def test_failed_cleanup_resumes_from_verified_archive_without_new_measurement(self):
        rmtree = bounded.shutil.rmtree
        with patch.object(bounded.shutil, 'rmtree', side_effect=OSError('interrupted cleanup')):
            with self.assertRaisesRegex(OSError, 'interrupted cleanup'):
                self.invoke()
        first = self.index()['cases'][0]
        self.assertEqual('verified', first['status'])
        self.assertTrue((self.output / first['rawDirectory']).is_dir())
        self.calls.clear()
        self.assertEqual(0, self.invoke(resume=True))
        self.assertEqual(['verify.py', 'run.py', 'seal.py', 'verify.py'], self.calls)

    def test_changed_completed_manifest_cannot_pass_resume(self):
        self.invoke()
        first = self.index()['cases'][0]
        manifest = self.output / first['sealedDirectory'] / 'native-artifacts.manifest.json'
        manifest.write_text(manifest.read_text() + ' ')
        self.calls.clear()
        with self.assertRaisesRegex(ValueError, 'manifest changed'):
            self.invoke(resume=True)
        self.assertEqual([], self.calls)

    def test_dirty_source_or_low_space_never_starts_a_native_case(self):
        self.dirty = True
        with self.assertRaisesRegex(ValueError, 'must be clean'):
            self.invoke()
        self.assertFalse(self.output.exists())
        self.dirty = False
        with self.assertRaisesRegex(ValueError, 'requires 400 MiB'):
            self.invoke(free=399 * bounded.MIB)
        self.assertEqual([], self.calls)
        self.assertEqual([], list((self.output / 'runs').iterdir()))


if __name__ == '__main__':
    unittest.main()
