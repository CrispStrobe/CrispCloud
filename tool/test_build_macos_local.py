#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).with_name('build_macos_local.sh')

class LocalMacBuildTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / 'tool').mkdir()
        (self.root / 'bin').mkdir()
        shutil.copy2(SOURCE, self.root / 'tool/build_macos_local.sh')
        (self.root / 'pubspec.yaml').write_text('version: 1.3.4+39\n')
        helper = self.root / 'record.py'
        helper.write_text('''import json,os,pathlib,sys
name=sys.argv[1]; args=sys.argv[2:]
root=pathlib.Path(os.environ['TEST_BUILD_ROOT'])
with (root/'calls.jsonl').open('a') as f:f.write(json.dumps({'tool':name,'args':args,'configuration':os.environ.get('SIGNING_CONFIGURATION')})+'\\n')
if name=='ps':print(os.environ.get('TEST_RUNNING_APP',''))
elif name=='git':print('abc12345')
elif name=='signer':
 key='TEST_PREFLIGHT_EXIT' if args==['--check'] else 'TEST_SIGN_EXIT'
 sys.exit(int(os.environ.get(key,'0')))
elif name=='codesign':sys.exit(int(os.environ.get('TEST_VERIFY_EXIT','0')))
elif name=='flutter':
 mode='Debug' if '--debug' in args else 'Profile' if '--profile' in args else 'Release'
 (root/'build/macos/Build/Products'/mode/'CrispCloud.app').mkdir(parents=True)
''')
        stub = '#!/usr/bin/env bash\nexec python3 "$TEST_BUILD_ROOT/record.py" %s "$@"\n'
        (self.root / 'tool/sign_macos_local.sh').write_text(stub % 'signer')
        for command in ['ps', 'git', 'flutter', 'codesign', 'open']:
            path = self.root / 'bin' / command
            path.write_text(stub % command)
            path.chmod(0o755)
        self.env = dict(os.environ, TEST_BUILD_ROOT=str(self.root), PATH=str(self.root/'bin')+os.pathsep+os.environ['PATH'])

    def run_build(self, *args, **env):
        result = subprocess.run(['bash', str(self.root/'tool/build_macos_local.sh'), *args], env=dict(self.env, **env), capture_output=True, text=True)
        calls = [json.loads(line) for line in (self.root/'calls.jsonl').read_text().splitlines()]
        return result, calls

    def test_debug_is_signed_and_verified_before_launch_and_preserves_arguments(self):
        result, calls = self.run_build('--debug', '--launch', '--no-pub', '--dart-define=VALUE=two words')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([x['tool'] for x in calls], ['ps','signer','git','flutter','signer','codesign','open'])
        self.assertEqual(calls[1]['args'], ['--check'])
        self.assertEqual(calls[1]['configuration'], 'Debug')
        self.assertEqual(calls[4]['configuration'], 'Debug')
        self.assertIn('--debug', calls[3]['args'])
        self.assertIn('--dart-define=VALUE=two words', calls[3]['args'])
        self.assertIn('--test-requirement', calls[5]['args'])
        self.assertIn('certificate leaf[subject.OU] = "N9XSJ4M3GT"', calls[5]['args'][calls[5]['args'].index('--test-requirement')+1])

    def test_missing_identity_fails_before_compilation(self):
        result,calls=self.run_build('--launch',TEST_PREFLIGHT_EXIT='1')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual([x['tool'] for x in calls],['ps','signer'])

    def test_signing_failure_never_launches(self):
        result,calls=self.run_build('--launch',TEST_SIGN_EXIT='1')
        self.assertNotEqual(result.returncode,0)
        self.assertNotIn('open',[x['tool'] for x in calls])
        self.assertNotIn('codesign',[x['tool'] for x in calls])

    def test_untrusted_signature_never_launches(self):
        result,calls=self.run_build('--launch',TEST_VERIFY_EXIT='1')
        self.assertNotEqual(result.returncode,0)
        self.assertNotIn('open',[x['tool'] for x in calls])

    def test_running_output_is_preserved(self):
        path=self.root/'build/macos/Build/Products/Release/CrispCloud.app/Contents/MacOS/CrispCloud'
        result,calls=self.run_build(TEST_RUNNING_APP=str(path))
        self.assertNotEqual(result.returncode,0)
        self.assertEqual([x['tool'] for x in calls],['ps'])

    def test_release_without_launch_is_default(self):
        result,calls=self.run_build()
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('--release',next(x['args'] for x in calls if x['tool']=='flutter'))
        self.assertNotIn('open',[x['tool'] for x in calls])

if __name__ == '__main__':unittest.main()
