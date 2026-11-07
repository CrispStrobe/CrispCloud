"""Failure-path tests for release evidence, independent of Flutter/signing."""

import hashlib
import io
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

import crypto_release_evidence as evidence


XCODE_BASELINE = b'''// !$*UTF8*$!
{
    archiveVersion = 1;
    objects = {
        CONFIG = {isa = XCBuildConfiguration; buildSettings = {
            OPTIMIZE = YES; OTHER_LDFLAGS = ("-ObjC", "-lz");
        }; };
        SCRIPT = {isa = PBXShellScriptBuildPhase; shellScript = "echo safe"; };
    };
    rootObject = CONFIG;
}
'''
XCODE_RESERIALIZED = b'''// !$*UTF8*$!
{ rootObject=CONFIG; /* Reordered dictionaries and changed formatting. */
  objects={
    SCRIPT={shellScript="echo safe"; isa=PBXShellScriptBuildPhase;};
    CONFIG={buildSettings={OTHER_LDFLAGS=("-ObjC", "-lz"); OPTIMIZE=YES;};
            isa=XCBuildConfiguration;};
  };
  archiveVersion=1;
}
'''


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
        self.write(
            "docs/export-compliance.md",
            "Release review fixture\navailableOnFrenchStore=false\n"
            "ITSAppUsesNonExemptEncryption=false\n",
        )
        self.write("lib/crypto.dart", "// reviewed fixture\n")
        self.write("pubspec.yaml", "name: fixture\n")
        self.write("pubspec.lock", "packages:\n  filen_client:\n  internxt_client:\n  pointycastle:\n")
        self.write(".fvmrc", '{"flutter":"3.47.8"}')
        for name in ("ios/Runner/Info.plist", "macos/Runner/Info.plist"):
            self.write(name, plistlib.dumps({"ITSAppUsesNonExemptEncryption": False}))

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

    def prepare_generated_metadata(self):
        """Use real Git object identities and diffs for native provenance tests."""
        for paths in evidence.GENERATED_METADATA.values():
            for name in paths:
                self.write(name, f"Baseline generated fixture: {name}\n")
        for name in ("ios/Podfile", "macos/Podfile", "ios/Runner.xcodeproj/project.pbxproj",
                     "macos/Runner.xcodeproj/project.pbxproj",
                     "android/app/src/main/java/example/Authored.java"):
            self.write(name, "Authored build fixture\n")
        self.write(".gitignore", "build/\n")
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        evidence.git(self.root, "config", "user.name", "Release Evidence Test")
        evidence.git(self.root, "config", "user.email", "test@example.invalid")
        evidence.git(self.root, "config", "core.fileMode", "true")
        evidence.git(self.root, "config", "core.autocrlf", "false")
        evidence.git(self.root, "add", ".")
        evidence.git(self.root, "commit", "-qm", "Reviewed fixture baseline")
        self.artifact = self.write("build/app.fixture", b"built application fixture")
        self.dependencies = self.write("build/deps.json", json.dumps({"packages": [
            {"name": "filen_client"}, {"name": "internxt_client"},
        ]}))

    def record_generated(self, platform):
        return evidence.collect(self.root, platform, [self.artifact], self.dependencies, True,
                                record_generated_metadata=True)

    def prepare_xcode_reserialization(self):
        self.prepare_generated_metadata()
        name = "ios/Runner.xcodeproj/project.pbxproj"
        self.write(name, XCODE_BASELINE)
        evidence.git(self.root, "add", name)
        evidence.git(self.root, "commit", "-qm", "Reviewed Xcode project fixture")
        return self.write(name, XCODE_RESERIALIZED)

    def controlled_plutil(self, *outputs):
        """Control only plutil; keep real Git identities, modes and diffs."""
        real_run = subprocess.run
        results = iter(outputs)

        def run(args, **kwargs):
            if args[0] == "/usr/bin/plutil":
                output = next(results)
                if isinstance(output, Exception):
                    raise output
                return subprocess.CompletedProcess(args, 0, stdout=output, stderr=b"")
            return real_run(args, **kwargs)

        return patch.object(subprocess, "run", side_effect=run)

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

    def test_reviewed_false_apple_declaration_passes(self):
        evidence.validate(self.root)

    def test_false_apple_declaration_without_france_evidence_fails(self):
        self.write("docs/export-compliance.md", "Release review fixture\n")
        with self.assertRaisesRegex(evidence.EvidenceError, "France-exclusion"):
            evidence.validate(self.root)

    def test_true_apple_declaration_without_code_fails(self):
        self.write("ios/Runner/Info.plist", plistlib.dumps({"ITSAppUsesNonExemptEncryption": True}))
        with self.assertRaisesRegex(evidence.EvidenceError, "ComplianceCode"):
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

    def test_generated_metadata_requires_explicit_opt_in(self):
        self.prepare_generated_metadata()
        self.write("ios/Podfile.lock", "Actual resolved native dependency graph\n")
        with self.assertRaisesRegex(evidence.EvidenceError, "differs from HEAD"):
            evidence.collect(self.root, "ios", [self.artifact], self.dependencies, True)

    def test_generated_recording_requires_strict_target_evidence(self):
        for platform, require_clean in (("source", True), ("ios", False)):
            with self.subTest(platform=platform, require_clean=require_clean):
                with self.assertRaisesRegex(evidence.EvidenceError, "--require-clean and a target"):
                    evidence.collect(self.root, platform, [], None, require_clean,
                                     record_generated_metadata=True)

    def test_exact_target_generated_files_retain_baseline_actual_and_patch(self):
        self.prepare_generated_metadata()
        for platform, paths in evidence.GENERATED_METADATA.items():
            for name in paths:
                with self.subTest(platform=platform, name=name):
                    path = self.root / name
                    baseline = path.read_bytes()
                    actual = baseline + b"Actual generated build contents\n"
                    path.write_bytes(actual)
                    result = self.record_generated(platform)
                    self.assertFalse(result["source_checkout_clean"])
                    self.assertEqual(result["tracked_changes"], [name])
                    self.assertEqual(result["authored_source_changes"], [])
                    self.assertEqual(set(result["generated_metadata_changes"]), {name})
                    record = result["generated_metadata_changes"][name]
                    self.assertEqual(record["head_blob"], evidence.git(self.root, "rev-parse", f"HEAD:{name}"))
                    self.assertEqual(record["built_sha256"], hashlib.sha256(actual).hexdigest())
                    self.assertEqual(record["built_bytes"], len(actual))
                    self.assertIn("+Actual generated build contents", record["diff"])
                    output = self.root / "build" / platform
                    evidence.write_generated_metadata(self.root, output, result)
                    self.assertEqual((output / record["head_file"]).read_bytes(), baseline)
                    self.assertEqual((output / record["built_file"]).read_bytes(), actual)
                    self.assertEqual((output / record["diff_file"]).read_text(), record["diff"])
                    self.assertEqual(evidence.sha256(output / record["diff_file"]), record["diff_sha256"])
                    path.write_bytes(baseline)

    def test_generated_opt_in_does_not_allow_other_platform_metadata(self):
        self.prepare_generated_metadata()
        for platform, name in (("ios", "macos/Podfile.lock"),
                               ("macos", "ios/Podfile.lock"),
                               ("android", "ios/Podfile.lock"),
                               ("android", "macos/Podfile.lock")):
            with self.subTest(platform=platform, name=name):
                path = self.root / name
                baseline = path.read_bytes()
                path.write_bytes(baseline + b"Changed other platform graph\n")
                with self.assertRaisesRegex(evidence.EvidenceError, name):
                    self.record_generated(platform)
                path.write_bytes(baseline)

    def test_apple_build_records_cross_platform_android_registration(self):
        self.prepare_generated_metadata()
        registrant = "android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java"
        for platform in ("ios", "macos"):
            with self.subTest(platform=platform):
                names = (registrant, f"{platform}/Podfile.lock")
                baseline = {name: (self.root / name).read_bytes() for name in names}
                for name in names:
                    self.write(name, baseline[name] + b"Regenerated by the Apple build\n")
                with self.assertRaisesRegex(evidence.EvidenceError, "differs from HEAD"):
                    evidence.collect(self.root, platform, [self.artifact], self.dependencies, True)
                result = self.record_generated(platform)
                self.assertEqual(set(result["generated_metadata_changes"]), set(names))
                self.assertEqual(result["authored_source_changes"], [])
                self.assertFalse(result["source_checkout_clean"])
                output = self.root / "build" / platform
                evidence.write_generated_metadata(self.root, output, result)
                for name in names:
                    record = result["generated_metadata_changes"][name]
                    self.assertEqual((output / record["head_file"]).read_bytes(), baseline[name])
                    self.assertEqual((output / record["built_file"]).read_bytes(), (self.root / name).read_bytes())
                    self.write(name, baseline[name])

    def test_generated_opt_in_still_rejects_authored_inputs_and_dependency_locks(self):
        self.prepare_generated_metadata()
        self.write("ios/Podfile.lock", "Resolved iOS graph\n")
        for name in ("lib/crypto.dart", "pubspec.yaml", "pubspec.lock", "ios/Podfile", "macos/Podfile",
                     "macos/Runner.xcodeproj/project.pbxproj",
                     "android/app/src/main/java/example/Authored.java"):
            with self.subTest(name=name):
                path = self.root / name
                baseline = path.read_bytes()
                path.write_bytes(baseline + b"\n# Unreviewed input change\n")
                with self.assertRaisesRegex(evidence.EvidenceError, "differs from HEAD"):
                    self.record_generated("ios")
                path.write_bytes(baseline)

    def test_xcode_reserialization_requires_opt_in_and_the_exact_ios_target(self):
        self.prepare_xcode_reserialization()
        with self.controlled_plutil() as parser:
            with self.assertRaisesRegex(evidence.EvidenceError, "differs from HEAD"):
                evidence.collect(self.root, "ios", [self.artifact], self.dependencies, True)
            for platform in ("android", "macos"):
                with self.subTest(platform=platform):
                    with self.assertRaisesRegex(evidence.EvidenceError, "differs from HEAD"):
                        self.record_generated(platform)
            self.assertFalse(any(call.args[0][0] == "/usr/bin/plutil"
                                 for call in parser.call_args_list))

    def test_xcode_reserialization_retains_exact_bytes_and_parser_method(self):
        path = self.prepare_xcode_reserialization()
        with self.controlled_plutil(b'{"z":[1,true],"a":{"b":"value"}}',
                                    b'{"a":{"b":"value"},"z":[1,true]}') as parser:
            result = self.record_generated("ios")
        calls = [call for call in parser.call_args_list if call.args[0][0] == "/usr/bin/plutil"]
        self.assertEqual([call.kwargs["input"] for call in calls],
                         [XCODE_BASELINE, XCODE_RESERIALIZED])
        self.assertTrue(all(call.args[0] == ["/usr/bin/plutil", "-convert", "json",
                                            "-o", "-", "--", "-"] for call in calls))
        self.assertFalse(result["source_checkout_clean"])
        self.assertEqual(result["authored_source_changes"], [])
        relative = str(path.relative_to(self.root))
        record = result["generated_metadata_changes"][relative]
        self.assertIn("Parsed Xcode project data unchanged", record["record_reason"])
        self.assertIn("/usr/bin/plutil", record["comparison_method"])
        self.assertEqual(record["canonical_json_sha256"], hashlib.sha256(
            b'{"a":{"b":"value"},"z":[1,true]}').hexdigest())
        self.assertEqual(record["built_sha256"], hashlib.sha256(XCODE_RESERIALIZED).hexdigest())
        output = self.root / "build/evidence"
        evidence.write_generated_metadata(self.root, output, result)
        self.assertEqual((output / record["head_file"]).read_bytes(), XCODE_BASELINE)
        self.assertEqual((output / record["built_file"]).read_bytes(), XCODE_RESERIALIZED)
        self.assertEqual((output / record["diff_file"]).read_text(), record["diff"])

    def test_xcode_parsed_setting_script_reference_array_and_scalar_changes_fail(self):
        self.prepare_xcode_reserialization()
        cases = (
            (b'{"buildSettings":{"ENCRYPTION":"YES"}}', b'{"buildSettings":{"ENCRYPTION":"NO"}}'),
            (b'{"shellScript":"echo safe"}', b'{"shellScript":"run unreviewed code"}'),
            (b'{"objects":{"A":"existing"}}', b'{"objects":{"A":"existing","B":"new"}}'),
            (b'{"buildPhases":["A","B"]}', b'{"buildPhases":["B","A"]}'),
            (b'{"value":true}', b'{"value":1}'),
            (b'{"value":1}', b'{"value":"1"}'),
            (b'{"value":1}', b'{"value":1.0}'),
            (b'{"value":[]}', b'{"value":{}}'),
        )
        for baseline, actual in cases:
            with self.subTest(baseline=baseline, actual=actual), self.controlled_plutil(baseline, actual):
                with self.assertRaisesRegex(evidence.EvidenceError, "parsed data differs from HEAD"):
                    self.record_generated("ios")

    def test_xcode_parser_missing_failed_and_timed_out_fail_closed(self):
        self.prepare_xcode_reserialization()
        errors = (FileNotFoundError("parser missing"),
                  subprocess.CalledProcessError(1, "/usr/bin/plutil"),
                  subprocess.TimeoutExpired("/usr/bin/plutil", 30))
        for error in errors:
            with self.subTest(error=type(error).__name__), self.controlled_plutil(error):
                with self.assertRaisesRegex(evidence.EvidenceError, "plutil unavailable or failed"):
                    self.record_generated("ios")

    def test_xcode_malformed_parser_output_fails_for_both_versions(self):
        self.prepare_xcode_reserialization()
        for output in (b"", b"not JSON", b"[]", b"null", b"\xff",
                       b'{"value":NaN}', b'{"value":1e999}', b'{"value":1,"value":2}'):
            for version, results in (("HEAD", (output,)), ("built", (b"{}", output))):
                with self.subTest(output=output, version=version), self.controlled_plutil(*results):
                    with self.assertRaisesRegex(evidence.EvidenceError, f"Malformed .* for {version}"):
                        self.record_generated("ios")

    def test_xcode_reserialization_preserves_file_replacement_guards(self):
        path = self.prepare_xcode_reserialization()
        path.unlink()
        with self.assertRaisesRegex(evidence.EvidenceError, "Missing or non-regular"):
            self.record_generated("ios")
        path.write_bytes(b"")
        with self.assertRaisesRegex(evidence.EvidenceError, "must not be empty"):
            self.record_generated("ios")
        path.unlink()
        try:
            path.symlink_to(self.root / "macos/Runner.xcodeproj/project.pbxproj")
        except OSError:
            self.skipTest("Symlinks unavailable on this test host")
        with self.assertRaisesRegex(evidence.EvidenceError, "Missing or non-regular|symlinks"):
            self.record_generated("ios")

    @unittest.skipIf(os.name == "nt", "POSIX executable mode fixture")
    def test_xcode_reserialization_rejects_mode_change_before_parsing(self):
        path = self.prepare_xcode_reserialization()
        path.chmod(0o755)
        with self.controlled_plutil():
            with self.assertRaisesRegex(evidence.EvidenceError, "type and mode"):
                self.record_generated("ios")

    def test_xcode_bytes_cannot_change_after_parsed_data_verification(self):
        path = self.prepare_xcode_reserialization()
        with self.controlled_plutil(b"{}", b"{}"):
            result = self.record_generated("ios")
        path.write_bytes(XCODE_RESERIALIZED + b"// Changed after verification\n")
        with self.assertRaisesRegex(evidence.EvidenceError, "changed during evidence collection"):
            evidence.write_generated_metadata(self.root, self.root / "build/evidence", result)

    @unittest.skipUnless(sys.platform == "darwin", "Requires Apple's actual /usr/bin/plutil")
    def test_native_plutil_accepts_openstep_dictionary_reordering(self):
        self.prepare_xcode_reserialization()
        result = self.record_generated("ios")
        self.assertIn("ios/Runner.xcodeproj/project.pbxproj", result["generated_metadata_changes"])

    @unittest.skipUnless(sys.platform == "darwin", "Requires Apple's actual /usr/bin/plutil")
    def test_native_plutil_rejects_openstep_settings_scripts_references_and_array_changes(self):
        path = self.prepare_xcode_reserialization()
        changes = (
            XCODE_RESERIALIZED.replace(b"OPTIMIZE=YES", b"OPTIMIZE=NO"),
            XCODE_RESERIALIZED.replace(b'"echo safe"', b'"echo altered"'),
            XCODE_RESERIALIZED.replace(b"objects={", b"objects={EXTRA={isa=PBXFileReference;path=extra.c;};"),
            XCODE_RESERIALIZED.replace(b'("-ObjC", "-lz")', b'("-lz", "-ObjC")'),
        )
        for actual in changes:
            with self.subTest(actual=actual):
                self.assertNotEqual(actual, XCODE_RESERIALIZED)
                path.write_bytes(actual)
                with self.assertRaisesRegex(evidence.EvidenceError, "parsed data differs from HEAD"):
                    self.record_generated("ios")

    def test_generated_opt_in_rejects_untracked_authored_source(self):
        self.prepare_generated_metadata()
        self.write("ios/Podfile.lock", "Resolved iOS graph\n")
        self.write("lib/unreviewed.dart", "Unreviewed application code\n")
        with self.assertRaisesRegex(evidence.EvidenceError, "lib/unreviewed.dart"):
            self.record_generated("ios")

    def test_generated_opt_in_rejects_untracked_metadata_without_head_identity(self):
        self.prepare_generated_metadata()
        evidence.git(self.root, "rm", "--cached", "ios/Podfile.lock")
        evidence.git(self.root, "commit", "-qm", "No tracked native baseline")
        with self.assertRaisesRegex(evidence.EvidenceError, "differs from HEAD"):
            self.record_generated("ios")

    def test_generated_opt_in_rejects_deleted_empty_and_directory_replacements(self):
        self.prepare_generated_metadata()
        path = self.root / "ios/Podfile.lock"
        path.unlink()
        with self.assertRaisesRegex(evidence.EvidenceError, "Missing or non-regular"):
            self.record_generated("ios")
        path.write_bytes(b"")
        with self.assertRaisesRegex(evidence.EvidenceError, "must not be empty"):
            self.record_generated("ios")
        path.unlink()
        path.mkdir()
        with self.assertRaisesRegex(evidence.EvidenceError, "Missing or non-regular"):
            self.record_generated("ios")

    def test_generated_opt_in_rejects_symlink_replacement(self):
        self.prepare_generated_metadata()
        path = self.root / "ios/Podfile.lock"
        path.unlink()
        try:
            path.symlink_to(self.root / "macos/Podfile.lock")
        except OSError:
            self.skipTest("Symlinks unavailable on this test host")
        with self.assertRaisesRegex(evidence.EvidenceError, "Missing or non-regular|symlinks"):
            self.record_generated("ios")

    @unittest.skipIf(os.name == "nt", "POSIX executable mode fixture")
    def test_generated_opt_in_rejects_file_mode_change(self):
        self.prepare_generated_metadata()
        path = self.root / "ios/Podfile.lock"
        path.chmod(0o755)
        with self.assertRaisesRegex(evidence.EvidenceError, "type and mode"):
            self.record_generated("ios")

    def test_generated_file_cannot_change_between_collection_and_copy(self):
        self.prepare_generated_metadata()
        self.write("ios/Podfile.lock", "Actual resolved graph\n")
        result = self.record_generated("ios")
        self.write("ios/Podfile.lock", "Different graph after hashing\n")
        with self.assertRaisesRegex(evidence.EvidenceError, "changed during evidence collection"):
            evidence.write_generated_metadata(self.root, self.root / "build/evidence", result)

    def test_cli_writes_generated_copies_and_an_honest_manifest(self):
        self.prepare_generated_metadata()
        relative = next(iter(evidence.GENERATED_METADATA["android"]))
        self.write(relative, "Actual generated Java registration\n")
        output = self.root / "build/evidence"
        with patch.object(evidence, "ROOT", self.root), redirect_stdout(io.StringIO()):
            code = evidence.main([
                "--platform", "android", "--require-clean", "--record-generated-metadata",
                "--artifact", str(self.artifact), "--dependencies", str(self.dependencies),
                "--output-dir", str(output),
            ])
        self.assertEqual(code, 0)
        manifest = json.loads((output / "crypto-evidence.json").read_text())
        self.assertFalse(manifest["source_checkout_clean"])
        record = manifest["generated_metadata_changes"][relative]
        self.assertEqual((output / record["built_file"]).read_bytes(), (self.root / relative).read_bytes())
        self.assertIn("not approval", manifest["generated_metadata_review_note"])


if __name__ == "__main__":
    unittest.main()
