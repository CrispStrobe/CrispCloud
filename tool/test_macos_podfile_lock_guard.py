import hashlib
import tempfile
import unittest
from pathlib import Path

import macos_podfile_lock_guard as guard

SPEC_NEW = '{\n  "name": "share_plus",\n  "dependencies": {\n    "FlutterMacOS": []\n  }\n}\n'
SPEC_OLD = '{\n  "name": "share_plus",\n  "dependencies": {\n    "FlutterMacOS": [\n\n    ]\n  }\n}\n'
sha = lambda text: hashlib.sha1(text.encode()).hexdigest()


def lock(share_plus: str, ordered: str = "a" * 40, version: str = "1.0.0",
         cocoapods: str = "1.17.0") -> str:
    return f"""PODS:
  - OrderedSet (6.0.3)
  - share_plus ({version}):
    - FlutterMacOS

DEPENDENCIES:
  - share_plus (from `Flutter/ephemeral/.symlinks/plugins/share_plus/macos`)

EXTERNAL SOURCES:
  share_plus:
    :path: Flutter/ephemeral/.symlinks/plugins/share_plus/macos

SPEC CHECKSUMS:
  OrderedSet: {ordered}
  share_plus: {share_plus}

PODFILE CHECKSUM: {"c" * 40}

COCOAPODS: {cocoapods}
"""


class PodfileLockGuardTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.specs = Path(self.dir.name)
        self.committed = lock(sha(SPEC_NEW))

    def tearDown(self):
        self.dir.cleanup()

    def check(self, built: str, spec: str = SPEC_OLD) -> list[str]:
        (self.specs / "share_plus.podspec.json").write_text(spec)
        return guard.problems(self.committed, built, self.specs)

    def test_old_json_gem_formatting_is_tolerated(self):
        self.assertNotEqual(sha(SPEC_OLD), sha(SPEC_NEW))
        self.assertEqual(self.check(lock(sha(SPEC_OLD))), [])

    def test_cocoapods_version_line_is_tolerated(self):
        self.assertEqual(self.check(lock(sha(SPEC_NEW), cocoapods="1.16.2"), SPEC_NEW), [])

    def test_real_podspec_change_fails(self):
        changed = SPEC_OLD.replace("share_plus", "share_plus2", 1)
        self.assertIn("podspec content differs", self.check(lock(sha(changed)), changed)[0])

    def test_version_change_fails(self):
        issues = self.check(lock(sha(SPEC_OLD), version="1.0.1"))
        self.assertIn("pod versions, dependencies or sources changed", issues)

    def test_downloaded_pod_checksum_change_fails(self):
        issues = self.check(lock(sha(SPEC_OLD), ordered="b" * 40))
        self.assertIn("OrderedSet: checksum of a downloaded pod changed", issues)

    def test_missing_local_podspec_fails(self):
        issues = guard.problems(self.committed, lock(sha(SPEC_OLD)), self.specs)
        self.assertIn("no ", issues[0])


if __name__ == "__main__":
    unittest.main()
