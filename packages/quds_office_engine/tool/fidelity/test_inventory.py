"""Negative controls for missing whole scenarios, stale evidence, and safe clean."""

import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import inventory


class InventoryTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "engine"
        self.root.mkdir()
        (self.root / "pubspec.yaml").write_text("name: quds_office_engine\n")
        self.build = self.root / "build"
        self.manifest_path = self.root / "manifest.json"
        # A separately authored miniature inventory, not discovered from output.
        self.data = {
            "version": 1,
            "package": "quds_office_engine",
            "expected_file_count": 7,
            "series": [
                {"pattern": "fidelity-word/edited-{cycle}.docx", "cycles": [1, 2, 3],
                 "producer": "authored-word-case"},
                {"pattern": "fidelity-sheet/imported-{cycle}.xlsx", "cycles": [0, 1, 2],
                 "producer": "authored-sheet-case"},
            ],
            "standalone": [{"path": "fidelity-source.pptx", "producer": "authored-source"}],
        }
        self.manifest = self.load()

    def load(self):
        self.manifest_path.write_text(json.dumps(self.data))
        return inventory.load_manifest(self.manifest_path)

    def output(self, name):
        target = self.build / name
        target.parent.mkdir(parents=True, exist_ok=True)
        # Minimal OPC envelope suffices here. OOXML schema/semantics have their
        # own independent gates and are deliberately not invented by this test.
        with zipfile.ZipFile(target, "w") as archive:
            archive.writestr("[Content_Types].xml", "<Types/>")
            archive.writestr("_rels/.rels", "<Relationships/>")
        return target

    def complete(self):
        for name in self.manifest.paths:
            self.output(name)

    def test_complete_inventory_receipt_records_real_bytes_and_manifest(self):
        self.complete()
        report = inventory.verify(self.manifest, self.root)
        self.assertTrue(report["ok"])
        self.assertEqual(report["expected_files"], 7)
        self.assertEqual(report["verified_files"], 7)
        self.assertEqual(report["three_cycle_series"], 2)
        self.assertEqual(report["standalone_files"], 1)
        self.assertEqual(report["manifest_sha256"],
                         hashlib.sha256(self.manifest_path.read_bytes()).hexdigest())
        for record in report["files"]:
            contents = (self.build / record["path"]).read_bytes()
            self.assertEqual(record["bytes"], len(contents))
            self.assertEqual(record["sha256"], hashlib.sha256(contents).hexdigest())
        receipt = inventory.write_receipt(report, self.root)
        self.assertEqual(json.loads(receipt.read_text()), report)

    def test_whole_missing_group_fails_even_when_other_groups_pass(self):
        for name in self.manifest.paths:
            if not name.startswith("fidelity-word/"):
                self.output(name)
        report = inventory.verify(self.manifest, self.root)
        self.assertFalse(report["ok"])
        self.assertEqual(report["verified_files"], 4)
        self.assertEqual(report["errors"], [
            "Missing required artifact: fidelity-word/edited-1.docx",
            "Missing required artifact: fidelity-word/edited-2.docx",
            "Missing required artifact: fidelity-word/edited-3.docx",
        ])

    def test_same_count_with_wrong_name_fails_exact_membership(self):
        self.complete()
        (self.build / "fidelity-word/edited-3.docx").rename(
            self.build / "fidelity-word/edited-4.docx"
        )
        report = inventory.verify(self.manifest, self.root)
        self.assertFalse(report["ok"])
        self.assertEqual(report["observed_files"], 7)
        self.assertEqual(len(report["errors"]), 2)
        self.assertIn("Unexpected Office artifact: fidelity-word/edited-4.docx", report["errors"])

    def test_unlisted_whole_directory_is_not_silently_ignored(self):
        self.complete()
        self.output("fidelity-unlisted/stray.docx")
        report = inventory.verify(self.manifest, self.root)
        self.assertFalse(report["ok"])
        self.assertEqual(report["errors"], ["Unexpected Office artifact: fidelity-unlisted/stray.docx"])

    def test_empty_or_truncated_zip_never_counts_as_evidence(self):
        self.complete()
        target = self.build / "fidelity-source.pptx"
        for contents in (b"", b"PK\x03\x04truncated", b"plain text"):
            with self.subTest(contents=contents):
                target.write_bytes(contents)
                report = inventory.verify(self.manifest, self.root)
                self.assertFalse(report["ok"])
                self.assertEqual(report["verified_files"], 6)
                self.assertIn("Invalid artifact fidelity-source.pptx", report["errors"][0])

    def test_empty_zip_is_not_an_office_package(self):
        self.complete()
        with zipfile.ZipFile(self.build / "fidelity-source.pptx", "w"):
            pass
        report = inventory.verify(self.manifest, self.root)
        self.assertFalse(report["ok"])
        self.assertIn("missing OPC", report["errors"][0])

    def test_missing_build_cannot_pass(self):
        report = inventory.verify(self.manifest, self.root)
        self.assertFalse(report["ok"])
        self.assertEqual(report["observed_files"], 0)
        self.assertEqual(len(report["errors"]), 7)

    def test_failed_run_replaces_prior_success_receipt(self):
        self.complete()
        with patch.object(inventory, "load_manifest", return_value=self.manifest):
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(inventory.main(["verify", "--package-root", str(self.root)]), 0)
                (self.build / "fidelity-source.pptx").unlink()
                self.assertEqual(inventory.main(["verify", "--package-root", str(self.root)]), 1)
        receipt = json.loads((self.build / inventory.RECEIPT).read_text())
        self.assertFalse(receipt["ok"])
        self.assertEqual(receipt["verified_files"], 6)

    def test_clean_removes_only_known_files_and_receipt(self):
        self.complete()
        inventory.write_receipt(inventory.verify(self.manifest, self.root), self.root)
        unexpected = self.output("fidelity-word/unlisted.docx")
        unrelated = self.output("arbitrary-build/user.docx")
        notes = self.build / "fidelity-word/notes.txt"
        notes.write_text("retain")
        sibling = self.root.parent / "editor/build/fidelity/editor.docx"
        sibling.parent.mkdir(parents=True)
        sibling.write_bytes(b"retain editor evidence")
        removed = inventory.clean(self.manifest, self.root)
        self.assertEqual(set(removed), {*self.manifest.paths, inventory.RECEIPT})
        for retained in (unexpected, unrelated, notes, sibling):
            self.assertTrue(retained.exists(), retained)
        report = inventory.verify(self.manifest, self.root)
        self.assertFalse(report["ok"])
        self.assertEqual(report["verified_files"], 0)
        self.assertTrue(any("Unexpected Office artifact" in error for error in report["errors"]))

    def test_clean_preflights_every_path_before_any_deletion(self):
        self.complete()
        last = self.build / self.manifest.paths[-1]
        last.unlink()
        outside = self.root.parent / "outside.docx"
        outside.write_bytes(b"preserve")
        last.symlink_to(outside)
        with self.assertRaisesRegex(inventory.InventoryError, "symlink"):
            inventory.clean(self.manifest, self.root)
        for name in self.manifest.paths[:-1]:
            self.assertTrue((self.build / name).exists(), name)
        self.assertEqual(outside.read_bytes(), b"preserve")
        self.assertFalse(inventory.verify(self.manifest, self.root)["ok"])

    def test_clean_refuses_symlinked_parent_directory(self):
        outside = self.root.parent / "outside"
        outside.mkdir()
        kept = outside / "edited-1.docx"
        kept.write_bytes(b"preserve")
        self.build.mkdir()
        (self.build / "fidelity-word").symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(inventory.InventoryError, "symlink"):
            inventory.clean(self.manifest, self.root)
        self.assertEqual(kept.read_bytes(), b"preserve")

    def test_wrong_package_is_rejected_before_mutation(self):
        self.complete()
        (self.root / "pubspec.yaml").write_text("name: quds_office_editor\n")
        with self.assertRaisesRegex(inventory.InventoryError, "package root"):
            inventory.clean(self.manifest, self.root)
        self.assertTrue(all((self.build / name).exists() for name in self.manifest.paths))

    def test_default_package_root_does_not_depend_on_cwd(self):
        previous = Path.cwd()
        try:
            os.chdir(self.root.parent)
            self.assertEqual(inventory.package_root(), inventory.DEFAULT_ROOT)
            self.assertEqual(inventory.package_root(self.root), self.root)
        finally:
            os.chdir(previous)

    def test_duplicate_empty_or_miscounted_manifest_fails(self):
        original = json.loads(json.dumps(self.data))
        for mutation in ("duplicate", "empty", "count"):
            with self.subTest(mutation=mutation):
                self.data = json.loads(json.dumps(original))
                if mutation == "duplicate":
                    self.data["standalone"].append(self.data["standalone"][0])
                elif mutation == "empty":
                    self.data.update(series=[], standalone=[], expected_file_count=0)
                else:
                    self.data["expected_file_count"] = 8
                with self.assertRaises(inventory.InventoryError):
                    self.load()

    def test_manifest_paths_cannot_escape_or_target_other_build_files(self):
        for unsafe in ("../outside.docx", "/outside.docx", "fidelity-word/../outside.docx",
                       "fidelity-word//edited.docx", "fidelity-word\\edited.docx",
                       "arbitrary-build/user.docx", "fidelity-word/data.json"):
            with self.subTest(path=unsafe):
                self.data["standalone"][0]["path"] = unsafe
                with self.assertRaises(inventory.InventoryError):
                    self.load()

    def test_manifest_cycle_definition_cannot_silently_shrink(self):
        for invalid in ([1, 2], [1, 2, 2], [1, 2, 3, 4], [True, 2, 3]):
            with self.subTest(cycles=invalid):
                self.data["series"][0]["cycles"] = invalid
                with self.assertRaises(inventory.InventoryError):
                    self.load()


if __name__ == "__main__":
    unittest.main()
