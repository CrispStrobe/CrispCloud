#!/usr/bin/env python3
"""Native bibliography ownership and metadata checks independent of Dart.

Certifies this fixture's current source list, scalar edits, structured-author
preservation and unrelated-part bytes. Native APA/MLA rendering and arbitrary
rich/multirun CITATION fields require separate interoperability coverage.
"""

from __future__ import annotations

import argparse
import json
import posixpath
from pathlib import Path
from xml.etree import ElementTree as ET
from zipfile import ZipFile

B = "http://schemas.openxmlformats.org/officeDocument/2006/bibliography"
W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PKG = "http://schemas.openxmlformats.org/package/2006/relationships"
CT = "http://schemas.openxmlformats.org/package/2006/content-types"
X = "urn:crispcloud:bibliography-extension"
NS = {"b": B, "w": W, "x": X}
UNRELATED_ITEM = b'<Sources xmlns="urn:crispcloud:unrelated"><Source>Keep item1 exactly</Source></Sources>'
UNRELATED_SOURCES = b'<audit xmlns="urn:crispcloud:unrelated">Keep sources.xml exactly</audit>'
PROPS = f'<ds:datastoreItem xmlns:ds="http://schemas.openxmlformats.org/officeDocument/2006/customXml" ds:itemID="{{6AD1A1C2-1B2A-4DFB-A9AD-000000000001}}"><ds:schemaRefs><ds:schemaRef ds:uri="{B}"/></ds:schemaRefs></ds:datastoreItem>'.encode()
EXPECTED_FILES = {f"{mode}-{cycle}.docx" for mode in ("direct", "isolate")
                  for cycle in range(1, 4)}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def related(owner: str, target: str) -> str:
    return (target.lstrip("/") if target.startswith("/") else
            posixpath.normpath(posixpath.join(posixpath.dirname(owner), target)))


def scalar(source: ET.Element, name: str) -> str | None:
    element = source.find(f"b:{name}", NS)
    return None if element is None else element.text or ""


def inspect_parts(parts: dict[str, bytes]) -> dict:
    require(parts.get("customXml/item1.xml") == UNRELATED_ITEM, "unrelated item1 XML overwritten")
    require(parts.get("customXml/sources.xml") == UNRELATED_SOURCES, "unrelated sources XML overwritten")
    require(parts.get("customXml/itemProps42.xml") == PROPS, "native custom XML properties changed")
    office = [rel for rel in ET.fromstring(parts["_rels/.rels"])
              if rel.get("Type") == R + "/officeDocument"]
    require(len(office) == 1 and office[0].get("TargetMode", "Internal") == "Internal",
            "missing owned main part")
    main = related("", office[0].get("Target", ""))
    require(main == "office/content/body.xml", "custom main-part location changed")
    rel_uri = posixpath.join(posixpath.dirname(main), "_rels", posixpath.basename(main) + ".rels")
    relationships = list(ET.fromstring(parts[rel_uri]))
    bibliography = []
    for rel in relationships:
        if rel.get("Type") != R + "/customXml" or rel.get("TargetMode", "Internal") != "Internal":
            continue
        uri = related(main, rel.get("Target", ""))
        require(uri in parts, "missing custom XML relationship target")
        root = ET.fromstring(parts[uri])
        if root.tag == f"{{{B}}}Sources":
            bibliography.append((rel, uri, root))
    require(len(bibliography) == 1, "expected one native bibliography owned by main document")
    relationship, uri, root = bibliography[0]
    require(relationship.get("Id") == "nativeBibliography" and uri == "customXml/catalog42.xml",
            "native bibliography relationship or part identity changed")
    require(any(rel.get("Type") == R + "/customXml" and
                rel.get("TargetMode", "Internal") == "Internal" and
                related(main, rel.get("Target", "")) == "customXml/item1.xml"
                for rel in relationships), "unrelated custom XML relationship lost")
    content_types = ET.fromstring(parts["[Content_Types].xml"])
    declared = [item.get("ContentType") for item in content_types
                if item.tag == f"{{{CT}}}Override" and item.get("PartName") == "/" + uri]
    require(declared == ["application/xml"], "bibliography native content type changed")
    for key, value in {"SelectedStyle": "/APA.XSL", "StyleName": "APA", "Version": "6"}.items():
        require(root.get(key) == value, f"bibliography {key} metadata changed")
    props_rels = ET.fromstring(parts["customXml/_rels/catalog42.xml.rels"])
    require(len(props_rels) == 1 and props_rels[0].get("Type") == R + "/customXmlProps" and
            props_rels[0].get("TargetMode", "Internal") == "Internal" and
            related(uri, props_rels[0].get("Target", "")) == "customXml/itemProps42.xml",
            "native source-properties ownership lost")
    sources = root.findall("b:Source", NS)
    tagged = {scalar(source, "Tag"): source for source in sources if scalar(source, "Tag")}
    require(len(sources) == 3 and set(tagged) == {"Native", "Added"}, "source inventory changed")
    untagged = [source for source in sources if scalar(source, "Tag") is None]
    require(len(untagged) == 1 and scalar(untagged[0], "Comments") == "Unmodeled source without a tag",
            "unmodeled native source lost")
    native = tagged["Native"]
    for name, value in {
        "SourceType": "Book", "Title": "Edited & expanded", "Year": "2026", "Pages": "12-19",
        "Guid": "{6AD1A1C2-1B2A-4DFB-A9AD-000000000001}", "Publisher": "Native publisher",
        "City": "London", "URL": "https://example.org/native-source",
    }.items():
        require(scalar(native, name) == value, f"native {name} value lost or edit missing")
    require(native.get(f"{{{X}}}kept") == "native-extension", "source extension attribute lost")
    foreign_title = native.find("x:Title", NS)
    require(foreign_title is not None and foreign_title.text == "Foreign title must remain",
            "foreign-namespace Title confused with native field")
    people = native.findall("b:Author/b:Author/b:NameList/b:Person", NS)
    require([(scalar(person, "Last"), scalar(person, "First"), scalar(person, "Middle"))
             for person in people] == [("Lovelace", "Ada", "Byron"), ("Hopper", "Grace", None)],
            "native structured author list flattened or changed")
    editor = native.find("b:Author/b:Editor/b:NameList/b:Person", NS)
    require(editor is not None and scalar(editor, "Last") == "Editor" and scalar(editor, "First") == "Native",
            "unmodeled editor role lost")
    added = tagged["Added"]
    require(scalar(added, "SourceType") == "Misc" and scalar(added, "Title") == "Added source" and
            scalar(added, "Year") == "2025", "new native source metadata missing")
    literal = added.find("b:Author/b:Author/b:Corporate", NS)
    require(literal is not None and literal.text == "CrispCloud Team", "new source author is not a native literal container")
    document = ET.fromstring(parts[main])
    paragraph = document.find("w:body/w:p", NS)
    require(paragraph is not None, "missing citation paragraph")
    text = "".join(node.text or "" for node in paragraph.iter(f"{{{W}}}t"))
    require(text == "Before (Original cached source) after", "surrounding body or citation cache changed")
    field = paragraph.find("w:fldSimple", NS)
    require(field is not None and field.get(f"{{{W}}}instr", "").strip() == "CITATION Native",
            "native citation instruction lost")
    return {"owned_source_part": uri, "editable_sources": 2,
            "unmodeled_sources": 1, "unrelated_parts_preserved": 3}


def inspect_package(path: Path) -> dict:
    with ZipFile(path) as archive:
        require(archive.testzip() is None, f"corrupt ZIP entry in {path.name}")
        return inspect_parts({name: archive.read(name) for name in archive.namelist()})


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", nargs="?", type=Path,
                        default=Path("build/fidelity-bibliography"))
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
