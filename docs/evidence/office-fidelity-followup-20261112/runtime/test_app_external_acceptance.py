"""Scratch-only controls for collection guards; never invokes SDK or rendering."""
import argparse
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
import app_external_acceptance as acceptance


class FrozenSnapshotTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(
            prefix='app-runner-controls-', dir=acceptance.RUNTIME.parent / 'tmp')
        self.addCleanup(temporary.cleanup)
        self.output = Path(temporary.name)
        self.inputs = self.output / 'inputs'
        self.inputs.mkdir()
        self.counts = argparse.Namespace(engine_count=2, host_count=1, managed_count=2)
        declared_engine = {
            'version': 1, 'package': 'quds_office_engine', 'expected_file_count': 2,
            'series': [], 'standalone': [{'path': f'fidelity/case-{n}.docx'} for n in (1, 2)],
        }
        declared_host = {'version': 1, 'outputs': ['build/fidelity-host/save.xlsx']}
        acceptance.write_json(self.output / 'engine-output-manifest.json', declared_engine)
        acceptance.write_json(self.output / 'host-output-manifest.json', declared_host)
        rows = []
        for name in [acceptance.ENGINE_PREFIX + p['path'] for p in declared_engine['standalone']] + declared_host['outputs']:
            path = self.inputs / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(('Synthetic guard input: ' + name).encode())
            rows.append({'path': name, 'bytes': path.stat().st_size, 'sha256': acceptance.sha(path),
                         'producer_group': 'engine' if name.startswith(acceptance.ENGINE_PREFIX) else 'host'})
        engine_rows = [{**r, 'path': r['path'][len(acceptance.ENGINE_PREFIX):]} for r in rows[:2]]
        engine = {'ok': True, 'errors': [], 'expected_files': 2, 'observed_files': 2, 'verified_files': 2,
                  'manifest_sha256': acceptance.sha(self.output / 'engine-output-manifest.json'), 'files': engine_rows}
        host = {'expected': 1, 'verified': 1, 'failures': [], 'files': rows[2:],
                'manifest_sha256': acceptance.sha(self.output / 'host-output-manifest.json')}
        acceptance.write_json(self.output / 'engine-inventory.json', engine)
        acceptance.write_json(self.output / 'host-inventory.json', host)
        acceptance.write_json(self.output / 'managed-source-manifest.json', {
            'source_commit': 'a' * 40, 'files': {'a.dart': '0' * 64, 'b.dart': '1' * 64}})
        self.manifest = {
            'input_root': str(self.inputs), 'total': 3, 'engine_files': 2, 'host_files': 1,
            'managed_source_files_verified': 2, 'managed_source_commit': 'a' * 40,
            'metadata_sha256': {name: acceptance.sha(self.output / name)
                                for name in acceptance.FROZEN_METADATA.values()},
            'files': rows,
        }
        acceptance.write_json(self.output / 'input-manifest.json', self.manifest)
        self.schema = {'Files': 3, 'Failures': 0, 'Reports': [
            {'File': str(self.inputs / r['path']), 'Sha256': r['sha256'], 'Errors': []} for r in rows]}
        acceptance.write_json(self.output / 'schema-report.json', self.schema)

    def test_complete_exact_snapshot_passes(self):
        result = acceptance.verify_schema(self.output, self.counts)
        self.assertEqual(result['total'], 3)

    def test_explicit_counts_reject_stale_snapshot(self):
        for field in ('engine_count', 'host_count', 'managed_count'):
            with self.subTest(field=field):
                wrong = copy.copy(self.counts)
                setattr(wrong, field, getattr(wrong, field) + 1)
                with self.assertRaises(ValueError):
                    acceptance.verify_schema(self.output, wrong)

    def test_input_tampering_and_extra_file_are_rejected(self):
        path = self.inputs / self.manifest['files'][0]['path']
        original = path.read_bytes()
        path.write_bytes(b'X' * len(original))
        with self.assertRaisesRegex(ValueError, 'Snapshot bytes changed'):
            acceptance.verify_schema(self.output, self.counts)
        path.write_bytes(original)
        (self.inputs / 'unexpected.docx').write_bytes(b'extra')
        with self.assertRaisesRegex(ValueError, 'file set differs'):
            acceptance.verify_schema(self.output, self.counts)

    def test_equal_count_inventory_substitution_is_rejected(self):
        host = acceptance.read_json(self.output / 'host-inventory.json')
        host['files'][0]['path'] = 'build/fidelity-host/replacement.xlsx'
        acceptance.write_json(self.output / 'host-inventory.json', host)
        self.manifest['metadata_sha256']['host-inventory.json'] = acceptance.sha(self.output / 'host-inventory.json')
        acceptance.write_json(self.output / 'input-manifest.json', self.manifest)
        with self.assertRaisesRegex(ValueError, 'Host receipt paths differ'):
            acceptance.verify_schema(self.output, self.counts)

    def test_copied_metadata_tampering_is_rejected(self):
        path = self.output / 'engine-output-manifest.json'
        path.write_text(path.read_text() + '\n')
        with self.assertRaisesRegex(ValueError, 'Frozen metadata bytes changed'):
            acceptance.verify_schema(self.output, self.counts)

    def test_sdk_duplicate_missing_wrong_hash_and_error_are_rejected(self):
        for kind in ('duplicate', 'missing', 'hash', 'error', 'exception'):
            with self.subTest(kind=kind):
                schema = copy.deepcopy(self.schema)
                if kind == 'duplicate':
                    schema['Reports'][1] = copy.deepcopy(schema['Reports'][0])
                elif kind == 'missing':
                    schema['Reports'].pop()
                elif kind == 'hash':
                    schema['Reports'][0]['Sha256'] = 'f' * 64
                elif kind == 'error':
                    schema['Reports'][0]['Errors'] = ['schema failure']
                else:
                    schema['Reports'][0]['Exception'] = 'read failure'
                acceptance.write_json(self.output / 'schema-report.json', schema)
                with self.assertRaises(ValueError):
                    acceptance.verify_schema(self.output, self.counts)

    def test_single_sdk_path_alias_is_rejected(self):
        file = Path(self.schema['Reports'][0]['File'])
        self.schema['Reports'][0]['File'] = str(file.parent) + '/./' + file.name
        acceptance.write_json(self.output / 'schema-report.json', self.schema)
        with self.assertRaisesRegex(ValueError, 'exact canonical input path'):
            acceptance.verify_schema(self.output, self.counts)

    def test_parent_directory_symlink_is_rejected(self):
        original = self.inputs / 'build/fidelity-host'
        moved = self.inputs / 'saved-host'
        original.rename(moved)
        original.symlink_to(moved, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'Symlink in evidence path'):
            acceptance.require_file(self.inputs, 'build/fidelity-host/save.xlsx')


class CountAndCliTests(unittest.TestCase):
    def test_current_explicit_counts_derive_exact_combined_set(self):
        counts = argparse.Namespace(engine_count=296, host_count=62, managed_count=1)
        engine_names = [f'fidelity/native-{n}.docx' for n in range(counts.engine_count)]
        host_names = [f'build/fidelity-host/host-{n}.xlsx' for n in range(counts.host_count)]
        def row(name):
            return {'path': name, 'bytes': 1, 'sha256': 'a' * 64}
        engine = {'ok': True, 'errors': [], 'expected_files': 296, 'observed_files': 296,
                  'verified_files': 296, 'files': [row(n) for n in engine_names]}
        host = {'expected': 62, 'verified': 62, 'failures': [], 'files': [row(n) for n in host_names]}
        declared_engine = {'version': 1, 'package': 'quds_office_engine', 'series': [],
                           'standalone': [{'path': n} for n in engine_names], 'expected_file_count': 296}
        declared_host = {'version': 1, 'outputs': host_names}
        entries = acceptance.inventory_entries(engine, host, declared_engine, declared_host, counts)
        self.assertEqual(len(entries), 358)
        self.assertEqual(sum(e['producer_group'] == 'engine' for e in entries), 296)

    def test_every_entry_point_requires_all_explicit_counts(self):
        for script, arguments in (
            ('app_external_acceptance.py', ['collect-schema', '--repository', '.', '--app-commit', 'a' * 40,
                                            '--source-commit', 'b' * 40, '--output-root', 'unused']),
            ('app_external_acceptance.py', ['native', '--output-root', 'unused']),
            ('probe_host_native_gap.py', ['.', '.', 'unused', '--manifest', 'unused.json',
                                          '--schema-report', 'unused-sdk.json']),
        ):
            for missing in ('engine', 'host', 'managed'):
                with self.subTest(script=script, command=arguments[0], missing=missing):
                    options = [part for name in ('engine', 'host', 'managed') if name != missing
                               for part in (f'--{name}-count', '1')]
                    run = subprocess.run([sys.executable, '-B', str(acceptance.RUNTIME / script),
                                          *arguments, *options], capture_output=True, text=True)
                    self.assertEqual(run.returncode, 2)
                    self.assertIn(f'--{missing}-count', run.stderr)

    def test_counts_must_be_positive(self):
        for value in ('0', '-1', 'not-an-integer'):
            with self.assertRaises(argparse.ArgumentTypeError):
                acceptance.positive_count(value)


if __name__ == '__main__':
    unittest.main()
