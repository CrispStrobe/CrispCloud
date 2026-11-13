#!/usr/bin/env python3
"""Read-only comparison of original native fidelity receipts.

Accepts either a bounded-corpus directory with an index or one native report.
Metric changes are observations, not automatic semantic-regression verdicts.
"""

import argparse
from collections import Counter
import hashlib
import json
import lzma
from pathlib import Path
import tarfile


METRICS = (
    "pageDimensionsMatch", "pageTextMatches", "matchesWithinTolerance",
    "rasterSettingsMatch", "rasterExactlyMatches", "layoutTextExactlyMatches",
    "exactOnThisRenderer",
)
CYCLE_METRICS = (
    "paginationFromBinaryDoc", "paginationFromPreviousImport",
    "paginationFromFirstImport",
)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def read_report(path, manifest=None):
    compressed = path.read_bytes()
    raw = lzma.decompress(compressed) if path.suffix == ".xz" else compressed
    if manifest is not None:
        assert sha(compressed) == manifest["sha256"]
        assert len(compressed) == manifest["bytes"]
        assert sha(raw) == manifest["uncompressedSha256"]
        assert len(raw) == manifest["uncompressedBytes"]
    return json.loads(raw), sha(raw)


def render_fingerprints(archive_path, cases, manifest):
    """Read render sidecars and bind them to both manifest and report hashes."""
    references = {}
    for case in cases:
        for name, ref in case.get("renders", {}).items():
            references[f"run/{case['id']}/{ref['path']}"] = (case["id"], name, ref)
    files = {entry["path"]: entry for entry in manifest["files"]}
    result = {}
    with tarfile.open(archive_path, "r|xz") as archive:
        for member in archive:
            if member.name not in references:
                continue
            case_id, name, reference = references[member.name]
            raw = archive.extractfile(member).read()
            assert sha(raw) == files[member.name]["sha256"] == reference["sha256"]
            render = json.loads(raw)
            result.setdefault(case_id, {})[name] = {
                "pagesSha256": sha(canonical(render["pages"])),
                "wordSequenceSha256": sha(canonical([
                    [w["text"] for w in page["words"]] for page in render["pages"]
                ])),
                "layoutTextSha256": sha(render["text"].encode()),
                "rasterSha256": render["rasterSha256"],
                "rasterDpi": render["rasterDpi"],
                "rasterColorSpace": render["rasterColorSpace"],
            }
    assert sum(len(v) for v in result.values()) == len(references)
    return result


def compact_case(case, fingerprints):
    return {
        "id": case["id"], "status": case["status"],
        "sourceFormat": case["sourceFormat"], "sourceSha256": case["sourceSha256"],
        "binaryDocSha256": case.get("binaryDocSha256"),
        "sourceUnchanged": case.get("sourceUnchanged"),
        "binaryDocUnchanged": case.get("binaryDocUnchanged"),
        "initial": case.get("pagination"),
        "bridge": case.get("bridgePagination"),
        "nativeExporter": case.get("nativeConversionPagination"),
        "sourceGolden": case.get("sourceGolden"),
        "parserAgainstSourceGolden": case.get("parserAgainstSourceGolden"),
        "strictInitialDifferences": len(case.get("semanticDifferencesFromNativeDoc", [])),
        "requestedCycles": case["roundtripCyclesRequested"],
        "cycles": [{key: cycle.get(key) for key in (
            "index", "status", "inputUnchanged", "binaryDocUnchanged", *CYCLE_METRICS,
        )} for cycle in case["roundtripCycles"]],
        "renderFingerprints": fingerprints,
    }


def load_dataset(path):
    cases, environments, receipts = {}, [], []
    manifests = []
    if path.is_dir() and (path / "index.json").is_file():
        index = json.loads((path / "index.json").read_bytes())
        assert index["status"] == "complete"
        assert [c["id"] for c in index["cases"]] == index["caseIds"]
        sources = []
        for entry in index["cases"]:
            assert entry["status"] == entry["stage"] == "complete"
            directory = path / entry["sealedDirectory"]
            raw_manifest = (directory / "native-artifacts.manifest.json").read_bytes()
            assert sha(raw_manifest) == entry["sealedManifestSha256"]
            manifest = json.loads(raw_manifest)
            assert manifest["report"]["uncompressedSha256"] == entry["reportSha256"]
            assert manifest["sourceCommit"] == index["sourceCommit"]
            assert manifest["archive"] == entry["sealedArchive"]
            archive_path = directory / manifest["archive"]["path"]
            archive = archive_path.read_bytes()
            assert sha(archive) == manifest["archive"]["sha256"]
            assert len(archive) == manifest["archive"]["bytes"]
            sources.append((directory / manifest["report"]["path"], manifest["report"], manifest, archive_path))
            manifests.append(manifest)
    else:
        path = path / "native-report.json.xz" if path.is_dir() else path
        summary_path = path.parent / "summary.json"
        metadata = json.loads(summary_path.read_bytes()).get("archives", {}).get(path.name) if summary_path.exists() else None
        sources = [(path, metadata, None, None)]
    for report_path, metadata, manifest, archive_path in sources:
        report, raw_hash = read_report(report_path, metadata)
        fingerprints = render_fingerprints(archive_path, report["cases"], manifest) if manifest else {}
        environment = {
            "schemaVersion": report["version"],
            "parserCommit": report["parserCommit"],
            "parserWorktreeDirty": report["parserWorktreeDirty"],
            "reportStatus": report["status"],
            "corpusSha256": report["corpusSha256"],
            "renderer": report["renderer"],
            "fontInventorySha256": report["fontInventorySha256"],
            "fontFilesSha256": report["fontFilesSha256"],
            "tools": {key: report["build"][key] for key in (
                "compiler", "office", "pdftotext", "pdftoppm", "pdfinfo",
            ) if key in report["build"]},
            "sources": report["build"]["sources"],
            "sourcesUnchangedDuringCompilation": report["build"]["sourcesUnchangedDuringCompilation"],
            "executableSha256": report["build"]["executable"]["sha256"],
        }
        environments.append(environment)
        receipts.append({"path": str(report_path), "rawSha256": raw_hash})
        for case in report["cases"]:
            assert case["id"] not in cases
            cases[case["id"]] = compact_case(case, fingerprints.get(case["id"], {}))
    assert all(e == environments[0] for e in environments), "Collection has differing source or environment identities"
    return {"input": str(path), "environment": environments[0], "receipts": receipts,
            "cases": cases, "manifests": manifests}


def totals(comparisons):
    comparisons = [c for c in comparisons if c is not None]
    return {"comparisons": len(comparisons),
            "pageCountsMatch": sum(c["referencePages"] == c["actualPages"] for c in comparisons),
            **{key: sum(c[key] is True for c in comparisons) for key in METRICS},
            "uncomparableWordDrift": sum(c["maximumWordDriftPoints"] is None for c in comparisons)}


def dataset_summary(dataset):
    cases = list(dataset["cases"].values())
    cycles = [r for c in cases for r in c["cycles"]]
    files = [f for m in dataset["manifests"] for f in m["files"]]
    return {
        "input": dataset["input"], "environment": dataset["environment"],
        "receipts": dataset["receipts"], "cases": len(cases), "cycles": len(cycles),
        "executionErrors": [c["id"] for c in cases if c["status"] != "measured" or
                            len(c["cycles"]) != c["requestedCycles"] or
                            any(r["status"] != "measured" for r in c["cycles"])],
        "allInputsUnchanged": all(c["sourceUnchanged"] and c["binaryDocUnchanged"] for c in cases) and
                              all(r["inputUnchanged"] and r["binaryDocUnchanged"] for r in cycles),
        "initial": totals([c["initial"] for c in cases]),
        "bridge": totals([c["bridge"] for c in cases]),
        "repeats": {key: totals([r[key] for r in cycles]) for key in CYCLE_METRICS},
        "sourceGoldenStatuses": dict(Counter(c["sourceGolden"]["status"] for c in cases)),
        "parserAgainstSourceGoldenStatuses": dict(Counter(c["parserAgainstSourceGolden"]["status"] for c in cases)),
        "strictInitialMatches": sum(c["strictInitialDifferences"] == 0 for c in cases),
        "artifactCountsFromManifests": {
            "archives": len(dataset["manifests"]), "files": len(files),
            "documents": sum(f["path"].endswith((".doc", ".docx")) for f in files),
            "pdfs": sum(f["path"].endswith(".pdf") for f in files),
            "gzipPages": sum(f["path"].endswith(".ppm.gz") for f in files),
            "rawRasterBytes": sum(f.get("uncompressedBytes", 0) for f in files),
        } if dataset["manifests"] else None,
    }


def metric_delta(before, after):
    if before is None or after is None:
        return {"comparable": False, "reason": "comparison absent in one receipt"}
    changed = {key: {"before": before.get(key), "after": after.get(key)}
               for key in set(before) | set(after) if before.get(key) != after.get(key)}
    drift_comparable = (before["pageTextMatches"] and after["pageTextMatches"] and
                        before["maximumWordDriftPoints"] is not None and after["maximumWordDriftPoints"] is not None)
    flags = []
    for key in METRICS:
        if before[key] != after[key]:
            flags.append(key + (": gained" if after[key] else ": lost"))
    if drift_comparable:
        change = after["maximumWordDriftPoints"] - before["maximumWordDriftPoints"]
        if abs(change) > 0.000001:
            flags.append("maximumWordDriftPoints: increased" if change > 0 else "maximumWordDriftPoints: decreased")
    else:
        change = None
    return {"changed": changed, "flags": flags,
            "wordDriftComparable": bool(drift_comparable), "wordDriftChangePoints": change}


def compare(before, after):
    b_env, a_env = before["environment"], after["environment"]
    tool_keys = set(b_env["tools"]) | set(a_env["tools"])
    b_files, a_files = b_env["sources"]["files"], a_env["sources"]["files"]
    context = {
        "sameRenderer": b_env["renderer"] == a_env["renderer"],
        "sameInstalledFontInventory": b_env["fontInventorySha256"] == a_env["fontInventorySha256"],
        "sameInstalledFontFiles": b_env["fontFilesSha256"] == a_env["fontFilesSha256"],
        "sameCorpusManifest": b_env["corpusSha256"] == a_env["corpusSha256"],
        "toolIdentityComparison": {key: (
            {k: b_env["tools"][key][k] for k in ("sha256", "version")} ==
            {k: a_env["tools"][key][k] for k in ("sha256", "version")}
            if key in b_env["tools"] and key in a_env["tools"] else None) for key in sorted(tool_keys)},
        "changedSourceFiles": [key for key in sorted(set(b_files) | set(a_files)) if b_files.get(key) != a_files.get(key)],
    }
    rows = []
    for case_id in sorted(set(before["cases"]) | set(after["cases"])):
        b, a = before["cases"].get(case_id), after["cases"].get(case_id)
        row = {"id": case_id, "before": b, "after": a}
        if b is None or a is None:
            row["presence"] = "added" if b is None else "missing"
        else:
            row["presence"] = "both"
            row["sameSourceBytes"] = b["sourceSha256"] == a["sourceSha256"]
            row["sameNativeBinaryBytes"] = b["binaryDocSha256"] == a["binaryDocSha256"]
            row["renderFingerprintEquality"] = {
                name: b["renderFingerprints"][name] == a["renderFingerprints"][name]
                for name in sorted(set(b["renderFingerprints"]) & set(a["renderFingerprints"]))
            }
            row["initialDelta"] = metric_delta(b["initial"], a["initial"])
            row["nativeExporterDelta"] = metric_delta(b["nativeExporter"], a["nativeExporter"])
            row["bridgeDelta"] = metric_delta(b["bridge"], a["bridge"])
            b_cycles, a_cycles = {r["index"]: r for r in b["cycles"]}, {r["index"]: r for r in a["cycles"]}
            row["cycleDeltas"] = [{"index": index, **{
                key: metric_delta(b_cycles[index][key], a_cycles[index][key]) for key in CYCLE_METRICS
            }} for index in sorted(set(b_cycles) & set(a_cycles))]
        rows.append(row)
    return {
        "schema": "legacy-doc-parser/independent-corpus-comparison", "version": 1,
        "scope": "Read-only derivation from original reports; metric losses require source/bridge/consumer attribution before a semantic-regression verdict.",
        "before": dataset_summary(before), "after": dataset_summary(after),
        "context": context, "cases": rows,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--after", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = compare(load_dataset(args.before), load_dataset(args.after))
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "beforeCases": result["before"]["cases"],
                      "afterCases": result["after"]["cases"], "context": result["context"]}))


if __name__ == "__main__":
    main()
