# SPDX-License-Identifier: MPL-2.0
"""Adversarial receipt checks; no .NET installation required."""
import argparse
import copy
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import zipfile

import schema


class SchemaGateTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        schema.write_controls(self.root / "controls")
        self.directory = self.root / "controls/positive"
        self.expected = schema.office_files(self.directory)
        self.report = {"Files": 1, "Failures": 0, "Reports": [
            {"File": name, "Sha256": digest, "Errors": []}
            for name, digest in self.expected.items()]}

    def test_success_requires_exact_hashes_and_file_coverage(self):
        self.assertEqual(schema.verify_report(self.report, self.expected, 0),
                         {"files": 1, "errors": 0, "hashesVerified": True})
        mutations = []
        missing = copy.deepcopy(self.report)
        missing["Reports"] = []
        mutations.append(missing)
        stale = copy.deepcopy(self.report)
        stale["Reports"][0]["Sha256"] = "0" * 64
        mutations.append(stale)
        duplicate = copy.deepcopy(self.report)
        duplicate["Reports"] *= 2
        mutations.append(duplicate)
        elsewhere = copy.deepcopy(self.report)
        elsewhere["Reports"][0]["File"] = str(self.root / "elsewhere.docx")
        mutations.append(elsewhere)
        for report in mutations:
            with self.subTest(report=report), self.assertRaises(ValueError):
                schema.verify_report(report, self.expected, 0)

    def test_nonzero_exit_and_schema_errors_cannot_be_swallowed(self):
        with self.assertRaises(ValueError):
            schema.verify_report(self.report, self.expected, 1)
        bad = copy.deepcopy(self.report)
        bad["Reports"][0]["Errors"] = [{"Id": "Sch_InvalidElementContent"}]
        for code in (0, 1):
            with self.subTest(code=code), self.assertRaises(ValueError):
                schema.verify_report(bad, self.expected, code)
        bad["Failures"] = 1
        with self.assertRaises(ValueError):
            schema.verify_report(bad, self.expected, 1)

    def test_negative_control_requires_real_rejection_of_each_file(self):
        with self.assertRaisesRegex(ValueError, "negative.*accepted"):
            schema.verify_report(self.report, self.expected, 0, require_errors=True)
        report = copy.deepcopy(self.report)
        report["Failures"] = 1
        report["Reports"][0]["Errors"] = [{"Id": "Sch_EnumerationConstraintFailed"}]
        self.assertEqual(schema.verify_report(report, self.expected, 1, require_errors=True)["errors"], 1)
        report["Reports"][0]["Exception"] = "Could not open the package"
        with self.assertRaisesRegex(ValueError, "could not inspect"):
            schema.verify_report(report, self.expected, 1, require_errors=True)

    def test_summary_counts_and_error_records_are_verified(self):
        for field, value in (("Files", True), ("Failures", False), ("Failures", 2)):
            report = copy.deepcopy(self.report)
            report[field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                schema.verify_report(report, self.expected, 0)
        for errors in (None, [None], [{}], ["invalid"]):
            report = copy.deepcopy(self.report)
            report["Reports"][0]["Errors"] = errors
            with self.subTest(errors=errors), self.assertRaises(ValueError):
                schema.verify_report(report, self.expected, 0)

    def test_control_packages_are_deterministic_and_distinct(self):
        second = self.root / "other-controls"
        schema.write_controls(second)
        self.assertEqual(schema.tree_snapshot(second), schema.tree_snapshot(self.root / "controls"))
        xml = {}
        for name in ("positive/valid.docx", "negative/invalid-child.docx", "negative/invalid-nowrap.docx"):
            with zipfile.ZipFile(second / name) as archive:
                xml[name] = archive.read("word/document.xml").decode()
        self.assertIn('w:noWrap w:val="off"', xml["positive/valid.docx"])
        self.assertIn('w:noWrap w:val="0"', xml["negative/invalid-nowrap.docx"])
        self.assertIn('<w:p/><w:t>Invalid child</w:t></w:body>', xml["negative/invalid-child.docx"])

    def test_input_mutation_invalidates_an_otherwise_passing_receipt(self):
        output = self.root / "gate"
        output.mkdir()
        gate = schema.Gate(output)
        def run(*args, **kwargs):
            schema.write_json(output / "validate.json", self.report)
            (self.directory / "valid.docx").write_bytes(b"mutated after validation")
            return subprocess.CompletedProcess([], 0, "", "")
        with mock.patch.object(gate, "command", side_effect=run):
            with self.assertRaisesRegex(ValueError, "read-only inputs"):
                schema.validate_directory(gate, "dotnet", Path("validator.dll"), self.directory, "validate")

    def test_upstream_receipt_binds_copied_code_and_license(self):
        target = self.root / "validator-source"
        shutil.copytree(schema.VALIDATOR, target)
        schema.verify_upstream(target)
        (target / "Program.cs").write_text("// Always returns success now.\n")
        with self.assertRaisesRegex(ValueError, "source changed"):
            schema.verify_upstream(target)

    def test_process_timeout_leaves_the_failed_stage_in_the_receipt(self):
        output = self.root / "timeout-gate"
        output.mkdir()
        gate = schema.Gate(output)
        with mock.patch.object(schema.subprocess, "run", side_effect=subprocess.TimeoutExpired(["validator"], 300)):
            with self.assertRaises(subprocess.TimeoutExpired):
                gate.command("timed-out", ["validator"])
        receipt = json.loads((output / "report.json").read_text())
        self.assertEqual(receipt["stages"][-1]["status"], "error")
        self.assertIn("TimeoutExpired", receipt["stages"][-1]["error"])

    def make_corpus(self):
        directory = self.root / "corpus"
        directory.mkdir()
        (directory / "case.doc").write_bytes(b"independently authored DOC")
        shutil.copyfile(self.directory / "valid.docx", directory / "case.docx")
        manifest = {"version": 1, "cases": [{"name": "case", "source": "case.doc",
                     "output": "case.docx", "producer": "literal binary source"}]}
        schema.write_json(directory / "manifest.json", manifest)
        return directory, manifest

    def test_corpus_requires_source_output_and_exact_inventory(self):
        directory, manifest = self.make_corpus()
        receipt = schema.corpus_receipt(directory, {"case"})
        self.assertEqual(receipt["cases"][0]["sourceSha256"], schema.sha(directory / "case.doc"))
        with self.assertRaises(ValueError):
            schema.corpus_receipt(directory, {"case", "lost-case"})
        manifest["cases"] *= 2
        schema.write_json(directory / "manifest.json", manifest)
        with self.assertRaises(ValueError):
            schema.corpus_receipt(directory, {"case"})

    def test_required_border_inventory_matches_the_independent_fixture_case_list(self):
        fixture = (schema.ROOT / "test/support/table_border_fixture.dart").read_text()
        names = re.findall(r"TableBorderCase\(\s*'([^']+)'", fixture)
        self.assertEqual(12, len(names))
        self.assertEqual(len(names), len(set(names)))
        required = {name.removeprefix("table-borders/") for name in schema.EXPECTED_CASES
                    if name.startswith("table-borders/")}
        self.assertEqual(set(names), required)

    def test_required_width_inventory_matches_literal_source_cases(self):
        fixture = (schema.ROOT / "test/support/table_width_fixture.dart").read_text()
        names = re.findall(r"TableWidthCase\(\s*'([^']+)'", fixture)
        self.assertEqual(18, len(names))
        self.assertEqual(len(names), len(set(names)))
        required = {name.removeprefix("table-width/") for name in schema.EXPECTED_CASES
                    if name.startswith("table-width/")}
        self.assertEqual(set(names), required)

    def test_required_media_review_inventory_covers_every_native_occurrence(self):
        fixture = (schema.ROOT / "test/support/media_revision_fixture.dart").read_text()
        declaration = re.search(r"const mediaReviewKinds = \[(.*?)\];", fixture, re.S)
        self.assertIsNotNone(declaration)
        kinds = re.findall(r"'([^']+)'", declaration.group(1))
        self.assertEqual(8, len(kinds))
        self.assertEqual(len(kinds), len(set(kinds)))
        required = {name.removeprefix("media-reviews/") for name in schema.EXPECTED_CASES
                    if name.startswith("media-reviews/")}
        self.assertEqual({f"{kind}-{state}" for kind in kinds
                          for state in ("inserted", "deleted", "overlapping")}, required)

    def test_required_reconciled_inventories_match_literal_case_lists(self):
        for prefix, filename, constant, count in (
            ("table-operations", "table_operations_fixture.dart", "tableOperationsCaseNames", 12),
            ("list-sequences", "list_sequence_fixture.dart", "listSequenceCaseNames", 7),
            ("image-appearance", "image_appearance_probe.dart", "imageAppearanceCases", 9),
        ):
            fixture = (schema.ROOT / "tool/fidelity" / filename).read_text()
            declaration = re.search(r"const " + constant + r" = \[(.*?)\];", fixture, re.S)
            self.assertIsNotNone(declaration)
            names = re.findall(r"'([^']+)'", declaration.group(1))
            self.assertEqual(count, len(names))
            self.assertEqual(len(names), len(set(names)))
            required = {name.removeprefix(prefix + "/") for name in schema.EXPECTED_CASES
                        if name.startswith(prefix + "/")}
            self.assertEqual(set(names), required)

    def test_required_textbox_boundaries_include_empty_and_intentional_blanks_in_both_stories(self):
        fixture = (schema.ROOT / "test/support/textbox_boundary_fixture.dart").read_text()
        declaration = re.search(r"const textboxBoundaryCases = .*?\{(.*?)\n\};", fixture, re.S)
        self.assertIsNotNone(declaration)
        names = re.findall(r"^\s*'([^']+)':", declaration.group(1), re.M)
        self.assertEqual(7, len(names))
        self.assertEqual(7, len(set(names)))
        required = {f"textbox-boundary/textbox-{story}-{name}"
                    for story in ("main", "header") for name in names}
        self.assertEqual(required, {name for name in schema.EXPECTED_CASES
                                    if name.startswith("textbox-boundary/")})

    def test_required_note_boundaries_preserve_table_tails_and_intentional_blanks(self):
        fixture = (schema.ROOT / "test/support/note_boundary_fixture.dart").read_text()
        declaration = re.search(r"const noteBoundaryCases = .*?\{(.*?)\n\};", fixture, re.S)
        self.assertIsNotNone(declaration)
        names = re.findall(r"^\s*'([^']+)':", declaration.group(1), re.M)
        self.assertEqual(8, len(names))
        self.assertEqual(8, len(set(names)))
        required = {f"note-boundary/{story}-{name}"
                    for story in ("footnote", "endnote") for name in names}
        self.assertEqual(required, {name for name in schema.EXPECTED_CASES
                                    if name.startswith("note-boundary/")})

    def test_required_header_aliases_include_blank_controls_and_native_regression(self):
        fixture = (schema.ROOT / "test/support/textbox_boundary_fixture.dart").read_text()
        declaration = re.search(r"const textboxBoundaryCases = .*?\{(.*?)\n\};", fixture, re.S)
        self.assertIsNotNone(declaration)
        names = re.findall(r"^\s*'([^']+)':", declaration.group(1), re.M)
        self.assertEqual(7, len(names))
        self.assertEqual(7, len(set(names)))
        required = {f"header-alias/header-alias-{name}" for name in names}
        self.assertEqual(required, {name for name in schema.EXPECTED_CASES
                                    if name.startswith("header-alias/")})
        self.assertIn("native-inputs/header-textbox-duplicate-chain", schema.EXPECTED_CASES)
        self.assertIn("native-inputs/header-textbox-first-enabled", schema.EXPECTED_CASES)
        self.assertIn("native-inputs/header-textbox-first-roundtrip", schema.EXPECTED_CASES)

    def test_corpus_rejects_unregistered_inputs_aliases_and_escape(self):
        directory, manifest = self.make_corpus()
        shutil.copyfile(directory / "case.docx", directory / "extra.DOCX")
        with self.assertRaisesRegex(ValueError, "unregistered"):
            schema.corpus_receipt(directory, {"case"})
        (directory / "extra.DOCX").unlink()
        manifest["cases"].append(dict(manifest["cases"][0], name="alias"))
        schema.write_json(directory / "manifest.json", manifest)
        with self.assertRaisesRegex(ValueError, "alias"):
            schema.corpus_receipt(directory, {"case", "alias"})
        manifest["cases"] = [dict(manifest["cases"][0], source="../outside.doc")]
        schema.write_json(directory / "manifest.json", manifest)
        with self.assertRaisesRegex(ValueError, "escapes"):
            schema.corpus_receipt(directory, {"case"})

    def test_noop_validator_leaves_failed_receipt_without_generating_corpus(self):
        output = self.root / "failed-gate"
        args = argparse.Namespace(out=output, dart=sys.executable, dotnet=sys.executable, cached_nuget=None)
        def fake_command(gate, name, args, **kwargs):
            text = schema.SELF_TEST_MARKER if name == "validator-self-test" else "test version"
            return subprocess.CompletedProcess(args, 0, text, "")
        def fake_validate(gate, dotnet, validator, directory, name, **kwargs):
            expected = schema.office_files(directory)
            report = {"Files": len(expected), "Failures": 0, "Reports": [
                {"File": name, "Sha256": digest, "Errors": []} for name, digest in expected.items()]}
            return schema.verify_report(report, expected, 0, **kwargs)
        with mock.patch.object(schema.Gate, "command", fake_command), \
                mock.patch.object(schema, "build_validator", return_value=self.root / "validator.dll"), \
                mock.patch.object(schema, "validate_directory", side_effect=fake_validate):
            self.assertEqual(schema.run_gate(args), 1)
        receipt = json.loads((output / "report.json").read_text())
        self.assertFalse(receipt["passed"])
        self.assertTrue(receipt["gitWorktreeDirty"])
        self.assertIn("Uncommitted source state", receipt["sourceIdentity"])
        self.assertIn("negative validator control was accepted", receipt["error"])
        self.assertFalse((output / "corpus").exists())


if __name__ == "__main__":
    unittest.main()
