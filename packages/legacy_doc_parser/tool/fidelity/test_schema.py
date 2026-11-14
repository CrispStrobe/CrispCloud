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

    def test_binary_contract_inventory_keeps_malformed_controls_out_of_successes(self):
        prefix = "binary-contracts/"
        required = {name.removeprefix(prefix) for name in schema.EXPECTED_CASES
                    if name.startswith(prefix)}
        self.assertEqual(57, len(required))
        self.assertEqual({"bool8-fkp-false", "bool8-fkp-true", "bool8-piece-false", "bool8-piece-true"},
                         {name for name in required if name.startswith("bool8-")})
        self.assertEqual(45, len([name for name in required if name.startswith("heading-")]))
        self.assertEqual({"normal-outline-0", "normal-outline-8", "normal-outline-9"},
                         {name for name in required if name.startswith("normal-")})
        self.assertEqual({"indirect-huge-first-replaces-tail", "indirect-huge-nonfirst-ignored",
                          "indirect-huge-nonfirst-cycle-ignored", "indirect-huge-minimum-size",
                          "indirect-table-to-huge-chain"},
                         {name for name in required if name.startswith("indirect-")})
        self.assertFalse(any("invalid" in name for name in required))
        self.assertNotIn("indirect-huge-short-data", required)
        self.assertNotIn("indirect-huge-first-cycle", required)

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

    def make_public_corpus(self, directory=None, *, raw=False):
        directory = directory or self.root / "public"
        directory.mkdir(parents=True)
        shutil.copyfile(self.directory / "valid.docx", directory / "case.docx")
        case = {"name": "case", "inputKind": "public-model", "output": "case.docx"}
        expected = {"case": {"output": "case.docx"}}
        if raw:
            (directory / "case.bin").write_bytes(b"independently retained raw input")
            case["source"] = expected["case"]["source"] = "case.bin"
        manifest = [case]
        schema.write_json(directory / "cases.json", manifest)
        return directory, manifest, expected

    def test_all_public_inventories_have_independent_required_sizes(self):
        self.assertEqual({
            "public-metafile": 24, "public-compound": 17,
            "public-formatting": 106, "public-table-formatting": 53,
            "cached-field-structure": 88, "display-field-evidence": 46,
            "public-section-geometry": 44,
            "public-bookmarks": 21, "public-textbox-references": 20,
        }, {name: len(specification["cases"]) for name, specification in schema.PUBLIC_CORPORA.items()})
        self.assertEqual(419, sum(len(item["cases"]) for item in schema.PUBLIC_CORPORA.values()))
        for specification in schema.PUBLIC_CORPORA.values():
            self.assertTrue((schema.ROOT / specification["generator"]).is_file())
            outputs = [case["output"] for case in specification["cases"].values()]
            self.assertEqual(len(outputs), len(set(outputs)))

    def test_public_semantic_inventories_require_terminal_owners_and_inert_controls(self):
        required = {
            "public-bookmarks": {
                "visible-auxiliary-end", "visible-adjacent-footnote-end", "visible-shared-auxiliary-point",
                "hidden-valid", "hidden-first-column", "hidden-last-column",
            },
            "public-textbox-references": {
                "visible-single-header", "visible-single-footer", "visible-single-footnoteSeparator",
                "visible-single-footnoteContinuationSeparator", "visible-single-footnoteContinuationNotice",
                "visible-single-endnoteSeparator", "visible-single-endnoteContinuationSeparator",
                "visible-single-endnoteContinuationNotice", "visible-unresolved-chain", "hidden-single", "hidden-chain",
            },
        }
        for group, controls in required.items():
            with self.subTest(group=group):
                expected = schema.PUBLIC_CORPORA[group]["cases"]
                self.assertLessEqual(controls, set(expected))
                self.assertTrue(all(set(case) == {"output"} for case in expected.values()))
                self.assertFalse(any(name.startswith(group + "/") for name in schema.EXPECTED_CASES))
                directory = self.root / group
                directory.mkdir()
                manifest = []
                for name, paths in expected.items():
                    shutil.copyfile(self.directory / "valid.docx", directory / paths["output"])
                    manifest.append({"name": name, "inputKind": "public-model", **paths})
                schema.write_json(directory / "cases.json", manifest)
                self.assertEqual(len(expected), len(schema.public_corpus_receipt(directory, expected)["cases"]))
                for omitted in controls:
                    with self.subTest(omitted=omitted):
                        schema.write_json(directory / "cases.json", [case for case in manifest if case["name"] != omitted])
                        with self.assertRaisesRegex(ValueError, "required case"):
                            schema.public_corpus_receipt(directory, expected)

    def test_public_receipts_bind_model_metadata_outputs_and_optional_raw_inputs(self):
        for index, (raw, wrapped) in enumerate(((False, False), (False, True), (True, False), (True, True))):
            with self.subTest(raw=raw, wrapped=wrapped):
                directory, manifest, expected = self.make_public_corpus(self.root / f"public-{index}", raw=raw)
                if wrapped:
                    schema.write_json(directory / "cases.json", {"cases": manifest, "uncheckedBaseline": False})
                receipt = schema.public_corpus_receipt(directory, expected)
                self.assertEqual(receipt["manifestSha256"], schema.sha(directory / "cases.json"))
                self.assertEqual(receipt["cases"][0]["outputSha256"], schema.sha(directory / "case.docx"))
                self.assertEqual(receipt["outputs"], schema.office_files(directory))
                if raw:
                    self.assertEqual(receipt["cases"][0]["sourceSha256"], schema.sha(directory / "case.bin"))
                else:
                    self.assertNotIn("sourceSha256", receipt["cases"][0])

    def test_public_manifest_rejects_missing_duplicate_extra_and_malformed_cases(self):
        directory, manifest, expected = self.make_public_corpus()
        for value in (
            [], manifest * 2, manifest + [dict(manifest[0], name="extra")],
            None, {}, {"cases": None}, [None], [{}], [dict(manifest[0], name=1)],
        ):
            with self.subTest(manifest=value):
                schema.write_json(directory / "cases.json", value)
                with self.assertRaises(ValueError):
                    schema.public_corpus_receipt(directory, expected)
        (directory / "cases.json").write_text("{invalid JSON")
        with self.assertRaises(ValueError):
            schema.public_corpus_receipt(directory, expected)
        (directory / "cases.json").unlink()
        with self.assertRaises(FileNotFoundError):
            schema.public_corpus_receipt(directory, expected)

    def test_public_manifest_rejects_unchecked_baselines(self):
        directory, manifest, expected = self.make_public_corpus()
        for unchecked in (True, 1, "false", None):
            with self.subTest(unchecked=unchecked):
                schema.write_json(directory / "cases.json", {"cases": manifest, "uncheckedBaseline": unchecked})
                with self.assertRaisesRegex(ValueError, "Unchecked"):
                    schema.public_corpus_receipt(directory, expected)

    def test_public_source_and_output_paths_are_pinned_and_contained(self):
        directory, manifest, expected = self.make_public_corpus(raw=True)
        for kind in ("source", "output"):
            for value in (None, [], "../outside.bin", str(directory / manifest[0][kind]), "other.docx"):
                with self.subTest(kind=kind, path=value):
                    changed = copy.deepcopy(manifest)
                    changed[0][kind] = value
                    schema.write_json(directory / "cases.json", changed)
                    with self.assertRaises(ValueError):
                        schema.public_corpus_receipt(directory, expected)
            changed = copy.deepcopy(manifest)
            del changed[0][kind]
            schema.write_json(directory / "cases.json", changed)
            with self.subTest(missing=kind), self.assertRaises(ValueError):
                schema.public_corpus_receipt(directory, expected)
        schema.write_json(directory / "cases.json", manifest)
        with self.assertRaisesRegex(ValueError, "unexpected public-model source"):
            schema.public_corpus_receipt(directory, {"case": {"output": "case.docx"}})

    def test_public_inventory_requires_retained_files_and_rejects_extras_and_aliases(self):
        directory, manifest, expected = self.make_public_corpus(raw=True)
        for filename in ("case.bin", "case.docx"):
            contents = (directory / filename).read_bytes()
            (directory / filename).unlink()
            with self.subTest(missing=filename), self.assertRaisesRegex(ValueError, "Missing public-model"):
                schema.public_corpus_receipt(directory, expected)
            (directory / filename).write_bytes(contents)
        for filename in ("unregistered.DOCX", "unregistered.bin"):
            (directory / filename).write_bytes(b"unregistered")
            with self.subTest(extra=filename), self.assertRaisesRegex(ValueError, "unregistered"):
                schema.public_corpus_receipt(directory, expected)
            (directory / filename).unlink()
        manifest.append(dict(manifest[0], name="alias"))
        schema.write_json(directory / "cases.json", manifest)
        with self.assertRaisesRegex(ValueError, "alias"):
            schema.public_corpus_receipt(directory, {**expected, "alias": dict(expected["case"])})

    def test_public_gate_checks_second_inventory_and_all_retained_bytes_before_validation(self):
        specification = {"sample": {"generator": "fixture.dart", "cases": {"case": {"output": "case.docx"}}}}
        for mutation in ("none", "missing-case", "output-bytes", "model-description"):
            with self.subTest(mutation=mutation):
                output = self.root / ("public-gate-" + mutation)
                output.mkdir()
                gate = schema.Gate(output)

                def generate(name, arguments, **kwargs):
                    directory, manifest, _ = self.make_public_corpus(Path(arguments[-1]))
                    if name == "repeat-sample":
                        if mutation == "missing-case":
                            schema.write_json(directory / "cases.json", [])
                        elif mutation == "output-bytes":
                            with (directory / "case.docx").open("ab") as stream:
                                stream.write(b"changed")
                        elif mutation == "model-description":
                            manifest[0]["scope"] = "changed"
                            schema.write_json(directory / "cases.json", manifest)
                    return subprocess.CompletedProcess(arguments, 0, "", "")

                with mock.patch.object(schema, "PUBLIC_CORPORA", specification), \
                        mock.patch.object(gate, "command", side_effect=generate) as commands, \
                        mock.patch.object(schema, "validate_directory", return_value={"files": 1}) as validate:
                    if mutation == "none":
                        schema.run_public_corpora(gate, "dart", "dotnet", Path("validator.dll"))
                        validate.assert_called_once_with(
                            gate, "dotnet", Path("validator.dll"), output / "public-corpora/sample",
                            "sample-schema-validation")
                        receipt = gate.report["publicCorpora"]["sample"]
                        self.assertTrue(receipt["determinism"]["passed"])
                        self.assertEqual(receipt["determinism"]["cases"], 1)
                        self.assertEqual(receipt["determinism"]["files"], 2)
                    else:
                        with self.assertRaises(ValueError):
                            schema.run_public_corpora(gate, "dart", "dotnet", Path("validator.dll"))
                        validate.assert_not_called()
                    self.assertEqual([call.args[0] for call in commands.call_args_list],
                                     ["generate-sample", "repeat-sample"])


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
