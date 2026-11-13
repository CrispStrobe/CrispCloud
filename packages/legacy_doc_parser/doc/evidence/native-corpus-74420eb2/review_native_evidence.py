#!/usr/bin/env python3
"""Verify native source/receipt bindings and reproduce the retained comparison.

Never executes Office, Dart, or any captured source. The inherited comparison
helper uses assertions, so optimized Python is explicitly refused.
"""
import argparse
import copy
import hashlib
import importlib.util
import io
import json
import lzma
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tarfile

if not __debug__:
    raise SystemExit("Run without Python optimization: comparison checks use assertions")

import compare_native_corpus as comparison

COMMIT = "74420eb2e0ec14401a0db5bcbb30ab6d202a2340"
TREE = "ac78b144d90bca0f44993d94ae0fd1c8115ce072"
WORKSPACE = "/workspace/scratch/c1ca2a1344e9"
DART = WORKSPACE + "/toolchains/dart-3.13.7/dart-sdk/bin/dart"


def require(value, message):
    if not value:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def check_bundle(root):
    record = json.loads((root / "bundle-files.json").read_bytes())
    require(record["sourceCommit"] == COMMIT and record["sourceTree"] == TREE, "Bundle identity")
    actual = [{"path": p.relative_to(root).as_posix(), "size": p.stat().st_size,
               "sha256": sha(p.read_bytes())} for p in sorted(root.rglob("*"))
              if p.is_file() and "__pycache__" not in p.relative_to(root).parts and
              p != root / "bundle-files.json"]
    require(record["files"] == actual, "Bundle file inventory/bytes differ: " + root.name)


def unpack_sources(root):
    manifest = json.loads((root / "source.manifest.json").read_bytes())
    require(manifest["sourceCommit"] == COMMIT and manifest["sourceTree"] == TREE,
            "Native source identity")
    record = manifest["archive"]
    require(record["path"] == "native-source.tar.xz", "Native source archive path")
    raw = (root / record["path"]).read_bytes()
    require(len(raw) == record["size"] and sha(raw) == record["sha256"], "Native source archive hash")
    expected = {entry["path"]: entry for entry in manifest["files"]}
    require(len(expected) == len(manifest["files"]) == 143, "Native source inventory")
    result = {}
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:xz") as archive:
        for member in archive:
            require(member.isfile() and member.name in expected and member.name not in result,
                    "Native source member inventory")
            data = archive.extractfile(member).read()
            require(expected[member.name] == {"path": member.name, "size": len(data), "sha256": sha(data)},
                    "Native source member bytes: " + member.name)
            result[member.name] = data
    require(set(result) == set(expected), "Missing native source")
    require(sha(canonical({name: sha(data) for name, data in result.items()})) == manifest["aggregateSha256"],
            "Native source aggregate")
    return result


def render_metrics(reference, actual):
    a, b = reference["pages"], actual["pages"]
    same_text = len(a) == len(b) and all(
        [w["text"] for w in x["words"]] == [w["text"] for w in y["words"]]
        for x, y in zip(a, b))
    drift = max([0.0] + [abs(x - y) for p, q in zip(a, b)
                for u, v in zip(p["words"], q["words"])
                for x, y in zip(u["box"], v["box"])]) if same_text else None
    sizes = len(a) == len(b) and all(x["size"] == y["size"] for x, y in zip(a, b))
    settings = (reference["rasterColorSpace"] == "RGB" and reference["rasterDpi"] > 0 and
                all(reference[k] == actual[k] for k in ("rasterDpi", "rasterColorSpace")))
    pixels = settings and reference["rasterSha256"] == actual["rasterSha256"]
    text = reference["text"] == actual["text"]
    return {"referencePages": len(a), "actualPages": len(b), "pageDimensionsMatch": sizes,
            "pageTextMatches": same_text, "maximumWordDriftPoints": drift, "tolerancePoints": 0.25,
            "matchesWithinTolerance": sizes and same_text and drift is not None and drift <= 0.25,
            "rasterSettingsMatch": settings, "rasterExactlyMatches": pixels,
            "layoutTextExactlyMatches": text,
            "exactOnThisRenderer": pixels and text and drift == 0 and sizes}


def check_report(report, sources, manifest, sidecars):
    require(report["parserCommit"] == manifest["sourceCommit"] == COMMIT and
            report["parserWorktreeDirty"] is manifest["sourceWorktreeDirty"] is False and
            report["status"] == "measured" and report["roundtripCyclesRequested"] == 3,
            "Native report completion/source identity")
    build = report["build"]
    hashes = {name: sha(data) for name, data in sources.items()}
    require(build["sources"]["files"] == hashes and build["sources"]["sha256"] == sha(canonical(hashes)) and
            build["sourcesUnchangedDuringCompilation"] is True, "Native build source binding")
    require(build["compileCommand"] == [DART, "compile", "exe", "tool/fidelity/convert.dart", "-o",
            WORKSPACE + "/parser-native-74420eb/convert"], "Native compile command")
    corpus = json.loads(sources["tool/fidelity/corpus.json"])
    require(report["corpusSha256"] == sha(sources["tool/fidelity/corpus.json"]), "Native corpus identity")
    require([case["id"] for case in report["cases"]] == [case["id"] for case in corpus["cases"]] and
            len(report["cases"]) == 24, "Native case inventory")
    require(all(stage["status"] == "complete" for stage in report["stages"]), "Incomplete global stage")
    entries = {entry["path"]: entry for entry in manifest["files"]}
    document_hashes = {entry["sha256"] for entry in manifest["files"] if entry["path"].endswith((".doc", ".docx"))}
    recomputed = 0
    for case, source in zip(report["cases"], corpus["cases"], strict=True):
        label = case["id"]
        require(case["status"] == "measured" and case["sourceUnchanged"] is True and
                case["binaryDocUnchanged"] is True and case["sourceSha256"] == source["sha256"] and
                entries["inputs/" + label + PurePosixPath(source["path"]).suffix]["sha256"] == source["sha256"],
                "Native case/source completion: " + label)
        require(all(stage["status"] == "complete" for stage in case["stages"]), "Incomplete case stage")
        renders = {}
        for kind in ("renders", "snapshots"):
            for name, ref in case[kind].items():
                path = "run/" + label + "/" + ref["path"]
                require(entries[path]["sha256"] == ref["sha256"] == sha(sidecars[path]) and
                        ref["documentSha256"] in document_hashes, "Native sidecar/document binding: " + path)
                if kind == "renders":
                    renders[name] = json.loads(sidecars[path])
                    require(renders[name]["rasterDpi"] == 72 and renders[name]["rasterColorSpace"] == "RGB",
                            "Native rendering settings")
        for name, key in (("binary", "binaryDocSha256"), ("converted", "convertedSha256"),
                          ("native", "nativeDocxSha256")):
            require(case["renders"][name]["documentSha256"] == case[key], "Native document identity")
        pairs = [("pagination", "binary", "converted"), ("nativeConversionPagination", "binary", "native")]
        if case["sourceFormat"] == "docx":
            pairs.append(("bridgePagination", "original", "binary"))
        for key, left, right in pairs:
            require(case[key] == render_metrics(renders[left], renders[right]), "Native metric derivation: " + label + "/" + key)
            recomputed += 1
        require(len(case["roundtripCycles"]) == case["roundtripCyclesRequested"] == 3, "Native cycle inventory")
        previous = "converted"
        for n, cycle in enumerate(case["roundtripCycles"], 1):
            prefix = f"roundtrip-{n:02d}-"
            require(cycle["index"] == n and cycle["status"] == "measured" and
                    cycle["inputUnchanged"] is True and cycle["binaryDocUnchanged"] is True,
                    "Native cycle completion")
            require(cycle["inputSha256"] == case["renders"][previous]["documentSha256"] and
                    cycle["binaryDocSha256"] == case["renders"][prefix + "binary"]["documentSha256"] and
                    cycle["convertedSha256"] == case["renders"][prefix + "converted"]["documentSha256"],
                    "Native cycle document chain")
            for key, left in (("paginationFromBinaryDoc", prefix + "binary"),
                              ("paginationFromPreviousImport", previous),
                              ("paginationFromFirstImport", "converted")):
                require(cycle[key] == render_metrics(renders[left], renders[prefix + "converted"]),
                        "Native cycle metric derivation: " + label + "/" + key)
                recomputed += 1
            previous = prefix + "converted"
    require(recomputed == 278, "Native metric coverage")
    return recomputed


def normalize_paths(value):
    result = copy.deepcopy(value)
    # Only the review helper's current input locations vary between checkouts.
    # Original tool paths and every other recorded field remain bound.
    for side in ("before", "after"):
        result[side].pop("input")
        for receipt in result[side]["receipts"]:
            receipt.pop("path")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--repository", type=Path)
    args = parser.parse_args()
    root = args.directory.resolve()
    check_bundle(root)
    artifact_check = json.loads(subprocess.check_output([sys.executable, str(root / "verify_native_artifacts.py"),
                                  "--directory", str(root / "sealed")]))
    manifest = json.loads((root / "sealed/native-artifacts.manifest.json").read_bytes())
    sources = unpack_sources(root)
    portable_root = root.parent / "continuation-74420eb2"
    check_bundle(portable_root)
    hosted = json.loads((portable_root / "hosted-ci.json").read_bytes())
    require(hosted["run"]["head_sha"] == COMMIT and hosted["run"]["id"] == 43383581993 and
            hosted["run"]["status"] == "completed" and hosted["run"]["conclusion"] == "success",
            "Hosted status source/result identity")
    jobs = hosted["jobs"]["jobs"]
    require({job["name"] for job in jobs} == {"test", "openxml-schema"} and len(jobs) == 2 and
            all(job["status"] == "completed" and job["conclusion"] == "success" and
                job["run_id"] == 43383581993 for job in jobs), "Hosted job status binding")
    spec = importlib.util.spec_from_file_location("portable_seal", portable_root / "seal_validation_evidence.py")
    portable_helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(portable_helper)
    portable_manifest, portable_payloads = portable_helper.load_archive(portable_root)
    portable_helper.verify_payloads(portable_manifest, portable_payloads)
    portable_inputs = json.loads(portable_payloads["portable/receipt.json"])["inputsBefore"]
    require(all(portable_inputs[name] == sha(data) for name, data in sources.items()),
            "Native sources differ from portable acceptance")
    if args.repository:
        portable_helper.verify_repository(args.repository, portable_payloads)
    report, raw_hash = comparison.read_report(root / "sealed/native-report.json.xz", manifest["report"])
    wanted = {"run/" + case["id"] + "/" + ref["path"] for case in report["cases"]
              for kind in ("renders", "snapshots") for ref in case[kind].values()}
    sidecars = {}
    with tarfile.open(root / "sealed/native-artifacts.tar.xz", "r|xz") as archive:
        for member in archive:
            if member.name in wanted:
                sidecars[member.name] = archive.extractfile(member).read()
    require(set(sidecars) == wanted, "Missing native sidecars")
    count = check_report(report, sources, manifest, sidecars)
    schema = json.loads(portable_payloads["schema/report.json"])
    require(report["build"]["compiler"]["sha256"] == schema["dart"]["executableSha256"] and
            report["build"]["compiler"]["version"] == schema["dart"]["version"],
            "Native and portable Dart binary identities differ")
    rejected = 0
    if args.self_test:
        # Mutate only targeted fields, restore each, and bypass outer checksums
        # deliberately so these controls reach semantic evidence bindings.
        fields = [(report, "parserWorktreeDirty", True), (report, "parserCommit", "0" * 40),
                  (report["build"], "compileCommand", ["true"]),
                  (report["build"], "sourcesUnchangedDuringCompilation", False),
                  (report["cases"][0], "status", "failed"),
                  (report["cases"][0]["pagination"], "exactOnThisRenderer", True),
                  (report["cases"][0]["roundtripCycles"][0], "inputSha256", "0" * 64),
                  (report["cases"][0]["roundtripCycles"][0]["paginationFromFirstImport"], "actualPages", 999),
                  (report["cases"][0]["renders"]["converted"], "sha256", "0" * 64)]
        for target, key, value in fields:
            old = target[key]
            require(old != value, "Nondiscriminating native corruption control")
            target[key] = value
            try:
                try:
                    check_report(report, sources, manifest, sidecars)
                except (ValueError, KeyError):
                    rejected += 1
                else:
                    raise ValueError("Accepted native corruption: " + key)
            finally:
                target[key] = old
    del report, sidecars
    before = comparison.load_dataset(root.parent / "native-corpus-48bf3a")
    after = comparison.load_dataset(root / "sealed")
    require(after["environment"]["parserCommit"] == COMMIT, "Comparison source identity")
    derived = comparison.compare(before, after)
    retained = json.loads(lzma.decompress((root / "comparison-vs-48bf3a.json.xz").read_bytes()))
    require(normalize_paths(derived) == normalize_paths(retained), "Retained comparison differs from original reports")
    summary = json.loads((root / "summary.json").read_bytes())
    for key in ("cases", "cycles", "executionErrors", "initial", "bridge", "repeats", "sourceGoldenStatuses",
                "parserAgainstSourceGoldenStatuses", "strictInitialMatches", "allInputsUnchanged", "artifactCountsFromManifests"):
        require(summary[key] == derived["after"][key], "Summary binding: " + key)
    require(summary["sourceCommit"] == COMMIT and summary["sourceTree"] == TREE and
            summary["baselineComparisonContext"] == derived["context"], "Summary identity/context binding")
    require(summary["environment"] == {k: after["environment"][k] for k in summary["environment"]},
            "Summary renderer/font identity")
    rows = [{"id": c["id"], "sameSourceBytes": c["sameSourceBytes"],
             "sameNativeBinaryBytes": c["sameNativeBinaryBytes"], "initialDelta": c["initialDelta"],
             "changedRenderFingerprints": [k for k, v in c["renderFingerprintEquality"].items() if not v],
             "cycleDeltas": c["cycleDeltas"]} for c in derived["cases"]]
    require(summary["casesSummary"] == rows, "Summary per-case comparison binding")
    print(json.dumps({"verified": True, "parserCommit": COMMIT, "parserTree": TREE,
          "retainedSources": len(sources), "recomputedRenderComparisons": count,
          "nativeCases": 24, "roundtripCycles": 72, "artifactCheck": artifact_check,
          "comparisonReproduced": True, "semanticCorruptionsRejected": rejected}, sort_keys=True))


if __name__ == "__main__":
    main()
