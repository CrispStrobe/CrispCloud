"""Mutation controls prove that the host schema gate cannot validate a subset."""
import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

import office_host_evidence as evidence


def package(file, extension=None, main=None):
    extension = extension or file.suffix
    kind, namespace, local = evidence.MAIN_TYPES[extension]
    main = main or {'.docx': 'word/document.xml', '.xlsx': 'xl/workbook.xml',
                    '.pptx': 'ppt/presentation.xml'}.get(extension, 'word/document.xml')
    file.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(file, 'w') as archive:
        archive.writestr('[Content_Types].xml',
            f'<Types xmlns="{evidence.CONTENT_TYPES}"><Override PartName="/{main}" '
            f'ContentType="{evidence.MAIN_CONTENT_TYPES[extension]}"/></Types>')
        archive.writestr('_rels/.rels',
            f'<Relationships xmlns="{evidence.PACKAGE_REL}"><Relationship Id="main" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
            f'Target="{main}"/></Relationships>')
        archive.writestr(main, f'<{local} xmlns="http://schemas.openxmlformats.org/{namespace}/2006/main"/>')


class HostEvidenceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def populate(self, base=None):
        base = base or self.root
        for name in evidence.expected_paths():
            file = base / name
            package(file)
        return base

    def test_complete_tree_has_hashes_for_every_expected_export(self):
        self.populate()
        report = evidence.inspect(self.root)
        self.assertEqual(report['failures'], [])
        self.assertEqual(report['verified'], len(evidence.expected_paths()))
        self.assertEqual({entry['path'] for entry in report['files']},
                         set(evidence.expected_paths()))
        for entry in report['files']:
            self.assertEqual(entry['sha256'], hashlib.sha256(
                (self.root / entry['path']).read_bytes()).hexdigest())

    def test_artifact_download_wrapper_preserves_complete_relative_paths(self):
        self.populate(self.root / 'downloaded-artifact')
        report = evidence.inspect(self.root)
        self.assertEqual(report['failures'], [])
        self.assertEqual(report['verified'], len(evidence.expected_paths()))

    def test_missing_any_declared_host_output_fails(self):
        for name in evidence.expected_paths():
            with self.subTest(name=name):
                self.populate()
                (self.root / name).unlink()
                self.assertTrue(evidence.inspect(self.root)['failures'])

    def test_duplicate_complete_artifacts_fail(self):
        self.populate(self.root / 'first')
        self.populate(self.root / 'second')
        self.assertTrue(evidence.inspect(self.root)['failures'])

    def test_extra_output_and_invalid_zip_fail(self):
        self.populate()
        for directory in ('fidelity-host', 'fidelity-custom-tabs'):
            with self.subTest(directory=directory):
                extra = self.root / 'build' / directory / 'unreviewed.docx'
                extra.write_bytes(b'unreviewed')
                self.assertTrue(evidence.inspect(self.root)['failures'])
                extra.unlink()
        (self.root / evidence.expected_paths()[0]).write_bytes(b'not a zip')
        self.assertTrue(evidence.inspect(self.root)['failures'])

    def test_each_office_extension_requires_its_own_format(self):
        for extension in evidence.OFFICE:
            with self.subTest(extension=extension):
                self.populate()
                name = next(name for name in evidence.expected_paths()
                            if Path(name).suffix == extension)
                wrong = '.xlsx' if extension != '.xlsx' else '.docx'
                package(self.root / name, extension=wrong)
                failures = evidence.inspect(self.root)['failures']
                self.assertEqual(len(failures), 1)
                self.assertIn(f'{name}: invalid Office package', failures[0])
                self.assertIn('content type', failures[0])

    def test_main_parts_require_valid_xml_with_the_correct_root(self):
        for extension in evidence.OFFICE:
            for content in ('<not-the-main-part/>', '<not-xml'):
                with self.subTest(extension=extension, content=content):
                    self.populate()
                    name = next(name for name in evidence.expected_paths()
                                if Path(name).suffix == extension)
                    file = self.root / name
                    main = evidence.inspect_package(file)
                    with ZipFile(file) as archive:
                        parts = {part: archive.read(part) for part in archive.namelist()}
                    parts[main] = content.encode()
                    with ZipFile(file, 'w') as archive:
                        for part, data in parts.items():
                            archive.writestr(part, data)
                    failures = evidence.inspect(self.root)['failures']
                    self.assertEqual(len(failures), 1)
                    self.assertIn(f'{name}: invalid Office package', failures[0])

    def test_external_file_cannot_satisfy_an_artifact(self):
        self.populate()
        file = self.root / evidence.expected_paths()[0]
        with tempfile.TemporaryDirectory() as outside:
            external = Path(outside) / 'outside.docx'
            external.write_bytes(file.read_bytes())
            file.unlink()
            file.symlink_to(external)
            self.assertTrue(evidence.inspect(self.root)['failures'])

    def test_clean_only_removes_manifest_outputs_and_receipt(self):
        self.populate()
        receipt = self.root / evidence.REPORT
        receipt.write_text('{}')
        unrelated = self.root / 'build/fidelity-host/keep.txt'
        unrelated.write_text('retained')
        evidence.clean(self.root)
        self.assertFalse(receipt.exists())
        self.assertTrue(all(not (self.root / p).exists() for p in evidence.expected_paths()))
        self.assertEqual(unrelated.read_text(), 'retained')

    def test_clean_preflights_later_symlink_before_deleting_any_evidence(self):
        paths = [evidence.expected_paths()[0], 'build/fidelity-host/late-symlink-check/late.docx']
        patched = patch.object(evidence, 'expected_paths', return_value=paths)
        patched.start()
        self.addCleanup(patched.stop)
        self.populate()
        last = self.root / evidence.expected_paths()[-1]
        original = last.read_bytes()
        last.unlink()
        last.parent.rmdir()
        with tempfile.TemporaryDirectory() as outside:
            external = Path(outside) / last.name
            external.write_bytes(original)
            last.parent.symlink_to(outside, target_is_directory=True)
            with self.assertRaises(ValueError):
                evidence.clean(self.root)
            self.assertTrue((self.root / evidence.expected_paths()[0]).exists())
            self.assertEqual(external.read_bytes(), original)

    def test_each_office_format_and_relocated_main_part(self):
        for extension in evidence.OFFICE:
            with self.subTest(format=extension):
                file = self.root / ('native' + extension)
                package(file, main='documents/main.xml')
                self.assertEqual(evidence.inspect_package(file), 'documents/main.xml')

    def test_renamed_docx_cannot_satisfy_a_presentation_or_workbook(self):
        for extension in ('.pptx', '.xlsx', '.docm', '.dotx', '.dotm'):
            with self.subTest(format=extension):
                file = self.root / ('renamed' + extension)
                package(file, extension='.docx')
                with self.assertRaisesRegex(ValueError, 'content type'):
                    evidence.inspect_package(file)

    def test_missing_escaping_external_duplicate_and_wrong_root_are_rejected(self):
        file = self.root / 'broken.pptx'
        changes = {
            'missing': ('_rels/.rels', lambda text: text.replace('ppt/presentation.xml', 'missing.xml')),
            'escaping': ('_rels/.rels', lambda text: text.replace('ppt/presentation.xml', '../outside.xml')),
            'external': ('_rels/.rels', lambda text: text.replace('Target=', 'TargetMode="External" Target=')),
            'wrong-root': ('ppt/presentation.xml', lambda text: text.replace('presentation ', 'workbook ')),
            'wrong-type': ('[Content_Types].xml', lambda text: text.replace('presentationml.presentation', 'spreadsheetml.sheet')),
            'malformed': ('ppt/presentation.xml', lambda _: '<'),
        }
        for label, (name, corrupt) in changes.items():
            with self.subTest(corruption=label):
                package(file)
                with ZipFile(file) as archive:
                    parts = {part: archive.read(part) for part in archive.namelist()}
                parts[name] = corrupt(parts[name].decode()).encode()
                with ZipFile(file, 'w') as archive:
                    for part, data in parts.items():
                        archive.writestr(part, data)
                with self.assertRaises((ValueError, evidence.ET.ParseError)):
                    evidence.inspect_package(file)
        package(file)
        with ZipFile(file, 'a') as archive, self.assertWarns(UserWarning):
            archive.writestr('ppt/presentation.xml', '<duplicate/>')
        with self.assertRaisesRegex(ValueError, 'duplicate ZIP'):
            evidence.inspect_package(file)

    def test_manifest_requires_normalized_scoped_supported_paths(self):
        manifest = self.root / 'manifest.json'
        for invalid in ('elsewhere/file.docx', 'build/./fidelity-host/a.docx',
                        'build/fidelity-host/../file.docx', 'build\\fidelity-host\\a.docx',
                        'build/fidelity-host/a.zip'):
            with self.subTest(path=invalid), patch.object(evidence, 'MANIFEST', manifest):
                manifest.write_text(evidence.json.dumps({'version': 1, 'outputs': [invalid]}))
                with self.assertRaises(ValueError):
                    evidence.expected_paths()
        with patch.object(evidence, 'MANIFEST', manifest):
            names = [f'build/fidelity-host/valid{extension}' for extension in sorted(evidence.OFFICE)]
            manifest.write_text(evidence.json.dumps({'version': 1, 'outputs': names}))
            self.assertEqual(evidence.expected_paths(), names)


if __name__ == '__main__':
    unittest.main()
