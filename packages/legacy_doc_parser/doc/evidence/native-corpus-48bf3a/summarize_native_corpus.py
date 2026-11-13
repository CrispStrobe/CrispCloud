#!/usr/bin/env python3
"""Derive a compact summary from the unchanged, sealed per-case reports."""
import argparse
from collections import Counter
import hashlib
import json
import lzma
from pathlib import Path


def sha(data):
    return hashlib.sha256(data).hexdigest()


def rendering_summary(comparisons):
    return {
        "comparisons": len(comparisons),
        "pageCountsMatch": sum(c["referencePages"] == c["actualPages"] for c in comparisons),
        "pageDimensionsMatch": sum(c["pageDimensionsMatch"] for c in comparisons),
        "pageTextMatches": sum(c["pageTextMatches"] for c in comparisons),
        "wordGeometryWithinTolerance": sum(c["matchesWithinTolerance"] for c in comparisons),
        "rasterExactlyMatches": sum(c["rasterExactlyMatches"] for c in comparisons),
        "layoutTextExactlyMatches": sum(c["layoutTextExactlyMatches"] for c in comparisons),
        "exactOnThisRenderer": sum(c["exactOnThisRenderer"] for c in comparisons),
    }


def summarize(directory):
    index_bytes = (directory / "index.json").read_bytes()
    index = json.loads(index_bytes)
    assert index["status"] == "complete"
    assert [c["id"] for c in index["cases"]] == index["caseIds"]
    rows, reports, manifests, cycles = [], [], [], []
    for entry in index["cases"]:
        assert entry["status"] == entry["stage"] == "complete"
        assert entry["rawRemovedAfterVerification"] is True
        sealed = directory / entry["sealedDirectory"]
        manifest_bytes = (sealed / "native-artifacts.manifest.json").read_bytes()
        assert sha(manifest_bytes) == entry["sealedManifestSha256"]
        manifest = json.loads(manifest_bytes)
        compressed = (sealed / manifest["report"]["path"]).read_bytes()
        assert sha(compressed) == manifest["report"]["sha256"]
        assert len(compressed) == manifest["report"]["bytes"]
        raw_report = lzma.decompress(compressed)
        assert sha(raw_report) == manifest["report"]["uncompressedSha256"] == entry["reportSha256"]
        assert len(raw_report) == manifest["report"]["uncompressedBytes"]
        archive = (sealed / manifest["archive"]["path"]).read_bytes()
        assert sha(archive) == manifest["archive"]["sha256"]
        assert len(archive) == manifest["archive"]["bytes"]
        report = json.loads(raw_report)
        assert report["status"] == "measured"
        assert report["parserCommit"] == index["sourceCommit"] == manifest["sourceCommit"]
        assert report["parserWorktreeDirty"] is False
        assert report["build"]["sourcesUnchangedDuringCompilation"] is True
        assert report["corpusSha256"] == index["corpusSha256"]
        assert len(report["cases"]) == 1
        case = report["cases"][0]
        assert case["id"] == entry["id"] and case["status"] == "measured"
        assert case["sourceUnchanged"] is True and case["binaryDocUnchanged"] is True
        assert case["pagination"] == entry["summary"]["pagination"]
        assert len(case["roundtripCycles"]) == index["roundtripCyclesRequested"]
        assert all(s["status"] == "complete" for s in report["stages"] + case["stages"])
        for n, cycle in enumerate(case["roundtripCycles"], 1):
            assert cycle["index"] == n and cycle["status"] == "measured"
            assert cycle["inputUnchanged"] is True and cycle["binaryDocUnchanged"] is True
        rows.append({
            "id": case["id"], "sourceFormat": case["sourceFormat"],
            "sourceSha256": case["sourceSha256"],
            "pagination": case["pagination"],
            "sourceGolden": case["sourceGolden"],
            "strictStructuralDifferenceCount": len(case["semanticDifferencesFromNativeDoc"]),
            "roundtrips": [{
                "index": c["index"],
                "paginationFromBinaryDoc": c["paginationFromBinaryDoc"],
                "paginationFromPreviousImport": c["paginationFromPreviousImport"],
                "paginationFromFirstImport": c["paginationFromFirstImport"],
                "strictDifferencesFromNativeDoc": len(c["semanticDifferencesFromNativeDoc"]),
                "strictDifferencesFromPreviousImport": len(c["semanticDifferencesFromPreviousImport"]),
                "strictDifferencesFromFirstImport": len(c["semanticDifferencesFromFirstImport"]),
            } for c in case["roundtripCycles"]],
            "manifestSha256": sha(manifest_bytes),
            "archiveSha256": manifest["archive"]["sha256"],
            "compressedReportSha256": manifest["report"]["sha256"],
            "rawReportSha256": sha(raw_report),
        })
        reports.append(report)
        manifests.append(manifest)
        cycles.extend(case["roundtripCycles"])
    cases = [r["cases"][0] for r in reports]
    assert len(cases) == index["completedCases"]
    assert len(cycles) == index["completedRoundtripCycles"]
    environments = [{
        "sources": r["build"]["sources"],
        "tools": {k: r["build"][k] for k in ("compiler", "office", "pdftotext", "pdftoppm", "pdfinfo")},
        "renderer": r["renderer"],
        "fontInventorySha256": r["fontInventorySha256"],
        "fontFilesSha256": r["fontFilesSha256"],
    } for r in reports]
    assert all(e == environments[0] for e in environments)
    files = [f for m in manifests for f in m["files"]]
    return {
        "schema": "legacy-doc-parser/bounded-corpus-summary", "version": 1,
        "indexSha256": sha(index_bytes),
        "sourceCommit": index["sourceCommit"], "sourceTree": index["sourceTree"],
        "method": index["method"],
        "definitions": {
            "initialComparison": "Native binary DOC render versus first parser DOCX render; original DOCX-to-DOC bridge changes are measured separately in each full report.",
            "renderExact": "All pixels, extracted layout text and word boxes agree on the recorded renderer; independent of strict structural comparison.",
            "strictStructuralDifferences": "Snapshot property differences include representation changes and native bridge losses; counts alone do not attribute semantic loss.",
            "wordGeometryTolerancePoints": 0.25,
            "rasterDpi": index["rasterDpi"],
            "bytes": "Decimal byte counts; raw report bytes and artifact bytes include some duplicate evidence by design.",
        },
        "completedCases": len(cases), "completedRoundtripCycles": len(cycles),
        "executionErrors": 0, "initial": rendering_summary([c["pagination"] for c in cases]),
        "initialStrictStructuralMatches": sum(not c["semanticDifferencesFromNativeDoc"] for c in cases),
        "sourceGoldenStatuses": dict(Counter(c["sourceGolden"]["status"] for c in cases)),
        "parserAgainstSourceGoldenStatuses": dict(Counter(c["parserAgainstSourceGolden"]["status"] for c in cases)),
        "bridge": rendering_summary([c["bridgePagination"] for c in cases if c["bridgePagination"]]),
        "roundtrip": {key: rendering_summary([c[key] for c in cycles]) for key in (
            "paginationFromBinaryDoc", "paginationFromPreviousImport", "paginationFromFirstImport")},
        "roundtripStrictStructuralMatches": {key: sum(not c[key] for c in cycles) for key in (
            "semanticDifferencesFromNativeDoc", "semanticDifferencesFromPreviousImport", "semanticDifferencesFromFirstImport")},
        "allSourceAndCycleInputBytesUnchanged": True,
        "sameCleanSourceCompilerRendererAndFonts": True,
        "sourceFileCount": len(environments[0]["sources"]["files"]),
        "sourceFilesSha256": environments[0]["sources"]["sha256"],
        "renderer": environments[0]["renderer"],
        "fontInventorySha256": environments[0]["fontInventorySha256"],
        "fontFilesSha256": environments[0]["fontFilesSha256"],
        "compiler": environments[0]["tools"]["compiler"],
        "distinctCompiledExecutableHashes": len({r["build"]["executable"]["sha256"] for r in reports}),
        "artifactTotals": {
            "files": len(files),
            "pdfs": sum(f["path"].endswith(".pdf") for f in files),
            "documents": sum(f["path"].endswith((".doc", ".docx")) for f in files),
            "gzipRasterPages": sum(f["path"].endswith(".ppm.gz") for f in files),
            "rawRasterBytes": sum(f.get("uncompressedBytes", 0) for f in files),
            "artifactArchiveBytes": sum(m["archive"]["bytes"] for m in manifests),
            "artifactFileBytes": sum(m["uncompressedFileBytes"] for m in manifests),
            "compressedReportBytes": sum(m["report"]["bytes"] for m in manifests),
            "rawReportBytes": sum(m["report"]["uncompressedBytes"] for m in manifests),
        },
        "cases": rows,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(summarize(args.directory), indent=2))
