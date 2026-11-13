"""Tamper tests for the dependency-free Apache LRC source boundary."""

import copy
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import unittest

import verify_file_viewer_lrc as guard


REPO_ROOT = Path(__file__).resolve().parents[1]
VALID_DART = """// Copyright 2026 Flyfish Viewer
// SPDX-License-Identifier: Apache-2.0
// Modified Dart port of File Viewer's standalone LRC parser.
// packages/file_viewer_lrc/UPSTREAM.md

String unchanged(String input) => input;
"""


class FileViewerLrcProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(
            prefix="file-viewer-lrc-guard-", dir=REPO_ROOT
        )
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.snapshot = self.root / guard.SNAPSHOT_DIR
        shutil.copytree(REPO_ROOT / guard.SNAPSHOT_DIR, self.snapshot)
        self.manifest_path = self.snapshot / "UPSTREAM.json"
        self.original_manifest = json.loads(
            self.manifest_path.read_text(encoding="utf-8")
        )
        self.dart = self.root / guard.DERIVATIVE_PATH
        self.dart.parent.mkdir(parents=True)
        self.dart.write_text(VALID_DART, encoding="utf-8")

    def fresh_manifest(self):
        return copy.deepcopy(self.original_manifest)

    def write_manifest(self, manifest):
        self.manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    def rejects(self, pattern=None):
        if pattern:
            return self.assertRaisesRegex(guard.VerificationError, pattern)
        return self.assertRaises(guard.VerificationError)

    def test_reviewed_snapshot_and_attributed_import_free_port_pass(self):
        guard.verify(self.root)

    def test_each_snapshot_rejects_same_length_tampering(self):
        for name in guard.APPROVED_FILES:
            with self.subTest(file=name):
                path = self.snapshot / name
                original = path.read_bytes()
                path.write_bytes(original[:-1] + bytes([original[-1] ^ 1]))
                with self.rejects("SHA-256"):
                    guard.verify(self.root)
                path.write_bytes(original)

    def test_rehashing_altered_parser_does_not_bypass_independent_pin(self):
        path = self.snapshot / "upstream/lrcParser.ts"
        data = path.read_bytes() + b"\nimport 'unreviewed-runtime';\n"
        path.write_bytes(data)
        manifest = self.fresh_manifest()
        entry = next(
            item for item in manifest["upstream_file_allowlist"]
            if item["local_path"] == "upstream/lrcParser.ts"
        )
        entry.update(
            bytes=len(data),
            sha256=hashlib.sha256(data).hexdigest(),
            git_blob_sha1=hashlib.sha1(
                b"blob " + str(len(data)).encode("ascii") + b"\0" + data
            ).hexdigest(),
        )
        self.write_manifest(manifest)
        with self.rejects("Unapproved upstream/lrcParser.ts"):
            guard.verify(self.root)

    def test_required_identity_license_and_dependency_fields_cannot_change(self):
        alternatives = {
            "schema_version": True,
            "repository": "https://github.com/unreviewed/fork",
            "commit": "0" * 40,
            "upstream_package": "@file-viewer/preset-all",
            "upstream_version": "999.0.0",
            "license": "MIT",
            "copyright": "Someone else",
            "upstream_notice_file": "NOTICE",
            "runtime_dependencies_added": ["marked"],
        }
        for key, value in alternatives.items():
            with self.subTest(field=key):
                manifest = self.fresh_manifest()
                manifest[key] = value
                self.write_manifest(manifest)
                with self.rejects(f"manifest {key}"):
                    guard.verify(self.root)

    def test_allowlist_cannot_add_omit_duplicate_or_extend_records(self):
        original = self.original_manifest["upstream_file_allowlist"]
        for entries in (
            original[:-1],
            [original[0]] * len(original),
            original + [original[0]],
            [dict(original[0], dependency="unreviewed"), original[1]],
        ):
            with self.subTest(entries=entries):
                manifest = self.fresh_manifest()
                manifest["upstream_file_allowlist"] = entries
                self.write_manifest(manifest)
                with self.rejects():
                    guard.verify(self.root)

    def test_source_licenses_paths_and_fingerprints_cannot_be_reclassified(self):
        alternatives = {
            "license": "Apache-2.0 OR MIT",
            "modified": 0,
            "upstream_path": "packages/renderers/cad/LICENSE",
            "git_blob_sha1": "0" * 40,
            "sha256": "0" * 64,
            "bytes": 9140.0,
        }
        for key, value in alternatives.items():
            with self.subTest(field=key):
                manifest = self.fresh_manifest()
                manifest["upstream_file_allowlist"][0][key] = value
                self.write_manifest(manifest)
                with self.rejects("Unapproved LICENSE"):
                    guard.verify(self.root)

    def test_missing_snapshots_license_and_provenance_are_rejected(self):
        for name in set(guard.APPROVED_FILES) | {"UPSTREAM.md", "UPSTREAM.json"}:
            with self.subTest(file=name):
                path = self.snapshot / name
                original = path.read_bytes()
                path.unlink()
                with self.rejects("Missing snapshot files"):
                    guard.verify(self.root)
                path.write_bytes(original)

    def test_unreviewed_wrappers_assets_dependencies_and_directories_are_rejected(self):
        for name in ("package.json", "upstream/lrc.ts", "decoder.wasm", "NOTICE"):
            with self.subTest(file=name):
                path = self.snapshot / name
                path.write_bytes(b"unreviewed content")
                with self.rejects("Unexpected snapshot file"):
                    guard.verify(self.root)
                path.unlink()
        (self.snapshot / "vendor").mkdir()
        with self.rejects("Unexpected snapshot directory"):
            guard.verify(self.root)

    def test_symlinked_source_manifest_and_derivative_are_rejected(self):
        for path in (
            self.snapshot / "upstream/lrcParser.ts", self.manifest_path, self.dart
        ):
            with self.subTest(path=path):
                target = self.root / "same-content"
                path.rename(target)
                path.symlink_to(target)
                with self.rejects("Symlink"):
                    guard.verify(self.root)
                path.unlink()
                target.rename(path)

    def test_manifest_paths_reject_traversals_and_alternate_spellings(self):
        paths = (
            "../LICENSE", "/tmp/LICENSE", "upstream/../LICENSE", "./LICENSE",
            "upstream//lrcParser.ts", "upstream\\lrcParser.ts", "C:/LICENSE",
            "upstream/\0lrcParser.ts",
        )
        for field in ("local_path", "upstream_path", "derivative"):
            for path in paths:
                with self.subTest(field=field, path=path):
                    manifest = self.fresh_manifest()
                    if field == "derivative":
                        manifest["derivative"]["path"] = path
                    else:
                        manifest["upstream_file_allowlist"][0][field] = path
                    self.write_manifest(manifest)
                    with self.rejects("Unsafe"):
                        guard.verify(self.root)

    def test_each_resource_and_timeline_limit_is_exact_and_required(self):
        for key, original in guard.APPROVED_LIMITS.items():
            for value in (original + 1, float(original), str(original), True, None):
                with self.subTest(limit=key, value=value):
                    manifest = self.fresh_manifest()
                    manifest["derivative"]["limits"][key] = value
                    self.write_manifest(manifest)
                    with self.rejects("derivative limits"):
                        guard.verify(self.root)
            with self.subTest(missing=key):
                manifest = self.fresh_manifest()
                del manifest["derivative"]["limits"][key]
                self.write_manifest(manifest)
                with self.rejects("derivative limits"):
                    guard.verify(self.root)

    def test_limit_set_cannot_grow_or_be_replaced(self):
        for value in (
            dict(guard.APPROVED_LIMITS, unreviewedLimit=100), [], None,
        ):
            with self.subTest(limits=value):
                manifest = self.fresh_manifest()
                manifest["derivative"]["limits"] = value
                self.write_manifest(manifest)
                with self.rejects("derivative limits"):
                    guard.verify(self.root)

    def test_derivative_path_imports_change_record_and_timeline_metadata_are_pinned(self):
        for key, value in (
            ("path", "lib/services/other.dart"),
            ("imports", ["dart:core"]),
            ("language", "TypeScript"),
            ("changes", []),
            ("maximum_timeline_milliseconds", 1 << 53),
        ):
            with self.subTest(field=key):
                manifest = self.fresh_manifest()
                manifest["derivative"][key] = value
                self.write_manifest(manifest)
                with self.rejects():
                    guard.verify(self.root)

    def test_each_leading_attribution_and_modification_notice_is_required(self):
        for notice in (
            "Copyright 2026 Flyfish Viewer", "SPDX-License-Identifier: Apache-2.0",
            "Modified Dart port", "packages/file_viewer_lrc/UPSTREAM.md",
        ):
            with self.subTest(notice=notice):
                self.dart.write_text(VALID_DART.replace(notice, "removed"), encoding="utf-8")
                with self.rejects("Missing leading"):
                    guard.verify(self.root)

    def test_wrong_subset_reference_and_broader_license_expression_are_rejected(self):
        for old, new in (
            ("packages/file_viewer_lrc/UPSTREAM.md", "packages/file_viewer_binary/UPSTREAM.md"),
            ("Apache-2.0", "Apache-2.0 OR MIT"),
        ):
            with self.subTest(replacement=new):
                self.dart.write_text(VALID_DART.replace(old, new), encoding="utf-8")
                with self.rejects("Missing leading"):
                    guard.verify(self.root)

    def test_notices_inside_executable_strings_are_not_leading_attribution(self):
        self.dart.write_text("const fake = r'''" + VALID_DART + "''';\n", encoding="utf-8")
        with self.rejects("Missing leading"):
            guard.verify(self.root)

    def test_all_dependency_directives_including_sdk_imports_are_rejected(self):
        directives = (
            "import 'dart:core';",
            "import 'dart:typed_data';",
            "import 'package:evil/evil.dart';",
            "import /* hidden */\n 'package:evil/evil.dart';",
            "import 'dart:core' if (dart.library.io) 'package:evil/evil.dart';",
            "import r'package:evil/evil.dart';",
            "export 'other.dart';",
            "part 'other.dart';",
            "part of 'other.dart';",
        )
        for directive in directives:
            with self.subTest(directive=directive):
                self.dart.write_text(VALID_DART + directive + "\n", encoding="utf-8")
                with self.rejects("Unapproved"):
                    guard.verify(self.root)

    def test_comments_and_string_examples_do_not_count_as_dependencies(self):
        self.dart.write_text(VALID_DART + '''
// import 'package:example/comment.dart';
/* outer /* nested */ export 'package:example/comment.dart'; */
const example = "import 'package:example/literal.dart';";
const rawExample = r"part 'package:example/literal.dart';";
''', encoding="utf-8")
        guard.verify(self.root)

    def test_duplicate_nested_limit_json_key_is_rejected(self):
        text = self.manifest_path.read_text(encoding="utf-8")
        text = text.replace(
            '"lrcMaxCues": 10000', '"lrcMaxCues": 99999, "lrcMaxCues": 10000', 1
        )
        self.manifest_path.write_text(text, encoding="utf-8")
        with self.rejects("Duplicate JSON key"):
            guard.verify(self.root)

    def test_invalid_manifest_and_non_utf8_derivative_are_rejected(self):
        for invalid in (b"{ invalid json", b"null", b"\xff"):
            with self.subTest(manifest=invalid):
                self.manifest_path.write_bytes(invalid)
                with self.rejects():
                    guard.verify(self.root)
        self.write_manifest(self.original_manifest)
        self.dart.write_bytes(VALID_DART.encode("utf-8") + b"\xff")
        with self.rejects("not UTF-8"):
            guard.verify(self.root)


if __name__ == "__main__":
    unittest.main()
