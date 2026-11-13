#!/usr/bin/env python3
"""Seal or verify the bb7d98fe portable/schema evidence, without rerunning tools.

The optional repository check verifies every captured tracked input against the
pinned Git commit. All other checks need only this directory and Python 3.
"""

import argparse
import base64
import copy
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile
import xml.etree.ElementTree as ET
import zipfile


COMMIT = "bb7d98fe25cc6e3e69fdad3a2483a6fe08e83dfc"
TREE = "cd8a4dae3208c45f3465be9f71d7cd3c789d1db0"
WORKSPACE = "/workspace/scratch/c1ca2a1344e9"
DART = WORKSPACE + "/toolchains/dart-3.13.7/dart-sdk/bin/dart"
DOTNET = WORKSPACE + "/toolchains/dotnet-8.0.428/dotnet"
CSC = WORKSPACE + "/toolchains/dotnet-8.0.428/sdk/8.0.428/Roslyn/bincore/csc.dll"
SCHEMA_ROOT = WORKSPACE + "/ink-schema-bb7d98"
VALIDATOR = SCHEMA_ROOT + "/validator/OfficeValidation.dll"
ARCHIVE = "validation-artifacts.tar.xz"
MANIFEST = "validation-artifacts.manifest.json"
PORTABLE_STAGES = (
    "dart-version", "format", "analyze", "dart-tests", "corpus-integrity",
    "python-tests", "javascript", "publish-dry-run",
)
SCHEMA_STAGES = (
    "git-head", "git-status", "dart-version", "dotnet-sdks", "compiler-version",
    "dotnet-runtimes", "validator-build", "validator-self-test",
    "positive-control", "negative-controls", "generate-corpus", "repeat-corpus",
    "schema-validation",
)
BINARIES = {
    "DocumentFormat.OpenXml.Framework.dll", "DocumentFormat.OpenXml.dll",
    "OfficeValidation.dll", "System.IO.Packaging.dll",
}
SELF_TEST_MARKER = (
    "Open XML SDK controls passed: 8 valid Word packages, 4 invalid XML, "
    "12 mismatched types, and exact discovery."
)
PORTABLE_COMMANDS = {
    "dart-version": [DART, "--version"],
    "format": [DART, "format", "--output=none", "--set-exit-if-changed", "."],
    "analyze": [DART, "analyze", "--fatal-infos"],
    "dart-tests": [DART, "test", "--reporter=expanded"],
    "corpus-integrity": ["python3", "tool/fidelity/oracle.py"],
    "python-tests": ["python3", "-m", "unittest", "discover", "-s", "tool/fidelity", "-p", "test_*.py"],
    "javascript": ["python3", "tool/verify_web.py", "--dart", DART],
    "publish-dry-run": [DART, "pub", "publish", "--dry-run"],
}
SCHEMA_COMMANDS = {
    "git-head": ["git", "rev-parse", "HEAD"],
    "git-status": ["git", "status", "--porcelain"],
    "dart-version": [DART, "--version"],
    "dotnet-sdks": [DOTNET, "--list-sdks"],
    "compiler-version": [DOTNET, "exec", CSC, "-version"],
    "dotnet-runtimes": [DOTNET, "--list-runtimes"],
    "validator-build": [DOTNET, "exec", CSC, "-noconfig", "@" + SCHEMA_ROOT + "/compile.rsp"],
    "validator-self-test": [DOTNET, VALIDATOR, "--self-test"],
    "positive-control": [DOTNET, VALIDATOR, SCHEMA_ROOT + "/controls/positive", SCHEMA_ROOT + "/positive-control.json"],
    "negative-controls": [DOTNET, VALIDATOR, SCHEMA_ROOT + "/controls/negative", SCHEMA_ROOT + "/negative-controls.json"],
    "generate-corpus": [DART, "run", "tool/fidelity/schema_corpus.dart", SCHEMA_ROOT + "/corpus"],
    "repeat-corpus": [DART, "run", "tool/fidelity/schema_corpus.dart", SCHEMA_ROOT + "/corpus-repeat"],
    "schema-validation": [DOTNET, VALIDATOR, SCHEMA_ROOT + "/corpus", SCHEMA_ROOT + "/schema-validation.json"],
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def record(name, data):
    return {"path": name, "size": len(data), "sha256": digest(data)}


def safe_path(name):
    path = PurePosixPath(name)
    require(not path.is_absolute() and ".." not in path.parts and
            str(path) == name and name not in ("", "."),
            "Unsafe or noncanonical path: " + name)
    return path


def subtree(payloads, prefix):
    return {name[len(prefix):]: digest(data) for name, data in payloads.items()
            if name.startswith(prefix)}


def check_hash_map(value, count, label):
    require(len(value) == count, label + " inventory count")
    for name, sha256 in value.items():
        safe_path(name)
        require(re.fullmatch(r"[0-9a-f]{64}", sha256), label + " invalid SHA256")


def stages(payloads, prefix, values, names, exit_key):
    require(tuple(item["name"] for item in values) == names,
            prefix + " incomplete or reordered stages")
    for item in values:
        name = item["name"]
        require(item[exit_key] == (1 if name == "negative-controls" else 0),
                prefix + " unexpected exit code: " + name)
        if exit_key == "returncode":
            require(item["status"] == "completed", "Incomplete schema stage")
        require(item["log"] == name + ".log", "Unexpected stage log path")
        require(digest(payloads[prefix + "/" + item["log"]]) == item["logSha256"],
                prefix + " stage log hash: " + name)
        expected_commands = PORTABLE_COMMANDS if prefix == "portable" else SCHEMA_COMMANDS
        require(item["command"] == expected_commands[name],
                "Incorrect stage command: " + prefix + "/" + name)


def verify_ink_evidence(payloads):
    log = payloads["portable/javascript.log"].decode()
    expected_js = {
        "Legacy DOC": {"unicode": True, "tables": 1, "images": 1, "headers": 3,
                       "footers": 3, "footnotes": 1, "internalRelationships": True,
                       "sourceUnchanged": True, "oleMetadata": True, "vbaMetadata": True,
                       "signatureValidityClaimed": False},
        "Media": {"checks": 51, "recordCounts": {"emf": 21, "wmf": 17},
                  "emfBytes": 540, "wmfBytes": 230},
        "Ink": {"cases": 24, "strokes": 32, "points": 96},
    }
    for label, expected in expected_js.items():
        prefix = label + " JavaScript acceptance passed: "
        lines = [line[len(prefix):] for line in log.splitlines() if line.startswith(prefix)]
        require(len(lines) == 1 and json.loads(lines[0]) == expected, "JavaScript actual result: " + label)

    root = "decoder-review/"
    receipt = json.loads(payloads[root + "receipt.json"])
    expected_files = {"legacy_word_ink.dart", "decoder-boundary-probe.dart", "decoder-fuzz-review.dart",
                      "decoder-boundary-probe.log", "decoder-fuzz-review.log"}
    require(set(receipt["files"]) == expected_files and set(subtree(payloads, root)) ==
            expected_files | {"receipt.json", "git-commit.raw", "git-tree.raw"}, "Decoder review file inventory")
    for name, item in receipt["files"].items():
        data = payloads[root + name]
        require(item == {"size": len(data), "sha256": digest(data)}, "Decoder review file bytes: " + name)
    require(receipt["sourceCommit"] == "e5afd69c30b2d94995aa367b783ba3d0771e80c2" and
            receipt["sourcePath"] == "lib/src/legacy_word_ink.dart" and receipt["sourceMatchesGit"] is True and
            receipt["sourceUnchanged"] is True and receipt["worktreeStatusBefore"] == receipt["worktreeStatusAfter"] == "",
            "Decoder review source identity/status")
    require(receipt["sourceSha256"] == digest(payloads[root + "legacy_word_ink.dart"]) ==
            digest(payloads["source/lib/src/legacy_word_ink.dart"]), "Reviewed decoder differs from accepted decoder")
    require(receipt["dart"] == DART and receipt["dartSha256"] ==
            json.loads(payloads["schema/report.json"])["dart"]["executableSha256"], "Decoder probe Dart identity")
    commit = payloads[root + "git-commit.raw"]
    tree_oid = commit.splitlines()[0].decode().removeprefix("tree ")
    for kind, oid in (("commit", receipt["sourceCommit"]), ("tree", tree_oid)):
        raw = payloads[root + "git-" + kind + ".raw"]
        require(hashlib.sha1((kind + " " + str(len(raw)) + "\0").encode() + raw).hexdigest() == oid,
                "Decoder probe Git object identity")
    fixtures = {name.removeprefix("source/test/fixtures/ink_wpf/"): digest(data)
                for name, data in payloads.items() if name.startswith("source/test/fixtures/ink_wpf/") and name.endswith(".isf")}
    require(len(fixtures) == 24 and fixtures == receipt["fixtureHashes"] and
            receipt["fixtureRoot"] == WORKSPACE + "/parser-ink-oracle/test/fixtures/ink_wpf", "Decoder review fixture identity")
    require([s["script"] for s in receipt["stages"]] ==
            ["decoder-boundary-probe.dart", "decoder-fuzz-review.dart"], "Decoder probe stage inventory")
    for stage in receipt["stages"]:
        script = stage["script"]
        require(stage["command"] == [DART, WORKSPACE + "/ink-oracle-collection/" + script] and
                stage["cwd"] == WORKSPACE + "/ink-oracle-collection" and stage["exitCode"] == 0 and
                stage["scriptSha256"] == digest(payloads[root + script]) and
                stage["log"] == script.removesuffix(".dart") + ".log" and
                stage["logSha256"] == digest(payloads[root + stage["log"]]), "Decoder probe command/result binding")
    require(json.loads(payloads[root + "decoder-fuzz-review.log"]) == {
        "calls": 23998, "truncationsRejected": 1550, "unknownTailNoPartialStrokes": 24,
        "oneBitMutations": 12400, "randomShortInputs": 10000,
        "counts": {"invalid": 4045, "unsupported": 15829, "decoded": 4060, "limitExceeded": 64},
        "uncaughtExceptions": 0, "sourceMutations": 0}, "Decoder bounded probe result")
    require(payloads[root + "decoder-boundary-probe.log"].decode().splitlines() == [
        "original: decoded, strokes=1, flags=20, width=212.0, reason=null",
        "empty-paint-table: invalid, strokes=0, flags=null, width=null, reason=Empty ISF paint table",
        "empty-paint-block: decoded, strokes=1, flags=0, width=25.0, reason=null",
        "no-paint-table: decoded, strokes=1, flags=16, width=53.0, reason=null",
        "empty-descriptor-table: invalid, strokes=0, flags=null, width=null, reason=Empty ISF packet descriptor table",
    ], "Decoder boundary results")

    # The preliminary attempt was blocked before package validation by a missing
    # temporary directory. It is distinct from the later clean full acceptance.
    diagnostic = "diagnostic/"
    prepared_prefix = diagnostic + "ink-schema-prepared/"
    prepared = {name: data for name, data in payloads.items() if name.startswith(prepared_prefix)}
    require(len(prepared) == 25, "Preliminary schema corpus inventory")
    for filename, failures in (("ink-schema-prepared-report.json", 12),
                               ("ink-schema-prepared-validated.json", 0)):
        result = json.loads(payloads[diagnostic + filename])
        require(result["Files"] == len(result["Reports"]) == 12 and result["Failures"] == failures,
                "Preliminary schema result count")
        seen = set()
        for item in result["Reports"]:
            relative = PurePosixPath(item["File"]).name
            require(item["File"] == WORKSPACE + "/root-gap-probes/ink-schema-prepared/" + relative and
                    relative not in seen and relative.endswith(".docx") and
                    item["Sha256"] == digest(prepared[prepared_prefix + relative]), "Preliminary schema input binding")
            seen.add(relative)
            if failures:
                require("System.IO.DirectoryNotFoundException" in item["Exception"] and
                        "Could not find a part of the path '/tmp/'" in item["Exception"] and
                        "Errors" not in item, "Original temporary-directory rejection")
            else:
                require(item["Errors"] == [] and "Exception" not in item, "Corrected preliminary SDK validation")
        require(seen == {PurePosixPath(name).name for name in prepared if name.endswith(".docx")},
                "Preliminary schema coverage")
    require(set(subtree(payloads, diagnostic)) ==
            {"ink-schema-prepared/" + PurePosixPath(name).name for name in prepared} |
            {"ink-schema-prepared-report.json", "ink-schema-prepared-validated.json"}, "Diagnostic artifact inventory")

    for prefix in (prepared_prefix, "schema/corpus/ink-strokes/"):
        cases = json.loads(payloads[prefix + "ink-cases.json"])
        require(len(cases) == len({case["name"] for case in cases}) == 12, "Nonempty ink case inventory")
        for case in cases:
            name, mode = case["name"].rsplit("-", 1)
            require(mode in ("compressed", "uncompressed"), "Ink fixture compression mode")
            fixture = "source/test/fixtures/ink_wpf/" + name + "/" + mode
            raw = payloads[fixture + ".isf"]
            oracle = json.loads(payloads[fixture + ".reloaded.json"])
            strokes = oracle["strokeCount"]
            points = sum(len(s["points"]) for s in oracle["strokes"])
            require(case["strokeCount"] == strokes > 0 and case["pointCount"] == points > 0 and
                    base64.b64decode(case["sourceIsfBase64"], validate=True) == raw and
                    case["preservedCounts"]["inkPayloads"] == case["preservedCounts"]["decodedInkPayloads"] == 1 and
                    case["preservedCounts"]["decodedInkStrokes"] == strokes and case["nativeInkEmitted"] is False,
                    "Nonempty ink WPF attribution")
            with zipfile.ZipFile(io.BytesIO(payloads[prefix + case["name"] + ".docx"])) as package:
                evidence = json.loads(package.read("word/evidence/manifest.json"))
                ink = [item for item in evidence["records"] if item["kind"] == "officeArtInk"]
                require(len(ink) == 1 and ink[0]["strokeDecodeStatus"] == "decoded" and
                        ink[0]["strokeSemanticsDecoded"] is True and ink[0]["strokeCount"] == strokes and
                        ink[0]["pointCount"] == points and ink[0]["nativeInkEmitted"] is False and
                        package.read(ink[0]["part"]) == raw, "DOCX ink evidence/payload binding")
                require(not any(element.tag.rsplit("}", 1)[-1] == "ink" for element in
                        ET.fromstring(package.read("word/document.xml")).iter()), "Unclaimed native ink emitted")


def sdk_report(payloads, schema, key, filename, expected, failures):
    summary = schema[key]
    require(summary["hashesVerified"] and summary["inputsUnchanged"],
            key + " input verification")
    require(summary["files"] == len(expected) and summary["errors"] == failures,
            key + " result count")
    require(summary["report"] == filename, key + " report name")
    data = payloads["schema/" + filename]
    require(digest(data) == summary["reportSha256"], key + " report hash")
    result = json.loads(data)
    require(result["Files"] == len(result["Reports"]) == len(expected) and
            result["Failures"] == failures, key + " SDK count")
    seen = set()
    for item in result["Reports"]:
        original = item["File"]
        require(original in expected and original not in seen,
                key + " unexpected or duplicate SDK input: " + original)
        seen.add(original)
        archive_path = expected[original]
        require(item["Sha256"] == digest(payloads[archive_path]),
                key + " SDK input hash: " + archive_path)
        require("Exception" not in item, key + " SDK exception")
        if failures:
            required_error = {
                "invalid-child.docx": "Sch_InvalidElementContentExpectingComplex",
                "invalid-nowrap.docx": "Sch_AttributeValueDataTypeDetailed",
            }[PurePosixPath(archive_path).name]
            require(len(item["Errors"]) == 1 and
                    item["Errors"][0]["Id"] == required_error and
                    item["Errors"][0]["Type"] == "Schema",
                    key + " expected malformed-input error absent")
        else:
            require(item["Errors"] == [], key + " SDK validation error")
    require(seen == set(expected), key + " incomplete SDK input coverage")


def verify_payloads(manifest, payloads):
    require(manifest["version"] == 2 and manifest["parserCommit"] == COMMIT and
            manifest["parserTree"] == TREE, "Evidence source identity")
    verify_ink_evidence(payloads)
    portable = json.loads(payloads["portable/receipt.json"])
    schema = json.loads(payloads["schema/report.json"])
    require(portable["commit"] == schema["gitHead"] == COMMIT and
            portable["tree"] == TREE, "Gate source identity")
    require(portable["success"] and portable["inputsUnchanged"] and
            portable["inputsBefore"] == portable["inputsAfter"] and
            portable["dirtyBefore"] == portable["dirtyAfter"] == "",
            "Portable source changed or gate failed")
    check_hash_map(portable["inputsBefore"], 1069, "Portable source")
    stages(payloads, "portable", portable["stages"], PORTABLE_STAGES, "exitCode")
    require(set(subtree(payloads, "portable/")) ==
            {"receipt.json", *(name + ".log" for name in PORTABLE_STAGES)},
            "Portable artifact inventory")
    for filename, marker in {
        "format.log": "Formatted 202 files (0 changed)",
        "analyze.log": "No issues found!",
        "dart-tests.log": "+992: All tests passed!",
        "python-tests.log": "Ran 162 tests",
        "corpus-integrity.log": "Verified 24 source hashes and OOXML package graphs",
        "javascript.log": 'Media JavaScript acceptance passed: {"checks":51,',
        "publish-dry-run.log": "Package has 0 warnings.",
    }.items():
        require(marker in payloads["portable/" + filename].decode(),
                "Portable result marker: " + filename)
    require("Legacy DOC JavaScript acceptance passed:" in
            payloads["portable/javascript.log"].decode(), "DOC JavaScript result")

    require(schema["passed"] and schema["selfTestPassed"] and
            not schema["gitWorktreeDirty"] and schema["source"] == schema["sourceAfter"],
            "Schema gate/source integrity")
    source = schema["source"]["files"]
    check_hash_map(source, 262, "Schema source")
    require(digest(json.dumps(source, sort_keys=True, separators=(",", ":")).encode())
            == schema["source"]["aggregateSha256"], "Schema source aggregate hash")
    require(subtree(payloads, "source/") == source, "Retained schema source bytes")
    require(all(portable["inputsBefore"].get(name) == sha256
                for name, sha256 in source.items()), "Portable/schema source mismatch")
    stages(payloads, "schema", schema["stages"], SCHEMA_STAGES, "returncode")
    require(payloads["schema/git-head.log"].decode().strip() == COMMIT and
            payloads["schema/git-status.log"] == b"", "Schema Git logs")
    require(payloads["schema/dart-version.log"] == payloads["portable/dart-version.log"]
            and payloads["schema/dart-version.log"].decode().strip() == schema["dart"]["version"],
            "Dart version receipts disagree")
    require(SELF_TEST_MARKER in payloads["schema/validator-self-test.log"].decode(),
            "Validator self-test marker absent")
    for name in ("generate-corpus", "repeat-corpus"):
        require(payloads["schema/" + name + ".log"] ==
                b"Generated 242 deterministic schema cases.\n", "Corpus generation log")

    deterministic = schema["determinism"]
    require(deterministic["passed"] and deterministic["cases"] == 242 and
            deterministic["files"] == 513, "Determinism receipt")
    hashes = deterministic["sha256ByRelativePath"]
    check_hash_map(hashes, 513, "Generated corpus")
    for prefix in ("schema/corpus/", "schema/corpus-repeat/"):
        require(subtree(payloads, prefix) == hashes,
                "Full generated corpus inventory/bytes differ: " + prefix)
    require(all(payloads["schema/corpus/" + name] ==
                payloads["schema/corpus-repeat/" + name] for name in hashes),
            "Repeated corpus bytes differ")
    cases = schema["corpus"]["cases"]
    require(len(cases) == len({item["name"] for item in cases}) == 242,
            "Schema case inventory")
    case_outputs = {item["output"]: item["outputSha256"] for item in cases}
    require(case_outputs == {name: sha256 for name, sha256 in hashes.items()
                             if name.endswith(".docx")}, "Case/output coverage")
    for item in cases:
        require(item["producer"] in source, "Uncaptured case producer")
        require(hashes[item["source"]] == item["sourceSha256"], "Case source hash")
        if item["producer"].endswith(".doc"):
            require(source[item["producer"]] == item["sourceSha256"],
                    "Native input copy differs from captured source")
    # Original absolute paths remain in the original reports; resolve only below
    # the unique corpus directory recorded by the generation stage.
    generate = next(item for item in schema["stages"] if item["name"] == "generate-corpus")
    corpus_root = generate["command"][-1].rstrip("/")
    require(corpus_root.endswith("/corpus"), "Unexpected original corpus root")
    expected_outputs = {corpus_root + "/" + name: sha256
                        for name, sha256 in case_outputs.items()}
    require(schema["corpus"]["outputs"] == expected_outputs, "Absolute SDK output inventory")
    sdk_report(payloads, schema, "validation", "schema-validation.json",
               {path: "schema/corpus/" + path[len(corpus_root) + 1:]
                for path in expected_outputs}, 0)
    original_root = corpus_root.rsplit("/", 1)[0]
    controls = {
        "positiveControl": ("positive-control.json", ["positive/valid.docx"], 0),
        "negativeControls": ("negative-controls.json",
                             ["negative/invalid-child.docx", "negative/invalid-nowrap.docx"], 2),
    }
    require(set(subtree(payloads, "schema/controls/")) ==
            {name for _, names, _ in controls.values() for name in names},
            "Control package inventory")
    for key, (filename, names, failures) in controls.items():
        sdk_report(payloads, schema, key, filename,
                   {original_root + "/controls/" + name: "schema/controls/" + name
                    for name in names}, failures)

    build = schema["validatorBuild"]
    require(build["mode"] == "direct-sdk-compiler" and build["sdkVersion"] == "8.0.428"
            and build["frameworkVersion"] == "8.0.34", "Validator SDK/framework version")
    require(payloads["schema/compiler-version.log"].decode().strip() == build["compilerVersion"],
            "Compiler version log")
    require(payloads["schema/dotnet-runtimes.log"].decode().strip() == build["installedRuntimes"],
            "Runtime version log")
    require(payloads["schema/dotnet-sdks.log"].decode().startswith("8.0.428 ["), "SDK version log")
    require(digest(payloads["schema/compile.rsp"]) == build["compilerResponseSha256"],
            "Compiler response hash")
    omitted = {item["path"]: item for item in manifest["omittedReproducibleBinaries"]}
    require(len(omitted) == len(manifest["omittedReproducibleBinaries"]) == 4 and
            set(omitted) == {"schema/validator/" + name for name in BINARIES},
            "Omitted binary inventory")
    require(set(build["artifacts"]) == BINARIES |
            {"ImplicitUsings.g.cs", "OfficeValidation.runtimeconfig.json"}, "Build artifact inventory")
    require(set(subtree(payloads, "schema/validator/")) ==
            {"ImplicitUsings.g.cs", "OfficeValidation.runtimeconfig.json"}, "Retained build artifact inventory")
    for name, sha256 in build["artifacts"].items():
        path = "schema/validator/" + name
        actual = omitted[path]["sha256"] if name in BINARIES else digest(payloads[path])
        require(actual == sha256, "Build artifact hash: " + name)
    require(digest(payloads["schema/validator/ImplicitUsings.g.cs"]) == build["implicitImportsSha256"],
            "Implicit imports hash")
    upstream = json.loads(payloads["source/tool/office-validation/upstream.json"])
    require(upstream == build["upstream"] and upstream["sdkPackage"] ==
            {"id": "DocumentFormat.OpenXml", "version": "3.3.0"} and
            upstream["validationVersion"] == "Office2019", "Validator upstream receipt")
    for name, item in upstream["files"].items():
        require(digest(payloads["source/tool/office-validation/" + name]) == item["sha256"],
                "Validator upstream source hash: " + name)
    recovered = json.loads(payloads["toolchains/nuget-recovery.json"])
    packages = {item["id"]: item for item in build["packages"]}
    require({item["name"] for item in recovered} == set(packages) ==
            {"DocumentFormat.OpenXml", "DocumentFormat.OpenXml.Framework", "System.IO.Packaging"},
            "NuGet package inventory")
    for item in recovered:
        package = packages[item["name"]]
        require(item["version"] == package["version"] and item["sha256"] == package["nupkgSha256"]
                and package["assemblySha256"] == build["artifacts"][item["name"] + ".dll"],
                "NuGet recovery/build hash: " + item["name"])
    require(json.loads(payloads["toolchains/dotnet-recovery.json"])["sdk"] == build["sdkVersion"],
            ".NET recovery version")
    dart_recovery = json.loads(payloads["toolchains/dart-recovery.json"])
    require(dart_recovery["matchesRetainedBinary"] and
            dart_recovery["binarySha256"] == schema["dart"]["executableSha256"], "Dart recovery hash")
    for kind, oid in (("commit", COMMIT), ("tree", TREE)):
        data = payloads["source-identity/git-" + kind + ".raw"]
        require(hashlib.sha1((kind + " " + str(len(data)) + "\0").encode() + data).hexdigest() == oid,
                "Git " + kind + " object identity")
    require(payloads["source-identity/git-commit.raw"].splitlines()[0] == ("tree " + TREE).encode(),
            "Git commit/tree linkage")
    return {"verified": True, "parserCommit": COMMIT, "parserTree": TREE,
            "portableStages": 8, "dartTests": 992, "pythonControls": 162,
            "capturedPortableInputs": 1069, "retainedSchemaSources": 262,
            "schemaStages": 13, "schemaOutputs": 242, "schemaErrors": 0,
            "corpusFilesPerRun": 513, "corpusRuns": 2, "negativeControlsRejected": 2,
            "files": len(payloads), "archiveBytes": manifest["archive"]["size"],
            "archiveSha256": manifest["archive"]["sha256"]}


def verify_repository(repository, payloads, commit=COMMIT, tree=TREE, prefix="portable/"):
    def git(*args, **kwargs):
        return subprocess.check_output(["git", "-C", str(repository), *args], **kwargs)
    require(git("rev-parse", commit + "^{tree}").decode().strip() == tree, "Pinned Git tree")
    entries = {}
    for entry in git("ls-tree", "-r", "-z", commit).split(b"\0"):
        if not entry:
            continue
        header, name = entry.split(b"\t", 1)
        mode, kind, oid = header.split()
        require(kind == b"blob" and mode in (b"100644", b"100755"), "Unexpected source Git entry")
        entries[name.decode()] = oid.decode()
    source = json.loads(payloads[prefix + "receipt.json"])["inputsBefore"]
    require(set(source) - set(entries) == {"pubspec.lock", ".dart_tool/package_config.json"}
            and len(entries) == 1067 and set(entries) <= set(source), "Full tracked source coverage")
    names = sorted(entries)
    stream = io.BytesIO(git("cat-file", "--batch", input="".join(entries[name] + "\n" for name in names).encode()))
    for name in names:
        oid, kind, size = stream.readline().split()
        require(oid.decode() == entries[name] and kind == b"blob", "Git batch object identity")
        require(digest(stream.read(int(size))) == source[name], "Pinned source SHA256: " + name)
        require(stream.read(1) == b"\n", "Git batch framing")
    require(stream.read() == b"", "Unexpected Git batch data")
    probe = json.loads(payloads["decoder-review/receipt.json"])
    require(git("show", probe["sourceCommit"] + ":" + probe["sourcePath"]) ==
            payloads["decoder-review/legacy_word_ink.dart"], "Decoder review source differs from recorded Git commit")
    return 1067


def load_archive(directory):
    manifest = json.loads((directory / MANIFEST).read_bytes())
    require(manifest["archive"]["path"] == ARCHIVE, "Unexpected archive path")
    data = (directory / ARCHIVE).read_bytes()
    require(len(data) == manifest["archive"]["size"] and
            digest(data) == manifest["archive"]["sha256"], "Archive size/SHA256")
    expected = {item["path"]: item for item in manifest["files"]}
    require(len(expected) == len(manifest["files"]), "Duplicate manifest file")
    payloads = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:xz") as packed:
        for member in packed:
            safe_path(member.name)
            require(member.isfile() and member.name in expected and member.name not in payloads,
                    "Unexpected/duplicate/nonregular archive member")
            content = packed.extractfile(member).read()
            require(record(member.name, content) == expected[member.name] and len(content) == member.size,
                    "Archive member size/hash: " + member.name)
            payloads[member.name] = content
    require(set(payloads) == set(expected), "Incomplete archive inventory")
    require(digest((directory / "seal_validation_evidence.py").read_bytes()) ==
            manifest["verifierSha256"], "Verifier source hash")
    return manifest, payloads


def self_test(manifest, payloads):
    """Reject targeted receipt/corpus corruption after the archive has been read."""
    def change_json(data, name, mutation):
        value = json.loads(data[name])
        mutation(value)
        data[name] = json_bytes(value)

    def remove_repeat_source(data, _):
        name = next(name for name in data if name.startswith("schema/corpus-repeat/") and name.endswith(".doc"))
        del data[name]

    def alter_case_source(data, _):
        name = next(name for name in data if name.startswith("schema/corpus/") and name.endswith(".doc"))
        data[name] += b"changed"
        data[name.replace("/corpus/", "/corpus-repeat/")] = data[name]

    def omit_stage(data, _):
        change_json(data, "schema/report.json", lambda value: value["stages"].pop())

    def accepted_negative(data, _):
        def accept(value):
            value["Failures"] = 0
            value["Reports"][0]["Errors"] = []
        change_json(data, "schema/negative-controls.json", accept)
        change_json(data, "schema/report.json", lambda value: value["negativeControls"].update(
            reportSha256=digest(data["schema/negative-controls.json"])))

    def invalid_sdk_hash(data, _):
        change_json(data, "schema/schema-validation.json", lambda value: value["Reports"][0].update(Sha256="0" * 64))
        change_json(data, "schema/report.json", lambda value: value["validation"].update(
            reportSha256=digest(data["schema/schema-validation.json"])))

    def changed_source(data, _):
        data["source/lib/legacy_doc_parser.dart"] += b"changed"

    def changed_after(data, _):
        change_json(data, "portable/receipt.json", lambda value: value["inputsAfter"].update({"pubspec.lock": "0" * 64}))

    def changed_binary(_, value):
        value["omittedReproducibleBinaries"][0]["sha256"] = "0" * 64

    def changed_log(data, _):
        data["schema/validator-build.log"] += b"changed"

    checks = [remove_repeat_source, alter_case_source, omit_stage, accepted_negative,
              invalid_sdk_hash, changed_source, changed_after, changed_binary, changed_log]
    for prefix, report, expected in (("portable/", "receipt.json", PORTABLE_STAGES),
                                     ("schema/", "report.json", SCHEMA_STAGES)):
        for index, name in enumerate(expected):
            def wrong_command(data, _, filename=prefix + report, index=index):
                change_json(data, filename, lambda value: value["stages"][index].update(command=["true"]))
            wrong_command.__name__ = "wrong_command_" + prefix.replace("/", "_") + name
            checks.append(wrong_command)
    def wrong_ink_js(data, _):
        data["portable/javascript.log"] = data["portable/javascript.log"].replace(b'"cases":24', b'"cases":0')
        change_json(data, "portable/receipt.json", lambda value: next(
            stage for stage in value["stages"] if stage["name"] == "javascript").update(
            logSha256=digest(data["portable/javascript.log"])))

    def wrong_review_command(data, _):
        change_json(data, "decoder-review/receipt.json", lambda value: value["stages"][0].update(command=["true"]))

    def wrong_review_source(data, _):
        change_json(data, "decoder-review/receipt.json", lambda value: value.update(sourceUnchanged=False))

    def wrong_review_result(data, _):
        name = "decoder-fuzz-review.log"
        change_json(data, "decoder-review/" + name, lambda value: value.update(sourceMutations=1))
        def update(value):
            raw = data["decoder-review/" + name]
            value["files"][name] = {"size": len(raw), "sha256": digest(raw)}
            value["stages"][1]["logSha256"] = digest(raw)
        change_json(data, "decoder-review/receipt.json", update)

    def erased_setup_failure(data, _):
        change_json(data, "diagnostic/ink-schema-prepared-report.json", lambda value: value.update(Failures=0))

    def false_corrected_success(data, _):
        change_json(data, "diagnostic/ink-schema-prepared-validated.json", lambda value:
                    value["Reports"][0].update(Errors=[{"Id": "unreported-error"}]))

    def empty_schema_ink(data, _):
        change_json(data, "schema/corpus/ink-strokes/ink-cases.json", lambda value: value[0].update(strokeCount=0))

    def fabricated_native_ink(data, _):
        change_json(data, "schema/corpus/ink-strokes/ink-cases.json", lambda value: value[0].update(nativeInkEmitted=True))

    checks.extend((wrong_ink_js, wrong_review_command, wrong_review_source, wrong_review_result,
                   erased_setup_failure, false_corrected_success, empty_schema_ink, fabricated_native_ink))
    for check in checks:
        data, value = dict(payloads), copy.deepcopy(manifest)
        check(data, value)
        try:
            verify_payloads(value, data)
        except (ValueError, KeyError):
            continue
        raise ValueError("Corruption control was accepted: " + check.__name__)
    return len(checks)


def seal(directory, portable_root, schema_root, repository, toolchains, diagnostic_root, decoder_root):
    require(not (directory / ARCHIVE).exists() and not (directory / MANIFEST).exists(),
            "Refusing to replace an existing sealed archive")
    payloads, omitted = {}, []
    for root, prefix in ((portable_root, "portable"), (schema_root, "schema"),
                         (decoder_root, "decoder-review")):
        for path in sorted(root.rglob("*")):
            require(not path.is_symlink(), "Unexpected symlink in gate artifacts")
            if not path.is_file():
                continue
            name = prefix + "/" + path.relative_to(root).as_posix()
            data = path.read_bytes()
            if prefix == "schema" and path.relative_to(root).parts[0] == "validator" and path.name in BINARIES:
                omitted.append(record(name, data))
            else:
                require(path.relative_to(root).parts[0] not in ("tmp", "dotnet-home", ".dotnet"),
                        "Unexpected incidental cache; review before sealing: " + str(path))
                payloads[name] = data
    for filename in ("ink-schema-prepared-report.json", "ink-schema-prepared-validated.json"):
        path = diagnostic_root / filename
        require(not path.is_symlink(), "Diagnostic report symlink")
        payloads["diagnostic/" + filename] = path.read_bytes()
    for path in sorted((diagnostic_root / "ink-schema-prepared").rglob("*")):
        require(not path.is_symlink(), "Diagnostic package symlink")
        if path.is_file():
            payloads["diagnostic/" + path.relative_to(diagnostic_root).as_posix()] = path.read_bytes()
    schema = json.loads(payloads["schema/report.json"])
    for name, sha256 in schema["source"]["files"].items():
        safe_path(name)
        data = (repository / name).read_bytes()
        require(digest(data) == sha256, "Current source differs from receipt: " + name)
        payloads["source/" + name] = data
    for kind, oid in (("commit", COMMIT), ("tree", TREE)):
        payloads["source-identity/git-" + kind + ".raw"] = subprocess.check_output(
            ["git", "-C", str(repository), "cat-file", kind, oid])
    probe_commit = json.loads(payloads["decoder-review/receipt.json"])["sourceCommit"]
    probe_tree = subprocess.check_output(["git", "-C", str(repository), "rev-parse", probe_commit + "^{tree}"]).decode().strip()
    for kind, oid in (("commit", probe_commit), ("tree", probe_tree)):
        payloads["decoder-review/git-" + kind + ".raw"] = subprocess.check_output(
            ["git", "-C", str(repository), "cat-file", kind, oid])
    for name, source in (("dart-recovery.json", "recovery-20261113/dart-recovery.json"),
                         ("dotnet-recovery.json", "dotnet-recovery.json"),
                         ("nuget-recovery.json", "nuget/recovery.json")):
        payloads["toolchains/" + name] = (toolchains / source).read_bytes()
    verify_repository(repository, payloads)
    archive = directory / ARCHIVE
    with tarfile.open(archive, "w:xz", preset=6) as packed:
        for name, data in sorted(payloads.items()):
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = len(data), 0o644, 0
            packed.addfile(info, io.BytesIO(data))
    manifest = {
        "version": 2, "parserCommit": COMMIT, "parserTree": TREE,
        "archive": record(ARCHIVE, archive.read_bytes()),
        "files": [record(name, data) for name, data in sorted(payloads.items())],
        "omittedReproducibleBinaries": omitted,
        "verifierSha256": digest((directory / "seal_validation_evidence.py").read_bytes()),
        "scope": "Portable gates and Office2019 Open XML SDK schema/semantic validation. Complete logs, source receipts, 262 schema sources including independent WPF fixtures, both full 513-file corpora, controls, build configuration and recovery receipts. Independent bounded decoder probes and the distinct preliminary temporary-directory rejection/correction are retained. Four reproducible validator DLLs omitted with hashes. No native rendering, Word ink placement or editing claim.",
    }
    (directory / MANIFEST).write_bytes(json_bytes(manifest))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--seal-portable", type=Path)
    parser.add_argument("--seal-schema", type=Path)
    parser.add_argument("--repository", type=Path)
    parser.add_argument("--toolchains", type=Path)
    parser.add_argument("--seal-diagnostic", type=Path)
    parser.add_argument("--seal-decoder-review", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.seal_portable:
        require(args.seal_schema and args.repository and args.toolchains and args.seal_diagnostic and args.seal_decoder_review,
                "Sealing requires both gate directories, repository and toolchains")
        seal(args.directory, args.seal_portable, args.seal_schema, args.repository, args.toolchains, args.seal_diagnostic, args.seal_decoder_review)
    manifest, payloads = load_archive(args.directory)
    result = verify_payloads(manifest, payloads)
    if args.repository:
        result["trackedGitInputsVerified"] = verify_repository(args.repository, payloads)
    if args.self_test:
        result["corruptionControlsRejected"] = self_test(manifest, payloads)
    print(json.dumps(result, sort_keys=True))
