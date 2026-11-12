#!/usr/bin/env python3
"""Build and run the independent Open XML SDK gate without native Office."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "tool/office-validation"
OFFICE_SUFFIXES = {".docx", ".docm", ".dotx", ".dotm", ".xlsx", ".pptx"}
EXPECTED_CASES = frozenset([
    *(f"table-origin/{name}" for name in (
        "default", "zero-margin", "wide-margin", "negative-origin",
        "positive-origin", "independent-gap", "cell-margin", "nested", "nested-wide")),
    "table-text-conditions", "table-text-relative-toggles",
    *(f"table-layout/{name}" for name in (
        "auto", "minimum-short", "minimum-content", "exact-short", "exact-content",
        "keep-row", "split-row", "cell-layout")),
    *(f"table-borders/{name}" for name in (
        "old-after", "old-before", "old-nil", "old-explicit", "modern-after", "modern-before",
        "modern-nil", "modern-explicit", "range-nil", "range-none", "interior-colors", "row-reset")),
    *(f"table-operations/{name}" for name in (
        "delete-resize", "merge", "split", "rtl-physical-left", "rtl-physical-center",
        "rtl-physical-right", "rtl-logical-left", "rtl-logical-center", "rtl-logical-right",
        "row-exceptions", "style-identities", "indirect-cache")),
    *(f"table-width/{name}" for name in (
        "tc80-nil",
        "range-nil",
        "tc80-auto",
        "range-auto",
        "tc80-percent",
        "range-percent",
        "tc80-dxa",
        "range-dxa",
        "tc80-narrow",
        "range-narrow",
        "dxa-to-auto",
        "auto-to-dxa",
        "range-reset",
        "style-auto",
        "style-dxa",
        "tc80-asymmetric",
        "range-asymmetric",
        "grid-asymmetric-control",
    )),
    *(f"table-reviews/table-review-{kind}-{state}" for kind in
      ("height", "split", "header") for state in ("review", "accepted", "rejected")),
    *(f"list-sequences/{name}" for name in (
        "shared-counter", "explicit-start", "format-continue", "same-instance-ancestor",
        "never-restart", "legal-decimal-zero", "hidden-marker")),
    *(f"shapes/{name}" for name in ("rect", "ellipse", "line", "custom")),
    *(f"shapes/line-{axis}-{flip}" for axis in ("h", "v") for flip in ("none", "x", "y", "xy")),
    *(f"metafiles/{kind}-{mode}" for kind in ("emf32", "emf16", "wmf")
      for mode in ("alternate", "winding")),
    *(f"image-appearance/{name}" for name in (
        "inline-horizontal",
        "floating-control",
        "floating-horizontal",
        "floating-vertical",
        "floating-both",
        "floating-quarter",
        "floating-negative-quarter",
        "floating-margin-quarter",
        "floating-outline-shadow",
    )),
    *(f"packed-shapes/{encoding}-{flip}" for encoding in
      ("full", "packed", "packed-header-excluded") for flip in ("none", "xy")),
    *(f"note-formats/note-formats-{name}" for name in (
        "east-asian-sepx", "korean-sepx", "rtl-dop", "south-asian-dop", "cyrillic-sepx",
        "none-sepx", "fallback-sepx", "unknown-sepx", "revision")),
    *(f"media-reviews/{kind}-{state}" for kind in (
        "inline-picture", "floating-picture", "embedded-object", "editable-shape",
        "footnote-picture", "footnote-anchor", "endnote-anchor", "comment-anchor",
    ) for state in ("inserted", "deleted", "overlapping")),
    "reviews/numbering-change", "reviews/numbering-insertion",
    "reviews/listnum-display-change", "section-review",
    "native-inputs/formatting", "native-inputs/linked-textboxes",
    "native-inputs/word14-margin-origin", "native-inputs/word16-page-origin",
    "native-inputs/poi-simple-table2",
    "native-inputs/word16-page-origin-lo-blip-count",
    "native-inputs/officeart-shapes",
    "native-inputs/header-textbox-duplicate-chain",
    "native-inputs/header-textbox-first-enabled",
    "native-inputs/header-textbox-first-roundtrip",
    *(f"header-alias/header-alias-{kind}" for kind in (
        "content", "empty", "leading-blank", "interior-blank", "trailing-blank",
        "two-trailing-blanks", "two-content-paragraphs")),
    *(f"native-inputs/{kind}-ending-{ending}" for kind in ("header", "footer")
      for ending in ("paragraph", "table")),
    *(f"textbox-boundary/textbox-{story}-{kind}" for story in ("main", "header")
      for kind in ("content", "empty", "leading-blank", "interior-blank",
                   "trailing-blank", "two-trailing-blanks", "two-content-paragraphs")),
    *(f"note-boundary/{story}-{kind}" for story in ("footnote", "endnote")
      for kind in ("plain", "empty", "trailing-blank", "two-trailing-blanks",
                   "table", "table-blank", "table-two-blanks", "table-text")),
    *(f"textbox-tables/textbox-{story}-{margin}-{nesting}-{anchor}"
      for story in ("main", "header") for margin in ("default", "zero", "wide")
      for nesting in ("flat", "nested") for anchor in ("paragraph", "table")),
])
PACKAGES = (
    ("DocumentFormat.OpenXml", "3.3.0",
     "53a74167552d886f0e312540db12c86a6133a83bd698795f3be6e25fc091b9e7",
     "72e8f6e3e3527d7e6ee29f2f9182ef1b39a4de6da355a33013c0940efb24d87e"),
    ("DocumentFormat.OpenXml.Framework", "3.3.0",
     "5f539f1602b642198ec6ed3ec567eac3fff62309f6ec65e28db2751a488ec30d",
     "5b8c2b9ca1aa70539af0b8054d649bd09fdce4dec812b263ab511b13789c8589"),
    ("System.IO.Packaging", "8.0.1",
     "c5fd0101fa90bc84e89a906cbdfa7188bb6cffab11404cdd8cd0377ffabfbd8e",
     "12ddc8bff279fad856551a74894dc52b80fa437d5d2b32722e70ae6899217b7c"),
)
SELF_TEST_MARKER = ("Open XML SDK controls passed: 8 valid Word packages, "
                    "4 invalid XML, 12 mismatched types, and exact discovery.")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value: object) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def source_snapshot(root: Path = ROOT) -> dict:
    paths = set()
    for pattern in ("lib/**/*.dart", "test/support/**/*.dart", "tool/fidelity/*.dart",
                    "tool/fidelity/schema.py", "tool/office-validation/*",
                    "test/fixtures/word_native/*.doc", "test/fixtures/fidelity/image-appearance/**/*",
                    "test/fixtures/fidelity/officeart-shapes.doc",
                    "pubspec.yaml", "pubspec.lock",
                    ".dart_tool/package_config.json"):
        paths.update(path for path in root.glob(pattern) if path.is_file())
    files = {path.relative_to(root).as_posix(): sha(path) for path in sorted(paths)}
    return {"files": files, "aggregateSha256": hashlib.sha256(
        json.dumps(files, sort_keys=True, separators=(",", ":")).encode()).hexdigest()}


def verify_upstream(directory: Path = VALIDATOR) -> dict:
    receipt = json.loads((directory / "upstream.json").read_text())
    if (receipt.get("version") != 1 or receipt.get("license") != "MIT" or
            receipt.get("sdkPackage") != {"id": "DocumentFormat.OpenXml", "version": "3.3.0"} or
            receipt.get("validationVersion") != "Office2019" or
            not re.fullmatch(r"[0-9a-f]{40}", receipt.get("commit", ""))):
        raise ValueError("Invalid validator source provenance")
    expected = {"Program.cs", "OfficeValidation.csproj", "LICENSE.quds"}
    if set(receipt.get("files", {})) != expected:
        raise ValueError("Incomplete validator source provenance")
    for name, record in receipt["files"].items():
        if sha(directory / name) != record["sha256"]:
            raise ValueError(f"Vendored validator source changed without a new receipt: {name}")
    return receipt


def tree_snapshot(directory: Path) -> dict[str, str]:
    return {path.relative_to(directory).as_posix(): sha(path)
            for path in sorted(directory.rglob("*")) if path.is_file()}


def office_files(directory: Path) -> dict[str, str]:
    return {str(path.resolve()): sha(path) for path in sorted(directory.rglob("*"))
            if path.is_file() and path.suffix.lower() in OFFICE_SUFFIXES}


def corpus_receipt(directory: Path, expected_cases=EXPECTED_CASES) -> dict:
    manifest = json.loads((directory / "manifest.json").read_text())
    cases = manifest.get("cases")
    if manifest.get("version") != 1 or not isinstance(cases, list):
        raise ValueError("Invalid schema corpus manifest")
    names = [case["name"] for case in cases]
    if len(names) != len(set(names)) or set(names) != set(expected_cases):
        raise ValueError("Schema corpus omitted, duplicated, or added a required case")
    outputs, records = {}, []
    for case in cases:
        record = dict(case)
        for kind in ("source", "output"):
            relative = Path(case[kind])
            path = (directory / relative).resolve()
            if relative.is_absolute() or ".." in relative.parts or not path.is_relative_to(directory.resolve()):
                raise ValueError(f"Corpus {kind} escapes its directory")
            if not path.is_file():
                raise ValueError(f"Missing corpus {kind}: {relative}")
            if path.suffix != (".doc" if kind == "source" else ".docx"):
                raise ValueError(f"Unexpected corpus {kind} type")
            record[kind + "Sha256"] = sha(path)
            if kind == "output":
                if str(path) in outputs:
                    raise ValueError("Two schema cases alias the same output")
                outputs[str(path)] = record[kind + "Sha256"]
        records.append(record)
    if outputs != office_files(directory):
        raise ValueError("Schema corpus has unregistered or missing Office outputs")
    return {"cases": records, "outputs": outputs}


def verify_report(report: dict, expected: dict[str, str], returncode: int,
                  *, require_errors: bool = False) -> dict:
    """A success code alone is insufficient: exact coverage and hashes must agree."""
    reports = report.get("Reports")
    if (not expected or not isinstance(reports, list) or
            type(report.get("Files")) is not int or report["Files"] != len(expected) or
            len(reports) != len(expected)):
        raise ValueError("Validator report has incomplete file coverage")
    seen, failures = set(), 0
    for item in reports:
        name = str(Path(item.get("File", "")).resolve())
        if name not in expected or name in seen or item.get("Sha256") != expected[name]:
            raise ValueError("Validator report has a duplicate, unexpected, or stale file receipt")
        seen.add(name)
        errors = item.get("Errors")
        if "Exception" in item or not isinstance(errors, list):
            raise ValueError("Validator could not inspect an Office package")
        if any(not isinstance(error, dict) or not error.get("Id") for error in errors):
            raise ValueError("Malformed validator error record")
        if require_errors and not errors:
            raise ValueError("A negative validator control was accepted")
        failures += len(errors)
    if type(report.get("Failures")) is not int or report["Failures"] != failures:
        raise ValueError("Validator error count disagrees with its file reports")
    if returncode != (1 if failures else 0):
        raise ValueError("Validator exit status disagrees with its report")
    if not require_errors and failures:
        raise ValueError(f"Open XML SDK rejected the corpus with {failures} schema errors")
    return {"files": len(seen), "errors": failures, "hashesVerified": True}


def write_controls(directory: Path) -> None:
    """Public OOXML contracts authored independently from the Dart converter."""
    w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    body = ('<w:tbl><w:tblPr/><w:tblGrid><w:gridCol w:w="2400"/></w:tblGrid>'
            '<w:tr><w:tc><w:tcPr><w:tcW w:w="2400" w:type="dxa"/>'
            '<w:noWrap w:val="off"/></w:tcPr><w:p><w:r><w:t>Control</w:t>'
            '</w:r></w:p></w:tc></w:tr></w:tbl><w:p/>')
    cases = {"positive/valid.docx": body,
             "negative/invalid-child.docx": body + "<w:t>Invalid child</w:t>",
             "negative/invalid-nowrap.docx": body.replace('w:val="off"', 'w:val="0"')}
    for name, content in cases.items():
        path = directory / name
        path.parent.mkdir(parents=True, exist_ok=True)
        entries = {
            "[Content_Types].xml": '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
            "_rels/.rels": '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
            "word/document.xml": f'<w:document xmlns:w="{w}"><w:body>{content}</w:body></w:document>',
        }
        with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
            for entry, xml in entries.items():
                info = zipfile.ZipInfo(entry, (2000, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, xml.encode())


class Gate:
    def __init__(self, output: Path):
        self.output = output
        self.report = {"version": 1, "passed": False, "stages": []}
        self.environment = dict(os.environ)
        temporary = output / "tmp"
        temporary.mkdir()
        self.environment.update(TMPDIR=str(temporary), DOTNET_NOLOGO="1",
                                DOTNET_CLI_TELEMETRY_OPTOUT="1",
                                DOTNET_SKIP_FIRST_TIME_EXPERIENCE="1",
                                DOTNET_CLI_HOME=str(output / "dotnet-home"))
        self.save()

    def save(self):
        write_json(self.output / "report.json", self.report)

    def command(self, name: str, args: list[str], *, allowed=(0,), cwd: Path = ROOT):
        stage = {"name": name, "command": list(map(str, args)), "status": "running"}
        self.report["stages"].append(stage)
        self.save()
        try:
            result = subprocess.run(stage["command"], cwd=cwd, env=self.environment,
                                    text=True, capture_output=True, timeout=300)
        except Exception as error:
            stage.update(status="error", error=f"{type(error).__name__}: {error}")
            self.save()
            raise
        log = self.output / (name + ".log")
        log.write_text(result.stdout + result.stderr)
        stage.update(returncode=result.returncode, log=log.name,
                     logSha256=sha(log), status="completed" if result.returncode in allowed else "error")
        self.save()
        if result.returncode not in allowed:
            raise RuntimeError(f"{name} failed with exit {result.returncode}; see {log}")
        return result


def select_sdk(gate: Gate, dotnet: str) -> tuple[str, Path]:
    result = gate.command("dotnet-sdks", [dotnet, "--list-sdks"])
    candidates = []
    for line in result.stdout.splitlines():
        match = re.fullmatch(r"(8\.\d+\.\d+) \[(.+)\]", line.strip())
        if match:
            candidates.append((match[1], Path(match[2]) / match[1]))
    if not candidates:
        raise ValueError("The schema gate requires a .NET 8 SDK")
    return max(candidates, key=lambda value: tuple(map(int, value[0].split("."))))


def build_validator(gate: Gate, dotnet: str, package_cache: Path | None) -> Path:
    upstream = verify_upstream()
    version, sdk = select_sdk(gate, dotnet)
    compiler = sdk / "Roslyn/bincore/csc.dll"
    compiler_version = gate.command("compiler-version", [dotnet, "exec", str(compiler), "-version"])
    output = gate.output / "validator"
    output.mkdir()
    receipt = {"upstream": upstream, "dotnetSha256": sha(Path(dotnet)),
               "sdkVersion": version, "compilerSha256": sha(compiler),
               "compilerVersion": compiler_version.stdout.strip()}
    receipt["installedRuntimes"] = gate.command("dotnet-runtimes", [dotnet, "--list-runtimes"]).stdout.strip()
    gate.report["validatorBuild"] = receipt
    gate.save()
    if package_cache is None:
        # Pin SDK selection even on hosts with several installed major versions.
        write_json(gate.output / "global.json", {"sdk": {"version": version, "rollForward": "disable"}})
        gate.command("validator-build", [dotnet, "publish", str(VALIDATOR / "OfficeValidation.csproj"),
                     "--configuration", "Release", "--output", str(output), "--self-contained", "false",
                     "-p:UseAppHost=false", f"-p:BaseIntermediateOutputPath={gate.output / 'obj'}/",
                     f"-p:BaseOutputPath={gate.output / 'bin'}/",
                     f"-p:RestorePackagesPath={gate.output / 'nuget'}"], cwd=gate.output)
        receipt["mode"] = "dotnet-publish"
        assets = gate.output / "obj/project.assets.json"
        receipt["resolvedAssetsSha256"] = sha(assets)
    else:
        # For environments where MSBuild's named mutexes are unavailable, invoke
        # the same SDK C# compiler directly with hash-pinned cached NuGet inputs.
        # No network, source rewrite, validation exclusion, or stale binary reuse.
        project = ET.parse(VALIDATOR / "OfficeValidation.csproj").getroot()
        values = {name: project.findtext(".//" + name) for name in
                  ("TargetFramework", "OutputType", "ImplicitUsings", "Nullable")}
        if values != {"TargetFramework": "net8.0", "OutputType": "Exe",
                      "ImplicitUsings": "enable", "Nullable": "enable"} or [
                (item.get("Include"), item.get("Version"))
                for item in project.findall(".//PackageReference")] != [("DocumentFormat.OpenXml", "3.3.0")]:
            raise ValueError("The direct build no longer matches the vendored project")
        archive_receipts = []
        for name, package_version, archive_hash, assembly_hash in PACKAGES:
            archive_path = package_cache / f"{name.lower()}.{package_version}.nupkg"
            if sha(archive_path) != archive_hash:
                raise ValueError(f"Unexpected NuGet package bytes: {name}")
            with zipfile.ZipFile(archive_path) as archive:
                (output / f"{name}.dll").write_bytes(archive.read(f"lib/net8.0/{name}.dll"))
            archive_receipts.append({"id": name, "version": package_version,
                                     "nupkgSha256": archive_hash, "assemblySha256": assembly_hash})
        reference_root = sdk.parent.parent / "packs/Microsoft.NETCore.App.Ref"
        versions = [path for path in reference_root.iterdir() if re.fullmatch(r"8\.\d+\.\d+", path.name)]
        framework = max(versions, key=lambda path: tuple(map(int, path.name.split("."))))
        references = sorted((framework / "ref/net8.0").glob("*.dll"))
        if not references:
            raise ValueError("No .NET 8 reference assemblies are available")
        props = sdk / "Sdks/Microsoft.NET.Sdk/targets/Microsoft.NET.Sdk.CSharp.props"
        usings = [item.get("Include") for item in ET.parse(props).getroot().findall(".//{*}Using")]
        if usings != ["System", "System.Collections.Generic", "System.IO", "System.Linq",
                      "System.Net.Http", "System.Threading", "System.Threading.Tasks"]:
            raise ValueError("Unrecognized SDK implicit imports")
        globals_path = output / "ImplicitUsings.g.cs"
        globals_path.write_text("".join(f"global using global::{name};\n" for name in usings))
        response = gate.output / "compile.rsp"
        response.write_text("\n".join([
            "-nologo", "-target:exe", "-langversion:12.0", "-nullable:enable",
            "-deterministic+", "-nostdlib+", f'-out:"{output / "OfficeValidation.dll"}"',
            *(f'-reference:"{path}"' for path in references),
            *(f'-reference:"{output / (name + ".dll")}"' for name, *_ in PACKAGES),
            f'"{VALIDATOR / "Program.cs"}"', f'"{globals_path}"',
        ]) + "\n")
        write_json(output / "OfficeValidation.runtimeconfig.json", {"runtimeOptions": {
            "tfm": "net8.0", "framework": {"name": "Microsoft.NETCore.App", "version": framework.name}}})
        gate.command("validator-build", [dotnet, "exec", str(compiler), "-noconfig", "@" + str(response)])
        reference_hashes = {path.name: sha(path) for path in references}
        receipt.update(mode="direct-sdk-compiler", packages=archive_receipts,
                       referenceAssemblies=reference_hashes, frameworkVersion=framework.name,
                       compilerResponseSha256=sha(response), implicitImportsSha256=sha(globals_path),
                       implicitImportsSdkSourceSha256=sha(props))
    for name, package_version, _, expected_hash in PACKAGES:
        if sha(output / (name + ".dll")) != expected_hash:
            raise ValueError(f"Unexpected resolved validator assembly: {name} {package_version}")
    receipt["artifacts"] = tree_snapshot(output)
    gate.save()
    return output / "OfficeValidation.dll"


def validate_directory(gate: Gate, dotnet: str, validator: Path, directory: Path,
                       name: str, *, require_errors=False) -> dict:
    before = tree_snapshot(directory)
    expected = office_files(directory)
    path = gate.output / (name + ".json")
    result = gate.command(name, [dotnet, str(validator), str(directory), str(path)], allowed=(0, 1))
    if tree_snapshot(directory) != before:
        raise ValueError(f"Validator modified its read-only inputs: {name}")
    report = json.loads(path.read_text())
    receipt = verify_report(report, expected, result.returncode, require_errors=require_errors)
    receipt.update(report=path.name, reportSha256=sha(path), inputsUnchanged=True)
    return receipt


def run_gate(args) -> int:
    output = args.out.resolve()
    if output.exists():
        raise ValueError("Choose a new output directory; schema receipts are never reused")
    output.mkdir(parents=True)
    gate = Gate(output)
    try:
        dart = shutil.which(args.dart)
        dotnet = shutil.which(args.dotnet)
        if not dart or not dotnet:
            raise ValueError("Both Dart and .NET 8 must be available")
        dart, dotnet = str(Path(dart).resolve()), str(Path(dotnet).resolve())
        before = source_snapshot()
        gate.report["source"] = before
        gate.report["scope"] = "Open XML SDK Office2019 schema/semantic validation; no layout or review-rendering claim"
        gate.report["gitHead"] = gate.command("git-head", ["git", "rev-parse", "HEAD"]).stdout.strip()
        status = gate.command("git-status", ["git", "status", "--porcelain"]).stdout
        gate.report["gitWorktreeDirty"] = bool(status.strip())
        gate.report["sourceIdentity"] = ("Uncommitted source state; the recorded file hashes identify this run."
                                          if status.strip() else "Clean worktree at the recorded gitHead, with file hashes retained.")
        dart_version = gate.command("dart-version", [dart, "--version"])
        gate.report["dart"] = {"executableSha256": sha(Path(dart)),
                               "version": (dart_version.stdout + dart_version.stderr).strip()}
        validator = build_validator(gate, dotnet, args.cached_nuget)
        result = gate.command("validator-self-test", [dotnet, str(validator), "--self-test"])
        if SELF_TEST_MARKER not in result.stdout:
            raise ValueError("Validator did not confirm its independent positive and negative controls")
        gate.report["selfTestPassed"] = True
        controls = output / "controls"
        write_controls(controls)
        gate.report["positiveControl"] = validate_directory(gate, dotnet, validator, controls / "positive", "positive-control")
        gate.report["negativeControls"] = validate_directory(gate, dotnet, validator, controls / "negative", "negative-controls", require_errors=True)
        gate.save()
        corpus = output / "corpus"
        gate.command("generate-corpus", [dart, "run", "tool/fidelity/schema_corpus.dart", str(corpus)])
        gate.report["corpus"] = corpus_receipt(corpus)
        gate.save()
        repeated = output / "corpus-repeat"
        gate.command("repeat-corpus", [dart, "run", "tool/fidelity/schema_corpus.dart", str(repeated)])
        repeated_receipt = corpus_receipt(repeated)
        first_files, repeated_files = tree_snapshot(corpus), tree_snapshot(repeated)
        if first_files != repeated_files:
            raise ValueError("Schema corpus generation was not byte-for-byte deterministic")
        gate.report["determinism"] = {"passed": True, "files": len(first_files),
                                       "cases": len(repeated_receipt["cases"]),
                                       "sha256ByRelativePath": first_files}
        gate.save()
        gate.report["validation"] = validate_directory(gate, dotnet, validator, corpus, "schema-validation")
        after = source_snapshot()
        gate.report["sourceAfter"] = after
        if before != after:
            raise ValueError("Parser, generator, or validator sources changed during the gate")
        if tree_snapshot(validator.parent) != gate.report["validatorBuild"]["artifacts"]:
            raise ValueError("Validator build artifacts changed during the gate")
        gate.report["passed"] = True
        gate.save()
        print(f'Open XML SDK gate passed: {len(gate.report["corpus"]["cases"])} DOCX outputs, positive/negative controls, exact hashes, unchanged inputs. {output / "report.json"}')
        return 0
    except Exception as error:
        gate.report["error"] = f"{type(error).__name__}: {error}"
        gate.save()
        print(f'Schema gate failed: {error}. Receipt: {output / "report.json"}', file=sys.stderr)
        return 1


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dart", default="dart")
    parser.add_argument("--dotnet", default="dotnet")
    parser.add_argument("--out", type=Path, default=ROOT / "build/schema-gate")
    parser.add_argument("--cached-nuget", type=Path,
                        help="Offline direct-SDK build from hash-pinned .nupkg archives (for hosts without MSBuild named mutexes)")
    return run_gate(parser.parse_args(argv))


if __name__ == "__main__":
    sys.exit(main())
