"""Failure-path tests for release evidence, independent of Flutter/signing."""

import hashlib
import json
import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import crypto_release_evidence as evidence


class ReleaseEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.inventory = {
            "schema_version": 1,
            "repository": "https://github.com/CrispStrobe/CrispCloud",
            "required_providers": ["filen_client", "internxt_client"],
            "crypto_packages": ["pointycastle"],
            "reviewed_files": ["lib/crypto.dart"],
        }
        self.write("docs/crypto-inventory.json", json.dumps(self.inventory))
        self.write("lib/crypto.dart", "// reviewed fixture\n")
        self.write("pubspec.yaml", "name: fixture\n")
        self.write("pubspec.lock", "packages:\n  filen_client:\n  internxt_client:\n  pointycastle:\n")
        self.write(".fvmrc", '{"flutter":"3.47.8"}')
        for name in ("ios/Runner/Info.plist", "macos/Runner/Info.plist"):
            self.write(name, plistlib.dumps({"ITSAppUsesNonExemptEncryption": True}))

    def write(self, name, contents):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(contents, bytes):
            path.write_bytes(contents)
        else:
            path.write_text(contents)
        return path

    def git_fixture(self, root, *args):
        if args == ("rev-parse", "HEAD"):
            return "a" * 40
        if args == ("rev-parse", "HEAD^{tree}"):
            return "b" * 40
        return ""

    def test_mandatory_provider_cannot_be_removed(self):
        self.inventory["required_providers"].remove("internxt_client")
        self.write("docs/crypto-inventory.json", json.dumps(self.inventory))
        with self.assertRaisesRegex(evidence.EvidenceError, "both Filen and Internxt"):
            evidence.validate(self.root)

    def test_unresolved_provider_and_reviewed_dependency_fail(self):
        for name in ("internxt_client", "pointycastle"):
            with self.subTest(name=name):
                self.write("pubspec.lock", "packages:\n" + "".join(
                    f"  {item}:\n" for item in ["filen_client", "internxt_client", "pointycastle"]
                    if item != name))
                with self.assertRaisesRegex(evidence.EvidenceError, name):
                    evidence.validate(self.root)

    def test_false_apple_declaration_fails(self):
        self.write("ios/Runner/Info.plist", plistlib.dumps({"ITSAppUsesNonExemptEncryption": False}))
        with self.assertRaisesRegex(evidence.EvidenceError, "questionnaire"):
            evidence.validate(self.root)

    def test_unreviewed_local_dependency_override_fails(self):
        self.write("packages/client/pubspec_overrides.yaml", "dependency_overrides: {}\n")
        with self.assertRaisesRegex(evidence.EvidenceError, "overrides"):
            evidence.validate(self.root)

    def test_inventory_cannot_read_outside_source(self):
        self.inventory["reviewed_files"] = ["../credentials"]
        self.write("docs/crypto-inventory.json", json.dumps(self.inventory))
        with self.assertRaisesRegex(evidence.EvidenceError, "escapes"):
            evidence.validate(self.root)

    def test_unreviewed_native_crypto_binary_override_fails(self):
        self.write("pubspec.yaml", "hooks:\n  user_defines:\n    dart_smb2:\n      libsmb2: /custom/libsmb2.so\n")
        with self.assertRaisesRegex(evidence.EvidenceError, "custom libsmb2"):
            evidence.validate(self.root)

    def test_missing_reviewed_source_fails(self):
        (self.root / "lib/crypto.dart").unlink()
        with self.assertRaisesRegex(evidence.EvidenceError, "Missing"):
            evidence.validate(self.root)

    def test_artifact_identity_matches_exact_bytes_without_embedding_contents(self):
        artifact = self.write("release.aab", b"signed artifact fixture")
        dependencies = self.write("deps.json", json.dumps({"packages": [
            {"name": "filen_client"}, {"name": "internxt_client"},
        ]}))
        with patch.object(evidence, "git", side_effect=self.git_fixture):
            result = evidence.collect(self.root, "android", [artifact], dependencies, True)
        self.assertEqual(result["artifacts"], [{
            "name": "release.aab", "bytes": artifact.stat().st_size,
            "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest(),
        }])
        self.assertEqual(result["git_commit"], "a" * 40)
        self.assertNotIn("signed artifact fixture", json.dumps(result))

    def test_platform_evidence_needs_both_artifacts_and_resolved_dependencies(self):
        artifact = self.write("release.ipa", b"signed fixture")
        with patch.object(evidence, "git", side_effect=self.git_fixture):
            with self.assertRaisesRegex(evidence.EvidenceError, "requires a built artifact"):
                evidence.collect(self.root, "ios", [], None, True)
            with self.assertRaisesRegex(evidence.EvidenceError, "resolved dependency graph"):
                evidence.collect(self.root, "ios", [artifact], None, True)

    def test_dirty_source_rejects_release_claim(self):
        def dirty(root, *args):
            if args[0] == "diff":
                return "lib/crypto.dart"
            return self.git_fixture(root, *args)
        with patch.object(evidence, "git", side_effect=dirty):
            with self.assertRaisesRegex(evidence.EvidenceError, "differs from HEAD"):
                evidence.collect(self.root, "ios", [], None, True)

    def test_untracked_source_rejects_release_claim(self):
        def untracked(root, *args):
            if args[0] == "ls-files":
                return "lib/unreviewed.dart"
            return self.git_fixture(root, *args)
        with patch.object(evidence, "git", side_effect=untracked):
            with self.assertRaisesRegex(evidence.EvidenceError, "differs from HEAD"):
                evidence.collect(self.root, "ios", [], None, True)

    def test_resolved_graph_must_contain_both_providers(self):
        deps = self.write("deps.json", json.dumps({"packages": [{"name": "filen_client"}]}))
        with patch.object(evidence, "git", side_effect=self.git_fixture):
            with self.assertRaisesRegex(evidence.EvidenceError, "omits Filen or Internxt"):
                evidence.collect(self.root, "macos", [], deps, True)

    def test_missing_or_empty_artifact_is_not_a_build(self):
        artifact = self.write("empty.ipa", b"")
        with patch.object(evidence, "git", side_effect=self.git_fixture):
            with self.assertRaisesRegex(evidence.EvidenceError, "nonempty built artifact"):
                evidence.collect(self.root, "ios", [artifact], None, True)


if __name__ == "__main__":
    unittest.main()
