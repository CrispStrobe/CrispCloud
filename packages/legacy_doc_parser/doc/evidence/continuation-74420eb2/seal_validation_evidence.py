#!/usr/bin/env python3
"""Seal or verify the 74420eb2 portable/schema evidence, without rerunning tools.

The optional repository check verifies every captured tracked input against the
pinned Git commit. All other checks need only this directory and Python 3.
"""

import argparse
import copy
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile


COMMIT = "74420eb2e0ec14401a0db5bcbb30ab6d202a2340"
TREE = "ac78b144d90bca0f44993d94ae0fd1c8115ce072"
FAILED_COMMIT = "f255c9da9baed1fdd6034818b1c97069d44589d4"
FAILED_TREE = "ed79243acead0cc5bc2de9aa1b203aef8fa22089"
WORKSPACE = "/workspace/scratch/c1ca2a1344e9"
DART = WORKSPACE + "/toolchains/dart-3.13.7/dart-sdk/bin/dart"
DOTNET = WORKSPACE + "/toolchains/dotnet-8.0.428/dotnet"
CSC = WORKSPACE + "/toolchains/dotnet-8.0.428/sdk/8.0.428/Roslyn/bincore/csc.dll"
SCHEMA_ROOT = WORKSPACE + "/parser-schema-74420eb"
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


def verify_diagnostic(payloads):
    prefix = "diagnostic/pre-format/"
    require(set(subtree(payloads, prefix)) ==
            {"receipt.json", "dart-version.log", "format.log", "git-commit.raw", "git-tree.raw"},
            "Original failed-gate artifact inventory")
    failed = json.loads(payloads[prefix + "receipt.json"])
    require(failed["commit"] == FAILED_COMMIT and failed["tree"] == FAILED_TREE and
            failed["success"] is False and failed["inputsUnchanged"] is True and
            failed["inputsBefore"] == failed["inputsAfter"] and
            failed["dirtyBefore"] == failed["dirtyAfter"] == "",
            "Original format rejection source/status changed")
    check_hash_map(failed["inputsBefore"], 950, "Original rejected source")
    require([stage["name"] for stage in failed["stages"]] == ["dart-version", "format"],
            "Original rejection stage inventory")
    for stage, code in zip(failed["stages"], [0, 1], strict=True):
        name = stage["name"]
        require(stage["command"] == PORTABLE_COMMANDS[name] and stage["exitCode"] == code and
                stage["log"] == name + ".log" and
                digest(payloads[prefix + name + ".log"]) == stage["logSha256"],
                "Original rejection stage differs: " + name)
    require(payloads[prefix + "dart-version.log"] == payloads["portable/dart-version.log"] and
            "Changed doc/evidence/textbox-next-20261113/source_inspect.dart\nFormatted 198 files (1 changed)" in
            payloads[prefix + "format.log"].decode(), "Original rejected format result")
    for kind, oid in (("commit", FAILED_COMMIT), ("tree", FAILED_TREE)):
        data = payloads[prefix + "git-" + kind + ".raw"]
        require(hashlib.sha1((kind + " " + str(len(data)) + "\0").encode() + data).hexdigest() == oid,
                "Original rejection Git " + kind + " identity")
    require(payloads[prefix + "git-commit.raw"].splitlines()[0] == ("tree " + FAILED_TREE).encode(),
            "Original rejection commit/tree linkage")


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
    verify_diagnostic(payloads)
    portable = json.loads(payloads["portable/receipt.json"])
    schema = json.loads(payloads["schema/report.json"])
    require(portable["commit"] == schema["gitHead"] == COMMIT and
            portable["tree"] == TREE, "Gate source identity")
    require(portable["success"] and portable["inputsUnchanged"] and
            portable["inputsBefore"] == portable["inputsAfter"] and
            portable["dirtyBefore"] == portable["dirtyAfter"] == "",
            "Portable source changed or gate failed")
    check_hash_map(portable["inputsBefore"], 950, "Portable source")
    stages(payloads, "portable", portable["stages"], PORTABLE_STAGES, "exitCode")
    require(set(subtree(payloads, "portable/")) ==
            {"receipt.json", *(name + ".log" for name in PORTABLE_STAGES)},
            "Portable artifact inventory")
    for filename, marker in {
        "format.log": "Formatted 198 files (0 changed)",
        "analyze.log": "No issues found!",
        "dart-tests.log": "+954: All tests passed!",
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
    check_hash_map(source, 168, "Schema source")
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
                b"Generated 230 deterministic schema cases.\n", "Corpus generation log")

    deterministic = schema["determinism"]
    require(deterministic["passed"] and deterministic["cases"] == 230 and
            deterministic["files"] == 488, "Determinism receipt")
    hashes = deterministic["sha256ByRelativePath"]
    check_hash_map(hashes, 488, "Generated corpus")
    for prefix in ("schema/corpus/", "schema/corpus-repeat/"):
        require(subtree(payloads, prefix) == hashes,
                "Full generated corpus inventory/bytes differ: " + prefix)
    require(all(payloads["schema/corpus/" + name] ==
                payloads["schema/corpus-repeat/" + name] for name in hashes),
            "Repeated corpus bytes differ")
    cases = schema["corpus"]["cases"]
    require(len(cases) == len({item["name"] for item in cases}) == 230,
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
            "portableStages": 8, "dartTests": 954, "pythonControls": 162,
            "capturedPortableInputs": 950, "retainedSchemaSources": 168,
            "schemaStages": 13, "schemaOutputs": 230, "schemaErrors": 0,
            "corpusFilesPerRun": 488, "corpusRuns": 2, "negativeControlsRejected": 2,
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
            and len(entries) == 948 and set(entries) <= set(source), "Full tracked source coverage")
    names = sorted(entries)
    stream = io.BytesIO(git("cat-file", "--batch", input="".join(entries[name] + "\n" for name in names).encode()))
    for name in names:
        oid, kind, size = stream.readline().split()
        require(oid.decode() == entries[name] and kind == b"blob", "Git batch object identity")
        require(digest(stream.read(int(size))) == source[name], "Pinned source SHA256: " + name)
        require(stream.read(1) == b"\n", "Git batch framing")
    require(stream.read() == b"", "Unexpected Git batch data")
    return 948


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
                                     ("schema/", "report.json", SCHEMA_STAGES),
                                     ("diagnostic/pre-format/", "receipt.json", ("dart-version", "format"))):
        for index, name in enumerate(expected):
            def wrong_command(data, _, filename=prefix + report, index=index):
                change_json(data, filename, lambda value: value["stages"][index].update(command=["true"]))
            wrong_command.__name__ = "wrong_command_" + prefix.replace("/", "_") + name
            checks.append(wrong_command)
    def erase_rejection(data, _):
        change_json(data, "diagnostic/pre-format/receipt.json", lambda value: value.update(success=True))
    checks.append(erase_rejection)
    for check in checks:
        data, value = dict(payloads), copy.deepcopy(manifest)
        check(data, value)
        try:
            verify_payloads(value, data)
        except (ValueError, KeyError):
            continue
        raise ValueError("Corruption control was accepted: " + check.__name__)
    return len(checks)


def seal(directory, portable_root, schema_root, repository, toolchains, diagnostic_root):
    require(not (directory / ARCHIVE).exists() and not (directory / MANIFEST).exists(),
            "Refusing to replace an existing sealed archive")
    payloads, omitted = {}, []
    for root, prefix in ((portable_root, "portable"), (schema_root, "schema"),
                         (diagnostic_root, "diagnostic/pre-format")):
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
    schema = json.loads(payloads["schema/report.json"])
    for name, sha256 in schema["source"]["files"].items():
        safe_path(name)
        data = (repository / name).read_bytes()
        require(digest(data) == sha256, "Current source differs from receipt: " + name)
        payloads["source/" + name] = data
    for kind, oid in (("commit", COMMIT), ("tree", TREE)):
        payloads["source-identity/git-" + kind + ".raw"] = subprocess.check_output(
            ["git", "-C", str(repository), "cat-file", kind, oid])
    for kind, oid in (("commit", FAILED_COMMIT), ("tree", FAILED_TREE)):
        payloads["diagnostic/pre-format/git-" + kind + ".raw"] = subprocess.check_output(
            ["git", "-C", str(repository), "cat-file", kind, oid])
    for name, source in (("dart-recovery.json", "recovery-20261113/dart-recovery.json"),
                         ("dotnet-recovery.json", "dotnet-recovery.json"),
                         ("nuget-recovery.json", "nuget/recovery.json")):
        payloads["toolchains/" + name] = (toolchains / source).read_bytes()
    verify_repository(repository, payloads)
    verify_repository(repository, payloads, FAILED_COMMIT, FAILED_TREE, "diagnostic/pre-format/")
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
        "scope": "Portable gates and Office2019 Open XML SDK schema/semantic validation. Complete logs, source receipts, 168 schema sources, both full 488-file corpora, controls, build configuration and recovery receipts. Four reproducible validator DLLs omitted with hashes. No native rendering, review rendering or layout-fidelity claim.",
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
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.seal_portable:
        require(args.seal_schema and args.repository and args.toolchains and args.seal_diagnostic,
                "Sealing requires both gate directories, repository and toolchains")
        seal(args.directory, args.seal_portable, args.seal_schema, args.repository, args.toolchains, args.seal_diagnostic)
    manifest, payloads = load_archive(args.directory)
    result = verify_payloads(manifest, payloads)
    if args.repository:
        result["trackedGitInputsVerified"] = verify_repository(args.repository, payloads)
        result["failedGateTrackedGitInputsVerified"] = verify_repository(
            args.repository, payloads, FAILED_COMMIT, FAILED_TREE, "diagnostic/pre-format/")
    if args.self_test:
        result["corruptionControlsRejected"] = self_test(manifest, payloads)
    print(json.dumps(result, sort_keys=True))
