#!/usr/bin/env python3
"""Independent native XML ownership and exact-span checks for tracked stories.

The corpus contains one insertion and one deletion in separate paragraphs in
each of ten stories. It does not certify overlapping/nested changes or rebasing
of multiple changes after editing the same paragraph.
"""

from __future__ import annotations

import argparse
import json
import posixpath
from pathlib import Path
from xml.etree import ElementTree as ET
from zipfile import ZipFile

W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PKG = "http://schemas.openxmlformats.org/package/2006/relationships"
NS = {"w": W, "r": R}
DATE = "2026-10-01T12:30:00Z"
EXPECTED_FILES = {f"{mode}-{cycle}.docx" for mode in ("direct", "isolate")
                  for cycle in range(1, 4)}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def text(element: ET.Element) -> str:
    return "".join(node.text or "" for node in element.iter()
                   if node.tag in {f"{{{W}}}t", f"{{{W}}}delText"})


def inspect_story(paragraphs: list[ET.Element], name: str) -> dict:
    require(len(paragraphs) == 2, f"{name}: expected two revision paragraphs")
    for paragraph, kind, changed in zip(paragraphs, ("ins", "del"),
                                         (" added", " removed")):
        require(text(paragraph) == f"{name}{changed} tail",
                f"{name}: story text or ownership changed")
        changes = [node for node in paragraph.iter()
                   if node.tag in {f"{{{W}}}ins", f"{{{W}}}del"}]
        direct = paragraph.findall(f"w:{kind}", NS)
        require(len(changes) == len(direct) == 1,
                f"{name}: missing or misplaced native {kind} wrapper")
        change = direct[0]
        require(text(change) == changed, f"{name}: tracked span includes unchanged text")
        require(change.get(f"{{{W}}}author") == "Native reviewer",
                f"{name}: reviewer changed")
        require(change.get(f"{{{W}}}date") == DATE, f"{name}: revision date changed")
        children = list(change)
        require(len(children) == 1 and children[0].tag == f"{{{W}}}r",
                f"{name}: expected one tracked native run")
        result = children[0].find(f"w:{'delText' if kind == 'del' else 't'}", NS)
        require(result is not None and result.text == changed,
                f"{name}: incorrect native deletion/insert text node")
        bold = children[0].find("w:rPr/w:b", NS)
        require(bold is not None and bold.get(f"{{{W}}}val", "1") in {"1", "true", "on"},
                f"{name}: tracked bold formatting changed")
        ordinary = [text(run) for run in paragraph.findall("w:r", NS) if text(run)]
        require(ordinary == [name, " tail"], f"{name}: ordinary prefix/suffix changed")
    return {"paragraphs": 2, "inserted": " added", "deleted": " removed"}


def inspect_parts(parts: dict[str, bytes]) -> dict:
    require("_rels/.rels" in parts, "missing package relationships")
    package_rels = ET.fromstring(parts["_rels/.rels"])
    office = [r for r in package_rels if r.get("Type") == R + "/officeDocument"]
    require(len(office) == 1 and office[0].get("TargetMode", "Internal") == "Internal",
            "main document must have one internal relationship")
    main = posixpath.normpath(office[0].get("Target", "").lstrip("/"))
    require(main in parts, "missing main document")
    folder, filename = posixpath.split(main)
    rel_uri = posixpath.join(folder, "_rels", filename + ".rels")
    require(rel_uri in parts, "missing main relationships")
    rels = {r.get("Id"): r for r in ET.fromstring(parts[rel_uri])}

    def related(relationship: ET.Element, expected_type: str) -> ET.Element:
        require(relationship.get("Type") == R + "/" + expected_type,
                f"incorrect {expected_type} relationship type")
        require(relationship.get("TargetMode", "Internal") == "Internal",
                f"{expected_type} must be internal")
        target = relationship.get("Target", "")
        uri = (target.lstrip("/") if target.startswith("/") else
               posixpath.normpath(posixpath.join(folder, target)))
        require(uri in parts, f"missing owned {expected_type} part")
        return ET.fromstring(parts[uri])

    root = ET.fromstring(parts[main])
    body = root.find("w:body", NS)
    require(body is not None, "missing body")
    paragraphs = body.findall("w:p", NS)
    require(len(paragraphs) == 3 and text(paragraphs[0]) == "UNCHANGED",
            "unchanged body paragraph corrupted")
    require(not paragraphs[0].findall(".//w:ins", NS) and
            not paragraphs[0].findall(".//w:del", NS),
            "auxiliary revision redirected into body")
    facts = {"Body": inspect_story(paragraphs[1:], "Body")}
    section = body.find("w:sectPr", NS)
    require(section is not None, "missing section properties")
    for kind in ("header", "footer"):
        references = section.findall(f"w:{kind}Reference", NS)
        require(len(references) == 3, f"missing {kind} variants")
        for variant in ("default", "first", "even"):
            refs = [node for node in references if node.get(f"{{{W}}}type") == variant]
            require(len(refs) == 1, f"missing or duplicate {kind}-{variant} reference")
            rid = refs[0].get(f"{{{R}}}id")
            require(rid in rels, f"unresolved {kind}-{variant} reference")
            story = related(rels[rid], kind)
            require(story.tag == f"{{{W}}}{'hdr' if kind == 'header' else 'ftr'}",
                    f"incorrect native {kind} root")
            name = kind.capitalize() + "-" + variant
            facts[name] = inspect_story(story.findall("w:p", NS), name)
    for name, kind, item in (("Footnote", "footnotes", "footnote"),
                             ("Endnote", "endnotes", "endnote"),
                             ("Comment", "comments", "comment")):
        matches = [rel for rel in rels.values() if rel.get("Type") == R + "/" + kind]
        require(len(matches) == 1, f"missing or duplicate owned {kind} relationship")
        story = related(matches[0], kind)
        identifier = "7" if name == "Comment" else "1"
        items = [node for node in story.findall(f"w:{item}", NS)
                 if node.get(f"{{{W}}}id") == identifier]
        require(len(items) == 1, f"missing {name} body")
        facts[name] = inspect_story(items[0].findall("w:p", NS), name)
    return facts


def inspect_package(path: Path) -> dict:
    with ZipFile(path) as archive:
        require(archive.testzip() is None, f"corrupt ZIP entry in {path.name}")
        return inspect_parts({name: archive.read(name) for name in archive.namelist()})


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", nargs="?", type=Path,
                        default=Path("build/fidelity-revision-stories"))
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
