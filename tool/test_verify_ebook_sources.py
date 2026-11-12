"""Exercise source provenance against small, local Git dependency checkouts."""

import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import update_ebook_sources as updater
import verify_ebook_sources as verifier


class EbookSourceVerificationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ebook-provenance-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name).resolve()
        self.root = self.directory / "app"
        self.checkout = self.directory / "shared checkout"
        self.root.mkdir()
        (self.root / "docs").mkdir()
        (self.root / ".dart_tool").mkdir()
        self.checkout.mkdir()
        self._git("init", "-q")
        self._git("config", "user.name", "Source verification fixture")
        self._git("config", "user.email", "fixture@example.invalid")
        self._git("config", "core.autocrlf", "false")
        self.sources = {
            ".gitignore": b"/lib/ignored.dart\n/assets/ignored.js\n",
            "README.md": b"Offline provenance fixture.\n",
            "assets/engine.wasm": b"\x00asm\x01\x00\x00\x00",
        }
        for name, relative in verifier.PACKAGES.items():
            prefix = "" if relative == "." else relative + "/"
            self.sources[prefix + "pubspec.yaml"] = f"name: {name}\n".encode()
            self.sources[prefix + f"lib/{name}.dart"] = b"library fixture;\n"
        for relative, content in self.sources.items():
            path = self.checkout / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        self._git("add", ".")
        self._git("commit", "-qm", "Create source fixture")
        self.revision = self._git("rev-parse", "HEAD").strip()
        self._write_pins()
        self.config = {
            "configVersion": 2,
            "packages": [
                {
                    "name": name,
                    "rootUri": (self.checkout / relative).as_uri() + "/",
                    "packageUri": "lib/",
                    "languageVersion": "3.13",
                }
                for name, relative in verifier.PACKAGES.items()
            ],
        }
        self._write_config()
        self._update_manifest()

    def _git(self, *arguments):
        return subprocess.check_output(
            ["git", "-C", str(self.checkout), *arguments],
            stderr=subprocess.PIPE,
            text=True,
        )

    def _write_pins(self):
        pubspec = ["name: app", "dependencies:"]
        lock = ["packages:"]
        for index, (name, relative) in enumerate(verifier.PACKAGES.items()):
            if index == 1:
                pubspec.append("dependency_overrides:")
            pubspec.extend([
                f"  {name}:", "    git:",
                f"      url: {verifier.REPOSITORY}",
                f"      ref: {self.revision}", f"      path: {relative}",
            ])
            lock.extend([
                f"  {name}:", "    dependency: direct main", "    description:",
                f'      path: "{relative}"', f"      ref: {self.revision}",
                f'      resolved-ref: "{self.revision}"',
                f'      url: "{verifier.REPOSITORY}"', "    source: git",
                '    version: "0.1.0"',
            ])
        (self.root / "pubspec.yaml").write_text("\n".join(pubspec) + "\n")
        (self.root / "pubspec.lock").write_text("\n".join(lock) + "\n")

    def _write_config(self):
        (self.root / ".dart_tool/package_config.json").write_text(
            json.dumps(self.config)
        )

    def _update_manifest(self, revision=None):
        arguments = [
            "update_ebook_sources.py", "--checkout", str(self.checkout),
            "--revision", revision or self.revision,
        ]
        with patch.object(updater, "ROOT", self.root), patch.object(
            sys, "argv", arguments
        ), contextlib.redirect_stdout(io.StringIO()):
            updater.main()

    def _manifest(self):
        return json.loads((self.root / verifier.MANIFEST).read_text())

    def _write_manifest(self, manifest):
        (self.root / verifier.MANIFEST).write_text(json.dumps(manifest))

    def _reject(self, message):
        with self.assertRaisesRegex(verifier.SourceError, message):
            verifier.verify(self.root)

    def _symlink(self, link, target, *, directory=False):
        try:
            link.symlink_to(target, target_is_directory=directory)
        except (NotImplementedError, OSError) as error:
            self.skipTest(f"Symlinks are unavailable: {error}")

    def test_complete_git_checkout_and_generated_manifest_pass(self):
        result = verifier.verify(self.root)
        self.assertTrue(result["resolved_bytes_verified"])
        self.assertEqual(result["revision"], self.revision)
        self.assertEqual(result["files_verified"], len(self.sources))
        self.assertEqual(len(result["manifest_sha256"]), 64)

    def test_relative_package_root_uris_resolve_from_config_file(self):
        for package in self.config["packages"]:
            relative = verifier.PACKAGES[package["name"]]
            package["rootUri"] = os.path.relpath(
                self.checkout / relative, self.root / ".dart_tool"
            ).replace(os.sep, "/") + "/"
        self._write_config()
        self.assertTrue(verifier.verify(self.root)["resolved_bytes_verified"])

    def test_pins_only_never_claims_byte_verification(self):
        (self.root / ".dart_tool/package_config.json").unlink()
        result = verifier.verify(self.root, resolve=False)
        self.assertFalse(result["resolved_bytes_verified"])
        self.assertNotIn("files_verified", result)

    def test_lock_resolved_revision_mismatch_is_rejected(self):
        path = self.root / "pubspec.lock"
        path.write_text(path.read_text().replace(
            f'resolved-ref: "{self.revision}"',
            f'resolved-ref: "{"0" * 40}"', 1,
        ))
        self._reject("does not resolve to the reviewed Git revision")

    def test_declared_revision_mismatch_is_rejected(self):
        path = self.root / "pubspec.yaml"
        path.write_text(path.read_text().replace(self.revision, "0" * 40, 1))
        self._reject("pubspec differs from the reviewed source pin")

    def test_same_length_byte_mutation_is_rejected(self):
        path = self.checkout / "lib/crisperbooks.dart"
        original = path.read_bytes()
        path.write_bytes(original.replace(b"fixture", b"changed"))
        self.assertEqual(path.stat().st_size, len(original))
        self._reject("source bytes differ")

    def test_omitted_tracked_manifest_entry_is_rejected(self):
        manifest = self._manifest()
        del manifest["files"]["README.md"]
        self._write_manifest(manifest)
        self._reject("does not cover the complete Git tree")

    def test_manifest_blob_identity_and_sha256_are_both_checked(self):
        original = self._manifest()
        for field, value, message in (
            ("git_blob", "0" * 40, "Git identity differs"),
            ("sha256", "0" * 64, "source bytes differ"),
        ):
            with self.subTest(field=field):
                manifest = json.loads(json.dumps(original))
                manifest["files"]["README.md"][field] = value
                self._write_manifest(manifest)
                self._reject(message)

    def test_checkout_at_different_head_is_rejected(self):
        self._git("commit", "--allow-empty", "-qm", "Different revision")
        self._reject("not at the reviewed revision")

    def test_package_root_redirect_is_rejected(self):
        self.config["packages"][-1]["rootUri"] = self.directory.as_uri()
        self._write_config()
        self._reject("redirected outside the shared checkout")

    def test_non_local_package_root_is_rejected_without_network(self):
        self.config["packages"][-1]["rootUri"] = "https://example.invalid/lib"
        self._write_config()
        self._reject("Non-local package root")

    def test_package_import_uri_cannot_escape_verified_library(self):
        for value in ("../unreviewed/", "file:///unreviewed/", "", "lib/../"):
            with self.subTest(package_uri=value):
                self.config["packages"][-1]["packageUri"] = value
                self._write_config()
                self._reject("package imports are redirected outside lib/")

    def test_duplicate_package_configuration_is_rejected(self):
        self.config["packages"].append(self.config["packages"][0].copy())
        self._write_config()
        self._reject("Resolve crisperbooks with flutter pub get first")

    def test_local_dependency_overrides_are_rejected(self):
        (self.root / "pubspec_overrides.yaml").write_text("{}\n")
        self._reject("Remove local dependency overrides")

    def test_duplicate_json_fields_are_rejected_in_both_inputs(self):
        for path in (
            self.root / verifier.MANIFEST,
            self.root / ".dart_tool/package_config.json",
        ):
            with self.subTest(input=path.name):
                original = path.read_text()
                path.write_text('{"duplicate": 1, "duplicate": 2, ' + original[1:])
                self._reject("Duplicate JSON field: duplicate")
                path.write_text(original)

    def test_identical_bytes_through_source_symlink_are_rejected(self):
        path = self.checkout / "lib/crisperbooks.dart"
        target = self.directory / "redirected.dart"
        target.write_bytes(path.read_bytes())
        path.unlink()
        self._symlink(path, target)
        self._reject("Missing or redirected source file")

    def test_symlinked_parent_directory_is_rejected(self):
        path = self.checkout / "lib"
        target = self.directory / "redirected-library"
        path.rename(target)
        self._symlink(path, target, directory=True)
        self._reject("Missing or redirected source file")

    def test_noncanonical_and_traversing_source_paths_are_rejected(self):
        for relative in (
            "../outside", "/absolute", "lib/../outside", "lib\\source.dart",
            "lib//source.dart", "./lib/source.dart", ".", "",
        ):
            with self.subTest(path=relative), self.assertRaisesRegex(
                verifier.SourceError, "Invalid source path"
            ):
                verifier.regular_file(self.checkout, relative)

    def test_untracked_runtime_file_is_rejected(self):
        (self.checkout / "lib/injected.dart").write_text("library injected;\n")
        self._reject("Unreviewed files.*lib/injected.dart")

    def test_git_ignored_runtime_file_is_still_rejected(self):
        for relative in ("lib/ignored.dart", "assets/ignored.js"):
            with self.subTest(path=relative):
                path = self.checkout / relative
                path.write_text("unreviewed runtime source\n")
                self.assertEqual(self._git("status", "--porcelain"), "")
                self._reject("Unreviewed files")
                path.unlink()

    def test_updater_records_git_bytes_without_blessing_dirty_worktree(self):
        original = self._manifest()
        path = self.checkout / "lib/crisperbooks.dart"
        path.write_text("library unreviewed;\n")
        self._update_manifest()
        self.assertEqual(self._manifest(), original)
        self._reject("source bytes differ")

    def test_updater_uses_requested_revision_without_rewriting_pins(self):
        original = self._manifest()
        pubspec = (self.root / "pubspec.yaml").read_bytes()
        lock = (self.root / "pubspec.lock").read_bytes()
        (self.checkout / "README.md").write_text("New committed content.\n")
        self._git("add", "README.md")
        self._git("commit", "-qm", "New source fixture")
        self._update_manifest(self.revision)
        self.assertEqual(self._manifest(), original)
        self.assertEqual((self.root / "pubspec.yaml").read_bytes(), pubspec)
        self.assertEqual((self.root / "pubspec.lock").read_bytes(), lock)


if __name__ == "__main__":
    unittest.main()
