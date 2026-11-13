#!/usr/bin/env python3
"""Derive a compact review from retained reports; never run Office or Dart."""

import argparse
import hashlib
import io
import json
import lzma
from pathlib import Path
import tarfile
import xml.etree.ElementTree as ET
import zipfile


if not __debug__:
    raise SystemExit(
        "Verification requires normal Python; do not use -O, -OO or PYTHONOPTIMIZE."
    )


ROOT = Path(__file__).resolve().parent
W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def compatibility_observation(directory):
    directory = directory / "sealed/03-word-compatibility"
    manifest = json.loads((directory / "native-artifacts.manifest.json").read_bytes())
    files = {f["path"]: f for f in manifest["files"]}
    report_raw = lzma.decompress((directory / "native-report.json.xz").read_bytes())
    assert sha(report_raw) == manifest["report"]["uncompressedSha256"]
    case = json.loads(report_raw)["cases"][0]
    archive_raw = (directory / "native-artifacts.tar.xz").read_bytes()
    assert sha(archive_raw) == manifest["archive"]["sha256"]
    with tarfile.open(fileobj=io.BytesIO(archive_raw), mode="r:xz") as archive:
        def read(path):
            data = archive.extractfile(path).read()
            assert len(data) == files[path]["bytes"]
            assert sha(data) == files[path]["sha256"]
            return data

        renders = {}
        for name in ("binary", "converted"):
            reference = case["renders"][name]
            raw = read(f"run/{case['id']}/{reference['path']}")
            assert sha(raw) == reference["sha256"]
            render = json.loads(raw)
            words = render["pages"][0]["words"]
            renders[name] = {
                "reference": reference,
                "firstPageHeaderWords": words[:4],
                "firstUnselectedWord": next(w for w in words if w["text"] == "UNSELECTED"),
            }
        raw = read("run/word-compatibility/converted.docx")
        with zipfile.ZipFile(io.BytesIO(raw)) as docx:
            document_raw = docx.read("word/document.xml")
            document = ET.fromstring(document_raw)
            sections = [{
                "bidi": section.find(W + "bidi") is not None,
                "rtlGutter": section.find(W + "rtlGutter") is not None,
            } for section in document.iter(W + "sectPr")]
    return {
        "archiveSha256": manifest["archive"]["sha256"],
        "convertedDocxSha256": sha(raw),
        "documentXmlSha256": sha(document_raw),
        "sectionDirections": sections,
        "renders": renders,
    }


def derive():
    path = ROOT / "comparison-vs-0c3e596.json.xz"
    raw = lzma.decompress(path.read_bytes()) if path.exists() else (ROOT / "comparison-vs-0c3e596.json").read_bytes()
    comparison = json.loads(raw)
    rows = []
    for case in comparison["cases"]:
        changes = []
        for cycle in case["cycleDeltas"]:
            for name, delta in cycle.items():
                if name != "index" and delta.get("changed"):
                    changes.append({"index": cycle["index"], "comparison": name, **delta})
        rows.append({
            "id": case["id"],
            "initialBefore": case["before"]["initial"],
            "initialAfter": case["after"]["initial"],
            "initialDelta": case["initialDelta"],
            "changedCycles": changes,
            "changedRenderComponents": {
                name: [key for key, value in case["before"]["renderFingerprints"][name].items()
                       if value != case["after"]["renderFingerprints"][name][key]]
                for name, equal in case["renderFingerprintEquality"].items() if not equal
            },
        })
    return {
        "schema": "legacy-doc-parser/native-corpus-comparison-review",
        "version": 1,
        "scope": "Read-only derivation from unchanged archives; no native rerun or runtime edit.",
        "comparisonRawSha256": sha(raw),
        "context": comparison["context"],
        "sameSourceBytes": sum(c["sameSourceBytes"] for c in comparison["cases"]),
        "sameNativeBinaryBytes": sum(c["sameNativeBinaryBytes"] for c in comparison["cases"]),
        "allRenderFingerprintsUnchangedCases": sum(all(c["renderFingerprintEquality"].values()) for c in comparison["cases"]),
        "cases": rows,
        "wordCompatibilitySourceAlignment": {
            "before": compatibility_observation(ROOT.parent / "native-corpus-0c3e596"),
            "after": compatibility_observation(ROOT),
            "interpretation": "Section-one bidi and rtlGutter now survive. The sampled body word moves into the source binary's right-hand column. Header boxes are unchanged. Existing note and line-number differences remain.",
        },
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    value = derive()
    output = ROOT / "comparison-review.json"
    if args.write:
        output.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    else:
        assert json.loads(output.read_bytes()) == value
    print(json.dumps({"verified": True, "cases": len(value["cases"]),
                      "unchangedRenderCases": value["allRenderFingerprintsUnchangedCases"]}))
