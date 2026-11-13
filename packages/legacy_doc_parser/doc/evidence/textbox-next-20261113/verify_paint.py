#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Verify source-hashed paint probes, raw raster bytes and measured comparisons."""
import gzip
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys
import tarfile

if not __debug__:
    raise SystemExit("Verification requires normal Python without -O or PYTHONOPTIMIZE.")

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tool/fidelity"))
from goldens import compare_render  # noqa: E402


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def main():
    manifest = json.loads((HERE / "manifest.json").read_bytes())
    assert sha((ROOT / "tool/fidelity/goldens.py").read_bytes()) == manifest["comparisonHelperSha256"]
    assert sha((HERE / "summary.json").read_bytes()) == manifest["summarySha256"]
    summary = json.loads((HERE / "summary.json").read_bytes())
    archive = HERE / manifest["archive"]["path"]
    assert archive.stat().st_size == manifest["archive"]["bytes"]
    assert sha(archive.read_bytes()) == manifest["archive"]["sha256"]
    expected = {f["path"]: f for f in manifest["files"]}
    assert len(expected) == len(manifest["files"])
    files = {}
    with tarfile.open(archive, "r:xz") as retained:
        for member in retained:
            path = PurePosixPath(member.name)
            assert member.isfile() and not path.is_absolute() and ".." not in path.parts
            assert member.name in expected and member.name not in files
            raw = retained.extractfile(member).read()
            entry = expected[member.name]
            assert member.size == len(raw) == entry["bytes"] and sha(raw) == entry["sha256"]
            files[member.name] = raw
    assert files.keys() == expected.keys()
    rasters = 0
    for name, raw in files.items():
        if not name.endswith("/raster-manifest.json"):
            continue
        receipt = json.loads(raw)
        parent = PurePosixPath(name).parent
        assert receipt["status"] == "complete"
        assert len(receipt["pages"]) == receipt["expectedPages"]
        pdfs = [payload for path, payload in files.items() if PurePosixPath(path).parent == parent and path.endswith(".pdf")]
        assert len(pdfs) == 1 and sha(pdfs[0]) == receipt["pdfSha256"]
        for page in receipt["pages"]:
            compressed = files[str(parent / page["path"])]
            assert len(compressed) == page["sizeBytes"] and sha(compressed) == page["sha256"]
            restored = gzip.decompress(compressed)
            assert len(restored) == page["uncompressedSizeBytes"] and sha(restored) == page["uncompressedSha256"]
            rasters += 1
    comparisons = cycles = 0
    for name, saved in summary["runs"].items():
        report = json.loads(files[f"{name}/report.json"])
        assert report["status"] == saved["status"] and report.get("error") == saved["error"]
        for build in report.get("builds", {}).values():
            assert build["sourcesUnchanged"]
            for expected_hash in build["sources"]["files"].values():
                assert sha(files[f"build-sources/{expected_hash}"]) == expected_hash
        for case in report["cases"]:
            assert case["status"] == "complete" and case["inputsUnchanged"]
            assert sha(files[f"{name}/{case['id']}/authored.docx"]) == case["sourceSha256"]
            assert sha(files[f"{name}/{case['id']}/binary/authored.doc"]) == case["binarySha256"]
            renders = case["renders"]
            for label, render in renders.items():
                prefix = f"{name}/{case['id']}/{label}"
                raster = json.loads(files[prefix + "/raster-manifest.json"])
                assert render["pdfSha256"] == raster["pdfSha256"]
                assert render["rasterSha256"] == [p["uncompressedSha256"] for p in raster["pages"]]
            assert compare_render(renders["original"], renders["binary-render"]) == case["authoredToBinary"]
            for label in ("baseline", "candidate"):
                assert compare_render(renders["binary-render"], renders[label]) == case[label + "AgainstBinary"]
                assert compare_render(renders["original"], renders[label]) == case[label + "AgainstAuthored"]
            comparisons += 1
            previous = renders["candidate"]
            for cycle in case["cycles"]:
                label = f"repeat-{cycle['index']:02d}"
                actual = renders[label + "-converted"]
                assert compare_render(renders[label + "-binary"], actual) == cycle["againstBinary"]
                assert compare_render(previous, actual) == cycle["againstPrevious"]
                assert compare_render(renders["candidate"], actual) == cycle["againstFirst"]
                previous = actual
                cycles += 1
    assert comparisons == summary["completedInitialCases"] and cycles == summary["completedRepeatCycles"]
    print(json.dumps({"verified": True, "archiveFiles": len(files), "rasterPages": rasters,
                      "initialCases": comparisons, "repeatCycles": cycles,
                      "retainedSetupFailures": summary["retainedSetupFailures"]}))


if __name__ == "__main__":
    main()
