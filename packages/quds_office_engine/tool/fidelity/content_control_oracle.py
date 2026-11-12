#!/usr/bin/env python3
"""Independent native SDT metadata, ownership and edited-content oracle.

The corpus covers body/note/table/frame block controls and inline controls in
ten logical stories. It does not certify block controls in paragraph-only
header/footer/comment editors, row/cell wrappers, binding refresh or control UI.
The raw source fixture supplies metadata expectations; expected edits and
container ancestry are asserted independently of the Dart model.
"""

from __future__ import annotations

import argparse
import base64
import copy
import json
import posixpath
from pathlib import Path
from xml.etree import ElementTree as ET
from zipfile import ZipFile

W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
M = "http://schemas.openxmlformats.org/officeDocument/2006/math"
A = "http://schemas.openxmlformats.org/drawingml/2006/main"
WP = "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
MC = "http://schemas.openxmlformats.org/markup-compatibility/2006"
NS = {"w": W, "r": R, "m": M, "a": A, "wp": WP, "mc": MC}
ENGINE = Path(__file__).resolve().parents[2]
SOURCE = ENGINE / "test/fixtures/fidelity/content_controls.xml"
CUSTOMER = b'<c:customer xmlns:c="urn:crispcloud:customer"><c:name>Original bound value</c:name></c:customer>'
PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3e0AAAAASUVORK5CYII=")
EXPECTED_FILES = {f"{mode}-{cycle}.docx" for mode in ("direct", "isolate")
                  for cycle in range(1, 4)}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def text(node: ET.Element) -> str:
    return "".join(item.text or "" for item in node.iter(f"{{{W}}}t"))


def identifier(control: ET.Element) -> str:
    value = control.find("w:sdtPr/w:id", NS)
    require(value is not None, "content control lost its native ID")
    return value.get(f"{{{W}}}val", "")


def semantic(node: ET.Element | None):
    if node is None:
        return None
    return (node.tag, tuple(sorted(node.attrib.items())),
            node.text.strip() if node.text and node.text.strip() else "",
            tuple(semantic(child) for child in node))


def active_tree(root: ET.Element) -> ET.Element:
    """Choose native drawing branches without counting VML fallback twice."""
    result = copy.deepcopy(root)

    def visit(parent):
        for child in list(parent):
            if child.tag == f"{{{MC}}}AlternateContent":
                choices = child.findall("mc:Choice", NS)
                require(len(choices) == 1 and choices[0].get("Requires") == "wps",
                        "unexpected frame compatibility branch")
                at = list(parent).index(child)
                parent.remove(child)
                for nested in list(choices[0]):
                    parent.insert(at, nested)
                    at += 1
                    visit(nested)
            else:
                visit(child)

    visit(result)
    return result


def controls(root: ET.Element) -> dict[str, ET.Element]:
    found = list(root.iter(f"{{{W}}}sdt"))
    result = {identifier(node): node for node in found}
    require(len(result) == len(found), "duplicate active content-control IDs")
    return result


def related(owner: str, target: str) -> str:
    return (target.lstrip("/") if target.startswith("/") else
            posixpath.normpath(posixpath.join(posixpath.dirname(owner), target)))


def relationships(parts: dict[str, bytes], owner: str) -> dict[str, ET.Element]:
    uri = posixpath.join(posixpath.dirname(owner), "_rels",
                         posixpath.basename(owner) + ".rels")
    require(uri in parts, f"missing relationships for {owner}")
    nodes = list(ET.fromstring(parts[uri]))
    result = {node.get("Id"): node for node in nodes}
    require(len(nodes) == len(result), f"duplicate relationship ID in {owner}")
    return result


def inspect_parts(parts: dict[str, bytes]) -> dict:
    office = [rel for rel in ET.fromstring(parts["_rels/.rels"])
              if rel.get("Type") == R + "/officeDocument"]
    require(len(office) == 1 and office[0].get("TargetMode", "Internal") == "Internal",
            "missing internal main document owner")
    main = related("", office[0].get("Target", ""))
    raw = ET.fromstring(parts[main])
    rels = relationships(parts, main)
    root = active_tree(raw)
    body = root.find("w:body", NS)
    require(body is not None, "missing body")
    body_controls = controls(root)
    require(set(body_controls) == {str(i) for i in range(71, 79)}, "body control inventory changed")
    expected = controls(ET.parse(SOURCE).getroot())
    for key, control in body_controls.items():
        for part in ("sdtPr", "sdtEndPr"):
            require(semantic(control.find("w:" + part, NS)) ==
                    semantic(expected[key].find("w:" + part, NS)),
                    f"control {key}: native {part} metadata changed")
        require(len(control.findall("w:sdtContent", NS)) == 1,
                f"control {key}: missing or duplicated native content container")

    outer = body_controls["71"]
    require(body.findall("w:sdt", NS) == [outer], "body control escaped its direct owner")
    require([text(p) for p in body.findall("w:p", NS)] ==
            ["Outside before edited", "Outside after"], "unrelated body text or ownership changed")
    content = outer.find("w:sdtContent", NS)
    require([child.tag for child in content] ==
            [f"{{{W}}}{name}" for name in ("p", "p", "sdt", "tbl", "p", "p", "p", "sdt")],
            "rich block order or paragraph split owner changed")
    first, tail = content.findall("w:p", NS)[:2]
    require(text(first) == "Block Edited" and text(tail) == " Beta", "block edit/split result changed")
    require(first.find("w:pPr/w:pStyle", NS).get(f"{{{W}}}val") == "RichBody",
            "block paragraph style lost")
    bold_runs = [run for run in first.findall("w:r", NS) if run.find("w:rPr/w:b", NS) is not None]
    require(len(bold_runs) == 1 and text(bold_runs[0]) == "Edited", "edited run formatting widened or lost")
    require(body_controls["72"] in list(content) and body_controls["78"] in list(content),
            "nested block controls escaped parent")
    require(text(body_controls["72"]) == "Nested heading" and
            [m.text for m in body_controls["72"].findall(".//m:t", NS)] == ["x+1"],
            "nested rich heading/equation content lost")
    table_control = content.find("w:tbl/w:tr/w:tc/w:sdt", NS)
    require(table_control is body_controls["73"] and text(table_control) == "Edited cell content",
            "table-cell content control lost its edited text or exact owner")
    frame_controls = content.findall(".//w:txbxContent/w:sdt", NS)
    require(frame_controls == [body_controls["74"]], "frame control escaped native textbox content")
    require([text(p) for p in frame_controls[0].findall("w:sdtContent/w:p", NS)] ==
            ["Frame content updated", "Frame second"], "frame edits escaped control or were discarded")
    fallback = raw.findall(".//mc:Fallback//w:txbxContent/w:sdt", NS)
    require(len(fallback) == 1 and identifier(fallback[0]) == "74" and
            semantic(fallback[0]) == semantic(body_controls["74"]),
            "native frame fallback disagrees with live content-control branch")

    inline_paragraphs = [p for p in content.findall("w:p", NS) if p.find("w:sdt", NS) is not None]
    require(len(inline_paragraphs) == 1, "inline controls moved to another paragraph")
    paragraph = inline_paragraphs[0]
    require(text(paragraph) == "Inline[Gamma Core tailempty filled]", "inline surrounding text changed")
    require(paragraph.findall("w:sdt", NS) == [body_controls["75"], body_controls["77"]],
            "inline control sibling order changed")
    require(body_controls["75"].find("w:sdtContent/w:sdt", NS) is body_controls["76"],
            "nested inline control was flattened")
    require([text(body_controls[str(i)]) for i in (75, 76, 77)] ==
            ["Gamma Core tail", "Core", "empty filled"], "inline ranges expanded or lost their edits")
    require([text(run) for run in paragraph.findall("w:r", NS)] == ["Inline[", "]"],
            "inline controls absorbed surrounding text")
    toc = body_controls["78"]
    instructions = toc.findall(".//w:instrText", NS)
    require(len(instructions) == 1 and (instructions[0].text or "").strip() == 'TOC \\o "1-3" \\h \\z \\u',
            "native TOC instruction missing or duplicated in cache")
    require([node.get(f"{{{W}}}fldCharType") for node in toc.findall(".//w:fldChar", NS)] ==
            ["begin", "separate", "end"], "TOC native field delimiters are unbalanced")
    require(text(toc) == "ContentsNested heading2", "TOC cache/title lost")
    anchors = {node.get(f"{{{W}}}name") for node in body_controls["72"].findall(".//w:bookmarkStart", NS)}
    require(anchors == {"sdtHeading"} and
            {node.get(f"{{{W}}}anchor") for node in toc.findall(".//w:hyperlink", NS)} == anchors,
            "TOC target no longer resolves to its controlled heading")

    images = content.findall(".//a:blip", NS)
    require(len(images) == 1, "control image lost or duplicated")
    image_rel = rels.get(images[0].get(f"{{{R}}}embed"))
    require(image_rel is not None and image_rel.get("Type") == R + "/image" and
            image_rel.get("TargetMode", "Internal") == "Internal", "control image relationship invalid")
    require(parts.get(related(main, image_rel.get("Target", ""))) == PNG, "control image payload changed")
    picture_properties = [node for node in content.findall(".//wp:docPr", NS)
                          if node.get("title") == "Inside content control"]
    require(len(picture_properties) == 1 and picture_properties[0].get("descr") == "Preserved image payload",
            "control image accessibility metadata lost")
    require(parts.get("customXml/controlData.xml") == CUSTOMER, "unrelated binding data overwritten")
    require(any(rel.get("Type") == R + "/customXml" and rel.get("TargetMode", "Internal") == "Internal" and
                related(main, rel.get("Target", "")) == "customXml/controlData.xml" for rel in rels.values()),
            "custom XML binding data ownership lost")
    data_rels = list(relationships(parts, "customXml/controlData.xml").values())
    require(len(data_rels) == 1 and data_rels[0].get("Type") == R + "/customXmlProps" and
            related("customXml/controlData.xml", data_rels[0].get("Target", "")) == "customXml/controlProps.xml",
            "bound custom XML source-properties relationship lost")
    props = ET.fromstring(parts["customXml/controlProps.xml"])
    require(props.get("{http://schemas.openxmlformats.org/officeDocument/2006/customXml}itemID") ==
            "{00000000-0000-0000-0000-000000000071}", "binding store identity changed")

    def owned(rel, kind):
        require(rel is not None and rel.get("Type") == R + "/" + kind and
                rel.get("TargetMode", "Internal") == "Internal", f"invalid owned {kind} relationship")
        uri = related(main, rel.get("Target", ""))
        require(uri in parts, f"missing owned {kind} part")
        return active_tree(ET.fromstring(parts[uri]))

    def check_aux(control, key, value):
        require(identifier(control) == str(key), f"auxiliary control {key} lost its story identity")
        require(control.find("w:sdtPr/w:alias", NS).get(f"{{{W}}}val") == f"Aux control {key}" and
                control.find("w:sdtPr/w:tag", NS).get(f"{{{W}}}val") == f"control-{key}" and
                control.find("w:sdtPr/w:richText", NS) is not None and
                control.find("w:sdtEndPr/w:rPr/w:color", NS).get(f"{{{W}}}val") == "112233",
                f"auxiliary control {key} metadata changed")
        require(text(control) == value, f"auxiliary control {key} range or text changed")

    seen = set(body_controls)
    section = body.find("w:sectPr", NS)
    require(section is not None, "missing section story references")
    key = 81
    for kind in ("header", "footer"):
        references = section.findall(f"w:{kind}Reference", NS)
        require(len(references) == 3, f"missing {kind} variants")
        for variant in ("default", "first", "even"):
            refs = [node for node in references if node.get(f"{{{W}}}type") == variant]
            require(len(refs) == 1, f"missing {kind}-{variant} reference")
            story = owned(rels.get(refs[0].get(f"{{{R}}}id")), kind)
            found = controls(story)
            require(set(found) == {str(key)}, f"unexpected controls in {kind}-{variant}")
            paragraph = story.find("w:p", NS)
            require(paragraph is not None and paragraph.find("w:sdt", NS) is found[str(key)] and
                    text(paragraph) == f"Before {kind}-{variant} after", f"{kind}-{variant} inline owner changed")
            check_aux(found[str(key)], key, f"{kind}-{variant}")
            seen.update(found)
            key += 1
    for kind, item, block_id, inline_id, value in (
        ("comments", "comment", None, 87, "Comment"),
        ("footnotes", "footnote", 91, 88, "Footnote"),
        ("endnotes", "endnote", 92, 89, "Endnote"),
    ):
        matches = [rel for rel in rels.values() if rel.get("Type") == R + "/" + kind]
        require(len(matches) == 1, f"missing {kind} owner")
        story = owned(matches[0], kind)
        stories = [node for node in story.findall("w:" + item, NS)
                   if node.get(f"{{{W}}}id") == ("7" if block_id is None else "1")]
        require(len(stories) == 1, f"missing {item} body")
        found = controls(stories[0])
        expected_ids = {str(inline_id)} | ({str(block_id)} if block_id else set())
        require(set(found) == expected_ids, f"unexpected controls in {item}")
        check_aux(found[str(inline_id)], inline_id, "body" if block_id else value)
        if block_id:
            check_aux(found[str(block_id)], block_id, value + " body edited")
            require(stories[0].find("w:sdt", NS) is found[str(block_id)] and
                    found[str(block_id)].find("w:sdtContent/w:p/w:sdt", NS) is found[str(inline_id)],
                    f"{item} control owner changed")
            markers = list(stories[0].iter(f"{{{W}}}{item}Ref"))
            require(len(markers) == 1 and
                    found[str(block_id)].find(f"w:sdtContent/w:p/w:r/w:{item}Ref", NS) is markers[0],
                    f"{item} automatic mark moved or duplicated")
        else:
            paragraph = stories[0].find("w:p", NS)
            require(paragraph is not None and paragraph.find("w:sdt", NS) is found[str(inline_id)] and
                    text(paragraph) == "Before Comment after", "comment inline owner changed")
        require(not seen.intersection(found), "control IDs collide across stories")
        seen.update(found)
    require(len(seen) == 19, "missing active content controls")
    return {"block_controls": 7, "inline_controls": 12, "stories": 10,
            "images": 1, "equations": 1, "native_tocs": 1,
            "binding_metadata_preserved": True, "frame_fallback_matches": True}


def inspect_package(path: Path) -> dict:
    with ZipFile(path) as archive:
        require(archive.testzip() is None, f"corrupt ZIP entry in {path.name}")
        return inspect_parts({name: archive.read(name) for name in archive.namelist()})


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", nargs="?", type=Path,
                        default=Path("build/fidelity-content-controls"))
    args = parser.parse_args()
    actual = {path.name for path in args.directory.glob("*.docx")}
    require(actual == EXPECTED_FILES,
            f"corpus mismatch; missing={sorted(EXPECTED_FILES - actual)}, "
            f"unexpected={sorted(actual - EXPECTED_FILES)}")
    results = {name: inspect_package(args.directory / name) for name in sorted(EXPECTED_FILES)}
    print(json.dumps({"status": "passed", "documents": results}, indent=2))


if __name__ == "__main__":
    main()
