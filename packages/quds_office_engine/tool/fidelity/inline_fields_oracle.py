#!/usr/bin/env python3
"""Independent ZIP/XML checks for the inline citation regression corpus.

This validates field boundaries, cached results, surrounding text and formatting.
It does not certify native Word bibliography-source refresh or arbitrary rich,
nested, complex, or cross-paragraph fields.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from xml.etree import ElementTree as ET
from zipfile import ZipFile

W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
NS = {"w": W}
EXPECTED_TEXT = "Before (Ada 2026) between (Grace 2025) after"
EXPECTED_FIELDS = [("CITATION PAGE", "(Ada 2026)"),
                   ("CITATION TIME", "(Grace 2025)")]
EXPECTED_FILES = {f"{mode}-{cycle}.docx" for mode in ("direct", "isolate")
                  for cycle in range(1, 4)}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def inspect_document(xml: bytes) -> dict:
    root = ET.fromstring(xml)
    paragraphs = root.findall("w:body/w:p", NS)
    require(len(paragraphs) == 1, "expected one body paragraph")
    paragraph = paragraphs[0]
    text = "".join(node.text or "" for node in paragraph.iter(f"{{{W}}}t"))
    require(text == EXPECTED_TEXT, f"surrounding text or field result changed: {text!r}")
    direct_fields = paragraph.findall("w:fldSimple", NS)
    all_fields = list(root.iter(f"{{{W}}}fldSimple"))
    require(len(direct_fields) == len(all_fields) == 2,
            "expected two independent inline fields directly in the paragraph")
    facts = []
    for field in direct_fields:
        runs = field.findall("w:r", NS)
        require(len(runs) == 1, "each citation must have one result run")
        instruction = field.get(f"{{{W}}}instr", "").strip()
        value = "".join(t.text or "" for t in runs[0].findall("w:t", NS))
        facts.append((instruction, value))
    require(facts == EXPECTED_FIELDS, f"citation instructions or results changed: {facts!r}")
    require(not list(paragraph.iter(f"{{{W}}}instrText")),
            "inline citations must not become a whole-paragraph complex field")
    ordinary = paragraph.findall("w:r", NS)
    require(len(ordinary) == 3, "prefix, middle and suffix must remain ordinary runs")
    require(["".join(t.text or "" for t in run.findall("w:t", NS))
             for run in ordinary] == ["Before ", " between ", " after"],
            "ordinary text was absorbed into a citation")
    bold = ordinary[0].find("w:rPr/w:b", NS)
    italic = ordinary[1].find("w:rPr/w:i", NS)
    underline = ordinary[2].find("w:rPr/w:u", NS)
    require(bold is not None and bold.get(f"{{{W}}}val", "1") in {"1", "true", "on"},
            "prefix bold formatting changed")
    require(italic is not None and italic.get(f"{{{W}}}val", "1") in {"1", "true", "on"},
            "middle italic formatting changed")
    require(underline is not None and underline.get(f"{{{W}}}val") == "single",
            "suffix underline formatting changed")
    return {"text": text, "fields": facts, "ordinary_runs": len(ordinary)}


def inspect_package(path: Path) -> dict:
    with ZipFile(path) as archive:
        require(archive.testzip() is None, f"corrupt ZIP entry in {path.name}")
        return inspect_document(archive.read("word/document.xml"))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", nargs="?", type=Path,
                        default=Path("build/fidelity-inline-fields"))
    args = parser.parse_args()
    actual = {path.name for path in args.directory.glob("*.docx")}
    require(actual == EXPECTED_FILES,
            f"corpus mismatch; missing={sorted(EXPECTED_FILES - actual)}, "
            f"unexpected={sorted(actual - EXPECTED_FILES)}")
    results = {name: inspect_package(args.directory / name)
               for name in sorted(EXPECTED_FILES)}
    print(json.dumps({"status": "passed", "documents": results}, indent=2))


if __name__ == "__main__":
    main()
