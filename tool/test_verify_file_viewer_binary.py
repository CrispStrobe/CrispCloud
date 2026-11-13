"""Tamper and boundary tests for the pinned Apache source provenance guard."""

import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import unittest

import verify_file_viewer_binary as guard


REPO_ROOT = Path(__file__).resolve().parents[1]
VALID_DART = """// Copyright 2026 Flyfish Viewer
// SPDX-License-Identifier: Apache-2.0
// Modified Dart port of File Viewer's binary parser and models.
// packages/file_viewer_binary/UPSTREAM.md

import 'dart:typed_data';
Uint8List unchanged(Uint8List input) => input;
"""


class FileViewerBinaryProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="file-viewer-guard-", dir=REPO_ROOT)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.snapshot = self.root / guard.SNAPSHOT_DIR
        shutil.copytree(REPO_ROOT / guard.SNAPSHOT_DIR, self.snapshot)
        self.manifest_path = self.snapshot / "UPSTREAM.json"
        self.original_manifest = json.loads(self.manifest_path.read_text(encoding="utf-8"))
        self.dart = self.root / guard.DERIVATIVE_PATH
        self.dart.parent.mkdir(parents=True)
        self.dart.write_text(VALID_DART, encoding="utf-8")

    def manifest(self):
        return json.loads(self.manifest_path.read_text(encoding="utf-8"))

    def write_manifest(self, data):
        self.manifest_path.write_text(json.dumps(data), encoding="utf-8")

    def rejects(self, pattern=None):
        if pattern:
            return self.assertRaisesRegex(guard.VerificationError, pattern)
        return self.assertRaises(guard.VerificationError)

    def test_reviewed_snapshot_and_attributed_sdk_only_port_pass(self):
        guard.verify(self.root)

    def test_each_snapshot_rejects_byte_tampering(self):
        for name in guard.APPROVED_FILES:
            with self.subTest(file=name):
                path = self.snapshot / name
                original = path.read_bytes()
                path.write_bytes(original[:-1] + bytes([original[-1] ^ 1]))
                with self.rejects("SHA-256"):
                    guard.verify(self.root)
                path.write_bytes(original)

    def test_rehashing_tampered_source_in_manifest_does_not_bypass_pin(self):
        path = self.snapshot / "upstream/parser.ts"
        data = path.read_bytes() + b"\n// unauthorized code\n"
        path.write_bytes(data)
        manifest = self.manifest()
        entry = next(item for item in manifest["upstream_file_allowlist"] if item["local_path"] == "upstream/parser.ts")
        entry.update(
            bytes=len(data),
            sha256=hashlib.sha256(data).hexdigest(),
            git_blob_sha1=hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest(),
        )
        self.write_manifest(manifest)
        with self.rejects("Unapproved upstream/parser.ts"):
            guard.verify(self.root)

    def test_repository_commit_license_and_dependency_metadata_cannot_change(self):
        alternatives = {
            "repository": "https://github.com/unreviewed/fork",
            "commit": "0" * 40,
            "upstream_version": "999.0.0",
            "license": "MIT",
            "copyright": "Someone else",
            "runtime_dependencies_added": ["@file-viewer/preset-all"],
            "upstream_notice_file": "NOTICE",
            "schema_version": True,
        }
        for key, value in alternatives.items():
            with self.subTest(field=key):
                manifest = dict(self.original_manifest)
                manifest[key] = value
                self.write_manifest(manifest)
                with self.rejects(f"manifest {key}"):
                    guard.verify(self.root)

    def test_license_source_and_modified_flag_cannot_be_reclassified(self):
        for key, value in (("license", "MIT"), ("modified", True), ("modified", 0), ("upstream_path", "packages/renderers/cad/LICENSE")):
            with self.subTest(field=key, value=value):
                manifest = json.loads(json.dumps(self.original_manifest))
                manifest["upstream_file_allowlist"][0][key] = value
                self.write_manifest(manifest)
                with self.rejects("Unapproved LICENSE"):
                    guard.verify(self.root)

    def test_allowlist_cannot_omit_duplicate_or_add_entries(self):
        original_entries = self.original_manifest["upstream_file_allowlist"]
        for entries in (original_entries[:-1], [original_entries[0]] * 3, original_entries + [original_entries[0]]):
            with self.subTest(entries=entries):
                manifest = dict(self.original_manifest)
                manifest["upstream_file_allowlist"] = entries
                self.write_manifest(manifest)
                with self.rejects():
                    guard.verify(self.root)

    def test_unexpected_source_asset_or_dependency_manifest_is_rejected(self):
        for name in ("package.json", "upstream/cad.ts", "decoder.wasm", "NOTICE"):
            with self.subTest(path=name):
                path = self.snapshot / name
                path.write_bytes(b"unreviewed content")
                with self.rejects("Unexpected snapshot file"):
                    guard.verify(self.root)
                path.unlink()

    def test_unexpected_empty_directory_is_rejected(self):
        (self.snapshot / "vendor").mkdir()
        with self.rejects("Unexpected snapshot directory"):
            guard.verify(self.root)

    def test_symlink_cannot_replace_snapshot_even_with_identical_bytes(self):
        path = self.snapshot / "upstream/parser.ts"
        target = self.root / "same-parser.ts"
        path.rename(target)
        path.symlink_to(target)
        with self.rejects("Symlink"):
            guard.verify(self.root)

    def test_symlinked_snapshot_directory_is_rejected(self):
        target = self.root / "same-upstream"
        (self.snapshot / "upstream").rename(target)
        (self.snapshot / "upstream").symlink_to(target, target_is_directory=True)
        with self.rejects("Symlink"):
            guard.verify(self.root)

    def test_symlinked_snapshot_root_is_rejected(self):
        target = self.root / "same-snapshot"
        self.snapshot.rename(target)
        self.snapshot.symlink_to(target, target_is_directory=True)
        with self.rejects("Symlink"):
            guard.verify(self.root)

    def test_symlinked_derivative_and_parent_are_rejected(self):
        target = self.root / "same-parser.dart"
        self.dart.rename(target)
        self.dart.symlink_to(target)
        with self.rejects("Symlink"):
            guard.verify(self.root)
        self.dart.unlink()
        target.rename(self.dart)
        services = self.dart.parent
        target_dir = self.root / "same-services"
        services.rename(target_dir)
        services.symlink_to(target_dir, target_is_directory=True)
        with self.rejects("Symlink"):
            guard.verify(self.root)

    def test_manifest_paths_reject_traversal_and_alternate_spellings(self):
        for field in ("local_path", "upstream_path"):
            for path in ("../LICENSE", "/tmp/LICENSE", "upstream/../LICENSE", "./LICENSE", "upstream//parser.ts", "upstream\\parser.ts", "C:/LICENSE"):
                with self.subTest(field=field, path=path):
                    manifest = json.loads(json.dumps(self.original_manifest))
                    manifest["upstream_file_allowlist"][0][field] = path
                    self.write_manifest(manifest)
                    with self.rejects("Unsafe"):
                        guard.verify(self.root)

    def test_derivative_path_import_metadata_and_change_record_cannot_drift(self):
        for key, value in (("path", "../outside.dart"), ("path", "lib/other.dart"), ("imports", ["package:evil/evil.dart"]), ("maximum_prefix_bytes", 1 << 30), ("changes", [])):
            with self.subTest(field=key):
                manifest = json.loads(json.dumps(self.original_manifest))
                manifest["derivative"][key] = value
                self.write_manifest(manifest)
                with self.rejects():
                    guard.verify(self.root)

    def test_each_required_leading_notice_is_enforced(self):
        for text in ("Copyright 2026 Flyfish Viewer", "SPDX-License-Identifier: Apache-2.0", "Modified Dart port", "packages/file_viewer_binary/UPSTREAM.md"):
            with self.subTest(notice=text):
                self.dart.write_text(VALID_DART.replace(text, "removed"), encoding="utf-8")
                with self.rejects("Missing leading"):
                    guard.verify(self.root)

    def test_spdx_cannot_silently_become_a_different_license_expression(self):
        self.dart.write_text(VALID_DART.replace("SPDX-License-Identifier: Apache-2.0", "SPDX-License-Identifier: Apache-2.0 OR MIT"), encoding="utf-8")
        with self.rejects("Apache SPDX"):
            guard.verify(self.root)

    def test_attribution_in_executable_string_is_not_a_leading_notice(self):
        self.dart.write_text("import 'dart:typed_data';\nconst fake = r'''" + VALID_DART + "''';\n", encoding="utf-8")
        with self.rejects("Missing leading"):
            guard.verify(self.root)

    def test_runtime_dependency_directives_cannot_hide_in_formatting(self):
        directives = (
            "import 'package:evil/evil.dart';",
            "import /* hidden */\n 'package:evil/evil.dart';",
            "import 'dart:typed_data' if (dart.library.io) 'package:evil/evil.dart';",
            "export 'package:evil/evil.dart';",
            "part 'hidden_runtime.dart';",
            "import r'package:evil/evil.dart';",
            "import 'dart:ffi';",
            "import 'dart:\\x74yped_data';",
        )
        for directive in directives:
            with self.subTest(directive=directive):
                self.dart.write_text(VALID_DART.replace("import 'dart:typed_data';", directive), encoding="utf-8")
                with self.rejects("Unapproved"):
                    guard.verify(self.root)

    def test_comments_and_string_examples_do_not_count_as_imports(self):
        source = VALID_DART + '''
// import 'package:example/comment.dart';
/* outer /* nested */ export 'package:example/comment.dart'; */
const example = "import 'package:example/literal.dart';";
const rawExample = r"part 'package:example/literal.dart';";
'''
        self.dart.write_text(source, encoding="utf-8")
        guard.verify(self.root)

    def test_duplicate_json_keys_are_rejected(self):
        text = self.manifest_path.read_text(encoding="utf-8")
        self.manifest_path.write_text(text.replace('"license": "Apache-2.0"', '"license": "MIT", "license": "Apache-2.0"', 1), encoding="utf-8")
        with self.rejects("Duplicate JSON key"):
            guard.verify(self.root)

    def test_missing_license_and_invalid_manifest_are_rejected(self):
        license_path = self.snapshot / "LICENSE"
        original = license_path.read_bytes()
        license_path.unlink()
        with self.rejects("Missing snapshot files"):
            guard.verify(self.root)
        license_path.write_bytes(original)
        self.manifest_path.write_text("{ invalid json", encoding="utf-8")
        with self.rejects("Invalid UPSTREAM.json"):
            guard.verify(self.root)


if __name__ == "__main__":
    unittest.main()
