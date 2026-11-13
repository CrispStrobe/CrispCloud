#!/usr/bin/env python3
"""Bind the observed exact-head GitHub job status to its returned decoded logs.

This checks retained API observations and UTF-8 encoded connector log strings;
it neither contacts GitHub nor claims the local gate artifacts came from CI.
"""
import argparse
import copy
import hashlib
import io
import json
from pathlib import Path
import tarfile

COMMIT = "c5ff75e76163d9abbdd44a9f2a7c5ad210929289"
RUN = 43387392944
JOBS = {"test": 131758985202, "openxml-schema": 131758984962}
REQUIRED_STEPS = {
    "test": {"Run actions/checkout@v4", "Run dart-lang/setup-dart@v1", "Run dart pub get",
             "Run dart format --output=none --set-exit-if-changed .", "Run dart analyze --fatal-infos",
             "Run dart test", "Run python3 tool/fidelity/oracle.py",
             "Run python3 -m unittest discover -s tool/fidelity -p 'test_*.py'",
             "Run python3 tool/verify_web.py", "Run dart pub publish --dry-run"},
    "openxml-schema": {"Run actions/checkout@v4", "Run dart-lang/setup-dart@v1",
                       "Run actions/setup-dotnet@v4", "Run dart pub get",
                       "Run python3 tool/fidelity/schema.py --out build/schema-ci",
                       "Run actions/upload-artifact@v4"},
}
JS = {
    "Legacy DOC": {"unicode": True, "tables": 1, "images": 1, "headers": 3,
                   "footers": 3, "footnotes": 1, "internalRelationships": True,
                   "sourceUnchanged": True, "oleMetadata": True, "vbaMetadata": True,
                   "signatureValidityClaimed": False},
    "Media": {"checks": 51, "recordCounts": {"emf": 21, "wmf": 17}, "emfBytes": 540, "wmfBytes": 230},
    "Ink": {"cases": 24, "strokes": 32, "points": 96},
    "Ink header": {"cases": 32, "strokes": 32, "points": 160, "specifiedMetricDifferences": 1},
}


def require(value, message):
    if not value:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def load(root):
    status = json.loads((root / "hosted-ci.json").read_bytes())
    manifest = json.loads((root / "hosted-logs.manifest.json").read_bytes())
    record = manifest["archive"]
    require(record["path"] == "hosted-logs.tar.xz", "Hosted log archive path")
    raw = (root / record["path"]).read_bytes()
    require(record["size"] == len(raw) and record["sha256"] == sha(raw), "Hosted log archive bytes")
    logs = {}
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:xz") as archive:
        for member in archive:
            require(member.isfile() and member.name not in logs and member.name in {n + ".log" for n in JOBS},
                    "Hosted log archive inventory")
            logs[member.name] = archive.extractfile(member).read()
    return status, manifest, logs


def validate(status, manifest, logs):
    run = status["run"]
    require(run["id"] == RUN and run["head_sha"] == run["head_commit"]["id"] == COMMIT and
            run["status"] == "completed" and run["conclusion"] == "success" and
            run["repository"]["full_name"] == "CrispStrobe/legacy-doc-parser" and
            run["path"] == ".github/workflows/ci.yml" and run["name"] == "Dart package" and
            run["html_url"] == f"https://github.com/CrispStrobe/legacy-doc-parser/actions/runs/{RUN}",
            "Hosted run source/status identity")
    jobs = status["jobs"]["jobs"]
    require(len(jobs) == 2 and {job["name"]: job["id"] for job in jobs} == JOBS, "Hosted job identities")
    for job in jobs:
        require(job["run_id"] == RUN and job["status"] == "completed" and job["conclusion"] == "success",
                "Hosted job completion")
        steps = {step["name"]: step["conclusion"] for step in job["steps"]}
        require(len(steps) == len(job["steps"]) and REQUIRED_STEPS[job["name"]].issubset(steps) and
                all(steps[name] == "success" for name in REQUIRED_STEPS[job["name"]]), "Hosted required steps")
    require(manifest["sourceCommit"] == COMMIT and manifest["runId"] == RUN, "Hosted log source identity")
    require(set(logs) == {name + ".log" for name in JOBS}, "Hosted log inventory")
    expected = [{"path": name, "jobName": name[:-4], "jobId": JOBS[name[:-4]],
                 "size": len(raw), "sha256": sha(raw)} for name, raw in sorted(logs.items())]
    require(manifest["files"] == expected, "Hosted log member hashes/identities")
    decoded = {name[:-4]: raw.decode("utf-8") for name, raw in logs.items()}
    for name, log in decoded.items():
        require(COMMIT in log and "/opt/hostedtoolcache/dart/3.14.0/x64" in log, "Hosted log head/toolchain")
    test = decoded["test"]
    for marker in ("Formatted 208 files (0 changed)", "1028 tests passed.", "Ran 162 tests in", "Package has 0 warnings."):
        require(marker in test, "Hosted test result: " + marker)
    for label, expected in JS.items():
        prefix = label + " JavaScript acceptance passed: "
        values = [line.split(prefix, 1)[1] for line in test.splitlines() if prefix in line]
        require(len(values) == 1 and json.loads(values[0]) == expected, "Hosted actual JS result: " + label)
    require("Open XML SDK gate passed: 254 DOCX outputs, positive/negative controls, exact hashes, unchanged inputs." in
            decoded["openxml-schema"], "Hosted SDK result")
    return {"verified": True, "sourceCommit": COMMIT, "runId": RUN, "jobIds": JOBS,
            "dartVersion": "3.14.0", "dartTests": 1028, "pythonTests": 162,
            "sdkOutputs": 254, "actualJavaScriptCohorts": JS,
            "retainedDecodedLogBytes": sum(map(len, logs.values()))}


def self_test(status, manifest, logs):
    def reseal(manifest, logs):
        for entry in manifest["files"]:
            raw = logs[entry["path"]]
            entry.update(size=len(raw), sha256=sha(raw))

    mutations = [
        lambda s, m, p: s["run"].update(head_sha="0" * 40),
        lambda s, m, p: s["jobs"]["jobs"][0].update(conclusion="failure"),
        lambda s, m, p: s["jobs"]["jobs"][1]["steps"][8].update(conclusion="failure"),
        lambda s, m, p: m["files"][0].update(sha256="0" * 64),
        lambda s, m, p: p.update({"openxml-schema.log": p["openxml-schema.log"].replace(b"254 DOCX outputs", b"253 DOCX outputs")}),
        lambda s, m, p: p.update({"test.log": p["test.log"].replace(b'"cases":32,"strokes":32,"points":160', b'"cases":31,"strokes":32,"points":160')}),
        lambda s, m, p: p.update({"test.log": p["test.log"].replace(COMMIT.encode(), b"0" * 40)}),
    ]
    for index, mutate in enumerate(mutations):
        s, m, p = copy.deepcopy(status), copy.deepcopy(manifest), dict(logs)
        mutate(s, m, p)
        if index >= 4:
            reseal(m, p)  # Reach semantic bindings after restoring outer byte receipts.
        try:
            validate(s, m, p)
        except (ValueError, KeyError):
            pass
        else:
            raise ValueError("Accepted hosted evidence corruption " + str(index))
    return len(mutations)


def verify(root, controls=False):
    status, manifest, logs = load(root)
    result = validate(status, manifest, logs)
    result["semanticCorruptionsRejected"] = self_test(status, manifest, logs) if controls else 0
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    print(json.dumps(verify(args.directory, args.self_test), sort_keys=True))
