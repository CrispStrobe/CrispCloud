#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Compare external DOC observations without treating any one reader as truth.

Text comparison uses main-story accepted text, excludes textbox stories and
field instructions, chooses the first AlternateContent choice, and normalizes
Unicode NFC and whitespace. Original output files remain the source of truth
for formatting and layout. Every discrepancy is retained with a first-difference
excerpt. Equality here does not establish visual or feature completeness.
"""
from __future__ import annotations

import argparse
from collections import Counter
import difflib
import json
from pathlib import Path
import re
import unicodedata
import xml.etree.ElementTree as ET
import zipfile

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
MC = "{http://schemas.openxmlformats.org/markup-compatibility/2006}"


def normalized(text: str) -> str:
    return re.sub(r"\s+", " ", unicodedata.normalize("NFC", text)).strip()


def visible(node: ET.Element) -> str:
    if node.tag in (W + "del", W + "txbxContent", W + "instrText", W + "delText"):
        return ""
    if node.tag == MC + "AlternateContent":
        chosen = node.find(MC + "Choice")
        if chosen is None:
            chosen = node.find(MC + "Fallback")
        return "" if chosen is None else visible(chosen)
    if node.tag == W + "t":
        return node.text or ""
    if node.tag in (W + "tab", W + "br", W + "cr"):
        return "\n" if node.tag != W + "tab" else "\t"
    if node.tag == W + "noBreakHyphen":
        return "\u2011"
    if node.tag == W + "softHyphen":
        return "\u00ad"
    return "".join(visible(child) for child in node) + ("\n" if node.tag == W + "p" else "")


def package(path: Path) -> dict:
    with zipfile.ZipFile(path) as archive:
        document = ET.fromstring(archive.read("word/document.xml"))
        body = document.find(W + "body")
        if body is None:
            raise ValueError("Missing transitional document body")
        text = normalized(visible(body))
        parents = {child: parent for parent in body.iter() for child in parent}

        def in_textbox(node):
            while node in parents:
                node = parents[node]
                if node.tag == W + "txbxContent":
                    return True
            return False

        tables = []
        for table in body.iter(W + "tbl"):
            if in_textbox(table):
                continue
            tables.append({
                "gridColumns": len(table.findall(f"{W}tblGrid/{W}gridCol")),
                "rows": [[normalized(visible(cell)) for cell in row.findall(W + "tc")]
                         for row in table.findall(W + "tr")],
            })
        return {"text": text, "tables": tables,
                "symbols": len(list(body.iter(W + "sym"))),
                "textboxes": len(list(body.iter(W + "txbxContent")))}


def comparison(left: str, right: str) -> dict:
    record = {"equal": left == right, "leftCharacters": len(left), "rightCharacters": len(right)}
    if left != right:
        index = next((i for i, (a, b) in enumerate(zip(left, right)) if a != b), min(len(left), len(right)))
        record.update(firstDifference=index, leftExcerpt=left[max(0, index - 50):index + 150],
                      rightExcerpt=right[max(0, index - 50):index + 150],
                      similarity=difflib.SequenceMatcher(None, left, right, autojunk=False).ratio())
    return record


def poi_text(observation: dict) -> str:
    # Field removal is Apache POI's own WordExtractor.stripFields implementation.
    # These are documented binary story/object/control markers, not printable text.
    text = "".join(observation.get("mainDisplayParagraphs", []))
    text = text.translate({1: None, 2: None, 5: None, 7: " ", 8: None,
                           19: None, 20: None, 21: None, 30: "\u2011", 31: "\u00ad"})
    return normalized(text)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--parser-output", required=True, type=Path)
    parser.add_argument("--native-output", required=True, type=Path)
    parser.add_argument("--poi-output", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Output report must be new")
    sources = json.loads((args.parser_output / "report.json").read_text())["cases"]
    native_report = json.loads((args.native_output / "report.json").read_text())
    native_cases = {Path(c.get("path", c.get("name", ""))).name: c for c in native_report["cases"]}
    result = {"version": 1, "comparisonPolicy": __doc__, "cases": []}
    for source in sorted(sources, key=lambda case: case["name"]):
        name = source["name"]
        stem = Path(name).stem
        record = {"name": name, "sourceSha256": source["sourceSha256"], "modes": {}}
        poi = json.loads((args.poi_output / f"poi-doc-{stem}.json").read_text())
        native = native_cases[name]["stages"]["docx"]
        native_path = Path(native["path"])
        if not native_path.is_absolute():
            native_path = args.native_output / native_path
        native_content = package(native_path)
        for mode in ("preserve", "cachedResults"):
            stage = source.get("result", {}).get("stages", {}).get("convert-" + mode, {})
            if stage.get("status") != "ok":
                record["modes"][mode] = {"status": "not-converted"}
                continue
            ours = package(args.parser_output / stem / stage["output"])
            record["modes"][mode] = {
                "status": "compared", "libreOfficeText": comparison(ours["text"], native_content["text"]),
                "poiText": comparison(ours["text"], poi_text(poi)),
                "tablesEqual": ours["tables"] == native_content["tables"],
                "ourTables": ours["tables"], "libreOfficeTables": native_content["tables"],
                "ourSymbols": ours["symbols"], "libreOfficeSymbols": native_content["symbols"],
                "ourTextboxes": ours["textboxes"], "libreOfficeTextboxes": native_content["textboxes"],
            }
        result["cases"].append(record)
    counts = Counter()
    for case in result["cases"]:
        for mode in case["modes"].values():
            counts[mode["status"]] += 1
            if mode["status"] == "compared":
                counts["libreOfficeTextEqual"] += mode["libreOfficeText"]["equal"]
                counts["poiTextEqual"] += mode["poiText"]["equal"]
                counts["tablesEqual"] += mode["tablesEqual"]
    result["counts"] = dict(counts)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(result["counts"], indent=2))


if __name__ == "__main__":
    main()
