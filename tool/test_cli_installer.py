from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

class InstallerTests(unittest.TestCase):
    def test_install_update_preserves_bundle_and_refuses_unrelated_commands(self):
        with tempfile.TemporaryDirectory(prefix='cli install ') as temporary:
            root = Path(temporary)
            bundle = root / 'bundle with spaces'
            (bundle / 'bin').mkdir(parents=True)
            (bundle / 'lib').mkdir()
            (bundle / 'lib/native-library').write_text('native asset')
            shutil.copy(Path(__file__).resolve().parents[1] / 'cli/install.sh', bundle)
            for name in ('crispcloud', 'crisp'):
                exe = bundle / 'bin' / name
                exe.write_text('#!/bin/sh\necho fixture-v1\n')
                exe.chmod(0o755)
            prefix = root / 'installed with spaces'
            command = ['sh', str(bundle / 'install.sh'), '--prefix', str(prefix)]
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(subprocess.check_output([str(prefix / 'bin/crispcloud')],text=True).strip(), 'fixture-v1')
            self.assertEqual((prefix / 'lib/crispcloud/current/lib/native-library').read_text(), 'native asset')
            (bundle / 'bin/crispcloud').write_text('#!/bin/sh\necho fixture-v2\n')
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(subprocess.check_output([str(prefix / 'bin/crispcloud')],text=True).strip(), 'fixture-v2')
            self.assertEqual(len(list((prefix / 'lib/crispcloud/releases').iterdir())),2)
            (prefix / 'bin/crisp').unlink()
            (prefix / 'bin/crisp').write_text('unrelated')
            self.assertNotEqual(subprocess.run(command,capture_output=True).returncode,0)
            self.assertEqual((prefix / 'bin/crisp').read_text(),'unrelated')

if __name__ == '__main__': unittest.main()
