#!/usr/bin/env python3
"""Seal or verify the 1b8cc9e2 portable/schema evidence, without rerunning tools.

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


COMMIT = "1b8cc9e28aa9f4da2d0f0fa9318758bce0e923f1"
TREE = "8b826eb2239438565faefa718bd42da61107d95e"
WORKSPACE = "/workspace/scratch/c1ca2a1344e9"
DART = WORKSPACE + "/toolchains/dart-3.13.7/dart-sdk/bin/dart"
DOTNET = WORKSPACE + "/toolchains/dotnet-8.0.428/dotnet"
CSC = WORKSPACE + "/toolchains/dotnet-8.0.428/sdk/8.0.428/Roslyn/bincore/csc.dll"
SCHEMA_ROOT = WORKSPACE + "/independent-schema-1b8cc9e2"
VALIDATOR = SCHEMA_ROOT + "/validator/OfficeValidation.dll"
PYTHON = "/opt/codex/runtimes/codex-primary-runtime/dependencies/python/bin/python3"
REPOSITORY_ROOT = WORKSPACE + "/parser-independent-combined"
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


def verify_final_context(payloads):
    commands = {
        "portable": [PYTHON, "doc/evidence/continuation-0c3e596/run_parser_gate.py", "--repo", REPOSITORY_ROOT,
                     "--out", WORKSPACE + "/independent-acceptance-1b8cc9e2", "--dart", DART],
        "schema": [PYTHON, "tool/fidelity/schema.py", "--dart", DART, "--dotnet", DOTNET,
                   "--cached-nuget", WORKSPACE + "/toolchains/nuget", "--out", SCHEMA_ROOT],
    }
    require(set(subtree(payloads, "launch/")) == {"run_final_acceptance_gate.py"} |
            {gate + ending for gate in commands for ending in (".launch.json", ".console.log")}, "Launch record inventory")
    inputs = json.loads(payloads["portable/receipt.json"])["inputsBefore"]
    for gate, command in commands.items():
        launch = json.loads(payloads["launch/" + gate + ".launch.json"])
        require(launch["gate"] == gate and launch["command"] == command and launch["cwd"] == REPOSITORY_ROOT and
                launch["status"] == "complete" and launch["exitCode"] == 0 and launch["success"] is True and
                launch["inputsUnchanged"] is True and launch["sourceBefore"] == launch["sourceAfter"], "Final gate launch/result binding")
        require(launch["sourceBefore"] == {"commit": COMMIT, "tree": TREE, "status": "", "files": inputs},
                "Final gate complete source binding")
        require(launch["environmentOverrides"] == {"TMPDIR": WORKSPACE + "/tmp", "DART_SUPPRESS_ANALYTICS": "true",
                "PUB_CACHE": WORKSPACE + "/toolchains/pub-cache"}, "Final gate environment")
        require(launch["launcherSha256"] == digest(payloads["launch/run_final_acceptance_gate.py"]) and
                launch["driverSourceSha256"] == inputs[command[1]] and launch["consoleLog"] == gate + ".console.log" and
                launch["consoleSha256"] == digest(payloads["launch/" + gate + ".console.log"]), "Final gate harness/log binding")
    require([json.loads(line) for line in payloads["launch/portable.console.log"].splitlines()] ==
            json.loads(payloads["portable/receipt.json"])["stages"], "Portable console/stage equality")


def verify_payloads(manifest, payloads):
    require(manifest["version"] == 2 and manifest["parserCommit"] == COMMIT and
            manifest["parserTree"] == TREE, "Evidence source identity")
    verify_javascript(payloads)
    verify_final_context(payloads)
    portable = json.loads(payloads["portable/receipt.json"])
    schema = json.loads(payloads["schema/report.json"])
    require(portable["commit"] == schema["gitHead"] == COMMIT and
            portable["tree"] == TREE, "Gate source identity")
    require(portable["success"] and portable["inputsUnchanged"] and
            portable["inputsBefore"] == portable["inputsAfter"] and
            portable["dirtyBefore"] == portable["dirtyAfter"] == "",
            "Portable source changed or gate failed")
    check_hash_map(portable["inputsBefore"], 1388, "Portable source")
    stages(payloads, "portable", portable["stages"], PORTABLE_STAGES, "exitCode")
    require(set(subtree(payloads, "portable/")) ==
            {"receipt.json", *(name + ".log" for name in PORTABLE_STAGES)},
            "Portable artifact inventory")
    for filename, marker in {
        "format.log": "Formatted 220 files (0 changed)",
        "analyze.log": "No issues found!",
        "dart-tests.log": "+1089: All tests passed!",
        "python-tests.log": "Ran 184 tests",
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
    check_hash_map(source, 390, "Schema source")
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
                b"Generated 265 deterministic schema cases.\n", "Corpus generation log")

    deterministic = schema["determinism"]
    require(deterministic["passed"] and deterministic["cases"] == 265 and
            deterministic["files"] == 560, "Determinism receipt")
    hashes = deterministic["sha256ByRelativePath"]
    check_hash_map(hashes, 560, "Generated corpus")
    for prefix in ("schema/corpus/", "schema/corpus-repeat/"):
        require(subtree(payloads, prefix) == hashes,
                "Full generated corpus inventory/bytes differ: " + prefix)
    require(all(payloads["schema/corpus/" + name] ==
                payloads["schema/corpus-repeat/" + name] for name in hashes),
            "Repeated corpus bytes differ")
    cases = schema["corpus"]["cases"]
    require(len(cases) == len({item["name"] for item in cases}) == 265,
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
            "portableStages": 8, "dartTests": 1089, "pythonControls": 184,
            "capturedPortableInputs": 1388, "retainedSchemaSources": 390,
            "schemaStages": 13, "schemaOutputs": 265, "schemaErrors": 0,
            "corpusFilesPerRun": 560, "corpusRuns": 2, "negativeControlsRejected": 2,
            "files": len(payloads), "archiveBytes": manifest["archive"]["size"],
            "archiveSha256": manifest["archive"]["sha256"]}


def verify_repository(repository, payloads, commit=COMMIT, tree=TREE, prefix="portable/", tracked_count=1386):
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
            and len(entries) == tracked_count and set(entries) <= set(source), "Full tracked source coverage")
    names = sorted(entries)
    stream = io.BytesIO(git("cat-file", "--batch", input="".join(entries[name] + "\n" for name in names).encode()))
    for name in names:
        oid, kind, size = stream.readline().split()
        require(oid.decode() == entries[name] and kind == b"blob", "Git batch object identity")
        require(digest(stream.read(int(size))) == source[name], "Pinned source SHA256: " + name)
        require(stream.read(1) == b"\n", "Git batch framing")
    require(stream.read() == b"", "Unexpected Git batch data")
    return tracked_count

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


def verify_javascript(payloads):
    expected = {
        'Legacy DOC': {'unicode': True, 'tables': 1, 'images': 1, 'headers': 3,
                       'footers': 3, 'footnotes': 1, 'internalRelationships': True,
                       'sourceUnchanged': True, 'oleMetadata': True, 'vbaMetadata': True,
                       'signatureValidityClaimed': False},
        'Media': {'checks': 51, 'recordCounts': {'emf': 21, 'wmf': 17}, 'emfBytes': 540, 'wmfBytes': 230},
        'Ink': {'cases': 24, 'strokes': 32, 'points': 96},
        'Ink header': {'cases': 32, 'strokes': 32, 'points': 160, 'specifiedMetricDifferences': 1},
        'Symbol': {'cases': 9, 'checks': 18, 'symbolCode': 'F061',
                   'ordinaryPunctuationIsDistinct': True, 'laterFalseIsQualified': True},
        'Field metadata': {'cases': {
            'external': {'fields': 4, 'sourceBytesUnchanged': True, 'representation': 'lockedFields', 'ownerBindingsChecked': True},
            'reference': {'fields': 3, 'sourceBytesUnchanged': True, 'representation': 'lockedFields', 'ownerBindingsChecked': True}},
            'fields': 7, 'fieldResultsEvaluated': False, 'bodyNoteTargetSwapRejected': True},
        'Font charset': {'cases': 8, 'checks': 40, 'puaRemapped': False},
    }
    log = payloads['portable/javascript.log'].decode()
    seen = {}
    for line in log.splitlines():
        if ' JavaScript acceptance passed: ' not in line:
            continue
        label, value = line.split(' JavaScript acceptance passed: ', 1)
        require(label not in seen, 'Duplicate JavaScript cohort')
        seen[label] = json.loads(value)
    require(seen == expected, 'JavaScript complete actual cohort results')


def self_test(manifest, payloads):
    controls = []

    def changed_json(values, name, mutation):
        item = json.loads(values[name])
        mutation(item)
        values[name] = json_bytes(item)

    def rejected(label, mutation, guard):
        values = dict(payloads)
        altered = copy.deepcopy(manifest)
        mutation(values, altered)
        try:
            verify_payloads(altered, values)
        except ValueError as error:
            require(guard in str(error), 'Wrong rejection for ' + label + ': ' + str(error))
            controls.append(label)
        else:
            raise ValueError('Accepted corrupted proof: ' + label)

    rejected('wrong measured source', lambda v, m: m.update(parserCommit='0' * 40), 'Evidence source identity')
    rejected('invented field evaluation claim', lambda v, m: v.update({'portable/javascript.log':
             v['portable/javascript.log'].replace(b'"fieldResultsEvaluated":false', b'"fieldResultsEvaluated":true')}), 'JavaScript complete actual cohort results')
    rejected('erased owner-swap control', lambda v, m: v.update({'portable/javascript.log':
             v['portable/javascript.log'].replace(b'"bodyNoteTargetSwapRejected":true', b'"bodyNoteTargetSwapRejected":false')}), 'JavaScript complete actual cohort results')
    rejected('changed launch executable', lambda v, m: changed_json(v, 'launch/portable.launch.json',
             lambda r: r['command'].__setitem__(0, '/usr/bin/true')), 'Final gate launch/result binding')
    rejected('omitted SDK case', lambda v, m: changed_json(v, 'schema/report.json',
             lambda r: r['corpus']['cases'].pop()), 'Schema case inventory')
    rejected('false repeated-corpus success', lambda v, m: changed_json(v, 'schema/report.json',
             lambda r: r['determinism'].update(files=559)), 'Determinism receipt')

    def wrong_sdk_hash(values, manifest):
        name = 'schema/schema-validation.json'
        changed_json(values, name, lambda r: r['Reports'][0].update(Sha256='0' * 64))
        changed_json(values, 'schema/report.json', lambda r: r['validation'].update(reportSha256=digest(values[name])))

    rejected('resealed wrong SDK document hash', wrong_sdk_hash, 'SDK input hash')

    def accepted_negative(values, manifest):
        name = 'schema/negative-controls.json'
        changed_json(values, name, lambda r: r['Reports'][0].update(Errors=[]))
        changed_json(values, 'schema/report.json', lambda r: r['negativeControls'].update(reportSha256=digest(values[name])))

    rejected('resealed accepted malformed XML', accepted_negative, 'expected malformed-input error absent')
    rejected('changed retained model source', lambda v, m: v.update({'source/lib/src/legacy_word_structured_model.dart':
             v['source/lib/src/legacy_word_structured_model.dart'] + b'\n// changed\n'}), 'Retained schema source bytes')
    return controls


def seal(directory, portable_root, schema_root, repository, toolchains, launch_root, launcher_source):
    require(not (directory / ARCHIVE).exists() and not (directory / MANIFEST).exists(),
            'Refusing to replace sealed evidence')
    payloads, omitted = {}, []
    for root, prefix in ((portable_root, 'portable'), (schema_root, 'schema')):
        for path in sorted(root.rglob('*')):
            require(not path.is_symlink(), 'Artifact symlink')
            if not path.is_file():
                continue
            name = prefix + '/' + path.relative_to(root).as_posix()
            raw = path.read_bytes()
            if prefix == 'schema' and path.relative_to(root).parts[0] == 'validator' and path.name in BINARIES:
                omitted.append(record(name, raw))
            else:
                require(path.relative_to(root).parts[0] not in ('tmp', 'dotnet-home', '.dotnet'), 'Unexpected incidental cache')
                payloads[name] = raw
    payloads['launch/run_final_acceptance_gate.py'] = launcher_source.read_bytes()
    for gate in ('portable', 'schema'):
        for ending in ('.launch.json', '.console.log'):
            payloads['launch/' + gate + ending] = (launch_root / (gate + ending)).read_bytes()
    schema = json.loads(payloads['schema/report.json'])
    for name, expected in schema['source']['files'].items():
        safe_path(name)
        raw = (repository / name).read_bytes()
        require(digest(raw) == expected, 'Source differs from measured bytes: ' + name)
        payloads['source/' + name] = raw
    for kind, oid in (('commit', COMMIT), ('tree', TREE)):
        payloads['source-identity/git-' + kind + '.raw'] = subprocess.check_output(
            ['git', '-C', str(repository), 'cat-file', kind, oid])
    for name, source in (('dart-recovery.json', 'recovery-20261113/dart-recovery.json'),
                         ('dotnet-recovery.json', 'dotnet-recovery.json'),
                         ('nuget-recovery.json', 'nuget/recovery.json')):
        payloads['toolchains/' + name] = (toolchains / source).read_bytes()
    verify_repository(repository, payloads)
    archive = directory / ARCHIVE
    with tarfile.open(archive, 'w:xz', preset=6) as packed:
        for name, raw in sorted(payloads.items()):
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = len(raw), 0o644, 0
            packed.addfile(info, io.BytesIO(raw))
    manifest = {'version': 2, 'parserCommit': COMMIT, 'parserTree': TREE,
                'archive': record(ARCHIVE, archive.read_bytes()),
                'files': [record(name, raw) for name, raw in sorted(payloads.items())],
                'omittedReproducibleBinaries': omitted,
                'verifierSha256': digest((directory / 'seal_validation_evidence.py').read_bytes()),
                'scope': 'Exact clean 1b8cc9e2 portable and Open XML SDK Office2019 gates: 390 captured build inputs, both full 560-file corpora, 265 validated outputs, independent controls, source/launch/log bindings and toolchain receipts. Four reproducible validator DLLs are omitted with hashes. Native rendering and earlier targeted proof remain separate.'}
    (directory / MANIFEST).write_bytes(json_bytes(manifest))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument('--seal-portable', type=Path)
    parser.add_argument('--seal-schema', type=Path)
    parser.add_argument('--repository', type=Path)
    parser.add_argument('--toolchains', type=Path)
    parser.add_argument('--seal-launches', type=Path)
    parser.add_argument('--launcher-source', type=Path)
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.seal_portable:
        require(all((args.seal_schema, args.repository, args.toolchains, args.seal_launches, args.launcher_source)),
                'Sealing needs both gates, repository, toolchains and launch receipts')
        seal(args.directory, args.seal_portable, args.seal_schema, args.repository, args.toolchains,
             args.seal_launches, args.launcher_source)
    manifest, payloads = load_archive(args.directory)
    result = verify_payloads(manifest, payloads)
    if args.repository:
        result['trackedGitInputsVerified'] = verify_repository(args.repository, payloads)
    if args.self_test:
        result['corruptionControlsRejected'] = self_test(manifest, payloads)
    print(json.dumps(result, sort_keys=True))


