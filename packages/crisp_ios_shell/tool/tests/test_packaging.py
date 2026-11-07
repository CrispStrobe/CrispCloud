"""Exercise the actual packaging gate with representative Mach-O load lists."""
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest import mock

TOOL = Path(__file__).resolve().parents[1] / 'check_packaging.py'
spec = importlib.util.spec_from_file_location('crisp_packaging', TOOL)
packaging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packaging)


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.app = Path(self.temporary.name) / 'Runner.app'
        self.app.mkdir()
        (self.app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable': 'Runner'}))
        (self.app / 'Runner').write_bytes(b'fake Mach-O fixture')
        manifest = json.loads((TOOL.parents[1] / 'tool/sources.json').read_text())
        for name in manifest['targets'] + manifest['dash_variants']:
            framework = self.app / 'Frameworks' / f'{name}.framework'
            framework.mkdir(parents=True)
            (framework / name).write_bytes(b'embedded command fixture')
        self.good_loads = 'Runner:\n\t@rpath/ios_system.framework/ios_system (compatibility version 1.0.0)\n'

    def test_validates_complete_embedding_and_lazy_commands(self):
        with mock.patch.object(packaging.subprocess, 'check_output', return_value=self.good_loads):
            packaging.validate(self.app)

    def test_requires_each_nested_dash_image(self):
        (self.app / 'Frameworks/dashE.framework/dashE').unlink()
        with self.assertRaisesRegex(RuntimeError, 'dashE'):
            packaging.validate(self.app)

    def test_rejects_eager_dash_linkage(self):
        loads = self.good_loads + '\t@rpath/dash.framework/dash\n'
        with mock.patch.object(packaging.subprocess, 'check_output', return_value=loads):
            with self.assertRaisesRegex(RuntimeError, 'eagerly links dash'):
                packaging.validate(self.app)

    def test_rejects_eager_linkage_inside_flutter_plugin(self):
        framework = self.app / 'Frameworks/crisp_ios_shell.framework'
        framework.mkdir()
        (framework / 'crisp_ios_shell').write_bytes(b'plugin fixture')
        with mock.patch.object(packaging.subprocess, 'check_output', side_effect=[self.good_loads, '@rpath/files.framework/files\n']):
            with self.assertRaisesRegex(RuntimeError, 'eagerly links files'):
                packaging.validate(self.app)

    def test_requires_the_real_runtime_to_be_linked(self):
        with mock.patch.object(packaging.subprocess, 'check_output', return_value='Runner:\n\t/usr/lib/libSystem.B.dylib\n'):
            with self.assertRaisesRegex(RuntimeError, 'real ios_system runtime'):
                packaging.validate(self.app)

    def test_accepts_runtime_linked_through_plugin(self):
        framework = self.app / 'Frameworks/crisp_ios_shell.framework'
        framework.mkdir()
        (framework / 'crisp_ios_shell').write_bytes(b'plugin fixture')
        with mock.patch.object(packaging.subprocess, 'check_output', side_effect=['Runner:\n\t@rpath/crisp_ios_shell.framework/crisp_ios_shell\n', self.good_loads]):
            packaging.validate(self.app)


if __name__ == '__main__':
    unittest.main()
