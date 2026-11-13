#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Resealed corruption controls for the evidence wrapper's additional claims."""
import io
import json
from pathlib import Path
import shutil
import tarfile
import tempfile
import unittest
import zipfile

import verify


def encode(value):
    return (json.dumps(value, ensure_ascii=False) + '\n').encode()


def change_json(files, name, mutate):
    value = json.loads(files[name])
    mutate(value)
    files[name] = encode(value)


def change_package(files, name, part, mutate):
    output = io.BytesIO()
    with zipfile.ZipFile(io.BytesIO(files[name])) as old, zipfile.ZipFile(output, 'w') as new:
        for item in old.infolist():
            data = old.read(item.filename)
            new.writestr(item, mutate(data) if item.filename == part else data)
    files[name] = output.getvalue()


class EvidenceControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='path-evidence-controls-')
        cls.root = Path(cls.temporary.name)
        cls.baseline = cls.root / 'baseline'
        cls.auxiliary = cls.root / 'auxiliary'
        verify.unpack(verify.HERE, 'baseline', cls.baseline)
        verify.unpack(verify.HERE, 'auxiliary', cls.auxiliary)
        cls.files = {p.relative_to(cls.auxiliary).as_posix(): p.read_bytes()
                     for p in cls.auxiliary.rglob('*') if p.is_file()}

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def reject(self, mutate, guard, check='note'):
        files = dict(self.files)
        mutate(files)
        with tempfile.TemporaryDirectory(prefix='path-evidence-resealed-') as temporary:
            root = Path(temporary)
            target = root / 'extracted'
            output = io.BytesIO()
            with tarfile.open(fileobj=output, mode='w:xz', preset=0) as tf:
                for name, raw in sorted(files.items()):
                    item = tarfile.TarInfo(name)
                    item.size, item.mode = len(raw), 0o644
                    tf.addfile(item, io.BytesIO(raw))
            packed = output.getvalue()
            (root / 'auxiliary.tar.xz').write_bytes(packed)
            manifest = {'schema': 1, 'archive': 'auxiliary.tar.xz', 'archiveBytes': len(packed),
                        'archiveSha256': verify.sha(packed), 'fileCount': len(files),
                        'rawBytes': sum(map(len, files.values())),
                        'files': [{'path': n, 'bytes': len(b), 'sha256': verify.sha(b), 'mode': '0o644'}
                                  for n, b in sorted(files.items())]}
            (root / 'auxiliary-manifest.json').write_bytes(encode(manifest))
            verify.unpack(root, 'auxiliary', target)
            # Both container and every member hash are now valid. Rejection
            # must come from the semantic/command/source guard under test.
            with self.assertRaisesRegex(ValueError, guard):
                if check == 'note':
                    verify.check_note_order(target, self.baseline)
                elif check == 'metadata':
                    verify.check_metadata(target)
                elif check == 'review':
                    with verify.replay_module(target) as replay:
                        verify.check_historical_reviews(target, self.baseline, replay)
                elif check == 'replay':
                    with verify.replay_module(target):
                        pass
                else:
                    raise RuntimeError('Unknown test scope')

    def test_original(self):
        result = verify.verify_extracted({'baseline': self.baseline, 'auxiliary': self.auxiliary}, verify.HERE.parents[2])
        self.assertTrue(result['verified'])
        self.assertEqual(result['baseline']['verifiedCommands'], 410)

    def test_false_note_result(self):
        self.reject(lambda f: change_json(f, 'note-order/report.json',
                    lambda r: r['cases'][0]['nodes']['ooxml-resave'].__setitem__('contractPreserved', True)), 'Note contract outcome')

    def test_actual_note_ownership_swap(self):
        def mutate(f):
            path = 'note-order/ids-only/ooxml-resave/ids-only.docx'
            def swap(raw):
                return raw.replace('NOTE-A:α'.encode(), b'TEMP').replace('NOTE-B:β'.encode(), 'NOTE-A:α'.encode()).replace(b'TEMP', 'NOTE-B:β'.encode())
            change_package(f, path, 'word/footnotes.xml', swap)
            def row(r):
                node = r['cases'][1]['nodes']['ooxml-resave']
                node.update(bytes=len(f[path]), sha256=verify.sha(f[path]))
                node['joins'][0]['text'], node['joins'][1]['text'] = node['joins'][1]['text'], node['joins'][0]['text']
                node['contractPreserved'] = False
            change_json(f, 'note-order/report.json', row)
        self.reject(mutate, 'Actual note anchor-to-content ownership')

    def test_note_input_unrelated_change(self):
        def mutate(f):
            path = 'note-order/ids-only/ids-only.docx'
            change_package(f, path, 'word/document.xml', lambda b: b.replace(b'12240', b'12241'))
            change_json(f, 'note-order/report.json', lambda r: r['cases'][1]['nodes']['source'].update(bytes=len(f[path]), sha256=verify.sha(f[path])))
        self.reject(mutate, 'Exact independent note input mutation')

    def test_note_native_executable(self):
        def mutate(f):
            label = 'original/ooxml-resave/command'
            change_json(f, 'note-order/report.json', lambda r: next(c for c in r['commands'] if c['directory'] == label)['argv'].__setitem__(0, '/usr/bin/true'))
            change_json(f, 'note-order/' + label + '/command.json', lambda c: c['argv'].__setitem__(0, '/usr/bin/true'))
        self.reject(mutate, 'Exact successful note command')

    def test_note_parser_identity(self):
        self.reject(lambda f: change_json(f, 'note-order/report.json',
                    lambda r: r['parser'].__setitem__('sha256', '0' * 64)), 'Note experiment uses old measured parser')

    def test_note_missing_variant(self):
        self.reject(lambda f: change_json(f, 'note-order/report.json', lambda r: r['cases'].pop()), 'Complete note variant inventory')

    def test_false_metadata_retention(self):
        self.reject(lambda f: change_json(f, 'markdown-metadata/report.json',
                    lambda r: r['paths']['body'].__setitem__('metadataEqual', True)), 'Metadata loss remains explicit', 'metadata')

    def test_empty_metadata_reader_body(self):
        def mutate(f):
            name = 'markdown-metadata/body.json'
            change_json(f, name, lambda r: r.__setitem__('blocks', []))
            change_json(f, 'markdown-metadata/report.json', lambda r: r['commands'][2].__setitem__('stdoutSha256', verify.sha(f[name])))
        self.reject(mutate, 'Metadata reread preserves body', 'metadata')

    def test_metadata_executable(self):
        self.reject(lambda f: change_json(f, 'markdown-metadata/report.json',
                    lambda r: r['commands'][1].__setitem__('argv', ['/usr/bin/true'])), 'Exact successful metadata command', 'metadata')

    def test_metadata_source_title(self):
        def mutate(f):
            path = 'markdown-metadata/metadata.docx'
            change_package(f, path, 'word/document.xml', lambda b: b.replace(b'KEPT-TITLE', b'WRONG-TITLE'))
            change_json(f, 'markdown-metadata/report.json', lambda r: r['input'].__setitem__('sha256', verify.sha(f[path])))
        self.reject(mutate, 'Authored metadata paragraph contract', 'metadata')

    def test_historical_review_relabel(self):
        self.reject(lambda f: change_json(f, 'independent-review/argv-counterexample-f5afbcb4ddef.json',
                    lambda r: r['outcome'].__setitem__('accepted', False)), 'Historical argv findings remain distinct', 'review')

    def test_replay_helper_substitution(self):
        def mutate(f):
            path = 'tool/fidelity/verify_path_matrix.py'
            f['replay-source/' + path] += b'\n# substituted helper\n'
            change_json(f, 'replay-source.json', lambda r: r['files'].__setitem__(path, verify.sha(f['replay-source/' + path])))
        self.reject(mutate, 'Exact replay source inventory', 'replay')

    def test_narrowed_measured_source_inventory(self):
        files = {p.relative_to(self.baseline).as_posix(): p.read_bytes()
                 for p in self.baseline.rglob('*') if p.is_file()}
        path = 'lib/src/legacy_word_structured_parser.dart'
        report = json.loads(files['run/report.json'])
        for name in ['sourceBefore', 'sourceAfterBuild', 'sourceAfter']:
            report[name]['files'].pop(path)
            report[name]['sha256'] = verify.sha(json.dumps(report[name]['files'], sort_keys=True, separators=(',', ':')).encode())
        files['run/report.json'] = encode(report)
        source = json.loads(files['source-identities.json'])
        source['files'] = [r for r in source['files'] if r['path'] != path]
        source['measuredSourceFiles'] -= 1
        files['source-identities.json'] = encode(source)
        del files['source/' + path]
        original_manifest = verify.read(verify.HERE / 'baseline-manifest.json')
        modes = {r['path']: r['mode'] for r in original_manifest['files']}
        with tempfile.TemporaryDirectory(prefix='path-source-resealed-') as temporary:
            root = Path(temporary)
            packed = root / 'baseline.tar.xz'
            with tarfile.open(packed, 'w:xz', preset=0) as tf:
                for name, raw in sorted(files.items()):
                    item = tarfile.TarInfo(name)
                    item.size, item.mode = len(raw), int(modes[name], 8)
                    tf.addfile(item, io.BytesIO(raw))
            raw = packed.read_bytes()
            manifest = {'schema': 1, 'archive': packed.name, 'archiveBytes': len(raw), 'archiveSha256': verify.sha(raw),
                        'fileCount': len(files), 'rawBytes': sum(map(len, files.values())),
                        'files': [{'path': n, 'bytes': len(b), 'sha256': verify.sha(b), 'mode': modes[n]}
                                  for n, b in sorted(files.items())]}
            (root / 'baseline-manifest.json').write_bytes(encode(manifest))
            target = root / 'extracted'
            verify.unpack(root, 'baseline', target)
            with self.assertRaisesRegex(ValueError, 'Complete immutable measured source inventory'):
                verify.check_sources(target, verify.BASELINE_PIN, verify.BASELINE_TREE, verify.HERE.parents[2])


if __name__ == '__main__':
    unittest.main()
